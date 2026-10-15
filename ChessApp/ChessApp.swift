import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "ForkChess", sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var game: GameViewModel?
    private var navigation: UINavigationController?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let game = GameViewModel()
        let navigation = ChessNavigationController(rootViewController: HomeViewController(game: game))
        let window = UIWindow(windowScene: scene)
        window.tintColor = ForkChessTheme.accent
        window.rootViewController = navigation
        self.game = game
        self.navigation = navigation
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        game?.setSuspended(true, gameVisible: navigation?.topViewController is GameViewController)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        game?.setSuspended(false, gameVisible: navigation?.topViewController is GameViewController)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        game?.pause()
    }
}
