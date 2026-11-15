import UIKit

/// TV 모드(실험): HDMI 어댑터나 AirPlay로 외부 화면이 연결되면 게임 화면을 TV로 옮깁니다.
/// 설정에서 TV 모드를 켰을 때만 TV용 창을 만듭니다. 창이 없으면 아이패드 화면이 그대로 미러링됩니다.
protocol ExternalDisplayHost: AnyObject {
    /// container(TV 화면)로 게임 화면을 옮겨 주세요.
    func externalDisplayDidConnect(_ container: UIView)
    /// 게임 화면을 아이패드로 되돌려 주세요.
    func externalDisplayDidDisconnect()
}

final class ExternalDisplayCoordinator {

    static let shared = ExternalDisplayCoordinator()

    weak var host: ExternalDisplayHost? {
        didSet { update() }
    }

    fileprivate weak var sceneDelegate: ExternalDisplaySceneDelegate?
    private var isShowingOnTV = false

    private init() {
        NotificationCenter.default.addObserver(forName: AppSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.update()
        }
    }

    /// 설정과 연결 상태에 맞춰 게임 화면 위치를 정합니다.
    fileprivate func update() {
        let wantTV = AppSettings.shared.tvModeEnabled && sceneDelegate != nil && host != nil
        if wantTV && !isShowingOnTV, let container = sceneDelegate?.showWindow() {
            isShowingOnTV = true
            host?.externalDisplayDidConnect(container)
        } else if !wantTV && isShowingOnTV {
            isShowingOnTV = false
            host?.externalDisplayDidDisconnect()
            sceneDelegate?.hideWindow()
        }
    }

    fileprivate func sceneGone() {
        if isShowingOnTV {
            isShowingOnTV = false
            host?.externalDisplayDidDisconnect()
        }
    }
}

/// 외부 화면용 장면. 터치가 없는 TV 화면입니다.
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private weak var windowScene: UIWindowScene?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        self.windowScene = windowScene
        ExternalDisplayCoordinator.shared.sceneDelegate = self
        ExternalDisplayCoordinator.shared.update()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        ExternalDisplayCoordinator.shared.sceneGone()
        window = nil
        if ExternalDisplayCoordinator.shared.sceneDelegate === self {
            ExternalDisplayCoordinator.shared.sceneDelegate = nil
        }
    }

    /// TV용 검은 창을 만들고, 게임 화면을 넣을 바탕을 돌려줍니다.
    fileprivate func showWindow() -> UIView? {
        guard let windowScene = windowScene else { return nil }
        let window = UIWindow(windowScene: windowScene)
        let root = UIViewController()
        root.view.backgroundColor = .black
        window.rootViewController = root
        window.isHidden = false
        self.window = window
        return root.view
    }

    /// 창을 없애 다시 미러링되게 합니다.
    fileprivate func hideWindow() {
        window?.isHidden = true
        window = nil
    }
}
