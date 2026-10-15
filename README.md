# ForkChess

A native UIKit iPhone/iPad chess practice app. The MIT-licensed Arasan engine and its neural network are
included in the app. No account, server, analytics, or internet connection is used.

## Run

Open `ForkChess.xcodeproj`, select the **ForkChess** scheme, choose an iPhone or
iPad simulator, and Run. Requires iOS 17 or later; developed with Xcode 26.6.

For a physical iPhone, select your signing team under Signing & Capabilities and
use the app bundle identifier `com.maogm12.forkchess` (tests use
`com.maogm12.forkchess.tests`). Automatic signing is enabled;
no signing identity or credentials are committed here.

## What works

- Play White or Black against the Arasan bot.
- A large side selector, new-game action, puzzle library, and game-history entry on the home screen.
  Saved games live on a separate History navigation page; opening a game and returning preserves
  the Home → History → Game navigation stack.
  Home cards use the app's own visual language: theme fills, one shared corner radius, serif
  section headings, and no reference-screenshot chrome such as badge chips, stripes, or arrows.
- Flat vector piece art from the `design/chess_pieces` icon set: white pieces use an ivory fill with
  a navy outline, black pieces are solid navy with transparent apertures. The geometry is drawn as
  paths in `ChessPieceArt.swift`, so pieces stay sharp at board size and in the captured-piece trays,
  and the colors come from the app theme.
- Bot skill levels 0–20 (mapped to Arasan strength) and bounded thinking time (0.4, 1, or 2 seconds).
  Settings and the game menu show estimated Elo and the exact current level, including slider
  values between presets. Estimates follow the bundled Arasan `Options::getRating` scale
  (1000–3450, with app skill × 5 as strength); these are not measured human ratings.
  Device and thinking time affect actual play.
- A **Puzzle** library of hand-built endgames. Every puzzle is a tile showing a preview of its
  starting position, the side you play, and its move count. The library and editor are full
  navigation pages. Returning from a puzzle game goes back to the library; saving replaces the
  editor with the game. The first tile opens the editor, where
  you tap an empty or occupied square to open an anchored piece popover. White and black pieces
  occupy two rows, with an eraser alongside them; illegal placements are disabled. Pick whether
  you play White or Black against the bot. The bot also takes the opening move when a saved position
  starts on its turn. Saving stores the position as a normal saved game, so puzzles replay, share, and
  delete like any other game. The app has no photo import: positions are entered by hand.
- Legal destinations, captures, castling, en passant, and all four promotion choices.
  Promotion first previews the pawn on its destination, then opens an icon popover anchored
  to that square. Icons stay centered inside the popover body, clear of its arrow.
  Choosing a piece commits the move; tapping outside cancels and restores the position without
  changing the saved history, including captures and Black's board perspective.
  The preview stays on the destination until the engine accepts the selected promotion.
- Check, checkmate, stalemate, insufficient material, 50-move, and threefold repetition detection.
  In this practice app the 50-move and threefold draws are automatically accepted.
  Selection outlines the square in green without changing its fill; recent moves use a muted
  yellow highlight. Check gives the threatened king a red background; checkmate uses a stronger
  red background with a small cross badge in the upper-right corner. Stalemate uses a calm
  slate-colored pause badge with two vertical bars on the blocked king's square.
  Both markers follow replay and board orientation. A newly played ending triggers haptic
  feedback once when haptics are enabled; reopening, replay, and flipping do not repeat it.
  The game screen has no status/difficulty text row above the board.
- Full-strength hints with board highlights and algebraic notation.
- Undo a turn, resign, flip the board, and start another game.
  Undo preserves the previous continuation as a branch.
- Piece movement animates in both directions, including undo and castling.
  Captured-piece trays follow each side of the board and restore during undo/replay.
  The move list fills the available space above compact bottom controls.
