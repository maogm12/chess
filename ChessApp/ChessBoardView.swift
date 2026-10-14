import UIKit

final class ChessBoardView: UIView {
    private let game: GameViewModel
    private let grid = UIView()
    private var squares: [BoardSquare] = []
    private var rankLabels: [UILabel] = []
    private var fileLabels: [UILabel] = []
    private var pieceViews: [Int: ChessPieceView] = [:]
    private var placements: [Int: Int] = [:]
    private var recordID: UUID?
    private let arrow = CAShapeLayer()
    private let endingMarker = BoardEndingMarker()
    private var endingSquare: Int?

    init(game: GameViewModel) {
        self.game = game
        super.init(frame: .zero)
        grid.layer.cornerRadius = 5
        grid.clipsToBounds = true
        grid.layer.borderWidth = 0.5
        grid.layer.borderColor = QuietChessTheme.navy.withAlphaComponent(0.1).cgColor
        addSubview(grid)
        for index in 0..<64 {
            let square = BoardSquare()
            square.accessibilityIdentifier = "square-\(game.squareLabel(index))"
            square.addAction(UIAction { [weak game] _ in game?.handleTap(index) }, for: .touchUpInside)
            grid.addSubview(square)
            squares.append(square)
        }
        for index in 0..<8 {
            let rank = chessLabel(size: 10, weight: .semibold, color: QuietChessTheme.slate)
            let file = chessLabel(size: 10, weight: .semibold, color: QuietChessTheme.slate)
            rank.textAlignment = .left
            file.textAlignment = .right
            [rank, file].forEach { $0.isAccessibilityElement = false; addSubview($0) }
            rank.accessibilityIdentifier = "rank-\(index)"
            file.accessibilityIdentifier = "file-\(index)"
            rankLabels.append(rank)
            fileLabels.append(file)
        }
        arrow.fillColor = UIColor.systemOrange.withAlphaComponent(0.9).cgColor
        arrow.strokeColor = arrow.fillColor
        arrow.lineCap = .round
        grid.layer.addSublayer(arrow)
        endingMarker.isHidden = true
        endingMarker.isAccessibilityElement = false
        endingMarker.isUserInteractionEnabled = false
        endingMarker.backgroundColor = .clear
        grid.addSubview(endingMarker)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(game:)") }

    private var colors: [UIColor] {
        ChessBoardPalette.colors(for: game.settings.boardTheme)
    }

    func update(animated: Bool = true, completion: (() -> Void)? = nil) {
        let switchedRecord = recordID != game.record?.id
        recordID = game.record?.id
        if switchedRecord {
            pieceViews.values.forEach { $0.removeFromSuperview() }
            pieceViews.removeAll()
            placements.removeAll()
        }
        // Preview the pawn on its destination without committing an incomplete
        // move to the engine or saved history before a promotion is chosen.
        var displayBoard = game.board
        let promotion = game.promotions.first
        if let promotion {
            displayBoard[promotion.to] = displayBoard[promotion.from]
            displayBoard[promotion.from] = nil
        }
        let last = promotion.map { Set([$0.from, $0.to]) } ?? game.lastMoveSquares
        let legal = promotion == nil ? game.legalTargets : []
        endingSquare = nil
        for index in 0..<64 {
            let piece = displayBoard[index]
            let square = squares[index]
            square.baseColor = colors[(index / 8 + index % 8).isMultiple(of: 2) ? 1 : 0]
            let kingInCheck = piece?.name == "king" && piece?.isWhite == game.whiteToMove && game.snapshot?.inCheck == true
            let kingCheckmated = kingInCheck && game.snapshot?.reason == "Checkmate"
            let kingStalemated = piece?.name == "king" && piece?.isWhite == game.whiteToMove &&
                game.snapshot?.reason == "Stalemate"
            var overlays: [UIColor] = []
            if last.contains(index) { overlays.append(BoardHighlights.lastMove) }
            if game.hint.map({ $0.from == index || $0.to == index }) == true { overlays.append(UIColor.systemOrange.withAlphaComponent(0.3)) }
            if kingInCheck {
                overlays.append(kingCheckmated ? BoardHighlights.checkmate : BoardHighlights.check)
            }
            if kingCheckmated || kingStalemated {
                endingSquare = index
                endingMarker.ending = kingCheckmated ? .checkmate : .stalemate
                endingMarker.accessibilityIdentifier = kingCheckmated ? "checkmate-marker" : "stalemate-marker"
            }
            square.selectionHighlighted = promotion == nil && game.selectedSquare == index
            square.overlays = overlays
            square.target = legal.contains(index)
            square.occupied = piece != nil
            // Disable interaction without dimming or flashing the board while thinking.
            square.isUserInteractionEnabled = game.inputAllowed && promotion == nil
            square.accessibilityLabel = (piece.map { ($0.isWhite ? "White " : "Black ") + $0.name } ?? "Empty") + " " + game.squareLabel(index)
            square.accessibilityValue = [
                promotion?.to == index ? "Awaiting promotion" :
                    game.selectedSquare == index && promotion == nil ? "Selected" : legal.contains(index) ? "Legal destination" : nil,
                kingCheckmated ? "Checkmate" : kingStalemated ? "Stalemate" : kingInCheck ? "Check" : nil
            ].compactMap { $0 }.joined(separator: ", ")
            square.setNeedsDisplay()
        }
        let previous = placements
        var next: [Int: Int] = [:]
        for (square, piece) in displayBoard.enumerated() {
            guard let piece else { continue }
            next[piece.id] = square
            if pieceViews[piece.id] == nil {
                let glyph = ChessPieceView()
                glyph.piece = piece
                pieceViews[piece.id] = glyph
                grid.addSubview(glyph)
                glyph.frame = ChessBoardLayout.pieceFrame(in: squareFrame(square))
            } else { pieceViews[piece.id]?.piece = piece }
        }
        for id in Array(pieceViews.keys) where next[id] == nil {
            pieceViews.removeValue(forKey: id)?.removeFromSuperview()
        }
        placements = next
        let movePieces = {
            for (id, square) in next {
                self.pieceViews[id]?.frame = ChessBoardLayout.pieceFrame(in: self.squareFrame(square))
            }
        }
        if animated && !switchedRecord && previous != next && !UIAccessibility.isReduceMotionEnabled && bounds.width > 0 {
            UIView.animate(withDuration: 0.24, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction],
                           animations: movePieces) { _ in completion?() }
        } else {
            movePieces()
            completion?()
        }
        grid.layer.addSublayer(arrow)
        endingMarker.isHidden = endingSquare == nil
        grid.bringSubviewToFront(endingMarker)
        updateArrow()
        updateEndingMarker()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The board bleeds to both edges; coordinates sit inside the outer squares.
        let side = max(0, min(bounds.width, bounds.height))
        grid.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        let size = side / 8
        for square in 0..<64 { squares[square].frame = squareFrame(square) }
        for (id, square) in placements {
            pieceViews[id]?.frame = ChessBoardLayout.pieceFrame(in: squareFrame(square))
        }
        let inset: CGFloat = max(2, size * 0.06)
        let labelHeight: CGFloat = min(12, size * 0.28)
        for index in 0..<8 {
            rankLabels[index].isHidden = !game.settings.coordinates
            fileLabels[index].isHidden = !game.settings.coordinates
            rankLabels[index].text = "\(game.whiteAtBottom ? 8 - index : index + 1)"
            fileLabels[index].text = String(UnicodeScalar(97 + (game.whiteAtBottom ? index : 7 - index))!)
            rankLabels[index].textAlignment = game.whiteAtBottom ? .left : .right
            fileLabels[index].textAlignment = game.whiteAtBottom ? .right : .left
            if game.whiteAtBottom {
                rankLabels[index].frame = CGRect(x: grid.frame.minX + inset,
                                                 y: grid.frame.minY + CGFloat(index) * size + inset,
                                                 width: size * 0.6, height: labelHeight)
                fileLabels[index].frame = CGRect(x: grid.frame.minX + CGFloat(index) * size + size * 0.4,
                                                 y: grid.frame.maxY - inset - labelHeight,
                                                 width: size * 0.6 - inset, height: labelHeight)
            } else {
                rankLabels[index].frame = CGRect(x: grid.frame.minX + 7 * size + size * 0.4,
                                                 y: grid.frame.minY + CGFloat(index) * size + inset,
                                                 width: size * 0.6 - inset, height: labelHeight)
                fileLabels[index].frame = CGRect(x: grid.frame.minX + CGFloat(index) * size + inset,
                                                 y: grid.frame.minY + inset,
                                                 width: size * 0.6, height: labelHeight)
            }
        }
        updateArrow()
        updateEndingMarker()
    }

