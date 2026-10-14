# Project Lessons

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