- The board is full-bleed: it spans both screen edges in portrait, with rank numbers 1-8 and
  file letters a-h drawn inside the outer squares instead of a gutter.
  Playing Black or opening a puzzle whose starting FEN has Black to move puts Black at the bottom.
  In that view, ranks occupy the rightmost column and files the top row. Puzzle setup and previews
  follow the same perspective, which stays fixed between moves. Piece art is inset from the
  square edges while tap targets keep their full size.
- The practice title shows a countdown, defaulting to 10 minutes (5/10/15/30
  selectable in Settings). It pauses away from the game, resumes from local
  saves, stops at zero without forcing a result, and resets for each new game.
- Automatic local saves, resume, game history, replay controls, and play against the bot from any recorded position.
  Game history lists every saved game, newest first, puzzles included.
  Tapping a puzzle tile or a saved puzzle in the home history opens it for play and resumes its moves.
- A persistent history tree inside each game, including puzzles. Scroll the move list and tap
  a move during play or review. Selecting a human move reveals a compact **重走** button beside
  that move; selecting a bot move does not. Redo forks immediately before the selected move,
  so the human can replace it while the old continuation remains saved. This also supports
  replacing a checkmating human move. There is no review-position counter, playback button row,
  or full-width continue button; that space belongs to the history list.
  Forks have an inline branch page row below the fork with the selected branch, page count,
  dots, and a visible horizontal swipe cue. Horizontal drags below a fork switch its continuation;
  only rows below that fork move horizontally; the shared moves and the pager stay in place.
  Switching lines preserves the history's vertical scroll position, even for shorter branches.
  Vertical drags scroll the history. Tapping a page dot or choosing a line in the branch menu
  also switches branches. **Latest** returns to the selected line's tip.
  Each branch has one parent; identical positions never merge. Branches retain their own
  moves, ratings, outcome, and timer, and one game occupies one history entry.
  PGN sharing exports the selected line.
- PGN sharing through the system share sheet, only when requested.
- Persistent settings for side, strength, time, colors, coordinates, legal-move markers, and haptics.
- Optional Good / OK / Bad ratings for each new move, saved with games for replay.
  Enable **Settings → Practice feedback → Rate each move**. Ratings use full-strength
  searches from the mover's perspective: up to 0.50 pawns lost is Good, up to 1.50
  is OK, and larger losses are Bad. Searches are bounded estimates (up to 700 ms
  each, depth 12); a best-move search and a search restricted to the played move
  are compared. Forced mate is treated as decisive. Existing unrated moves are
  left unrated. Old saved libraries remain compatible.
- Full-size iPhone launch configuration and layouts that scroll on smaller displays.

Games and settings are stored atomically in Application Support/ForkChess/library.json.
On first use, an existing Application Support/QuietChess/library.json in the same
sandbox is copied to the new path. The original is preserved, and an existing
ForkChess library always takes precedence. The saved-library format is unchanged.
Changing the bundle identifier creates a separate iOS app sandbox, so data belonging
to an installed app with the old identifier cannot be migrated automatically.
The library directory is excluded from device backup. There is no cloud sync.
All playable games use a bot opponent. Old manual-play saves remain in the library as puzzles,
with their positions, moves, results, and chosen player color preserved. Resuming an unfinished
old save gives the opposite side to the bot. Undo returns to the player's last decision, including
positions that start with Black to move; the bot's opening move alone cannot be undone.

## Verification

In Xcode, Product → Test runs the integration tests in `Tests/GameTests.swift`.
They also check the ForkChess app/test bundle identities, PGN branding, and storage
migration, including preservation of history branches and newer saves.
They cover White/Black games, hints, undo, resignation, complete-game results,
storage and settings restoration, history/replay/PGN, promotion, cancellation,
hand-built puzzle setup and validation, add-tile navigation, square popovers and disabled choices,
playable puzzle navigation from both the library and home history, and the iPhone window size.
They also verify bot-only controls, bot openings in Black-start puzzles, undo to the player's
previous decision, and migration of legacy manual-play libraries without losing history.
Tree coverage includes nested forks, earlier forks attaching to ancestors, persistence,
search cancellation during historical navigation, preserved undo routes, native move
selection, inline branch pages, and human-only redo before the selected move, including
Black-start positions and checkmate. Pre-tree libraries load as one main line.
`testPhoneWindowAndRenderScreens` also writes a PNG per screen to the app's `tmp`
directory and prints `REVIEW IMAGE <path>` for a quick visual check.