    private func updateEndingMarker() {
        guard let square = endingSquare else { return }
        let frame = squareFrame(square)
        let size = min(22, frame.width * 0.36)
        let inset = max(2, frame.width * 0.04)
        endingMarker.frame = CGRect(x: frame.maxX - size - inset, y: frame.minY + inset, width: size, height: size)
    }

    private func squareFrame(_ square: Int) -> CGRect {
        ChessBoardLayout.squareFrame(square, side: grid.bounds.width, whiteAtBottom: game.whiteAtBottom)
    }

    func promotionAnchor(at square: Int) -> UIView {
        squares[square]
    }

    private func updateArrow() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let hint = game.hint else { arrow.path = nil; return }
        let fromRect = squareFrame(hint.from), toRect = squareFrame(hint.to)
        let from = CGPoint(x: fromRect.midX, y: fromRect.midY)
        let to = CGPoint(x: toRect.midX, y: toRect.midY)
        let angle = atan2(to.y - from.y, to.x - from.x)
        let head = grid.bounds.width / 8 * 0.23
        let path = UIBezierPath()
        path.move(to: from)
        path.addLine(to: to)
        path.move(to: to)
        path.addLine(to: CGPoint(x: to.x - head * cos(angle - .pi / 6), y: to.y - head * sin(angle - .pi / 6)))
        path.addLine(to: CGPoint(x: to.x - head * cos(angle + .pi / 6), y: to.y - head * sin(angle + .pi / 6)))
        path.close()
        arrow.path = path.cgPath
        arrow.lineWidth = grid.bounds.width / 8 * 0.11
    }
}

