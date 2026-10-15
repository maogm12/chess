import UIKit
import Combine

enum ForkChessTheme {
    static let background = UIColor(red: 0.975, green: 0.977, blue: 0.967, alpha: 1)
    static let navy = UIColor(red: 0.055, green: 0.125, blue: 0.220, alpha: 1)
    static let slate = UIColor(red: 0.35, green: 0.43, blue: 0.52, alpha: 1)
    static let accent = UIColor(red: 0.26, green: 0.38, blue: 0.49, alpha: 1)
    static let panel = UIColor(red: 0.925, green: 0.938, blue: 0.95, alpha: 1)
    static let line = UIColor(red: 0.84, green: 0.87, blue: 0.89, alpha: 1)
    /// Corner radius shared by the app's cards and filled buttons.
    static let radius: CGFloat = 12
}

/// Square colors for each board theme, shared by the game board, the puzzle editor, and previews.
enum ChessBoardPalette {
    static func colors(for theme: String) -> [UIColor] {
        switch theme {
        case "Forest": return [UIColor(red: 0.92, green: 0.94, blue: 0.86, alpha: 1),
                               UIColor(red: 0.45, green: 0.58, blue: 0.45, alpha: 1)]
        case "Walnut": return [UIColor(red: 0.95, green: 0.89, blue: 0.78, alpha: 1),
                               UIColor(red: 0.65, green: 0.46, blue: 0.32, alpha: 1)]
        default: return [UIColor(red: 0.95, green: 0.93, blue: 0.88, alpha: 1),
                         UIColor(red: 0.61, green: 0.70, blue: 0.77, alpha: 1)]
        }
    }
}

enum ChessBoardLayout {
    static let pieceInset: CGFloat = 0.06

    static func squareFrame(_ index: Int, side: CGFloat, whiteAtBottom: Bool) -> CGRect {
        let size = side / 8
        let file = whiteAtBottom ? index % 8 : 7 - index % 8
        let rank = whiteAtBottom ? 7 - index / 8 : index / 8
        return CGRect(x: CGFloat(file) * size, y: CGFloat(rank) * size, width: size, height: size)
    }

    static func pieceFrame(in square: CGRect) -> CGRect {
        square.insetBy(dx: square.width * pieceInset, dy: square.height * pieceInset)
    }
}

final class ChessNavigationController: UINavigationController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = ForkChessTheme.background
        appearance.titleTextAttributes = [.foregroundColor: ForkChessTheme.navy]
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.tintColor = ForkChessTheme.accent
        overrideUserInterfaceStyle = .light
    }
}

class GameObservingViewController: UIViewController {
    let game: GameViewModel
    private var observation: AnyCancellable?
    private var updateScheduled = false

