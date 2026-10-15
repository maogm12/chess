import UIKit
import Combine

enum ForkChessTheme {
    static func adaptive(_ light: UIColor, dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    static let background = adaptive(UIColor(red: 0.975, green: 0.977, blue: 0.967, alpha: 1),
                                     dark: UIColor(red: 0.055, green: 0.075, blue: 0.105, alpha: 1))
    static let surface = adaptive(.white, dark: UIColor(red: 0.105, green: 0.14, blue: 0.18, alpha: 1))
    static let navy = adaptive(UIColor(red: 0.055, green: 0.125, blue: 0.220, alpha: 1),
                               dark: UIColor(red: 0.90, green: 0.93, blue: 0.95, alpha: 1))
    static let slate = adaptive(UIColor(red: 0.35, green: 0.43, blue: 0.52, alpha: 1),
                                dark: UIColor(red: 0.64, green: 0.71, blue: 0.77, alpha: 1))
    static let accent = adaptive(UIColor(red: 0.26, green: 0.38, blue: 0.49, alpha: 1),
                                 dark: UIColor(red: 0.63, green: 0.77, blue: 0.86, alpha: 1))
    static let actionFill = adaptive(UIColor(red: 0.26, green: 0.38, blue: 0.49, alpha: 1),
                                     dark: UIColor(red: 0.25, green: 0.42, blue: 0.56, alpha: 1))
    static let panel = adaptive(UIColor(red: 0.925, green: 0.938, blue: 0.95, alpha: 1),
                                dark: UIColor(red: 0.145, green: 0.19, blue: 0.24, alpha: 1))
    static let line = adaptive(UIColor(red: 0.84, green: 0.87, blue: 0.89, alpha: 1),
                               dark: UIColor(red: 0.24, green: 0.30, blue: 0.36, alpha: 1))
    static let good = adaptive(UIColor(red: 0.15, green: 0.45, blue: 0.30, alpha: 1),
                               dark: UIColor(red: 0.43, green: 0.80, blue: 0.58, alpha: 1))
    static let okay = adaptive(UIColor(red: 0.55, green: 0.37, blue: 0.06, alpha: 1),
                               dark: UIColor(red: 0.91, green: 0.72, blue: 0.35, alpha: 1))
    static let bad = adaptive(UIColor(red: 0.70, green: 0.22, blue: 0.19, alpha: 1),
                              dark: UIColor(red: 0.98, green: 0.53, blue: 0.48, alpha: 1))
    /// Corner radius shared by the app's cards and filled buttons.
    static let radius: CGFloat = 12
}

/// Square colors for each board theme, shared by the game board, the puzzle editor, and previews.
enum ChessBoardPalette {
    static func colors(for theme: String) -> [UIColor] {
        switch theme {
        case "Forest": return [
            ForkChessTheme.adaptive(UIColor(red: 0.92, green: 0.94, blue: 0.86, alpha: 1),
                                     dark: UIColor(red: 0.65, green: 0.70, blue: 0.59, alpha: 1)),
            ForkChessTheme.adaptive(UIColor(red: 0.45, green: 0.58, blue: 0.45, alpha: 1),
                                     dark: UIColor(red: 0.36, green: 0.48, blue: 0.38, alpha: 1))
        ]
        case "Walnut": return [
            ForkChessTheme.adaptive(UIColor(red: 0.95, green: 0.89, blue: 0.78, alpha: 1),
                                     dark: UIColor(red: 0.73, green: 0.66, blue: 0.54, alpha: 1)),
            ForkChessTheme.adaptive(UIColor(red: 0.65, green: 0.46, blue: 0.32, alpha: 1),
                                     dark: UIColor(red: 0.52, green: 0.38, blue: 0.29, alpha: 1))
        ]
        default: return [
            ForkChessTheme.adaptive(UIColor(red: 0.95, green: 0.93, blue: 0.88, alpha: 1),
                                     dark: UIColor(red: 0.64, green: 0.68, blue: 0.70, alpha: 1)),
            ForkChessTheme.adaptive(UIColor(red: 0.61, green: 0.70, blue: 0.77, alpha: 1),
                                     dark: UIColor(red: 0.40, green: 0.49, blue: 0.55, alpha: 1))
        ]
        }
    }

    static func coordinateColor(on square: UIColor, traits: UITraitCollection) -> UIColor {
        func luminance(_ color: UIColor) -> CGFloat {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            func linear(_ value: CGFloat) -> CGFloat {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
        let light = ChessPiecePalette.body(isWhite: true)
        let dark = ChessPiecePalette.ink
        let background = luminance(square)
        func contrast(_ color: UIColor) -> CGFloat {
            let foreground = luminance(color)
            return (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
        }
        return contrast(dark) >= contrast(light) ? dark : light
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
        updateAppearance()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (navigation: ChessNavigationController, _: UITraitCollection) in
            navigation.updateAppearance()
        }
    }

    private func updateAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = ForkChessTheme.background.resolvedColor(with: traitCollection)
        appearance.titleTextAttributes = [.foregroundColor: ForkChessTheme.navy.resolvedColor(with: traitCollection)]
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.tintColor = ForkChessTheme.accent
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

    func share(_ record: SavedGame, from source: UIView, barButtonItem: UIBarButtonItem? = nil) {
        let controller = UIActivityViewController(activityItems: [game.pgn(for: record)], applicationActivities: nil)
        if let barButtonItem {
            controller.popoverPresentationController?.barButtonItem = barButtonItem
        } else {
            controller.popoverPresentationController?.sourceView = source
            controller.popoverPresentationController?.sourceRect = source.bounds
        }
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
    configuration.baseBackgroundColor = ForkChessTheme.actionFill
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
    /// CGColor does not retain a dynamic UIColor's appearance variants.
    func setThemeBorderColor(_ color: UIColor) {
        layer.borderColor = color.resolvedColor(with: traitCollection).cgColor
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: UIView, _: UITraitCollection) in
            view.layer.borderColor = color.resolvedColor(with: view.traitCollection).cgColor
        }
    }

    func redrawOnAppearanceChange() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: UIView, _: UITraitCollection) in
            view.setNeedsDisplay()
        }
    }

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
