import UIKit

final class SettingsViewController: GameObservingViewController, UITableViewDataSource, UITableViewDelegate {
    enum Scope { case global, currentGame }
    private let scope: Scope
    private enum Row {
        case side, duration, strength, slider, thinking, ratings, colors, legal, coordinates, haptics
        case offline, storage, privacy, version, license
    }
    private struct Section {
        let title: String
        let footer: String?
        let rows: [Row]
    }
    private var sections: [Section] {
        if scope == .currentGame {
            return [
                Section(title: "Bot for this game",
                        footer: "Saved with this game and shared by its branches. Bot changes apply to the next search. Elo is an engine estimate, not a measured human rating; device and thinking time affect play. Hints always use full strength.",
                        rows: [.strength, .slider, .thinking]),
                Section(title: "Feedback for this game",
                        footer: "Rate future moves as Good, OK, or Bad. Analysis adds a short pause. Existing ratings stay saved.",
                        rows: [.ratings]),
                Section(title: "Practice timer",
                        footer: "Changing the duration restarts this line's countdown. Other branches keep their remaining time. You can keep playing at zero.",
                        rows: [.duration])
            ]
        }
        return [
            Section(title: "New game defaults",
                    footer: "Used when starting a new game or creating a puzzle. Existing games keep their own settings.",
                    rows: [.side, .duration]),
            Section(title: "Default bot",
                    footer: "For new games only. Change an existing game's bot in Game settings. Elo is an engine estimate, not a measured human rating; device and thinking time affect play. Hints always use full strength.",
                    rows: [.strength, .slider, .thinking]),
            Section(title: "Default practice feedback",
                    footer: "For new games only. Ratings estimate each move as Good, OK, or Bad and add a short analysis pause.",
                    rows: [.ratings]),
            Section(title: "Board & interaction", footer: "Applies across all games.", rows: [.colors, .legal, .coordinates, .haptics]),
            Section(title: "Privacy & storage", footer: nil, rows: [.offline, .storage, .privacy]),
            Section(title: "About", footer: nil, rows: [.version, .license])
        ]
    }
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var renderedSettings: PracticeSettings?

    init(game: GameViewModel, scope: Scope = .global) {
        self.scope = scope
        super.init(game: game)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(game:scope:)") }

    private var preferences: PracticeSettings {
        var values = game.settings
        if scope == .currentGame {
            let configuration = game.gameSettings
            values.skill = configuration.skill
            values.thinkSeconds = configuration.thinkSeconds
            values.moveRatingsEnabled = configuration.rateMoves
            values.practiceMinutes = configuration.practiceMinutes
        }
        return values
    }

    private func change(_ update: (inout PracticeSettings) -> Void) {
        var values = preferences
        update(&values)
        if scope == .global { game.settings = values }
        else { game.updateGameSettings(GameSettings(defaults: values)) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = scope == .global ? "Settings" : "Game settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        table.backgroundColor = .clear
        table.accessibilityIdentifier = "settings-list"
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 48
        view.addSubview(table)
        table.pinEdges(to: view)
        updateView()
    }
    override func updateView() {
        guard isViewLoaded, renderedSettings != preferences else { return }
        renderedSettings = preferences
        table.reloadData()
    }

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].rows.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].title }
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { sections[section].footer }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.backgroundColor = ForkChessTheme.surface
        cell.textLabel?.textColor = ForkChessTheme.navy
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.textColor = ForkChessTheme.slate
        cell.selectionStyle = .none
        switch row {
        case .side:
            cell.textLabel?.text = "Play as"
            cell.accessoryView = picker(title: preferences.playWhite ? "White" : "Black", label: "Play as",
                                       options: [("White", preferences.playWhite, { [weak self] in self?.change { $0.playWhite = true } }),
                                                 ("Black", !preferences.playWhite, { [weak self] in self?.change { $0.playWhite = false } })])
        case .duration:
            cell.textLabel?.text = "Duration"
            cell.accessoryView = picker(title: "\(preferences.practiceMinutes) minutes", label: "Practice duration",
                                       options: [5, 10, 15, 30].map { value in
                ("\(value) minutes", preferences.practiceMinutes == value, { [weak self] in self?.change { $0.practiceMinutes = value } })
            })
        case .strength:
            cell.textLabel?.text = "Strength"
            let button = picker(title: preferences.strengthDescription, label: "Bot strength", options: [])
            button.menu = botStrengthMenu(settings: preferences) { [weak self] skill in
                self?.change { $0.skill = skill }
            }
            cell.accessoryView = button
        case .slider:
            let slider = UISlider()
            slider.minimumValue = 0
            slider.maximumValue = 20
            slider.value = Float(preferences.skill)
            slider.isContinuous = false
            slider.tintColor = ForkChessTheme.accent
            slider.accessibilityLabel = "Bot skill level"
            slider.accessibilityValue = "\(preferences.skill) of 20"
            slider.addAction(UIAction { [weak self, weak slider] _ in
                guard let slider else { return }
                self?.change { $0.skill = Int(slider.value.rounded()) }
            }, for: .valueChanged)
            cell.contentView.addSubview(slider)
            slider.pinEdges(to: cell.contentView, insets: UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16))
            slider.heightAnchor.constraint(equalToConstant: 28).isActive = true
        case .thinking:
            cell.textLabel?.text = "Thinking time"
            let values: [(String, Double)] = [("Quick · 0.4 seconds", 0.4), ("Balanced · 1 second", 1), ("Deeper · 2 seconds", 2)]
            cell.accessoryView = picker(title: values.first { $0.1 == preferences.thinkSeconds }?.0 ?? "Balanced · 1 second",
                                       label: "Thinking time", options: values.map { name, value in
                (name, preferences.thinkSeconds == value, { [weak self] in self?.change { $0.thinkSeconds = value } })
            })
        case .ratings:
            cell.textLabel?.text = "Rate each move"
            cell.accessoryView = toggle("Rate each move", value: preferences.moveRatingsEnabled) { [weak self] enabled in self?.change { $0.moveRatingsEnabled = enabled } }
        case .colors:
            cell.textLabel?.text = "Colors"
            cell.accessoryView = picker(title: preferences.boardTheme, label: "Board colors", options: ["Slate", "Forest", "Walnut"].map { name in
                (name, preferences.boardTheme == name, { [weak self] in self?.change { $0.boardTheme = name } })
            })
        case .legal:
            cell.textLabel?.text = "Show legal moves"
            cell.accessoryView = toggle("Show legal moves", value: preferences.showLegalMoves) { [weak self] enabled in self?.change { $0.showLegalMoves = enabled } }
        case .coordinates:
            cell.textLabel?.text = "Show coordinates"
            cell.accessoryView = toggle("Show coordinates", value: preferences.coordinates) { [weak self] enabled in self?.change { $0.coordinates = enabled } }
        case .haptics:
            cell.textLabel?.text = "Move haptics"
            cell.accessoryView = toggle("Move haptics", value: preferences.haptics) { [weak self] enabled in self?.change { $0.haptics = enabled } }
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
        control.onTintColor = ForkChessTheme.actionFill
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
        text.accessibilityIdentifier = "engine-license"
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
