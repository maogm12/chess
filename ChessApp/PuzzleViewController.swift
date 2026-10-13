import UIKit

/// The puzzle library: every saved endgame is a tile, and the first tile adds a new one.
final class PuzzleViewController: GameObservingViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    private let grid = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private var puzzles: [SavedGame] = []
    private var tileSize = CGSize.zero

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Puzzle"
        navigationItem.backButtonTitle = "Puzzle"
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "plus"),
                                                            primaryAction: UIAction { [weak self] _ in
            self?.addPuzzle()
        })
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Add puzzle"
        grid.backgroundColor = .clear
        grid.alwaysBounceVertical = true
        grid.dataSource = self
        grid.delegate = self
        grid.register(PuzzleTile.self, forCellWithReuseIdentifier: PuzzleTile.reuseIdentifier)
        grid.register(AddPuzzleTile.self, forCellWithReuseIdentifier: AddPuzzleTile.reuseIdentifier)
        view.addSubview(grid)
        grid.pinEdges(to: view)
        updateView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        updateView()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let margin: CGFloat = 18
        let spacing: CGFloat = 14
        let columns = min(4, max(2, Int((view.bounds.width - margin * 2 + spacing) / 200)))
        let width = (((view.bounds.width - margin * 2) - spacing * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down)
        let size = CGSize(width: width, height: width + 58)
        guard size != tileSize else { return }
        tileSize = size
        if let layout = grid.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.itemSize = size
            layout.minimumInteritemSpacing = spacing
            layout.minimumLineSpacing = spacing
            layout.sectionInset = UIEdgeInsets(top: 18, left: margin, bottom: 28, right: margin)
            layout.invalidateLayout()
        }
    }

    override func updateView() {
        guard isViewLoaded else { return }
        let next = game.games.filter(\.isSavedPractice).sorted { $0.date > $1.date }
        if next != puzzles {
            puzzles = next
            grid.reloadData()
        }
    }

    private var boardColors: [UIColor] { ChessBoardPalette.colors(for: game.settings.boardTheme) }

    private func addPuzzle() {
        let editor = PuzzleEditorViewController(game: game) { [weak self] record in
            guard let self, let navigation = self.navigationController,
                  navigation.topViewController is PuzzleEditorViewController else { return }
            self.game.openPuzzle(record)
            // Replace the editor so returning from play goes straight back to the library.
            let stack = Array(navigation.viewControllers.dropLast()) + [GameViewController(game: self.game)]
            navigation.setViewControllers(stack, animated: true)
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    private func play(_ record: SavedGame) {
        game.openPuzzle(record)
        navigationController?.pushViewController(GameViewController(game: game), animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        puzzles.count + 1
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.item == 0 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AddPuzzleTile.reuseIdentifier,
                                                          for: indexPath) as! AddPuzzleTile
            cell.accessibilityLabel = "Add puzzle"
            return cell
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PuzzleTile.reuseIdentifier,
                                                      for: indexPath) as! PuzzleTile
        cell.apply(puzzles[indexPath.item - 1], colors: boardColors, previewSide: tileSize.width - 20)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard indexPath.item > 0 else { addPuzzle(); return }
        play(puzzles[indexPath.item - 1])
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPath.item > 0 else { return nil }
        let record = puzzles[indexPath.item - 1]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self?.game.deleteGame(record.id)
            }
            let share = UIAction(title: "Share PGN", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                guard let self, let cell = collectionView.cellForItem(at: indexPath) else { return }
                self.share(record, from: cell)
            }
            return UIMenu(children: [share, delete])
        }
    }
}

/// One saved puzzle: a preview of the starting position plus the side you play.
final class PuzzleTile: UICollectionViewCell {
    static let reuseIdentifier = "puzzle"

    private let preview = UIImageView()
    private let title = chessLabel(size: 14, weight: .semibold)
    private let detail = chessLabel(size: 12, color: QuietChessTheme.slate)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = QuietChessTheme.radius
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = QuietChessTheme.line.cgColor
        preview.contentMode = .scaleAspectFill
        preview.clipsToBounds = true
        preview.layer.cornerRadius = 7
        preview.layer.cornerCurve = .continuous
        [preview, title, detail].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            preview.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            preview.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            preview.heightAnchor.constraint(equalTo: preview.widthAnchor),
            title.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 9),
            title.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: preview.trailingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            detail.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: preview.trailingAnchor)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func apply(_ record: SavedGame, colors: [UIColor], previewSide: CGFloat) {
        preview.image = PuzzleThumbnail.image(fen: record.baseFEN, side: max(40, previewSide), colors: colors,
                                             whiteAtBottom: record.defaultWhiteAtBottom)
        title.text = record.playerWhite ? "You play White" : "You play Black"
        detail.text = record.moves.isEmpty
            ? record.date.formatted(.dateTime.month(.abbreviated).day())
            : "\(record.moves.count) moves · " + record.date.formatted(.dateTime.month(.abbreviated).day())
        if record.result != "*" { detail.text = record.homeOutcome }
        if record.branchCount > 1 { detail.text = "\(record.branchCount) branches · " + (detail.text ?? "") }
        accessibilityLabel = "\(title.text ?? ""), \(detail.text ?? "")"
    }

    override var isHighlighted: Bool {
        didSet { contentView.backgroundColor = isHighlighted ? QuietChessTheme.panel : .white }
    }
}

/// The always-visible first tile that opens the setup board.
final class AddPuzzleTile: UICollectionViewCell {
    static let reuseIdentifier = "add"

    private let symbol = UIImageView(image: UIImage(systemName: "plus"))
    private let title = chessLabel("New puzzle", size: 14, weight: .semibold)
    private let detail = chessLabel("Set up a position by hand", size: 12, color: QuietChessTheme.slate)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = QuietChessTheme.panel
        contentView.layer.cornerRadius = QuietChessTheme.radius
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = QuietChessTheme.accent.withAlphaComponent(0.5).cgColor
        symbol.tintColor = QuietChessTheme.accent
        detail.textAlignment = .center
        title.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [symbol, title, detail])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.isUserInteractionEnabled = false
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -10),
            symbol.widthAnchor.constraint(equalToConstant: 26),
            symbol.heightAnchor.constraint(equalToConstant: 26)
        ])
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override var isHighlighted: Bool {
        didSet { contentView.alpha = isHighlighted ? 0.7 : 1 }
    }
}
