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
        let game = makeGame()
        let navigation = ChessNavigationController(rootViewController: HomeViewController(game: game))
        let window = UIWindow(windowScene: scene)
        window.tintColor = ForkChessTheme.accent
        window.rootViewController = navigation
        self.game = game
        self.navigation = navigation
        self.window = window
        window.makeKeyAndVisible()
    }

    private func makeGame() -> GameViewModel {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let identifier = environment["FORKCHESS_UI_TEST_ID"], UUID(uuidString: identifier) != nil {
            // UI tests get a separate library, retained across relaunches in the same test.
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("UITests", isDirectory: true)
                .appendingPathComponent(identifier, isDirectory: true)
            let url = directory.appendingPathComponent("library.json")
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if let fixture = environment["FORKCHESS_UI_TEST_LIBRARY"] {
                    let data = Data(fixture.utf8)
                    _ = try JSONDecoder().decode(LocalLibrary.self, from: data)
                    try data.write(to: url, options: .atomic)
                }
            } catch {
                fatalError("Invalid UI test library: \(error)")
            }
            return GameViewModel(storageURL: url)
        }
        #endif
        return GameViewModel()
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