private enum BoardHighlights {
    static let selection = UIColor(red: 0.24, green: 0.60, blue: 0.39, alpha: 1)
    static let lastMove = UIColor(red: 1, green: 0.84, blue: 0.18, alpha: 0.2)
    static let check = UIColor(red: 0.98, green: 0.25, blue: 0.30, alpha: 0.38)
    static let checkmate = UIColor(red: 0.98, green: 0.25, blue: 0.30, alpha: 0.58)
}

private final class BoardEndingMarker: UIView {
    enum Ending { case checkmate, stalemate }
    static let mateColor = UIColor(red: 0.80, green: 0.15, blue: 0.20, alpha: 1)
    var ending: Ending = .checkmate { didSet { setNeedsDisplay() } }

    override func draw(_ rect: CGRect) {
        (ending == .checkmate ? Self.mateColor : QuietChessTheme.slate).setFill()
        UIBezierPath(ovalIn: bounds).fill()
        let path = UIBezierPath()
        let inset = bounds.width * 0.31
        if ending == .checkmate {
            path.move(to: CGPoint(x: inset, y: inset))
            path.addLine(to: CGPoint(x: bounds.maxX - inset, y: bounds.maxY - inset))
            path.move(to: CGPoint(x: bounds.maxX - inset, y: inset))
            path.addLine(to: CGPoint(x: inset, y: bounds.maxY - inset))
        } else {
            for fraction in [CGFloat(0.36), CGFloat(0.64)] {
                path.move(to: CGPoint(x: bounds.width * fraction, y: bounds.height * 0.3))
                path.addLine(to: CGPoint(x: bounds.width * fraction, y: bounds.height * 0.7))
            }
        }
        path.lineCapStyle = .round
        UIColor.white.setStroke()
        path.lineWidth = max(2, bounds.width * 0.13)
        path.stroke()
    }
}

