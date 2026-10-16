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
xcrun simctl list devices available --json > "$output_dir/simulators.json"
selection="$(python3 - "$output_dir/simulators.json" "$family" <<'PY'
import json
import sys

with open(sys.argv[1]) as source:
    devices = json.load(source)["devices"]
family = sys.argv[2]
candidates = []
for runtime, entries in devices.items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(int(part) for part in runtime.split(".iOS-")[1].split("-"))
    for device in entries:
        if device.get("isAvailable") and device["name"].startswith(family):
            preferred = device["name"] in ("iPhone 17 Pro", "iPad mini (A17 Pro)")
            candidates.append((version, preferred, runtime, device))
if not candidates:
    sys.exit(f"No available {family} simulator. Install an iOS runtime in Xcode.")
_, _, runtime, device = max(candidates, key=lambda item: (item[0], item[1]))
print(device["deviceTypeIdentifier"])
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

# No retries: a flaky UI path must fail its PR check, with the original evidence.
xcodebuild test \
  -project ForkChess.xcodeproj \
  -scheme ForkChessE2E \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -destination-timeout 120 \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 240 \
  -maximum-test-execution-time-allowance 360 \
  -resultBundlePath "$output_dir/EndToEnd.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$output_dir/e2e.log"
