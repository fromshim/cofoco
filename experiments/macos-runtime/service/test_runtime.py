"""Process-boundary checks for the disposable Cofoco service spike.

Run with the compiled helper path. Uses only temporary fixture directories.
"""

import json
import os
import signal
import socket
import subprocess
import sys
import tempfile
import time


def request(port, token, *, host=None, origin=None, authorized=True):
    headers = [
        "GET /health HTTP/1.1",
        f"Host: {host or f'127.0.0.1:{port}'}",
    ]
    if authorized:
        headers.append(f"Authorization: Bearer {token}")
    if origin:
        headers.append(f"Origin: {origin}")
    payload = ("\r\n".join(headers) + "\r\n\r\n").encode()
    with socket.create_connection(("127.0.0.1", port), timeout=2) as connection:
        connection.sendall(payload)
        return connection.recv(4096).decode()


def check(binary):
    with tempfile.TemporaryDirectory(prefix="cofoco-service-process-") as directory:
        process = subprocess.Popen(
            [binary, "--data-dir", directory, "--parent-pid", str(os.getpid())],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            ready = json.loads(process.stdout.readline())
            assert ready["status"] == "ready" and ready["protocol_version"] == 1
            assert ready["pid"] == process.pid
            port, token = ready["port"], ready["token"]
            assert request(port, token).startswith("HTTP/1.1 200")
            assert request(port, token, authorized=False).startswith("HTTP/1.1 403")
            assert request(port, token, host="evil.local").startswith("HTTP/1.1 403")
            assert request(port, token, origin="https://evil.local").startswith("HTTP/1.1 403")
            duplicate = subprocess.run(
                [binary, "--data-dir", directory], capture_output=True, text=True, timeout=4
            )
            assert duplicate.returncode != 0 and "already_running" in duplicate.stderr
            process.send_signal(signal.SIGTERM)
            assert process.wait(timeout=4) == 0
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()

        orphan_directory = os.path.join(directory, "orphan")
        script = """
import json, os, subprocess, sys
p = subprocess.Popen([sys.argv[1], '--data-dir', sys.argv[2], '--parent-pid', str(os.getpid())], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
assert json.loads(p.stdout.readline())['status'] == 'ready'
print(p.pid, flush=True)
"""
        short_lived_parent = subprocess.run(
            [sys.executable, "-c", script, binary, orphan_directory],
            capture_output=True, text=True, timeout=4,
        )
        assert short_lived_parent.returncode == 0, short_lived_parent.stderr
        orphan_pid = int(short_lived_parent.stdout.strip())
        stopped = False
        for _ in range(30):
            state = subprocess.run(["ps", "-o", "stat=", "-p", str(orphan_pid)],
                                   capture_output=True, text=True).stdout.strip()
            if not state or state.startswith("Z"):
                stopped = True
                break
            time.sleep(0.1)
        if not stopped:
            os.kill(orphan_pid, signal.SIGKILL)
        assert stopped, "service survived abrupt parent exit"
        print(json.dumps({"status": "passed", "health": 200, "rejections": 3,
                          "duplicate_instance": "rejected", "sigterm": "clean",
                          "parent_exit": "detected"}, sort_keys=True))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: test_runtime.py COMPILED_HELPER")
    check(sys.argv[1])