Hand-built positions are validated in Swift (`ChessPosition.issue`) before the engine sees them,
because Arasan asserts instead of returning an error for a position it considers impossible —
for example one whose side that just moved is still in check. `addPuzzle` throws
`PuzzleError.invalidPosition` instead of taking the app down.

The standalone engine suite can be run on macOS with:

```sh
bash Tests/run-engine-tests.sh
```

It validates starting-position perft (8,902 positions at depth 3), castling,
en passant, promotion, mate, stalemate, draw rules, invalid moves, and 24 engine plies.
Assertions remain enabled in Debug builds.

### GitHub Actions

The **Regression tests** workflow runs on every pull request targeting `main`,
on pushes to `main`, and manually from the Actions tab. Separate jobs run the
engine suite and all simulator integration tests on an ARM64 `macos-26` runner
with Xcode 26.6. The simulator job selects an available iPhone from the latest
installed iOS runtime and disables code signing. No signing credentials are needed.

Each run keeps its logs, the `.xcresult` bundle, and exported XCTest image
attachments as downloadable artifacts for 14 days, including on test failures.
Screenshot attachments show the screens rendered by the tests; they are not
automatic visual comparisons. PRs fixing UI issues should still include screenshots
of the affected behavior in their descriptions.

To run the same simulator suite locally on an ARM64 Mac:

```sh
bash Tests/run-ios-tests.sh
```

Results go to `build/ci`. To repeat a local run, pass a fresh output directory,
for example `bash Tests/run-ios-tests.sh build/ci-next`.

## Structure

- `ChessApp.swift`: UIKit application/scene delegates and background lifecycle.
- `HomeViewController.swift`: side selection, new game, and entry points for Puzzle and History.
- `GameViewController.swift`: game controls, countdown, move list, and replay.
- `PuzzleViewController.swift`: the puzzle library, its tiles, and the tile that opens the editor.
- `PuzzleEditorViewController.swift`: hand-built positions, square popovers, and side selection.
- `PuzzleViews.swift`: setup board/palette controls and the position thumbnails used by puzzle tiles.
- `ChessPosition.swift`: FEN conversion, position validation, and attack checks for hand-built setups.
- `HistoryViewController.swift`: every saved game, deletion, and PGN sharing.
- `SettingsViewController.swift`: native settings controls and engine license.
- `UIKitSupport.swift`: theme, shared UIKit components, and model subscriptions.
- `ChessPieceArt.swift`: vector piece geometry converted from the `design/chess_pieces` SVGs.
- `GameViewModel.swift`: game lifecycle, save library, replay, and request invalidation.
- `ChessBoardView.swift`: oriented board, pieces, selection, legal targets, and highlights.
- `ArasanEngine.swift`: serial Swift actor, native snapshots and bounded searches.
- `ArasanBridge.mm`: required engine initialization, move rules, SAN, results, search.
- `design/chess_design.png`: visual reference.

The theme follows the ForkChess reference with native controls adapted to the device.
The artwork for the icon is generated by `swift scripts/render-icon.swift`.

## Engine (Arasan, MIT)

Upstream source and the matching NNUE network are vendored, pinned to revision
`1ed18c14fadded300f0d8888ada0a8ffa644708e` (v26.0).
See `THIRD_PARTY.md` and `ChessApp/Vendor/Arasan/LICENSE-Arasan.txt`.
The app's Settings includes the engine license.
