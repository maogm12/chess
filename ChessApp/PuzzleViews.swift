import UIKit

/// What a tap on the setup board writes into a square.
enum PaletteChoice: Equatable {
    case eraser
    case piece(Character)
}

/// One square of the puzzle setup board. It paints its own color, piece, and coordinate hint so a
/// half-filled editor needs no subview bookkeeping.
final class SetupSquare: UIControl {
    enum Hint: Equatable {
        case topLeading
        case topTrailing
        case bottomTrailing
    }

    var baseColor: UIColor = .white { didSet { setNeedsDisplay() } }
    var glyph: (kind: Character, isWhite: Bool)? { didSet { setNeedsDisplay() } }
    var hints: [(text: String, corner: Hint)] = [] { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        redrawOnAppearanceChange()
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func draw(_ rect: CGRect) {
        baseColor.setFill()
        UIRectFill(bounds)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        if let glyph {
            ChessPieceArt.draw(kind: glyph.kind, isWhite: glyph.isWhite,
                               in: ChessBoardLayout.pieceFrame(in: bounds), context: context)
        }
        let size = max(8, min(11, bounds.height * 0.24))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: ChessBoardPalette.coordinateColor(on: baseColor, traits: traitCollection)
        ]
        let inset = max(2, min(bounds.width, bounds.height) * 0.07)
        for hint in hints {
            let text = hint.text as NSString
            let box = text.size(withAttributes: attributes)
            switch hint.corner {
            case .topLeading:
                text.draw(at: CGPoint(x: inset, y: inset), withAttributes: attributes)
            case .topTrailing:
                text.draw(at: CGPoint(x: bounds.maxX - box.width - inset, y: inset), withAttributes: attributes)
            case .bottomTrailing:
                text.draw(at: CGPoint(x: bounds.maxX - box.width - inset, y: bounds.maxY - box.height - inset),
                          withAttributes: attributes)
            }
        }
    }
}

/// A board you fill in by hand: tap a square to choose its piece.
final class SetupBoardView: UIView {
    private let grid = UIView()
    private var squares = [Character](repeating: ChessPosition.empty, count: 64)
    private var cells: [SetupSquare] = []

    var colors = ChessBoardPalette.colors(for: "Slate") { didSet { refresh() } }
    var selectedSquare: Int? { didSet { refresh() } }
    var whiteToMove = true {
        didSet {
            guard whiteToMove != oldValue else { return }
            refresh()
            setNeedsLayout()
        }
    }
    var haptics = true
    var onChange: (() -> Void)?
    var onSelect: ((Int, SetupSquare) -> Void)?

    var placement: [Character] { squares }

    override init(frame: CGRect) {
        super.init(frame: frame)
        grid.layer.cornerRadius = 5
        grid.clipsToBounds = true
        grid.layer.borderWidth = 0.5
        grid.setThemeBorderColor(ForkChessTheme.line)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (board: SetupBoardView, _: UITraitCollection) in
            board.refresh()
        }
        addSubview(grid)
        for index in 0..<64 {
            let cell = SetupSquare()
            cell.addAction(UIAction { [weak self, weak cell] _ in
                guard let self, let cell else { return }
                self.selectedSquare = index
                self.onSelect?(index, cell)
            }, for: .touchUpInside)
            grid.addSubview(cell)
            cells.append(cell)
        }
        refresh()
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width, bounds.height)
        grid.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        for index in 0..<64 {
            cells[index].frame = ChessBoardLayout.squareFrame(index, side: side, whiteAtBottom: whiteToMove)
        }
    }

    func clear() {
        selectedSquare = nil
        squares = [Character](repeating: ChessPosition.empty, count: 64)
        refresh()
        onChange?()
    }

    @discardableResult
    func place(_ choice: PaletteChoice, at index: Int) -> Bool {
        guard squares.indices.contains(index) else { return false }
        switch choice {
        case .eraser: squares[index] = ChessPosition.empty
        case .piece(let piece):
            guard ChessPosition.canPlace(piece, at: index, in: squares, whiteToMove: whiteToMove) else { return false }
            squares[index] = piece
        }
        if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        selectedSquare = nil
        refresh()
        onChange?()
        return true
    }

    private func refresh() {
        for index in 0..<64 {
            let file = index % 8
            let rank = index / 8
            let cell = cells[index]
            cell.baseColor = colors[(rank + file).isMultiple(of: 2) ? 1 : 0]
            cell.glyph = ChessPosition.piece(squares[index])
            var hints: [(text: String, corner: SetupSquare.Hint)] = []
            if file == 0 {
                hints.append(("\(rank + 1)", whiteToMove ? .topLeading : .topTrailing))
            }
            if rank == 0 {
                hints.append((String(UnicodeScalar(97 + file)!), whiteToMove ? .bottomTrailing : .topLeading))
            }
            cell.hints = hints
            let coordinate = String(UnicodeScalar(97 + file)!) + String(rank + 1)
            let name = ChessPosition.piece(squares[index]).map {
                ($0.isWhite ? "White " : "Black ") + BoardPiece(id: index, kind: $0.kind, isWhite: $0.isWhite).name
            } ?? "Empty square"
            cell.accessibilityLabel = "\(coordinate), \(name)"
            cell.accessibilityTraits = selectedSquare == index ? [.button, .selected] : .button
            cell.layer.borderColor = ForkChessTheme.accent.resolvedColor(with: traitCollection).cgColor
            cell.layer.borderWidth = selectedSquare == index ? 2 : 0
            cell.layer.zPosition = selectedSquare == index ? 1 : 0
            cell.setNeedsDisplay()
        }
    }
}

