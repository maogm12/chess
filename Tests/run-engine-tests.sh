#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/forkchess-tests.XXXXXX)
# Prefer the Xcode toolchain, but fall back to the Command Line Tools copy
# when the Xcode license gate blocks xcrun (no sudo in this environment).
if xcrun clang++ --version >/dev/null 2>&1; then
  CXX="xcrun clang++"
  SYSROOT="$(xcrun --sdk macosx --show-sdk-path)"
else
  CXX="/Library/Developer/CommandLineTools/usr/bin/clang++"
  SYSROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
fi
sources=()
# bitbase.cpp is textually included by globals.cpp; tbprobe.c is C (also
# accepted by clang++ here) so it is appended separately below.
while IFS= read -r source; do sources+=("$source"); done < <(rg --files ChessApp/Vendor/Arasan/src -g '*.cpp' | rg -v 'bitbase\.cpp$')
$CXX -std=c++17 -O2 -isysroot "$SYSROOT" -IChessApp/Vendor/Arasan/src -IChessApp/Vendor/Arasan/src/nnue \
    -DSIMD -DNEON -D_64BIT -DSYZYGY_TBS -DNETWORK=arasanv8-20260906.nnue -fobjc-arc \
    -framework Foundation Tests/EngineTests.mm ChessApp/ArasanBridge.mm \
    "${sources[@]}" ChessApp/Vendor/Arasan/src/syzygy/src/tbprobe.c \
    -o "$test_dir/engine-tests"
"$test_dir/engine-tests" "$PWD/ChessApp/Vendor/Arasan"
