import UIKit

final class HistoryViewController: GameObservingViewController, UITableViewDataSource, UITableViewDelegate {
    private let open: (SavedGame) -> Void
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var records: [SavedGame] = []

    init(game: GameViewModel, open: @escaping (SavedGame) -> Void) {
        self.open = open
        super.init(game: game)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(game:open:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "History"
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 98
        view.addSubview(table)
        table.pinEdges(to: view)
        updateView()
    }

    override func updateView() {
        guard isViewLoaded else { return }
        let next = game.games.sorted { $0.date > $1.date }
        if next != records { records = next; table.reloadData() }
        if records.isEmpty {
            var configuration = UIContentUnavailableConfiguration.empty()
            configuration.image = UIImage(systemName: "clock.arrow.circlepath")
            configuration.text = "Your games live here"
            configuration.secondaryText = "Play a game, then return to replay moves or practice a different line."
            contentUnavailableConfiguration = configuration
        } else { contentUnavailableConfiguration = nil }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { records.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let record = records[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "history") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "history")
        var configuration = cell.defaultContentConfiguration()
        configuration.text = record.title
        configuration.textProperties.font = .systemFont(ofSize: 17, weight: .semibold)
        configuration.textProperties.color = QuietChessTheme.navy
        configuration.secondaryText = "\(record.outcome)\n\(record.date.formatted(date: .abbreviated, time: .shortened)) · \(record.moves.count) moves" +
            (record.branchCount > 1 ? " · \(record.branchCount) branches" : "")
        configuration.secondaryTextProperties.numberOfLines = 0
        configuration.secondaryTextProperties.color = QuietChessTheme.slate
        cell.contentConfiguration = configuration
        cell.backgroundColor = .white
        let share = chessButton("", icon: "square.and.arrow.up") { [weak self, weak cell] in
            guard let self, let cell else { return }
            self.share(record, from: cell)
        }
        share.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        share.accessibilityLabel = "Share PGN"
        cell.accessoryView = share
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard game.ready else { return }
        open(records[indexPath.row])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let record = records[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            let alert = UIAlertController(title: "Delete this saved game?",
                                          message: "This removes the game and all its branches from this device. It cannot be undone.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
                self?.game.deleteGame(record.id)
                completion(true)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(false) })
            self.present(alert, animated: true)
        }
        let actions = UISwipeActionsConfiguration(actions: [delete])
        actions.performsFirstActionWithFullSwipe = false
        return actions
    }
}