/// The two-row picker inside the square's popover, with an eraser beside the pieces.
final class PiecePaletteView: UIView {
    private final class Cell: UIControl {
        let glyph = ChessPieceArtworkView(frame: .zero)
        let eraser = UIImageView(image: UIImage(systemName: "eraser"))
        var chosen = false { didSet { refresh() } }
        override var isEnabled: Bool {
            didSet {
                alpha = isEnabled ? 1 : 0.25
                refresh()
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            layer.cornerRadius = 8
            layer.cornerCurve = .continuous
            eraser.tintColor = ForkChessTheme.slate
            eraser.contentMode = .scaleAspectFit
            [glyph, eraser].forEach { $0.isUserInteractionEnabled = false; addSubview($0) }
            setThemeBorderColor(ForkChessTheme.accent)
            refresh()
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

        override func layoutSubviews() {
            super.layoutSubviews()
            glyph.frame = bounds.insetBy(dx: 4, dy: 4)
            eraser.frame = bounds.insetBy(dx: bounds.width * 0.28, dy: bounds.height * 0.28)
        }

        private func refresh() {
            backgroundColor = chosen ? ForkChessTheme.panel : .clear
            layer.borderWidth = chosen ? 1.5 : 0
            accessibilityTraits = chosen ? [.button, .selected] : .button
            if !isEnabled { accessibilityTraits.insert(.notEnabled) }
        }
    }

    private var cells: [Cell] = []
    var onChange: ((PaletteChoice) -> Void)?

    private static let choices: [PaletteChoice] = [
        .piece("K"), .piece("Q"), .piece("R"), .piece("B"), .piece("N"), .piece("P"),
        .piece("k"), .piece("q"), .piece("r"), .piece("b"), .piece("n"), .piece("p"),
        .eraser
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        for item in Self.choices {
            let cell = Cell(frame: .zero)
            cell.isAccessibilityElement = true
            switch item {
            case .eraser:
                cell.glyph.isHidden = true
                cell.accessibilityLabel = "Eraser"
            case .piece(let piece):
                cell.eraser.isHidden = true
                cell.glyph.kind = Character(piece.lowercased())
                cell.glyph.isWhite = piece.isUppercase
                cell.accessibilityLabel = (piece.isUppercase ? "White " : "Black ") + BoardPiece(id: 0, kind: piece, isWhite: piece.isUppercase).name
            }
            cell.addAction(UIAction { [weak self, weak cell] _ in
                guard cell?.isEnabled == true else { return }
                self?.onChange?(item)
            }, for: .touchUpInside)
            addSubview(cell)
            cells.append(cell)
        }
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let spacing: CGFloat = 4
        let size = (bounds.width - spacing * 6) / 7
        for (index, cell) in cells.enumerated() {
            let column = CGFloat(index == 12 ? 6 : index % 6)
            let y = index == 12 ? (size + 8) / 2 : CGFloat(index / 6) * (size + 8)
            cell.frame = CGRect(x: column * (size + spacing), y: y, width: size, height: size)
        }
    }

    func configure(squares: [Character], at index: Int, whiteToMove: Bool) {
        for (offset, choice) in Self.choices.enumerated() {
            let cell = cells[offset]
            switch choice {
            case .eraser:
                cell.isEnabled = true
                cell.chosen = false
            case .piece(let piece):
                cell.isEnabled = ChessPosition.canPlace(piece, at: index, in: squares, whiteToMove: whiteToMove)
                cell.chosen = squares[index] == piece
            }
        }
    }
}

/// Draws a saved position as a small board image for the puzzle tiles.
enum PuzzleThumbnail {
    private static var cache: [String: UIImage] = [:]

    static func image(fen: String, side: CGFloat, colors: [UIColor], whiteAtBottom: Bool,
                      traits: UITraitCollection = .current) -> UIImage {
        let colors = colors.map { $0.resolvedColor(with: traits) }
        let key = "\(fen)|\(whiteAtBottom)|\(side)|\(traits.userInterfaceStyle.rawValue)|\(traits.displayScale)|\(colors.map(\.description).joined(separator: ","))"
        if let cached = cache[key] { return cached }
        let squares = ChessPosition.squares(from: fen)
        let format = UIGraphicsImageRendererFormat(for: traits)
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            traits.performAsCurrent {
                for index in 0..<64 {
                    let file = index % 8
                    let rank = index / 8
                    let rect = ChessBoardLayout.squareFrame(index, side: side, whiteAtBottom: whiteAtBottom)
                    colors[(rank + file).isMultiple(of: 2) ? 1 : 0].setFill()
                    UIRectFill(rect)
                    guard let piece = ChessPosition.piece(squares[index]) else { continue }
                    ChessPieceArt.draw(kind: piece.kind, isWhite: piece.isWhite,
                                       in: ChessBoardLayout.pieceFrame(in: rect),
                                       context: context.cgContext)
                }
            }
        }
        cache[key] = image
        return image
    }
}