private final class BoardSquare: UIButton {
    var baseColor: UIColor = .white { didSet { setNeedsDisplay() } }
    var overlays: [UIColor] = []
    var target = false
    var occupied = false
    var selectionHighlighted = false
    override func draw(_ rect: CGRect) {
        // Paint the square here instead of using backgroundColor: an opaque layer
        // background would premultiply the translucent highlights below to black.
        baseColor.setFill()
        UIRectFill(bounds)
        for color in overlays { color.setFill(); UIRectFill(bounds) }
        if selectionHighlighted {
            let border = UIBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), cornerRadius: bounds.width * 0.07)
            BoardHighlights.selection.setStroke()
            border.lineWidth = 3
            border.stroke()
        }
        guard target else { return }
        let diameter = occupied ? bounds.width - 4 : bounds.width * 0.23
        let circle = UIBezierPath(ovalIn: CGRect(x: (bounds.width - diameter) / 2, y: (bounds.height - diameter) / 2,
                                               width: diameter, height: diameter))
        if occupied {
            QuietChessTheme.navy.withAlphaComponent(0.35).setStroke()
            circle.lineWidth = 3
            circle.stroke()
        } else {
            QuietChessTheme.navy.withAlphaComponent(0.25).setFill()
            circle.fill()
        }
    }
}

final class ChessPieceView: ChessPieceArtworkView {
    var piece: BoardPiece? {
        didSet {
            guard oldValue != piece else { return }
            guard let piece else { isHidden = true; return }
            kind = piece.kind
            isWhite = piece.isWhite
            isHidden = false
        }
    }
}

final class CapturedPiecesView: UIView {
    private let sideLabel = chessLabel(size: 11, weight: .medium, color: QuietChessTheme.slate)
    private let emptyLabel = chessLabel("—", size: 12, color: QuietChessTheme.slate.withAlphaComponent(0.45))
    private var glyphs: [ChessPieceView] = []
    private var currentPieces: [BoardPiece] = []
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(sideLabel)
        addSubview(emptyLabel)
        isAccessibilityElement = true
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    func update(pieces: [BoardPiece], byWhite: Bool) {
        sideLabel.text = byWhite ? "White" : "Black"
        accessibilityLabel = "Captured by " + (byWhite ? "White" : "Black")
        accessibilityValue = pieces.isEmpty ? "None" : pieces.map(\.name).joined(separator: ", ")
        if currentPieces != pieces {
            currentPieces = pieces
            glyphs.forEach { $0.removeFromSuperview() }
            glyphs = pieces.map { piece in
                let glyph = ChessPieceView()
                glyph.piece = piece
                addSubview(glyph)
                return glyph
            }
        }
        emptyLabel.isHidden = !pieces.isEmpty
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        sideLabel.frame = CGRect(x: 0, y: 0, width: 38, height: bounds.height)
        emptyLabel.frame = CGRect(x: 44, y: 0, width: 24, height: bounds.height)
        let spacing = min(21, max(8, (bounds.width - 68) / CGFloat(max(1, glyphs.count - 1))))
        for (index, glyph) in glyphs.enumerated() {
            glyph.frame = CGRect(x: 44 + CGFloat(index) * spacing, y: 0, width: 24, height: 26)
        }
    }
}
