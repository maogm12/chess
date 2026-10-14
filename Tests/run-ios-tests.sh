#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$(uname -m)" != arm64 ]; then
  echo "The Arasan NEON build requires an ARM64 Mac." >&2
  exit 1
fi

output_dir="${1:-build/ci}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
if [ -e "$output_dir/Regression.xcresult" ]; then
  echo "Choose a fresh output directory; Regression.xcresult already exists." >&2
  exit 1
fi

xcodebuild -version
xcrun simctl list devices available --json > "$output_dir/simulators.json"
simulator_id="$(python3 - "$output_dir/simulators.json" <<'PY'
import json
import sys

with open(sys.argv[1]) as source:
    devices = json.load(source)["devices"]
candidates = []
for runtime, entries in devices.items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(int(part) for part in runtime.split(".iOS-")[1].split("-"))
    for device in entries:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            candidates.append((version, device["name"] == "iPhone 17 Pro", device))
if not candidates:
    sys.exit("No available iPhone simulator. Install an iOS runtime in Xcode.")
_, _, selected = max(candidates, key=lambda entry: (entry[0], entry[1]))
print(f"Testing on {selected['name']} ({selected['udid']})", file=sys.stderr)
print(selected["udid"])
PY
)"

# Keep the hosted UIKit tests in one simulator; they manipulate app windows.
xcodebuild test \
  -project ForkChess.xcodeproj \
  -scheme ForkChess \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -parallel-testing-enabled NO \
  -resultBundlePath "$output_dir/Regression.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$output_dir/ios.log"
