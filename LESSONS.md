# Project Lessons

Read this file before changing code. These initial lessons summarize constraints
documented in the repository and visible in the implementation, rather than
claiming a newly investigated incident. Add future lessons only with evidence.

## Validate puzzle positions before calling the native engine

- Cause: Arasan asserts on impossible positions, including a position in which
  the side that just moved remains in check.
- Prevention: Keep Swift position validation ahead of native engine calls.
  Reject invalid puzzle input with `PuzzleError.invalidPosition`.
- Evidence: `README.md` (Verification), `ChessApp/ChessPosition.swift`,
  and `GameViewModel.addPuzzle` in `ChessApp/GameViewModel.swift`.
- Verification: `testPuzzleSetupRejectsIllegalPositions` and
  `testPuzzleSetupValidationAndPlay` in `Tests/GameTests.swift`.

## Ignore engine results from an obsolete game or history selection

- Cause: A bounded engine search may finish after the user starts another game,
  undoes a turn, or navigates to a historical position.
- Prevention: Preserve serial native-engine ownership and the view model's
  generation checks around asynchronous results, including hints and ratings.
  Cancellation alone does not establish that a result belongs to current state.
- Evidence: `ChessApp/ArasanEngine.swift` and the `generation` checks in
  `ChessApp/GameViewModel.swift`.
- Verification: Relevant cancellation/history tests in `Tests/GameTests.swift`,
  including `testRatingPersistenceUndoCancellationAndLegacyLibrary`.

## Preserve history branches and compatibility with older saves

- Cause: Equal board positions can belong to different continuations, and old
  libraries predate the tree representation and bot-only play.
- Prevention: Do not merge history nodes by board position. Preserve branch
  moves, ratings, outcomes, and timers. Keep migrations compatible with existing
  saves and preserve the player's color and history.
- Evidence: `README.md` (history tree, legacy saves, and Verification).
- Verification: `testNestedForksAndAncestorForksFormATreeWithoutMerging`,
  `testNestedBranchSwipeAndUndoPreserveOriginalLines`, and
  `testLegacyManualSavesBecomeBotPuzzlesWithoutLosingHistory` in
  `Tests/GameTests.swift`.

## Keep test scripts compatible with the macOS system Bash

- Date and symptom: On 2026-10-14, the first GitHub Actions engine regression
  run stopped before compilation with `SYSROOT[@]: unbound variable`.
- Cause: `Tests/run-engine-tests.sh` expanded an empty array with `set -u`.
  The macOS runner's system Bash 3.2 treats that expansion as an unset variable.
- Prevention: Use an explicit SDK path for the compiler sysroot rather than an
  optional empty argument array in scripts executed by `/bin/bash` on macOS.
- Evidence: Run `38621507437`, artifact `engine-regression-1/engine.log`.
- Verification: The initial cloud run reproduced the failure. The updated
  script passed the full engine suite under Bash 3.2.57 locally and in the
  engine job of GitHub Actions run `38622610066` (commit `56a20d7`).

## Share FEN placement decoding while preserving engine piece identities

- Date and problem: On 2026-10-14, maintenance found duplicate FEN rank/file
  decoding in `GameViewModel.accept` and `ChessPosition.squares(from:)`. Gameplay
  and puzzle previews maintained separate implementations of the same board order.
- Cause: Gameplay decoded placement inline while attaching native piece IDs;
  puzzle code already used the shared character-array decoder.
- Prevention: Use `ChessPosition.squares(from:)` for placement decoding, then
  attach `PositionSnapshot.pieceIDs[index]` to occupied squares in gameplay.
  Do not replace engine identities with square indices: pieces retain their IDs
  when moving, which is required for movement animations and undo.
- Evidence: `ChessApp/GameViewModel.swift` (`accept`),
  `ChessApp/ChessPosition.swift` (`squares(from:)`), and
  `ChessApp/PuzzleViews.swift` (`PuzzleThumbnail.image`).
- Verification: The simulator build and all six selected existing integration
  tests passed on iPhone 17 Pro / iOS 26.5: piece identities and captured trays
  through undo, all promotion choices and stalemate, puzzle setup/play, Black
  perspective and puzzle setup, history/replay/PGN/persistence, and check/mate
  markers during replay. The full suite was not run for this scoped refactor.

## Adding or updating a lesson

Use a short descriptive heading and record:

- Date and the concrete symptom or maintenance problem.
- Confirmed cause, with file/symbol references and a PR or commit when available.
- The specific rule that prevents recurrence and when it applies.
- Actual verification, including any limitations.

Prefer updating a related entry. Keep run logs in the automation's memory;
this file is for reusable project knowledge.
