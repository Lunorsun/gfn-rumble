import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 게임 중 화면이 꺼지지 않게
        application.isIdleTimerDisabled = true
        // 서명 만료 알림 (알림 권한을 처음 한 번 물어봅니다)
        ExpiryMonitor.shared.start()
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if #available(iOS 16.0, *), connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            // TV 모드(실험): 외부 화면
            let configuration = UISceneConfiguration(name: "External", sessionRole: connectingSceneSession.role)
            configuration.delegateClass = ExternalDisplaySceneDelegate.self
            return configuration
        }
        let configuration = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = WebViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
