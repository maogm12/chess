import UIKit

/// Builds a puzzle by hand using a piece popover anchored to the selected square.
final class PuzzleEditorViewController: UIViewController, UIPopoverPresentationControllerDelegate {
    private let game: GameViewModel
    private let onSaved: (SavedGame) -> Void

    private let board = SetupBoardView()
    private let sideRow = UIView()
    private let sideLabel = chessLabel("You play", size: 13, weight: .semibold, color: ForkChessTheme.slate)
    private let sideControl = UISegmentedControl(items: ["White", "Black"])
    private let hint = chessLabel("", size: 13, color: ForkChessTheme.slate)
    private lazy var clear = chessButton("Clear board", icon: "arrow.counterclockwise") { [weak self] in
        self?.board.clear()
    }
    private lazy var save = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(savePuzzle))

    private let instructions = "Tap a square to set its piece. The side you choose moves first."

    init(game: GameViewModel, onSaved: @escaping (SavedGame) -> Void) {
        self.game = game
        self.onSaved = onSaved
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(game:onSaved:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "New puzzle"
        view.backgroundColor = ForkChessTheme.background
        view.tintColor = ForkChessTheme.accent
        navigationItem.rightBarButtonItem = save

        board.colors = ChessBoardPalette.colors(for: game.settings.boardTheme)
        board.haptics = game.settings.haptics
        board.onChange = { [weak self] in self?.refresh() }
        board.onSelect = { [weak self] index, square in self?.showPieces(at: index, from: square) }

        sideLabel.textAlignment = .left
        sideControl.selectedSegmentIndex = game.settings.playWhite ? 0 : 1
        sideControl.selectedSegmentTintColor = ForkChessTheme.panel
        sideControl.setTitleTextAttributes([.foregroundColor: ForkChessTheme.navy,
                                            .font: UIFont.systemFont(ofSize: 14, weight: .semibold)], for: .selected)
        sideControl.setTitleTextAttributes([.foregroundColor: ForkChessTheme.slate,
                                            .font: UIFont.systemFont(ofSize: 14)], for: .normal)
        sideControl.addAction(UIAction { [weak self] _ in self?.refresh() }, for: .valueChanged)

        hint.numberOfLines = 2

        [sideLabel, sideControl].forEach { sideRow.addSubview($0) }
        [hint, board, sideRow, clear].forEach { view.addSubview($0) }
        refresh()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let margin: CGFloat = 18
        let safe = view.safeAreaLayoutGuide.layoutFrame
        let width = safe.width - margin * 2
        let side = max(140, min(width, 420, safe.height - 160))

        hint.frame = CGRect(x: margin, y: safe.minY + 4, width: width, height: 38)
        board.frame = CGRect(x: safe.midX - side / 2, y: hint.frame.maxY + 12, width: side, height: side)
        sideRow.frame = CGRect(x: margin, y: board.frame.maxY + 14, width: width, height: 34)
        sideLabel.frame = CGRect(x: 0, y: 0, width: 68, height: 34)
        sideControl.frame = CGRect(x: 68, y: 0, width: width - 68, height: 34)
        clear.frame = CGRect(x: margin, y: sideRow.frame.maxY + 12, width: 160, height: 34)
    }

    private var playsWhite: Bool { sideControl.selectedSegmentIndex == 0 }

    private func refresh() {
        guard isViewLoaded else { return }
        board.whiteToMove = playsWhite
        let issue = ChessPosition.issue(in: board.placement, whiteToMove: playsWhite)
        save.isEnabled = issue == nil
        hint.text = ChessPosition.count(board.placement) == 0 ? instructions : issue ?? instructions
        let missingKing = !board.placement.contains("K") || !board.placement.contains("k")
        hint.textColor = issue == nil || missingKing ? ForkChessTheme.slate : UIColor.systemRed.withAlphaComponent(0.85)
    }

    private func showPieces(at index: Int, from square: SetupSquare) {
        guard presentedViewController == nil else { return }
        let picker = PuzzlePiecePickerViewController()
        picker.loadViewIfNeeded()
        picker.palette.configure(squares: board.placement, at: index, whiteToMove: playsWhite)
        picker.squareLabel.text = "\(game.squareLabel(index)) / Choose a piece"
        picker.preferredContentSize = CGSize(width: min(352, view.bounds.width - 24), height: 146)
        picker.modalPresentationStyle = .popover
        picker.palette.onChange = { [weak self, weak picker] choice in
            guard let self, self.board.place(choice, at: index) else { return }
            picker?.dismiss(animated: true)
        }
        if let popover = picker.popoverPresentationController {
            popover.sourceView = square
            popover.sourceRect = square.bounds
            popover.permittedArrowDirections = [.up, .down]
            popover.backgroundColor = ForkChessTheme.background
            popover.delegate = self
        }
        present(picker, animated: true)
    }

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle { .none }

    func adaptivePresentationStyle(for controller: UIPresentationController,
                                   traitCollection: UITraitCollection) -> UIModalPresentationStyle { .none }

    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        board.selectedSquare = nil
    }

    @objc private func savePuzzle() {
        let squares = board.placement
        let playerWhite = playsWhite
        if let issue = ChessPosition.issue(in: squares, whiteToMove: playerWhite) {
            present(message(title: "Finish the position", text: issue), animated: true)
            return
        }
        save.isEnabled = false
        Task {
            do {
                let record = try await game.addPuzzle(fen: ChessPosition.fen(from: squares, whiteToMove: playerWhite),
                                                      playerWhite: playerWhite)
                onSaved(record)
            } catch {
                save.isEnabled = true
                present(message(title: "That position cannot be played", text: error.localizedDescription), animated: true)
            }
        }
    }

    private func message(title: String, text: String) -> UIAlertController {
        let alert = UIAlertController(title: title, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        return alert
    }
}

final class PuzzlePiecePickerViewController: UIViewController {
    let palette = PiecePaletteView()
    let squareLabel = chessLabel(size: 13, weight: .semibold, color: ForkChessTheme.slate)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ForkChessTheme.background
        squareLabel.accessibilityTraits = .header
        [squareLabel, palette].forEach { view.addSubview($0) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaLayoutGuide.layoutFrame
        squareLabel.frame = CGRect(x: safe.minX + 10, y: safe.minY + 6, width: safe.width - 20, height: 22)
        palette.frame = CGRect(x: safe.minX + 10, y: squareLabel.frame.maxY + 4,
                               width: safe.width - 20, height: safe.height - 38)
    }
}
