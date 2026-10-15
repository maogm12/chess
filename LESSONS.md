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
  When integrating other `accept` changes, retain request-local cleanup such
  as clearing `pendingPromotion` after the new board is accepted. PR #5's
  merge with this refactor conflicted at that cleanup; replacing the whole
  acceptance block would leave the completed promotion preview active.
- Evidence: `ChessApp/GameViewModel.swift` (`accept`),
  `ChessApp/ChessPosition.swift` (`squares(from:)`), and
  `ChessApp/PuzzleViews.swift` (`PuzzleThumbnail.image`).
- Verification: The simulator build and all six selected existing integration
  tests passed on iPhone 17 Pro / iOS 26.5: piece identities and captured trays
  through undo, all promotion choices and stalemate, puzzle setup/play, Black
  perspective and puzzle setup, history/replay/PGN/persistence, and check/mate
  markers during replay. The full suite was not run for this scoped refactor.

## Keep promotion previews alive until the engine accepts the move

- Date and symptom: 2026-10-14, issue #1 / PR #5. Selecting a promotion
  briefly returned the pawn to its source and restored a captured piece.
- Cause: `GameViewModel.play(_:)` cleared `promotions` before awaiting the
  serial engine, while `ChessBoardView.update` used only the picker choices
  to decide whether to display the destination preview.
- Prevention: Keep pending display state separate from picker choices and
  saved moves. Clear it after accepting the new board, on request invalidation,
  or on a current-request failure. An obsolete engine response must not clear
  the current request's preview. See `pendingPromotion`, `accept`, `invalidate`,
  and `fail` in `ChessApp/GameViewModel.swift`, and `ChessBoardView.update`.
- Verification: The promotion popover regression failed eight destination
  assertions before the fix, for both colors. After the fix, all 31 integration
  tests passed on iPhone 17 Pro / iOS 26.5, including pending capture display,
  cancellation, saved promotion, and new-game invalidation. Synchronous UIKit
  window-layer captures show pending layout; assertions verify behavior across
  engine acceptance. No physical device was tested.

## Keep popover controls inside the body safe area

- Date and symptom: 2026-10-14, PR #5 feedback. Promotion icons overlapped
  the popover's top edge and sat above its vertical center.
- Cause: `PromotionPickerViewController` pinned the choices to the root view
  at y=8, although UIKit's top-arrow safe area began at y=13. A second Cancel
  row also shifted the icons above the center of the body.
- Prevention: Anchor popover content to `view.safeAreaLayoutGuide`, with
  symmetric body padding, rather than the bounds that include the arrow.
  Keep the picker responsible for its content size. Outside dismissal uses
  `GameViewController.popoverPresentationControllerDidDismissPopover` to
  restore the preview; no additional Cancel row is needed for this picker.
- Verification: The unchanged picker failed 18 geometry/Cancel assertions
  across both colors. The corrected source built and passed all 33 integration
  tests on a dedicated iPhone 17 Pro / iOS 26.5 simulator with Xcode 27.0.
  `testPromotionPickerLayoutClearsEitherArrow` forces both arrow directions
  and checks safe-area containment, centering, and tappable heights;
  `testPromotionPopoverPreviewsDestinationAndRestoresOnCancel` covers both
  colors, flipped boards, cancellation callback, saved moves and pending
  display. Real UIWindow captures show the before/after layouts. Cancellation
  is exercised via the UIKit delegate callback, not an automated screen tap;
  no physical device or full animation recording was tested.

## Adding or updating a lesson

Use a short descriptive heading and record:

- Date and the concrete symptom or maintenance problem.
- Confirmed cause, with file/symbol references and a PR or commit when available.
- The specific rule that prevents recurrence and when it applies.
- Actual verification, including any limitations.

Prefer updating a related entry. Keep run logs in the automation's memory;
this file is for reusable project knowledge.

## Renaming the app identifier creates a new data container

- Date and problem: On 2026-10-14, Quiet Chess was renamed to ForkChess, with
  bundle identifiers moving from `com.example.localchess` to
  `com.maogm12.forkchess` and `...forkchess.tests`.
- Cause: iOS keys an app's sandbox to its bundle identifier, so renaming it
  installs alongside the old build and reads an empty Application Support
  directory. The in-sandbox directory name (`QuietChess`) is also part of the
  storage path but can be migrated by copying once.
- Prevention: Keep `GameViewModel.libraryURL(in:)` tolerant of the legacy
  directory by copying `QuietChess/library.json` into `ForkChess/` only when the
  new file is absent, and never overwrite an existing ForkChess library.
  Directory renames inside one sandbox can migrate data; bundle-identifier
  changes cannot, so document that path for users with the old app installed.
- Evidence: `ChessApp/GameViewModel.swift` (`libraryURL(in:)`), `README.md`
  (Run and storage sections), and `ForkChess.xcodeproj/project.pbxproj`
  (`PRODUCT_BUNDLE_IDENTIFIER`).
- Verification: `testForkChessIdentityAndPGNBranding` and
  `testRenamedLibraryPreservesLegacyGamesAndNeverOverwritesNewerSaves` pass
  inside the full suite, 35 tests on iPhone 17 Pro / iOS 26.5 locally and in
  GitHub Actions run `38637299742`. The built `ForkChess.app` reports
  `CFBundleIdentifier com.maogm12.forkchess` and
  `CFBundleDisplayName ForkChess`, and the CI screenshot of the home screen
  shows the ForkChess wordmark.

## Give branch swipes the whole continuation region

- Date and symptom: 2026-10-14, issue #12. Rightward drags in an empty branch
  continuation could leave the game instead of switching branches.
- Cause: `GameViewController.branchPoint(at:)` required a populated table row.
  It returned nil for blank space below the fork; the horizontal history pan
  also had no precedence over navigation's interactive back gestures.
- Prevention: Resolve ownership from rendered fork boundaries, including blank
  space and scroll offsets. Let both edge and iOS 26 content-pop gestures wait
  for the history pan's direction/region decision using its gesture delegate.
  Do not replace UIKit's internal navigation delegate or disable back globally.
  Vertical drags and shared rows remain outside horizontal paging; actual
  switching still observes `pageBranch` readiness/busy guards.
- Verification: `testEmptyBranchContinuationOwnsHistorySwipes` covers an empty
  two-line fork, horizontal/vertical ownership, shared rows, both system pop
  recognizers, branch round trips and explicit navigation. Existing nested
  branch, partial drag and scroll-position tests cover populated continuations.
