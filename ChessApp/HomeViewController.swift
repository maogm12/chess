import UIKit

final class HomeViewController: GameObservingViewController, UITableViewDataSource, UITableViewDelegate {
    private let table = UITableView(frame: .zero, style: .plain)
    private let header = UIView()
    private let wordmark = chessSerifLabel("Quiet Chess", size: 21)
    private let settingsButton = UIButton(type: .system)
    private let whiteTile = SideTile(white: true)
    private let blackTile = SideTile(white: false)
    private let startButton = UIButton(type: .system)
    private let puzzleButton = UIButton(type: .system)
    private let historyButton = UIButton(type: .system)
    private let historyCount = chessLabel(size: 13, color: QuietChessTheme.slate)
    private let loading = chessLabel("Preparing board…", size: 13, color: QuietChessTheme.slate)
    private var records: [SavedGame] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.backButtonTitle = "Home"
        table.backgroundColor = .clear
        table.separatorColor = QuietChessTheme.line
        table.separatorInset = UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 18)
        table.showsVerticalScrollIndicator = false
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 82
        table.dataSource = self
        table.delegate = self
        table.register(HomeGameCell.self, forCellReuseIdentifier: "game")
        table.tableHeaderView = header
        view.addSubview(table)
        table.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            table.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            table.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            table.widthAnchor.constraint(lessThanOrEqualToConstant: 596),
            table.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor).withPriority(.defaultHigh)
        ])
        configureHeader()
        updateView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        updateView()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutHeader()
    }

    private func configureHeader() {
        [wordmark, settingsButton, whiteTile, blackTile, startButton, puzzleButton, historyButton, loading]
            .forEach { header.addSubview($0) }
        wordmark.accessibilityTraits = .header
        settingsButton.setImage(UIImage(systemName: "gearshape"), for: .normal)
        settingsButton.tintColor = QuietChessTheme.accent
        settingsButton.accessibilityLabel = "Settings"
        settingsButton.addAction(UIAction { [weak self] _ in self?.presentSettings() }, for: .touchUpInside)

        whiteTile.addAction(UIAction { [weak self] _ in self?.game.settings.playWhite = true }, for: .touchUpInside)
        blackTile.addAction(UIAction { [weak self] _ in self?.game.settings.playWhite = false }, for: .touchUpInside)

        startButton.configuration = .quietChess(title: "Start new game", background: QuietChessTheme.accent,
                                                foreground: .white, size: 19,
                                                insets: .init(top: 17, leading: 18, bottom: 17, trailing: 18))
        startButton.accessibilityLabel = "Start new game"
        startButton.addAction(UIAction { [weak self] _ in
            guard let self, self.game.ready else { return }
            self.game.newGame()
            self.navigationController?.pushViewController(GameViewController(game: self.game), animated: true)
        }, for: .touchUpInside)

        puzzleButton.accessibilityLabel = "Puzzle"
        puzzleButton.contentHorizontalAlignment = .leading
        puzzleButton.addAction(UIAction { [weak self] _ in self?.openPuzzles() }, for: .touchUpInside)

        let line = UIView()
        line.backgroundColor = QuietChessTheme.line
        let historyTitle = chessSerifLabel("Game history", size: 22)
        [line, historyTitle, historyCount].forEach {
            $0.isUserInteractionEnabled = false
            $0.translatesAutoresizingMaskIntoConstraints = false
            historyButton.addSubview($0)
        }
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: historyButton.topAnchor),
            line.leadingAnchor.constraint(equalTo: historyButton.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: historyButton.trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
            historyTitle.leadingAnchor.constraint(equalTo: historyButton.leadingAnchor),
            historyTitle.topAnchor.constraint(equalTo: historyButton.topAnchor, constant: 18),
            historyCount.trailingAnchor.constraint(equalTo: historyButton.trailingAnchor),
            historyCount.firstBaselineAnchor.constraint(equalTo: historyTitle.firstBaselineAnchor),
            historyTitle.trailingAnchor.constraint(lessThanOrEqualTo: historyCount.leadingAnchor, constant: -12)
        ])
        historyButton.accessibilityLabel = "Game history"
        historyButton.addAction(UIAction { [weak self] _ in self?.openHistory() }, for: .touchUpInside)
        loading.textAlignment = .center
    }

    private var puzzleSubtitle: String {
        "\(game.games.filter(\.isSavedPractice).count) saved"
    }

    private func layoutHeader() {
        let width = table.bounds.width
        guard width > 0 else { return }
        let margin: CGFloat = 18
        let contentWidth = width - margin * 2
        let top: CGFloat = view.bounds.height > 750 ? 16 : 8
        wordmark.frame = CGRect(x: margin, y: top, width: contentWidth - 40, height: 30)
        settingsButton.frame = CGRect(x: margin + contentWidth - 30, y: top, width: 30, height: 30)

        let gutter: CGFloat = 10
        let tileWidth = (contentWidth - gutter) / 2
        let tileHeight = min(250, max(170, contentWidth * 0.52))
        let tileTop = wordmark.frame.maxY + 16
        whiteTile.frame = CGRect(x: margin, y: tileTop, width: tileWidth, height: tileHeight)
        blackTile.frame = CGRect(x: margin + tileWidth + gutter, y: tileTop, width: tileWidth, height: tileHeight)

        startButton.frame = CGRect(x: margin, y: whiteTile.frame.maxY + 22, width: contentWidth, height: 58)
        loading.frame = CGRect(x: margin, y: startButton.frame.maxY + 6, width: contentWidth, height: 16)
        puzzleButton.frame = CGRect(x: margin, y: startButton.frame.maxY + (game.ready ? 10 : 30),
                                    width: contentWidth, height: 64)
        historyButton.frame = CGRect(x: margin, y: puzzleButton.frame.maxY + 26, width: contentWidth, height: 62)
        let height = historyButton.frame.maxY
        if header.frame.width != width || header.frame.height != height {
            header.frame = CGRect(x: 0, y: 0, width: width, height: height)
            table.tableHeaderView = header
        }
    }

    override func updateView() {
        guard isViewLoaded else { return }
        whiteTile.setSelected(game.settings.playWhite)
        blackTile.setSelected(!game.settings.playWhite)
        startButton.isEnabled = game.ready
        startButton.alpha = game.ready ? 1 : 0.45
        loading.isHidden = game.ready
        puzzleButton.configuration = .quietChess(title: "Puzzle", subtitle: puzzleSubtitle,
                                                 icon: "puzzlepiece.extension", alignment: .leading)
        puzzleButton.contentHorizontalAlignment = .leading
        historyCount.text = "\(game.games.count) \(game.games.count == 1 ? "game" : "games")"
        puzzleButton.accessibilityValue = puzzleSubtitle
        historyButton.accessibilityValue = historyCount.text
        let next = game.games.sorted { $0.date > $1.date }
        if records != next {
            records = next
            table.reloadData()
        }
        if records.isEmpty {
            let empty = chessLabel("Your first move starts here.\nYour games will appear here, ready to replay.", size: 15, color: QuietChessTheme.slate)
            empty.textAlignment = .center
            empty.frame = CGRect(x: 18, y: 0, width: table.bounds.width - 36, height: 90)
            table.tableFooterView = empty
        } else { table.tableFooterView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 28)) }
        view.setNeedsLayout()
    }

    private func openPuzzles() {
        navigationController?.pushViewController(PuzzleViewController(game: game), animated: true)
    }

    private func openHistory() {
        let controller = HistoryViewController(game: game) { [weak self] record in
            guard let self else { return }
            self.dismiss(animated: true) { self.open(record) }
        }
        present(ChessNavigationController(rootViewController: controller), animated: true)
    }

    private func open(_ record: SavedGame) {
        guard game.ready else { return }
        if record.isSavedPractice {
            game.openPuzzle(record)
        } else {
            game.review(record)
        }
        navigationController?.pushViewController(GameViewController(game: game), animated: true)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { records.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "game", for: indexPath) as! HomeGameCell
        cell.configure(records[indexPath.row])
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        open(records[indexPath.row])
    }
}

