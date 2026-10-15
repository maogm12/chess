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

## Show exact slider strength when a menu offers presets

- Date and symptom: 2026-10-14, issue #10. Bot strength menus had no checkmark
  at the default level 5 because their shortcuts use levels 2/6/11/16/20.
  Settings and game menus also omitted the engine's estimated Elo scale.
- Cause: Menu selection compared only exact preset values and shared no builder
  with Settings' strength display.
- Prevention: Share the menu builder, keep exact slider values, and add one
  selected current-level entry when the current value is between presets.
  Mark Elo as approximate and derive it from bundled Arasan's
  `Options::getRating` and the app bridge's skill × 5 mapping. Do not present
  the scale as measured human performance at this device/time control.
- Evidence: `botStrengthMenu` in `UIKitSupport.swift`, `PracticeSettings` in
  `GameViewModel.swift`, `ArasanBridge.mm` search strength mapping and vendored
  `src/options.h` rating scale (1000–3450).
- Verification: `testStrengthMenusDescribeEloAndExactCurrentLevel` checks all
  21 levels for exactly one selected entry, preset Elo values, both menus and
  preservation through settings encoding. Native simulator captures show the
  actual opened menu; no empirical human rating calibration was performed.

## Adding or updating a lesson

Use a short descriptive heading and record:

- Date and the concrete symptom or maintenance problem.
- Confirmed cause, with file/symbol references and a PR or commit when available.
- The specific rule that prevents recurrence and when it applies.
- Actual verification, including any limitations.

Prefer updating a related entry. Keep run logs in the automation's memory;
this file is for reusable project knowledge.

## Keep icon regeneration aligned with the approved artwork

- Date and problem: On 2026-10-14, the supplied light and dark app icons replaced
  a generated knight glyph, but `scripts/render-icon.swift` still drew the old art.
- Cause: The generated asset alone did not preserve the approved source artwork.
- Prevention: Keep both originals in `design/app-icon-light.jpg` and
  `design/app-icon-dark.jpg`, and resize them through `scripts/render-icon.swift`.
  Keep the dark appearance assigned in the app icon catalog.
- Verification: The simulator build passed. Compiled catalog inspection confirmed
  opaque 1024x1024 default and dark icons; regenerating preserved both PNG hashes.
  No physical device or full integration suite was tested for this asset change.

## Snapshot game settings instead of reading mutable new-game defaults

- Date and symptom: On 2026-10-14, the board's bot menu wrote directly to
  `PracticeSettings`, so changing one game also changed other games and defaults.
- Cause: Engine searches, move ratings and fork timers read shared settings;
  `SavedGame` had no independent bot or feedback configuration.
- Prevention: Store `GameSettings` in `SavedGame.configuration`. Snapshot defaults
  when creating a game or puzzle, and migrate all legacy games with their library's
  defaults before those defaults can change. Use that game's configuration for
  searches, feedback and new-fork duration. Keep board appearance and haptics global.
  A search or rating retains the settings captured when its move began.
  When moving the board's settings entry into a direct toolbar button (issue #16),
  keep `presentSettings(scope: .currentGame)` rather than the global default.
  Toolbar sharing should use a `UIBarButtonItem` popover anchor; list sharing
  continues to anchor to its source view.
- Evidence: `GameViewModel.updateGameSettings`, `prepareGameSettings`,
  `replyIfNeeded`, `rateMove`, and the scope in `SettingsViewController`.
- Verification: All 38 integration tests passed on iPhone 17 Pro / iOS 26.5.
  New tests cover defaults and game isolation, editing a reviewed game while
  another is active, persistence, legacy migration and branch timer preservation.
  Existing search invalidation coverage also changes game settings during search.
  Settings and Game settings screenshots were visually inspected.
  Integrating PR #15's Elo menu required passing the scoped preferences through
  the shared menu builder and routing selection through the scoped update method;
  binding it to `game.settings` would restore the original cross-game mutation.
  `testGameToolbarOpensScopedSettingsAndAnchoredShareDirectly` additionally
  exercises the direct settings action, edits its slider without changing defaults,
  and checks the share controller's bar-item anchor and unchanged game/orientation.
  After merging PRs #13/#14/#15, all 41 tests passed, including exact strength
  selection at every level, stable history heights and empty-branch gestures.

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

## Reserve redo space before selecting a history move

- Date and symptom: 2026-10-14, issue #11. Selecting a human move grew its
  history row from 32 to 40 points and shifted every following row.
- Cause: `GameViewController.tableView(_:heightForRowAt:)` based unrated row
  height on `redoPly`, although selection should only reveal an inline action.
- Prevention: Reserve the 40-point redo height for every unrated move row.
  Keep rated rows at 54 points for their second line, independently of selection.
  Preserve the human-only redo condition in the cell configuration.
- Verification: `testHistoryRowsKeepRedoHeightAcrossSelection` compares complete
  row frames across human/bot selection and returning to the latest position,
  checks redo visibility, and checks rated rows separately. UIWindow captures
  document the unselected and selected layouts; frame assertions establish
  layout stability that still images alone cannot prove.

## Refresh derived drawing state when system appearance changes

- Date and symptom: On 2026-10-14, adding dark appearance exposed fixed white
  surfaces, a navigation title retaining its light-mode ink, stale layer borders,
  and puzzle thumbnails that did not account for the current appearance.
- Cause: The app forced light appearance. Dynamic UIColor alone does not refresh
  CGColor assignments, rendered bitmap caches, custom drawing, or the resolved
  title attributes retained by UINavigationBarAppearance. Sharing the text color
  with black-piece ink would also turn black pieces pale in dark appearance.
- Prevention: Keep semantic UI colors dynamic, keep piece identity colors fixed,
  and refresh derived state on trait changes. Resolve navigation appearance and
  border colors with the owning view's traits; redraw artwork and board squares.
  Include appearance, scale, palette and perspective in thumbnail cache keys,
  and render with those traits. Choose coordinate ink by square contrast.
  Keep filled controls and ending badges dark enough for white text, thumbs and
  symbols; a pale text accent is not a suitable fill.
- Evidence: `ForkChessTheme`, `ChessNavigationController` and UIView helpers in
  `UIKitSupport.swift`, `ChessPiecePalette` in `ChessPieceArt.swift`,
  `PuzzleThumbnail` in `PuzzleViews.swift`, and `PuzzleTile` in
  `PuzzleViewController.swift`.
- Verification: All 45 integration tests passed on iPhone 17 Pro / iOS 26.5.
  New tests check contrast, fixed piece identities, appearance-aware thumbnails,
  and light/dark/light switching on the same screen instances, including border
  and preview refresh while preserving saved game state. UIWindow screenshots
  of the dark home, game, settings, puzzle library and editor were inspected.
  Both existing anchored-popover tests also passed with the simulator set to
  system dark appearance.

## Blend board highlights over an opaque square

- Date and symptom: On 2026-10-14, dark-mode screenshot review showed last-move
  highlights as dark brown squares instead of translucent yellow over the board.
- Cause: `BoardSquare.draw` used UIRectFill for both the base and overlays.
  Its copy blend mode replaced the opaque base with a translucent color.
- Prevention: Fill the base once, then use UIRectFillUsingBlendMode with `.normal`
  for translucent overlays. Keep the resulting board square opaque.
- Evidence: `BoardSquare.draw` in `ChessBoardView.swift`.
- Verification: `testBoardHighlightsBlendWithBothAppearances` samples actual
  rendered pixels against the expected source-over color and alpha in both
  appearances. It passed in the full 45-test suite; the corrected dark game
  screenshot shows the board beneath the yellow highlight.
