import UIKit

final class GameViewController: GameObservingViewController, UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate {
    private enum TimelineRow: Equatable {
        case moves(number: Int, white: Int?, black: Int?)
        case fork(BranchPoint)
        var lastPly: Int {
            switch self {
            case .moves(_, let white, let black): return max(white ?? -1, black ?? -1) + 1
            case .fork(let point): return point.ply
            }
        }
        func contains(ply: Int) -> Bool {
            switch self {
            case .moves(_, let white, let black): return white == ply - 1 || black == ply - 1
            case .fork: return false
            }
        }
    }
    private lazy var board = ChessBoardView(game: game)
    private let topCaptured = CapturedPiecesView()
    private let bottomCaptured = CapturedPiecesView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let timerTitle = UIView(frame: CGRect(x: 0, y: 0, width: 132, height: 30))
    private let timerLabel = chessLabel(size: 21, weight: .semibold)
    private let hintLabel = chessLabel(size: 14, weight: .medium)
    private let movesTable = UITableView(frame: .zero, style: .plain)
    private let actions = UIStackView()
    private lazy var branchPicker = chessButton("Main line", icon: "arrow.triangle.branch", action: {})
    private lazy var latest = chessButton("Latest", icon: "forward.end.fill") { [weak self] in self?.game.returnToLatest() }
    private let branchBar = UIStackView()
    private lazy var undo = actionButton("Undo", icon: "arrow.uturn.backward") { [weak self] in self?.game.undo() }
    private lazy var hint = actionButton("Hint", icon: "lightbulb") { [weak self] in self?.game.requestHint() }
    private lazy var end = actionButton("Resign", icon: "flag") { [weak self] in self?.confirmEnd() }
    private lazy var newGame = chessButton("New Game", primary: true) { [weak self] in self?.game.newGame() }
    private lazy var historyPan = UIPanGestureRecognizer(target: self, action: #selector(pannedHistory(_:)))
    private var timer: Timer?
    private var notation: [String] = []
    private var ratings: [MoveRating?] = []
    private var selectedPly: Int?
    private var redoPly: Int?
    private var timeline: [TimelineRow] = []
    private var pagingPoint: BranchPoint?
    private var pagingStartX: CGFloat?
    private var renderedBranches: [GameBranch] = []
    private var renderedBranchID: UUID?
    private struct FeedbackPosition {
        let gameID: UUID
        let branchID: UUID
        let moves: [String]
    }
    private var previousFeedbackPosition: FeedbackPosition?
    private let endFeedback: (UINotificationFeedbackGenerator.FeedbackType) -> Void
    private weak var promotionAlert: UIAlertController?

    init(game: GameViewModel,
         endFeedback: @escaping (UINotificationFeedbackGenerator.FeedbackType) -> Void = {
             UINotificationFeedbackGenerator().notificationOccurred($0)
         }) {
        self.endFeedback = endFeedback
        super.init(game: game)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(game:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        [board, topCaptured, bottomCaptured, hintLabel, movesTable,
         actions, branchBar, newGame].forEach { view.addSubview($0) }
        spinner.hidesWhenStopped = true
        spinner.accessibilityLabel = "Thinking"
        timerTitle.addSubview(timerLabel)
        timerTitle.addSubview(spinner)
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 21, weight: .semibold)
        timerLabel.textAlignment = .center
        timerLabel.accessibilityLabel = "Practice time remaining"
        timerLabel.frame = CGRect(x: 24, y: 0, width: 84, height: 30)
        spinner.frame = CGRect(x: 0, y: 5, width: 20, height: 20)
        hintLabel.backgroundColor = QuietChessTheme.panel
        hintLabel.layer.cornerRadius = 10
        hintLabel.clipsToBounds = true
        hintLabel.textAlignment = .center
        movesTable.dataSource = self
        movesTable.delegate = self
        movesTable.separatorColor = QuietChessTheme.line
        movesTable.backgroundColor = .white
        movesTable.layer.cornerRadius = 12
        movesTable.layer.borderColor = QuietChessTheme.line.cgColor
        movesTable.layer.borderWidth = 0.6
        movesTable.allowsSelection = false
        movesTable.register(MoveCell.self, forCellReuseIdentifier: "move")
        movesTable.register(ForkCell.self, forCellReuseIdentifier: "fork")
        movesTable.accessibilityIdentifier = "move-timeline"
        historyPan.delegate = self
        movesTable.addGestureRecognizer(historyPan)
        // Horizontal paging wins only for horizontal drags; vertical history scrolling stays native.
        movesTable.panGestureRecognizer.require(toFail: historyPan)
        branchBar.axis = .horizontal
        branchBar.alignment = .center
        branchBar.addArrangedSubview(branchPicker)
        branchBar.addArrangedSubview(UIView())
        branchBar.addArrangedSubview(latest)
        branchPicker.showsMenuAsPrimaryAction = true
        branchPicker.accessibilityIdentifier = "branch-picker"
        latest.accessibilityIdentifier = "return-to-latest"
        actions.axis = .horizontal
        actions.distribution = .fillEqually
        actions.spacing = 12
        [undo, hint, end].forEach { actions.addArrangedSubview($0) }
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: optionsMenu()),
            UIBarButtonItem(image: UIImage(systemName: "arrow.triangle.2.circlepath"),
                            primaryAction: UIAction { [weak self] _ in self?.game.flipped.toggle() })
        ]
        navigationItem.rightBarButtonItems?[0].accessibilityLabel = "Game options"
        navigationItem.rightBarButtonItems?[1].accessibilityLabel = "Flip board"
        updateView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        game.setPracticeVisible(true)
        if !game.reviewing { game.resume() }
        updateTimer()
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.updateTimer() }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        timer?.invalidate()
        timer = nil
        game.setPracticeVisible(false)
        if isMovingFromParent { game.pause() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 18, dy: 8)
        let contentWidth = min(900, safe.width)
        let left = safe.midX - contentWidth / 2
        let controlsHeight: CGFloat = game.reviewing ? 0 : 56
        let bottom = safe.maxY - controlsHeight
        let landscape = safe.width > safe.height
        let hintHeight: CGFloat = game.hint == nil ? 0 : 44
        let boardSide: CGFloat
        let boardX: CGFloat
        let boardY = safe.minY
        let historyX: CGFloat
        let historyY: CGFloat
        let historyWidth: CGFloat
        let historyBottom = bottom - 10
        if landscape {
            boardSide = max(80, min(contentWidth * 0.48, historyBottom - boardY - 60))
            boardX = left
            historyX = left + boardSide + 16
            historyY = boardY
            historyWidth = max(80, contentWidth - boardSide - 16)
        } else {
            // Portrait: the board bleeds to both screen edges (coordinates live
            // inside the outer squares), clamped to the vertical room available.
            let available = historyBottom - boardY - 52 - hintHeight - 112
            boardSide = max(80, min(view.bounds.width, available))
            boardX = (view.bounds.width - boardSide) / 2
            historyX = left
            historyY = boardY + boardSide + 56
            historyWidth = contentWidth
        }
        let trayInset: CGFloat = 14
        topCaptured.frame = CGRect(x: boardX + trayInset, y: boardY, width: boardSide - trayInset * 2, height: 26)
        board.frame = CGRect(x: boardX, y: boardY + 30, width: boardSide, height: boardSide)
        bottomCaptured.frame = CGRect(x: boardX + trayInset, y: board.frame.maxY + 4,
                                      width: boardSide - trayInset * 2, height: 20)
        hintLabel.frame = CGRect(x: historyX, y: historyY, width: historyWidth, height: hintHeight > 0 ? 36 : 0)
        let branchHeight: CGFloat = branchBar.isHidden ? 0 : 32
        branchBar.frame = CGRect(x: historyX, y: historyY + hintHeight, width: historyWidth, height: branchHeight)
        let gap: CGFloat = branchHeight > 0 ? 4 : 0
        movesTable.frame = CGRect(x: historyX, y: branchBar.frame.maxY + gap, width: historyWidth,
                                 height: max(44, historyBottom - branchBar.frame.maxY - gap))
        let controlsWidth = min(contentWidth, 680)
        let controlsX = safe.midX - controlsWidth / 2
        actions.frame = CGRect(x: controlsX, y: bottom, width: controlsWidth, height: 56)
        newGame.frame = actions.frame
    }

    override func updateView() {
        guard isViewLoaded else { return }
        if game.isThinking || game.isHinting || game.isRating || game.busy { spinner.startAnimating() }
        else { spinner.stopAnimating() }
        if game.reviewing { spinner.isHidden = true }
        if game.reviewing {
            navigationItem.titleView = nil
            title = "Review game"
        } else {
            title = nil
            navigationItem.titleView = timerTitle
        }
        topCaptured.update(pieces: game.capturedPieces(byWhite: !game.whiteAtBottom), byWhite: !game.whiteAtBottom)
        bottomCaptured.update(pieces: game.capturedPieces(byWhite: game.whiteAtBottom), byWhite: game.whiteAtBottom)
        board.update()
        hintLabel.isHidden = game.hint == nil
        if let hint = game.hint { hintLabel.text = "Try \(hint.san) · \(game.squareLabel(hint.from)) → \(game.squareLabel(hint.to))" }
        undo.isEnabled = game.canUndo
        hint.isEnabled = game.inputAllowed
        end.isEnabled = !game.gameOver && !game.busy
        actions.isHidden = game.reviewing || game.gameOver
        newGame.isHidden = game.reviewing || !game.gameOver
        latest.isHidden = !game.reviewing
        latest.isEnabled = !game.busy
        updateBranches()
        let nextRatings = game.settings.moveRatingsEnabled ? (game.record?.ratings ?? []) : []
        let ply = game.cursorPly
        let nextRedoPly = game.canRedoSelectedMove ? game.selectedHistoricalPly : nil
        let branches = game.record?.branches ?? []
        if notation != game.timelineNotation || ratings != nextRatings || selectedPly != ply ||
            renderedBranches != branches || renderedBranchID != game.record?.branchID || redoPly != nextRedoPly {
            let changedMoves = notation != game.timelineNotation
            notation = game.timelineNotation
            ratings = nextRatings
            selectedPly = ply
            redoPly = nextRedoPly
            renderedBranches = branches
            renderedBranchID = game.record?.branchID
            timeline = makeTimeline()
            movesTable.reloadData()
            if changedMoves && !notation.isEmpty {
                movesTable.layoutIfNeeded()
                let row = timeline.firstIndex { $0.contains(ply: ply) } ?? 0
                movesTable.scrollToRow(at: IndexPath(row: row, section: 0), at: .bottom, animated: false)
            }
        }
        if notation.isEmpty && !game.gameOver && game.snapshot?.result == "*" {
            let empty = chessLabel("The board is yours.\nTap a piece, then a highlighted square.", size: 13, color: QuietChessTheme.slate)
            empty.textAlignment = .center
            movesTable.backgroundView = empty
        } else { movesTable.backgroundView = nil }
        updateHaptics()
        navigationItem.rightBarButtonItems?.first?.menu = optionsMenu()
        updateTimer()
        view.setNeedsLayout()
        showPromotionIfNeeded()
    }

    private func updateHaptics() {
        if game.reviewing { previousFeedbackPosition = nil; return }
        guard !game.busy, let record = game.active, let position = game.snapshot,
              position.notation.count == record.moves.count else { return }
        let previous = previousFeedbackPosition
        previousFeedbackPosition = FeedbackPosition(gameID: record.id, branchID: record.branchID, moves: record.moves)
        guard game.settings.haptics, view.window != nil, let previous,
              previous.gameID == record.id, previous.branchID == record.branchID,
              previous.moves.count < record.moves.count,
              record.moves.starts(with: previous.moves) else { return }
        // Only a new move can trigger ending feedback, never replay, reopening, or a redraw.
        if position.reason == "Checkmate" {
            let humanWon = position.result == (record.playerWhite ? "1-0" : "0-1")
            endFeedback(humanWon ? .success : .error)
        } else if position.reason == "Stalemate" {
            endFeedback(.warning)
        } else {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    private func updateBranches() {
        guard let record = game.record else { return }
        let point = record.branchPoints.last { $0.ply <= game.cursorPly }
        var configuration = branchPicker.configuration
        let context = point.map { " · \($0.selectedIndex + 1)/\($0.options.count) at \($0.ply)" } ?? ""
        configuration?.title = record.branchName + context
        configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes
            result.font = .systemFont(ofSize: 12, weight: .medium)
            return result
        }
        branchPicker.configuration = configuration
        branchPicker.accessibilityValue = "\(record.branchCount) branches. Swipe moves left or right to switch."
        branchPicker.isEnabled = record.branchCount > 1 && !game.busy
        branchPicker.isHidden = record.branchCount == 1
        branchBar.isHidden = branchPicker.isHidden && latest.isHidden
        func entries(parent: UUID?) -> [UIMenuElement] {
            record.branches.filter { $0.parentID == parent }.flatMap { branch -> [UIMenuElement] in
                let prefix = String(repeating: "  ", count: record.depth(of: branch.id))
                let suffix = branch.parentID == nil ? "" : " · from position \(branch.forkPly)"
                let action = UIAction(title: prefix + record.name(of: branch.id) + suffix,
                                      state: branch.id == record.branchID ? .on : .off) { [weak self] _ in
                    self?.game.selectBranch(branch.id)
                }
                return [action] + entries(parent: branch.id)
            }
        }
        branchPicker.menu = UIMenu(title: "Branches · swipe moves to switch", children: entries(parent: nil))
    }

    private func branchPoint(at location: CGPoint) -> BranchPoint? {
        guard let record = game.record else { return nil }
        let index = movesTable.indexPathForRow(at: location)?.row
        let ply = index.flatMap { timeline.indices.contains($0) ? timeline[$0].lastPly : nil } ?? notation.count
        return record.branchPoints.last { $0.ply <= ply }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === historyPan else { return true }
        let velocity = historyPan.velocity(in: movesTable)
        let location = historyPan.location(in: movesTable)
        guard abs(velocity.x) > abs(velocity.y), branchPoint(at: location) != nil else { return false }
        // Keep the initial travel even if the scroll view resets the pan's translation.
        pagingStartX = location.x - historyPan.translation(in: movesTable).x
        return true
    }

    @objc private func pannedHistory(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began {
            pagingPoint = branchPoint(at: gesture.location(in: movesTable))
            return
        }
        if gesture.state == .cancelled || gesture.state == .failed {
            pagingPoint = nil
            pagingStartX = nil
            return
        }
        guard gesture.state == .ended else { return }
        defer { pagingPoint = nil; pagingStartX = nil }
        guard let point = pagingPoint, let startX = pagingStartX else { return }
        let distance = gesture.location(in: movesTable).x - startX
        let speed = gesture.velocity(in: movesTable).x
        guard abs(distance) > 35 || (abs(distance) > 8 && abs(speed) > 350) else { return }
        let direction = distance < 0 ? 1 : -1
        guard point.options.indices.contains(point.selectedIndex + direction) else { return }
        let transition = CATransition()
        transition.duration = 0.2
        transition.type = UIAccessibility.isReduceMotionEnabled ? .fade : .push
        transition.subtype = direction > 0 ? .fromRight : .fromLeft
        movesTable.layer.add(transition, forKey: "branch-page")
        game.switchBranch(direction: direction, at: point.ply)
    }

    private var firstMoveOffset: Int {
        ChessPosition.whiteToMove(in: game.record?.baseFEN ?? GameViewModel.startFEN) ? 0 : 1
    }
    private func makeTimeline() -> [TimelineRow] {
        guard let record = game.record else { return [] }
        let fields = record.baseFEN.split(separator: " ")
        let firstNumber = fields.count > 5 ? Int(fields[5]) ?? 1 : 1
        let points = Dictionary(uniqueKeysWithValues: record.branchPoints.map { ($0.ply, $0) })
        var rows: [TimelineRow] = []
        if let start = points[0] { rows.append(.fork(start)) }
        for row in 0..<((notation.count + firstMoveOffset + 1) / 2) where !notation.isEmpty {
            let white = row * 2 - firstMoveOffset
            let black = white + 1
            let whiteIndex = notation.indices.contains(white) ? white : nil
            let blackIndex = notation.indices.contains(black) ? black : nil
            if let point = points[white + 1], whiteIndex != nil {
                rows.append(.moves(number: firstNumber + row, white: whiteIndex, black: nil))
                rows.append(.fork(point))
                if blackIndex != nil { rows.append(.moves(number: firstNumber + row, white: nil, black: blackIndex)) }
            } else {
                rows.append(.moves(number: firstNumber + row, white: whiteIndex, black: blackIndex))
            }
            if let point = points[black + 1], blackIndex != nil { rows.append(.fork(point)) }
        }
        return rows
    }

    private func updateTimer() {
        let seconds = Int(ceil(game.practiceTimeRemaining()))
        timerLabel.text = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        timerLabel.textColor = seconds == 0 ? .systemRed : QuietChessTheme.navy
        timerLabel.accessibilityValue = "\(seconds / 60) minutes, \(seconds % 60) seconds"
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> UIButton {
        let button = chessButton(title, icon: icon, action: action)
        var configuration = button.configuration
        configuration?.imagePlacement = .top
        configuration?.baseForegroundColor = QuietChessTheme.navy
        configuration?.background.backgroundColor = QuietChessTheme.panel
        configuration?.background.cornerRadius = 12
        configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes
            result.font = .systemFont(ofSize: 12)
            return result
        }
        button.configuration = configuration
        button.accessibilityLabel = title
        return button
    }

    private func confirmEnd() {
        let alert = UIAlertController(title: "Resign this game?",
                                      message: "The game will remain in your local history for review.", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Resign", style: .destructive) { [weak self] _ in
            self?.game.resign()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentActionSheet(alert, from: end)
    }

    private func showPromotionIfNeeded() {
        guard !game.promotions.isEmpty, promotionAlert == nil, presentedViewController == nil,
              view.window != nil else { return }
        let alert = UIAlertController(title: "Promote pawn", message: nil, preferredStyle: .actionSheet)
        for move in game.promotions {
            let name: String
            switch move.promotion { case "q": name = "Queen"; case "r": name = "Rook"; case "b": name = "Bishop"; default: name = "Knight" }
            alert.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in self?.game.play(move) })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.game.promotions = [] })
        promotionAlert = alert
        presentActionSheet(alert, from: board)
    }

    private func optionsMenu() -> UIMenu {
        let skills: [(String, Int)] = [("Beginner", 2), ("Casual", 6), ("Club", 11), ("Expert", 16), ("Full strength", 20)]
        let strength = UIMenu(title: "Bot strength", children: skills.map { name, value in
            UIAction(title: name, state: game.settings.skill == value ? .on : .off) { [weak self] _ in self?.game.settings.skill = value }
        })
        let times: [(String, Double)] = [("Quick · 0.4 seconds", 0.4), ("Balanced · 1 second", 1), ("Deeper · 2 seconds", 2)]
        let thinking = UIMenu(title: "Thinking time", children: times.map { name, value in
            UIAction(title: name, state: game.settings.thinkSeconds == value ? .on : .off) { [weak self] _ in self?.game.settings.thinkSeconds = value }
        })
        var children: [UIMenuElement] = [strength, thinking,
            UIAction(title: "All settings…", image: UIImage(systemName: "gearshape")) { [weak self] _ in self?.presentSettings() }]
        if let record = game.record {
            children.append(UIAction(title: "Share PGN", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                guard let self else { return }; self.share(record, from: self.view)
            })
        }
        return UIMenu(children: children)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        timeline.count
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch timeline[indexPath.row] {
        case .fork(let point):
            let cell = tableView.dequeueReusableCell(withIdentifier: "fork", for: indexPath) as! ForkCell
            if let record = game.record {
                cell.configure(point: point, record: record) { [weak self] branchID in self?.game.selectBranch(branchID) }
            }
            return cell
        case .moves(let number, let white, let black):
            let cell = tableView.dequeueReusableCell(withIdentifier: "move", for: indexPath) as! MoveCell
            cell.configure(number: number, whiteIndex: white, blackIndex: black, notation: notation, ratings: ratings,
                           selectedPly: selectedPly, redoPly: redoPly,
                           forks: Set(game.record?.branchPoints.map(\.ply) ?? []),
                           select: { [weak self] ply in self?.game.seek(ply) },
                           redo: { [weak self] in self?.game.redoSelectedMove() })
            return cell
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch timeline[indexPath.row] {
        case .fork: return 44
        case .moves(_, let white, let black):
            let rated = [white, black].compactMap { $0 }.contains { ratings.indices.contains($0) && ratings[$0] != nil }
            return rated ? 54 : (timeline[indexPath.row].contains(ply: redoPly ?? -1) ? 40 : 32)
        }
    }
}

