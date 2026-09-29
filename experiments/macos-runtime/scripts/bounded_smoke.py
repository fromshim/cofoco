"""Run either process-boundary spike with a firm outer timeout."""

import subprocess
import sys


if len(sys.argv) == 2:
    command = [sys.argv[1], "--smoke-test"]
    label = "app smoke"
    limit = 12
elif len(sys.argv) == 4 and sys.argv[1] == "--service-test":
    command = [sys.executable, sys.argv[2], sys.argv[3]]
    label = "service process test"
    limit = 8
else:
    raise SystemExit("usage: bounded_smoke.py APP_BINARY | --service-test TEST_SCRIPT HELPER_BINARY")

try:
    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        timeout=limit,
    )
except subprocess.TimeoutExpired as error:
    if error.stdout:
        sys.stdout.write(error.stdout.decode() if isinstance(error.stdout, bytes) else error.stdout)
    if error.stderr:
        sys.stderr.write(error.stderr.decode() if isinstance(error.stderr, bytes) else error.stderr)
    raise SystemExit(f"{label} timed out after {error.timeout}s") from error

if result.stderr:
    sys.stderr.write(result.stderr)
if result.stdout:
    sys.stdout.write(result.stdout)
if result.returncode != 0:
    raise SystemExit(f"{label} exited {result.returncode}")
