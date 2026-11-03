#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$(uname -m)" != arm64 ]; then
  echo "The Arasan NEON build requires an ARM64 Mac." >&2
  exit 1
fi

output_dir="${1:-build/e2e}"
family="${2:-iPhone}"
case "$family" in
  iPhone|iPad) ;;
  *) echo "Device family must be iPhone or iPad." >&2; exit 1 ;;
esac
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
if [ -e "$output_dir/EndToEnd.xcresult" ]; then
  echo "Choose a fresh output directory; EndToEnd.xcresult already exists." >&2
  exit 1
fi

xcodebuild -version
xcrun simctl list runtimes --json > "$output_dir/runtimes.json"
selection="$(python3 - "$output_dir/runtimes.json" "$family" "${E2E_IOS_VERSION:-}" <<'PY'
import json
import sys

with open(sys.argv[1]) as source:
    runtimes = json.load(source)["runtimes"]
family = sys.argv[2]
requested = tuple(int(part) for part in sys.argv[3].split(".")) if sys.argv[3] else ()
candidates = []
for runtime in runtimes:
    identifier = runtime["identifier"]
    if not runtime.get("isAvailable") or ".iOS-" not in identifier:
        continue
    version = tuple(int(part) for part in runtime["version"].split("."))
    if requested and version[:len(requested)] != requested:
        continue
    for device in runtime.get("supportedDeviceTypes", []):
        if device["name"].startswith(family):
            preferred = device["name"] in ("iPhone 17 Pro", "iPad mini (A17 Pro)")
            candidates.append((version, preferred, identifier, device))
if not candidates:
    target = f" on iOS {sys.argv[3]}" if requested else ""
    sys.exit(f"No available {family} simulator{target}. Install an iOS runtime in Xcode.")
# Use the newest available runtime, then prefer a familiar screen size.
_, _, runtime, device = max(candidates, key=lambda item: (item[0], item[1]))
print(device["identifier"])
print(runtime)
print(f"Using isolated {device['name']} on {runtime}", file=sys.stderr)
PY
)"
device_type="$(printf '%s\n' "$selection" | head -n 1)"
runtime="$(printf '%s\n' "$selection" | tail -n 1)"
simulator_id="$(xcrun simctl create "ForkChess E2E $family" "$device_type" "$runtime")"
cleanup() {
  xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
  xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf '%s\n' "$simulator_id" > "$output_dir/simulator-id.txt"

# Keep simulator boot and data migration outside each UI test's time allowance.
xcrun simctl bootstatus "$simulator_id" -b 2>&1 | tee "$output_dir/boot.log"
# The boot summary can report completion while migration is still pending, or
# report a failure even though the individual plugins succeeded.
python3 - "$simulator_id" "$output_dir/boot.log" "$output_dir/migration.log" <<'PY'
from pathlib import Path
import os
import re
import subprocess
import sys
import time

simulator, summary_path, details_path = sys.argv[1:]
summary = Path(summary_path).read_text()
timeout = float(os.environ.get("E2E_MIGRATION_TIMEOUT_SECONDS", "180"))
poll_interval = float(os.environ.get("E2E_MIGRATION_POLL_SECONDS", "2"))
status_timeout = float(os.environ.get("E2E_MIGRATION_STATUS_TIMEOUT_SECONDS", "30"))
deadline = time.monotonic() + timeout

while True:
    try:
        result = subprocess.run(
            ["xcrun", "simctl", "bootstatus", simulator, "-d"],
            capture_output=True, text=True, timeout=status_timeout,
        )
    except subprocess.TimeoutExpired as error:
        # TimeoutExpired can carry bytes even when text=True. Normalize each
        # stream before joining: the other stream may be empty (None).
        output = "".join(
            stream.decode(errors="replace") if isinstance(stream, bytes) else (stream or "")
            for stream in (error.stdout, error.stderr)
        )
        Path(details_path).write_text(
            output + f"\nMigration status read timed out after {status_timeout:g}s; retrying.\n"
        )
        if time.monotonic() >= deadline:
            sys.exit(f"Simulator migration is incomplete; see {details_path}.")
        time.sleep(min(poll_interval, deadline - time.monotonic()))
        continue
    details = result.stdout + result.stderr
    Path(details_path).write_text(details)
    if result.returncode != 0:
        sys.exit(result.returncode)

    plugins = re.findall(r"^\s*[\w.-]+\s*:\s*duration:.*$", details, re.MULTILINE)
    if not plugins:
        sys.exit(f"Simulator migration details are missing; see {details_path}.")
    if any(re.search(r",\s*status:\s*failed\s*$", line) for line in plugins):
        sys.exit(f"Simulator migration failed; see {details_path}.")
    if all(re.search(r",\s*status:\s*success\s*$", line) for line in plugins):
        break

    remaining = deadline - time.monotonic()
    if remaining <= 0:
        sys.exit(f"Simulator migration is incomplete; see {details_path}.")
    time.sleep(min(poll_interval, remaining))

if "Data Migration Failed" in summary:
    print(f"Boot summary reported failure, but all {len(plugins)} migration plugins succeeded.",
          file=sys.stderr)
PY

# No retries: a flaky UI path must fail its PR check, with the original evidence.
xcodebuild test \
  -project ForkChess.xcodeproj \
  -scheme ForkChessE2E \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -destination-timeout 120 \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -collect-test-diagnostics never \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 240 \
  -maximum-test-execution-time-allowance 360 \
  -resultBundlePath "$output_dir/EndToEnd.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$output_dir/e2e.log"
