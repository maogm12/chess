# Arasan

Source: https://github.com/jdart1/arasan-chess

Pinned revision: 1ed18c14fadded300f0d8888ada0a8ffa644708e (upstream v26.0)

Syzygy probing code (compiled in but unused without tablebase files):
https://github.com/jdart1/Fathom at c9c6fef0dddc05d2e242c183acf5833149ab676d

Bundled neural network: arasanv8-20260906.nnue (from the Arasan archive's
`network/` directory)

Arasan is licensed under the MIT License (Copyright 1994-2026 Jon Dart).
The license is in ChessApp/Vendor/Arasan/LICENSE-Arasan.txt and is
accessible in the app's Settings. The engine runs in-process (single
thread, no opening book, no tablebases) and has no online service
dependency.

Vendored files are the upstream `src/*.cpp/*.h` set plus `src/nnue/`,
`src/syzygy/` and `src/bitbase.cpp` (the latter is textually included by
`globals.cpp` and is not built separately). The build defines
`SIMD`/`NEON`/`_64BIT`/`SYZYGY_TBS` (same backend selection as the
upstream Apple build); on Intel Macs replace `NEON` with `SSE2`.
