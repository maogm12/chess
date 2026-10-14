import UIKit

final class HomeViewController: GameObservingViewController {
    private let scroll = UIScrollView()
    private let header = UIView()
    private let wordmark = chessSerifLabel("Quiet Chess", size: 21)
    private let settingsButton = UIButton(type: .system)
    private let whiteTile = SideTile(white: true)
    private let blackTile = SideTile(white: false)
    private let startButton = UIButton(type: .system)
    private let puzzleButton = UIButton(type: .system)
    private let historyButton = UIButton(type: .system)
    private let loading = chessLabel("Preparing board…", size: 13, color: QuietChessTheme.slate)

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.backButtonTitle = "Home"
        scroll.showsVerticalScrollIndicator = false
        scroll.addSubview(header)
        view.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor)
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

        historyButton.accessibilityLabel = "Game history"
        historyButton.accessibilityIdentifier = "open-game-history"
        historyButton.contentHorizontalAlignment = .leading
        historyButton.addAction(UIAction { [weak self] _ in self?.openHistory() }, for: .touchUpInside)
        loading.textAlignment = .center
    }

    private var puzzleSubtitle: String {
        "\(game.games.filter(\.isSavedPractice).count) saved"
    }

    private func layoutHeader() {
        let width = min(596, scroll.bounds.width)
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
        historyButton.frame = CGRect(x: margin, y: puzzleButton.frame.maxY + 26, width: contentWidth, height: 64)
        let height = historyButton.frame.maxY + 18
        header.frame = CGRect(x: (scroll.bounds.width - width) / 2, y: 0, width: width, height: height)
        scroll.contentSize = CGSize(width: scroll.bounds.width, height: height)
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
        let count = "\(game.games.count) \(game.games.count == 1 ? "game" : "games")"
        historyButton.configuration = .quietChess(title: "Game history", subtitle: count,
                                                  icon: "clock.arrow.circlepath", alignment: .leading)
        historyButton.contentHorizontalAlignment = .leading
        puzzleButton.accessibilityValue = puzzleSubtitle
        historyButton.accessibilityValue = count
        view.setNeedsLayout()
    }

    private func openPuzzles() {
        navigationController?.pushViewController(PuzzleViewController(game: game), animated: true)
    }

    private func openHistory() {
        let controller = HistoryViewController(game: game) { [weak self] record in
            guard let self else { return }
            self.open(record)
        }
        navigationController?.pushViewController(controller, animated: true)
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
