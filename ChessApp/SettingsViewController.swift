import UIKit

final class SettingsViewController: GameObservingViewController, UITableViewDataSource, UITableViewDelegate {
    private enum Row {
        case side, duration, strength, slider, level, thinking, ratings, colors, legal, coordinates, haptics
        case offline, storage, privacy, version, license
    }
    private struct Section {
        let title: String
        let footer: String?
        let rows: [Row]
    }
    private let sections = [
        Section(title: "New game defaults",
                footer: "You always play against the bot. Your color takes effect when you start a new game.",
                rows: [.side]),
        Section(title: "Practice timer",
                footer: "Applies to new games. The countdown pauses when you leave the game. You can keep practicing when time runs out.",
                rows: [.duration]),
        Section(title: "Bot",
                footer: "Choose how strong the bot plays and how long it thinks. Hints always use full strength.",
                rows: [.strength, .slider, .level, .thinking]),
        Section(title: "Practice feedback",
                footer: "Show Good, OK, or Bad beside each new move, including the bot's moves. Ratings compare the move with the best available option and are estimates. Analysis adds a short pause after each move. Ratings are saved for replay.",
                rows: [.ratings]),
        Section(title: "Board", footer: nil, rows: [.colors, .legal, .coordinates, .haptics]),
        Section(title: "Privacy & storage", footer: nil, rows: [.offline, .storage, .privacy]),
        Section(title: "About", footer: nil, rows: [.version, .license])
    ]
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var renderedSettings: PracticeSettings?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 48
        view.addSubview(table)
        table.pinEdges(to: view)
        updateView()
    }
    override func updateView() {
        guard isViewLoaded, renderedSettings != game.settings else { return }
        renderedSettings = game.settings
        table.reloadData()
    }

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].title }
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { sections[section].footer }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.backgroundColor = .white
        cell.textLabel?.textColor = ForkChessTheme.navy
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.textColor = ForkChessTheme.slate
        cell.selectionStyle = .none
        switch row {
        case .side:
            cell.textLabel?.text = "Play as"
            cell.accessoryView = picker(title: game.settings.playWhite ? "White" : "Black", label: "Play as",
                                       options: [("White", game.settings.playWhite, { [weak self] in self?.game.settings.playWhite = true }),
                                                 ("Black", !game.settings.playWhite, { [weak self] in self?.game.settings.playWhite = false })])
        case .duration:
            cell.textLabel?.text = "Duration"
            cell.accessoryView = picker(title: "\(game.settings.practiceMinutes) minutes", label: "Practice duration",
                                       options: [5, 10, 15, 30].map { value in
                ("\(value) minutes", game.settings.practiceMinutes == value, { [weak self] in self?.game.settings.practiceMinutes = value })
            })
        case .strength:
            cell.textLabel?.text = "Strength"
            cell.detailTextLabel?.text = game.settings.difficulty
        case .slider:
            let slider = UISlider()
            slider.minimumValue = 0
            slider.maximumValue = 20
            slider.value = Float(game.settings.skill)
            slider.isContinuous = false
            slider.tintColor = ForkChessTheme.accent
            slider.accessibilityLabel = "Bot skill level"
            slider.accessibilityValue = "\(game.settings.skill) of 20"
            slider.addAction(UIAction { [weak self, weak slider] _ in
                guard let slider else { return }
                self?.game.settings.skill = Int(slider.value.rounded())
            }, for: .valueChanged)
            cell.contentView.addSubview(slider)
            slider.pinEdges(to: cell.contentView, insets: UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16))
            slider.heightAnchor.constraint(equalToConstant: 28).isActive = true
        case .level:
            cell.textLabel?.text = "Skill level"
            cell.detailTextLabel?.text = "\(game.settings.skill) of 20"
        case .thinking:
            cell.textLabel?.text = "Thinking time"
            let values: [(String, Double)] = [("Quick · 0.4 seconds", 0.4), ("Balanced · 1 second", 1), ("Deeper · 2 seconds", 2)]
            cell.accessoryView = picker(title: values.first { $0.1 == game.settings.thinkSeconds }?.0 ?? "Balanced · 1 second",
                                       label: "Thinking time", options: values.map { name, value in
                (name, game.settings.thinkSeconds == value, { [weak self] in self?.game.settings.thinkSeconds = value })
            })
        case .ratings:
            cell.textLabel?.text = "Rate each move"
            cell.accessoryView = toggle("Rate each move", value: game.settings.moveRatingsEnabled) { [weak self] in self?.game.settings.moveRatingsEnabled = $0 }
        case .colors:
            cell.textLabel?.text = "Colors"
            cell.accessoryView = picker(title: game.settings.boardTheme, label: "Board colors", options: ["Slate", "Forest", "Walnut"].map { name in
                (name, game.settings.boardTheme == name, { [weak self] in self?.game.settings.boardTheme = name })
            })
        case .legal:
            cell.textLabel?.text = "Show legal moves"
            cell.accessoryView = toggle("Show legal moves", value: game.settings.showLegalMoves) { [weak self] in self?.game.settings.showLegalMoves = $0 }
        case .coordinates:
            cell.textLabel?.text = "Show coordinates"
            cell.accessoryView = toggle("Show coordinates", value: game.settings.coordinates) { [weak self] in self?.game.settings.coordinates = $0 }
        case .haptics:
            cell.textLabel?.text = "Move haptics"
            cell.accessoryView = toggle("Move haptics", value: game.settings.haptics) { [weak self] in self?.game.settings.haptics = $0 }
        case .offline:
            cell.textLabel?.text = "No account or internet required"
            cell.imageView?.image = UIImage(systemName: "wifi.slash")
        case .storage:
            cell.textLabel?.text = "Games and settings saved locally"
            cell.imageView?.image = UIImage(systemName: "internaldrive")
        case .privacy:
            cell.textLabel?.text = "No analytics, ads, or cloud sync. Games are saved automatically, including when you leave the app. Share a PGN only when you choose to."
            cell.textLabel?.font = .preferredFont(forTextStyle: .footnote)
            cell.textLabel?.textColor = ForkChessTheme.slate
        case .version:
            cell.textLabel?.text = "ForkChess"
            cell.detailTextLabel?.text = "1.0"
        case .license:
            cell.textLabel?.text = "Engine license (MIT)"
            cell.textLabel?.textColor = ForkChessTheme.accent
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        }
        return cell
    }

    private func picker(title: String, label: String, options: [(String, Bool, () -> Void)]) -> UIButton {
        let button = chessButton(title, icon: "chevron.down", action: {})
        var configuration = button.configuration
        configuration?.imagePlacement = .trailing
        configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 11)
        configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes
            result.font = .systemFont(ofSize: 14)
            return result
        }
        button.configuration = configuration
        button.menu = UIMenu(children: options.map { name, selected, action in
            UIAction(title: name, state: selected ? .on : .off) { _ in action() }
        })
        button.showsMenuAsPrimaryAction = true
        button.sizeToFit()
        button.accessibilityLabel = label
        button.accessibilityValue = title
        return button
    }

    private func toggle(_ label: String, value: Bool, changed: @escaping (Bool) -> Void) -> UISwitch {
        let control = UISwitch()
        control.isOn = value
        control.onTintColor = ForkChessTheme.accent
        control.accessibilityLabel = label
        control.addAction(UIAction { [weak control] _ in
            guard let control else { return }; changed(control.isOn)
        }, for: .valueChanged)
        return control
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard sections[indexPath.section].rows[indexPath.row] == .license else { return }
        navigationController?.pushViewController(LicenseViewController(), animated: true)
    }
}

private final class LicenseViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Arasan · MIT"
        view.backgroundColor = ForkChessTheme.background
        let text = UITextView()
        text.isEditable = false
        text.backgroundColor = .clear
        text.textColor = ForkChessTheme.navy
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        if let url = Bundle.main.url(forResource: "LICENSE-Arasan", withExtension: "txt"),
           let contents = try? String(contentsOf: url, encoding: .utf8) { text.text = contents }
        else { text.text = "Arasan chess engine, MIT licensed (Copyright 1994-2026 Jon Dart). See THIRD_PARTY.md for source." }
        view.addSubview(text)
        text.pinEdges(to: view)
    }
}