    init(game: GameViewModel) {
        self.game = game
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(game:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ForkChessTheme.background
        view.tintColor = ForkChessTheme.accent
        observation = game.objectWillChange.sink { [weak self] in
            // Published sends before its value changes. Coalesce a batch into
            // one render on the next main-loop turn, after all values are set.
            guard let self, !self.updateScheduled else { return }
            self.updateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateScheduled = false
                self.updateView()
                self.showPendingError()
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateView()
        showPendingError()
    }

    func updateView() {}

    private func showPendingError() {
        guard viewIfLoaded?.window != nil, navigationController?.topViewController === self,
              presentedViewController == nil, navigationController?.presentedViewController == nil,
              let message = game.errorMessage else { return }
        let alert = UIAlertController(title: "Something needs attention", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel) { [weak self] _ in self?.game.errorMessage = nil })
        present(alert, animated: true)
    }

    func presentSettings(scope: SettingsViewController.Scope = .global) {
        present(ChessNavigationController(rootViewController: SettingsViewController(game: game, scope: scope)), animated: true)
    }

    func share(_ record: SavedGame, from source: UIView) {
        let controller = UIActivityViewController(activityItems: [game.pgn(for: record)], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = source
        controller.popoverPresentationController?.sourceRect = source.bounds
        present(controller, animated: true)
    }

    func presentActionSheet(_ controller: UIAlertController, from source: UIView) {
        controller.popoverPresentationController?.sourceView = source
        controller.popoverPresentationController?.sourceRect = source.bounds
        present(controller, animated: true)
    }
}

func chessLabel(_ text: String = "", size: CGFloat = 17, weight: UIFont.Weight = .regular,
                color: UIColor = ForkChessTheme.navy) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = color
    label.numberOfLines = 0
    label.adjustsFontForContentSizeCategory = true
    return label
}

func chessSerifLabel(_ text: String = "", size: CGFloat = 22, weight: UIFont.Weight = .semibold,
                     color: UIColor = ForkChessTheme.navy) -> UILabel {
    let label = chessLabel(text, size: size, weight: weight, color: color)
    if let descriptor = label.font.fontDescriptor.withDesign(.serif) {
        label.font = UIFont(descriptor: descriptor, size: size)
    }
    return label
}

func chessButton(_ title: String, icon: String? = nil, primary: Bool = false,
                 action: @escaping () -> Void) -> UIButton {
    var configuration = primary ? UIButton.Configuration.filled() : .plain()
    configuration.title = title
    configuration.baseForegroundColor = primary ? .white : ForkChessTheme.accent
    configuration.baseBackgroundColor = ForkChessTheme.accent
    configuration.cornerStyle = .medium
    if let icon {
        configuration.image = UIImage(systemName: icon)
        configuration.imagePadding = 7
    }
    return UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
}

extension UIButton.Configuration {
    /// The app's card/button look: flat theme fill, shared corner radius, optional leading icon
    /// and a secondary line of text. Used for the home cards so they match the rest of the app
    /// instead of borrowing chrome from a reference screenshot.
    static func forkChess(title: String, subtitle: String? = nil, icon: String? = nil,
                           background: UIColor = ForkChessTheme.panel,
                           foreground: UIColor = ForkChessTheme.navy,
                           size: CGFloat = 17, weight: UIFont.Weight = .semibold,
                           alignment: UIButton.Configuration.TitleAlignment = .center,
                           insets: NSDirectionalEdgeInsets = .init(top: 14, leading: 16, bottom: 14, trailing: 16))
        -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.background.backgroundColor = background
        configuration.background.cornerRadius = ForkChessTheme.radius
        configuration.baseForegroundColor = foreground
        configuration.contentInsets = insets
        configuration.titleAlignment = alignment
        var title = AttributedString(title)
        title.font = .systemFont(ofSize: size, weight: weight)
        title.foregroundColor = foreground
        configuration.attributedTitle = title
        if let subtitle {
            var line = AttributedString(subtitle)
            line.font = .systemFont(ofSize: 13)
            line.foregroundColor = ForkChessTheme.slate
            configuration.attributedSubtitle = line
        }
        if let icon {
            configuration.image = UIImage(systemName: icon)
            configuration.imagePlacement = .leading
            configuration.imagePadding = 12
            configuration.preferredSymbolConfigurationForImage =
                UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
        }
        return configuration
    }
}

extension UIView {
    func pinEdges(to other: UIView, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom)
        ])
    }
}

extension SavedGame {
    var isSavedPractice: Bool { isPuzzle || baseFEN != GameViewModel.startFEN }
    var homeOutcome: String {
        if result == "*" { return "In progress" }
        if result == "1/2-1/2" { return reason.isEmpty ? "Draw" : "\(reason) · Draw" }
        let outcome = result == (playerWhite ? "1-0" : "0-1") ? "You won" : "You lost"
        return reason.isEmpty ? outcome : "\(reason) · \(outcome)"
    }
    var homeDetail: String {
        "\(date.formatted(.dateTime.month(.abbreviated).day())) · \(moves.count) moves · \(playerWhite ? "White" : "Black")" +
            (branchCount > 1 ? " · \(branchCount) branches" : "")
    }
}

final class KingArtworkView: ChessPieceArtworkView {
    var white = true { didSet { if oldValue != white { isWhite = white } } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        kind = "k"
        isWhite = white
    }
}

/// Keep app defaults and game settings consistent, including values between presets.
func botStrengthMenu(settings: PracticeSettings, select: @escaping (Int) -> Void) -> UIMenu {
    var actions = PracticeSettings.strengthPresets.map { preset in
        UIAction(title: "\(preset.name) · ≈\(PracticeSettings.estimatedElo(for: preset.skill)) Elo",
                 subtitle: "Level \(preset.skill) of 20",
                 state: settings.skill == preset.skill ? .on : .off) { _ in select(preset.skill) }
    }
    if !PracticeSettings.strengthPresets.contains(where: { $0.skill == settings.skill }) {
        actions.insert(UIAction(title: settings.strengthDescription,
                                subtitle: "Current · level \(settings.skill) of 20", state: .on) { _ in
            select(settings.skill)
        }, at: 0)
    }
    return UIMenu(title: "Bot strength", children: actions)
}