private final class MoveCell: UITableViewCell {
    private let number = chessLabel(size: 14, color: QuietChessTheme.slate)
    private let white = UIButton(configuration: .plain())
    private let black = UIButton(configuration: .plain())
    private let whiteRating = chessLabel(size: 11, weight: .semibold)
    private let blackRating = chessLabel(size: 11, weight: .semibold)
    private let whiteRedo = UIButton()
    private let blackRedo = UIButton()
    private var select: ((Int) -> Void)?
    private var redo: (() -> Void)?
    private var whitePly: Int?
    private var blackPly: Int?
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        let whiteMove = UIStackView(arrangedSubviews: [white, whiteRedo])
        let blackMove = UIStackView(arrangedSubviews: [black, blackRedo])
        [whiteMove, blackMove].forEach { $0.spacing = 4; $0.alignment = .center }
        let whiteColumn = UIStackView(arrangedSubviews: [whiteMove, whiteRating])
        let blackColumn = UIStackView(arrangedSubviews: [blackMove, blackRating])
        [whiteColumn, blackColumn].forEach { $0.axis = .vertical; $0.spacing = 2 }
        let columns = UIStackView(arrangedSubviews: [whiteColumn, blackColumn])
        columns.distribution = .fillEqually
        let row = UIStackView(arrangedSubviews: [number, columns])
        row.alignment = .center
        contentView.addSubview(row)
        row.pinEdges(to: contentView, insets: UIEdgeInsets(top: 3, left: 16, bottom: 3, right: 12))
        number.widthAnchor.constraint(equalToConstant: 36).isActive = true
        white.contentHorizontalAlignment = .leading
        black.contentHorizontalAlignment = .leading
        white.addAction(UIAction { [weak self] _ in
            guard let self, let ply = self.whitePly else { return }; self.select?(ply)
        }, for: .touchUpInside)
        black.addAction(UIAction { [weak self] _ in
            guard let self, let ply = self.blackPly else { return }; self.select?(ply)
        }, for: .touchUpInside)
        for button in [whiteRedo, blackRedo] {
            button.configuration = .quietChess(title: "重走", background: QuietChessTheme.accent,
                                                foreground: .white, size: 12,
                                                insets: .init(top: 3, leading: 5, bottom: 3, trailing: 5))
            let width = button.widthAnchor.constraint(equalToConstant: 44)
            let height = button.heightAnchor.constraint(equalToConstant: 28)
            width.priority = .defaultHigh
            height.priority = .defaultHigh
            NSLayoutConstraint.activate([width, height])
            button.addAction(UIAction { [weak self] _ in self?.redo?() }, for: .touchUpInside)
        }
        selectionStyle = .none
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(style:reuseIdentifier:)") }
    func configure(number moveNumber: Int, whiteIndex: Int?, blackIndex: Int?, notation: [String],
                   ratings: [MoveRating?], selectedPly: Int?, redoPly: Int?, forks: Set<Int>,
                   select: @escaping (Int) -> Void, redo: @escaping () -> Void) {
        self.select = select
        self.redo = redo
        number.text = "\(moveNumber)."
        whitePly = whiteIndex.map { $0 + 1 }
        blackPly = blackIndex.map { $0 + 1 }
        for (index, label, ratingLabel, redoButton) in [(whiteIndex ?? -1, white, whiteRating, whiteRedo),
                                                       (blackIndex ?? -1, black, blackRating, blackRedo)] {
            let exists = notation.indices.contains(index)
            let ply = index + 1
            var configuration = label.configuration
            configuration?.title = exists ? notation[index] : "—"
            configuration?.baseForegroundColor = selectedPly == ply ? QuietChessTheme.accent : QuietChessTheme.navy
            configuration?.background.backgroundColor = selectedPly == ply ? QuietChessTheme.panel : .clear
            configuration?.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 4, bottom: 3, trailing: 4)
            configuration?.image = exists && forks.contains(ply) ? UIImage(systemName: "arrow.triangle.branch") : nil
            configuration?.imagePlacement = .trailing
            configuration?.imagePadding = 4
            configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 10)
            configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes; result.font = .systemFont(ofSize: 14, weight: .medium); return result
            }
            label.configuration = configuration
            label.isEnabled = exists
            label.accessibilityIdentifier = exists ? "move-ply-\(ply)" : nil
            label.accessibilityLabel = exists ? "\(notation[index]), position \(ply)" + (forks.contains(ply) ? ", branch point" : "") : "No move"
            redoButton.isHidden = !exists || redoPly != ply
            redoButton.accessibilityIdentifier = exists ? "redo-ply-\(ply)" : nil
            redoButton.accessibilityLabel = exists ? "重走 \(notation[index])" : nil
            if ratings.indices.contains(index), let rating = ratings[index] {
                ratingLabel.text = rating.rawValue
                ratingLabel.textColor = rating == .good ? UIColor(red: 0.15, green: 0.45, blue: 0.30, alpha: 1)
                    : rating == .ok ? UIColor(red: 0.55, green: 0.37, blue: 0.06, alpha: 1)
                    : UIColor(red: 0.70, green: 0.22, blue: 0.19, alpha: 1)
                ratingLabel.isHidden = false
            } else { ratingLabel.isHidden = true }
        }
        backgroundColor = selectedPly == whitePly || selectedPly == blackPly
            ? QuietChessTheme.panel.withAlphaComponent(0.7) : .white
    }
}

