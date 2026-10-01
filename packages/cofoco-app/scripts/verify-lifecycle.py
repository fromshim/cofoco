#!/usr/bin/env python3
"""Bounded isolated helper checks: rapid restart and parent-loss cleanup."""
import argparse
import os
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument("--helper", required=True)
parser.add_argument("--database", required=True)
parser.add_argument("--keychain-service", required=True)
args = parser.parse_args()
if not args.keychain_service.startswith("com.fromshim.cofoco.desktop-smoke."):
    parser.error("an isolated desktop-smoke namespace is required")
environment = dict(os.environ, COFOCO_KEYCHAIN_SERVICE=args.keychain_service)

def healthy():
    try:
        with urllib.request.urlopen("http://127.0.0.1:57321/health", timeout=0.5) as response:
            return response.status == 200
    except (urllib.error.URLError, TimeoutError):
        return False

def wait_for(predicate):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError("lifecycle condition timed out")

assert not healthy(), "do not run against an already-running service"
for attempt in range(3):
    helper = subprocess.Popen([args.helper, "--database", args.database, "--parent-pid", str(os.getpid())],
                              env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        wait_for(lambda: healthy() or helper.poll() is not None)
        assert helper.poll() is None, helper.stderr.read().decode()
        # Each health call exercises the same close-after-response HTTP socket.
        assert healthy()
        helper.terminate()
        status = helper.wait(timeout=5)
        assert status == 0, (status, helper.stderr.read().decode())
        wait_for(lambda: not healthy())
    finally:
        if helper.poll() is None:
            helper.kill()
            helper.wait(timeout=5)
print("rapid_restart: 3/3 helper starts and graceful exits passed")

wrapper_code = """
import os, subprocess, signal, sys
p = subprocess.Popen([sys.argv[1], '--database', sys.argv[2], '--parent-pid', str(os.getpid())], stdout=subprocess.DEVNULL)
print(p.pid, flush=True)
signal.pause()
"""
wrapper = subprocess.Popen([sys.executable, "-c", wrapper_code, args.helper, args.database],
                           env=environment, stdout=subprocess.PIPE, text=True)
child_pid = int(wrapper.stdout.readline().strip())
try:
    wait_for(healthy)
    wrapper.kill()
    wrapper.wait(timeout=5)
    wait_for(lambda: not healthy())
    def child_gone():
        try:
            os.kill(child_pid, 0)
            return False
        except ProcessLookupError:
            return True
    wait_for(child_gone)
    print("parent_loss: helper exited and port closed after parent SIGKILL")
finally:
    if wrapper.poll() is None:
        wrapper.kill()
        wrapper.wait(timeout=5)
