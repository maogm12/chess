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
