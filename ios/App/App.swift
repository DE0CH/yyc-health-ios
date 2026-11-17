// YYC Systems: Deyao's system health page (newswatch.yyc-internal.com/app/health, DE0CH/yyc-code news-stream
// -HealthPage.tsx) full screen in a WebView, signed in with his Cloudflare Access token. UIKit, one screen.
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let health = HealthViewController()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: ws)
        w.overrideUserInterfaceStyle = .dark
        w.rootViewController = health
        w.makeKeyAndVisible()
        window = w
    }

    func sceneWillEnterForeground(_ scene: UIScene) { health.cameToForeground() }
    func sceneDidBecomeActive(_ scene: UIScene) { health.becameActive() }
}