private final class ForkCell: UITableViewCell {
    private let title = chessLabel(size: 12, weight: .medium, color: QuietChessTheme.accent)
    private let caption = chessLabel("左右滑动切换分支", size: 11, color: QuietChessTheme.slate)
    private let pages = UIPageControl()
    private var options: [UUID] = []
    private var select: ((UUID) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = QuietChessTheme.panel
        selectionStyle = .none
        let labels = UIStackView(arrangedSubviews: [title, caption])
        labels.axis = .vertical
        labels.spacing = 2
        let icon = UIImageView(image: UIImage(systemName: "arrow.triangle.branch"))
        icon.tintColor = QuietChessTheme.accent
        let row = UIStackView(arrangedSubviews: [icon, labels, pages])
        row.alignment = .center
        row.spacing = 8
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        pages.widthAnchor.constraint(equalToConstant: 88).isActive = true
        pages.pageIndicatorTintColor = QuietChessTheme.line
        pages.currentPageIndicatorTintColor = QuietChessTheme.accent
        pages.backgroundStyle = .minimal
        pages.addAction(UIAction { [weak self] _ in
            guard let self, self.options.indices.contains(self.pages.currentPage) else { return }
            self.select?(self.options[self.pages.currentPage])
        }, for: .valueChanged)
        contentView.addSubview(row)
        row.pinEdges(to: contentView, insets: .init(top: 4, left: 16, bottom: 4, right: 12))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(style:reuseIdentifier:)") }

    func configure(point: BranchPoint, record: SavedGame, select: @escaping (UUID) -> Void) {
        self.select = select
        options = point.options
        title.text = "\(record.name(of: options[point.selectedIndex])) · \(point.selectedIndex + 1)/\(options.count)"
        pages.numberOfPages = options.count
        pages.currentPage = point.selectedIndex
        pages.accessibilityIdentifier = "fork-pager-\(point.ply)"
        pages.accessibilityLabel = "分叉点 \(point.ply)，左右滑动切换分支"
        accessibilityIdentifier = "fork-row-\(point.ply)"
    }
}