private final class SideTile: UIControl {
    private let artwork = KingArtworkView(frame: .zero)
    private let badge = chessLabel(size: 13, weight: .semibold)

    init(white: Bool) {
        super.init(frame: .zero)
        artwork.white = white
        badge.text = white ? "Play White" : "Play Black"
        badge.textAlignment = .center
        layer.cornerRadius = QuietChessTheme.radius
        layer.cornerCurve = .continuous
        [artwork, badge].forEach { $0.isUserInteractionEnabled = false; addSubview($0) }
        accessibilityLabel = badge.text
        isAccessibilityElement = true
        accessibilityTraits = .button
        setSelected(false)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(white:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = min(bounds.height * 0.62, bounds.width - 32)
        let total = size * 1.1 + 12 + 22
        artwork.frame = CGRect(x: (bounds.width - size) / 2, y: (bounds.height - total) / 2, width: size, height: size * 1.1)
        badge.frame = CGRect(x: 8, y: artwork.frame.maxY + 12, width: bounds.width - 16, height: 22)
    }
    func setSelected(_ selected: Bool) {
        isSelected = selected
        backgroundColor = selected ? .white : QuietChessTheme.panel
        layer.borderColor = (selected ? QuietChessTheme.accent : QuietChessTheme.line).cgColor
        layer.borderWidth = selected ? 2 : 1
        badge.font = .systemFont(ofSize: 14, weight: selected ? .semibold : .regular)
        badge.textColor = selected ? QuietChessTheme.navy : QuietChessTheme.slate
        accessibilityValue = selected ? "Selected" : ""
        accessibilityTraits = selected ? [.button, .selected] : .button
    }
}

private final class HomeGameCell: UITableViewCell {
    private let king = KingArtworkView(frame: .zero)
    private let puzzle = UIImageView(image: UIImage(systemName: "puzzlepiece.extension"))
    private let title = chessLabel(size: 17, weight: .semibold)
    private let detail = chessLabel(size: 13, color: QuietChessTheme.slate)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectedBackgroundView = {
            let view = UIView()
            view.backgroundColor = QuietChessTheme.panel
            view.layer.cornerRadius = QuietChessTheme.radius
            view.layer.cornerCurve = .continuous
            return view
        }()
        puzzle.tintColor = QuietChessTheme.accent
        let text = UIStackView(arrangedSubviews: [title, detail])
        text.axis = .vertical
        text.spacing = 6
        let icon = UIView()
        icon.addSubview(king)
        icon.addSubview(puzzle)
        king.pinEdges(to: icon, insets: UIEdgeInsets(top: 3, left: 4, bottom: 3, right: 4))
        puzzle.pinEdges(to: icon, insets: UIEdgeInsets(top: 7, left: 4, bottom: 7, right: 4))
        let row = UIStackView(arrangedSubviews: [icon, text])
        row.spacing = 14
        row.alignment = .center
        contentView.addSubview(row)
        row.pinEdges(to: contentView, insets: UIEdgeInsets(top: 16, left: 18, bottom: 16, right: 18))
        icon.widthAnchor.constraint(equalToConstant: 38).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(style:reuseIdentifier:)") }
    func configure(_ record: SavedGame) {
        king.white = record.playerWhite
        king.isHidden = record.isSavedPractice
        puzzle.isHidden = !record.isSavedPractice
        title.text = record.homeOutcome
        detail.text = record.homeDetail
        accessibilityLabel = "\(record.homeOutcome), \(record.homeDetail)"
    }
}

extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
