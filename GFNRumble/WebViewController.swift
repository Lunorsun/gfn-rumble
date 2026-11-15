import UIKit
import WebKit

/// 지포스 나우 웹페이지를 전체 화면으로 띄우고, 진동 브리지를 연결합니다.
final class WebViewController: UIViewController {

    private static let homeURL = URL(string: "https://play.geforcenow.com/")!

    private var webView: WKWebView!
    private var popup: WKWebView?
    private let menuButton = UIButton(type: .system)
    private let popupCloseButton = UIButton(type: .system)

    // 진단용 상태
    private var bridgeScriptLoaded = false
    private var bridgeReady = false
    private var bridgeInstalled = false
    private var pageCheckedRumble = false

    // 실험 기능
    private let mouseModeOn = AppSettings.shared.mouseModeEnabled   // 앱을 다시 켜야 바뀜
    private var mouseInput: MouseInput?
    private lazy var gyroAim = GyroAim { [weak self] in self?.webView }
    private let tvLabel = UILabel()

    // MARK: - 화면 설정

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersPointerLocked: Bool { mouseInput?.isLocked ?? false }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        _ = RumbleManager.shared   // 컨트롤러 감시 시작
        setUpWebView()
        setUpButtons()
        setUpTVLabel()
        WarningCenter.shared.attach(to: view)
        WarningCenter.shared.start()
        TriggerEffects.shared.start()
        ExternalDisplayCoordinator.shared.host = self
        gyroAim.start()

        if mouseModeOn {
            let input = MouseInput(viewController: self) { [weak self] in self?.webView }
            input.start()
            mouseInput = input
            webView.configuration.userContentController.add(input, name: MouseInput.handlerName)
            let unlock = UITapGestureRecognizer(target: self, action: #selector(unlockMouse))
            unlock.numberOfTouchesRequired = 3
            view.addGestureRecognizer(unlock)
        }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(settingsChanged),
                           name: AppSettings.didChange, object: nil)
        center.addObserver(self, selector: #selector(appBecameActive),
                           name: UIApplication.didBecomeActiveNotification, object: nil)

        webView.load(URLRequest(url: Self.homeURL))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        appBecameActive()
    }

    private func setUpWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // 아이패드 Safari와 똑같이 "데스크톱 모드"로 동작
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(iOS 15.4, *) {
            // 마우스 모드에서는 전체 화면 기능이 마우스 고정을 깨뜨려서 끕니다.
            configuration.preferences.isElementFullscreenEnabled = !mouseModeOn
        }

        let contentController = WKUserContentController()
        contentController.add(self, name: "rumble")
        contentController.add(SessionAlerts.shared, name: SessionAlerts.handlerName)
        contentController.add(QualityAlerts.shared, name: QualityAlerts.handlerName)
        contentController.add(AudioHaptics.shared, name: AudioHaptics.handlerName)

        // 설정 전달 통로를 가장 먼저 넣습니다.
        contentController.addUserScript(WKUserScript(source: Self.configHubScript(),
                                                     injectionTime: .atDocumentStart,
                                                     forMainFrameOnly: false))
        var scripts = ["rumble-bridge", "gamepad-tweaks", "video-fit", "session-watch", "resolution-2k", "audio-haptics"]
        if mouseModeOn { scripts.append("pointer-lock") }
        for name in scripts {
            guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
                  let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            contentController.addUserScript(WKUserScript(source: source,
                                                         injectionTime: .atDocumentStart,
                                                         forMainFrameOnly: false))
            if name == "rumble-bridge" { bridgeScriptLoaded = true }
        }
        configuration.userContentController = contentController

        let webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.customUserAgent = Self.safariUserAgent()
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .black
        view.addSubview(webView)
        self.webView = webView
    }

    private func setUpButtons() {
        // 왼쪽 아래의 흐릿한 톱니바퀴: 진동 테스트/상태 확인 메뉴
        menuButton.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        menuButton.tintColor = .white
        menuButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        menuButton.layer.cornerRadius = 18
        menuButton.alpha = 0.3
        menuButton.frame = CGRect(x: 10, y: view.bounds.height - 46, width: 36, height: 36)
        menuButton.autoresizingMask = [.flexibleRightMargin, .flexibleTopMargin]
        menuButton.addTarget(self, action: #selector(showMenu), for: .touchUpInside)
        view.addSubview(menuButton)

        // 로그인 등 팝업 창을 닫는 버튼
        popupCloseButton.setTitle("✕ 닫기", for: .normal)
        popupCloseButton.setTitleColor(.white, for: .normal)
        popupCloseButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        popupCloseButton.layer.cornerRadius = 8
        popupCloseButton.frame = CGRect(x: view.bounds.width - 100, y: 10, width: 90, height: 36)
        popupCloseButton.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        popupCloseButton.addTarget(self, action: #selector(closePopup), for: .touchUpInside)
        popupCloseButton.isHidden = true
        view.addSubview(popupCloseButton)
    }

    private func setUpTVLabel() {
        tvLabel.text = "TV에 게임을 보여 주는 중이에요\n설정에서 TV 모드를 끄면 아이패드로 돌아와요"
        tvLabel.numberOfLines = 0
        tvLabel.textAlignment = .center
        tvLabel.textColor = .white
        tvLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        tvLabel.frame = view.bounds
        tvLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tvLabel.isHidden = true
        view.insertSubview(tvLabel, at: 0)
    }

    /// 웹페이지에 설정을 넘기는 통로 (설정 값만, 개인정보 없음)
    private static func configHubScript() -> String {
        """
        (function () {
          if (window.__gfnApplyConfig) return;
          window.__gfnConfig = \(AppSettings.shared.jsConfigJSON());
          window.__gfnConfigListeners = window.__gfnConfigListeners || [];
          window.__gfnApplyConfig = function (c) {
            window.__gfnConfig = c;
            window.__gfnConfigListeners.forEach(function (f) { try { f(c); } catch (e) {} });
          };
        })();
        """
    }

    @objc private func settingsChanged() {
        let script = "window.__gfnApplyConfig&&window.__gfnApplyConfig(\(AppSettings.shared.jsConfigJSON()))"
        webView.evaluateJavaScript(script, completionHandler: nil)
        popup?.evaluateJavaScript(script, completionHandler: nil)
    }

    @objc private func appBecameActive() {
        ExpiryMonitor.shared.refresh()
        if let text = ExpiryMonitor.shared.bannerText() {
            WarningCenter.shared.show(text)
        }
    }

    @objc private func unlockMouse() {
        mouseInput?.unlock()
    }

    @objc private func openSettings() {
        let navigation = UINavigationController(rootViewController: SettingsViewController())
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }

    /// 아이패드 Safari가 보내는 것과 같은 브라우저 정보
    private static func safariUserAgent() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "Version/\(version.majorVersion).\(version.minorVersion) Safari/605.1.15"
    }

    // MARK: - 메뉴

    @objc private func showMenu() {
        let sheet = UIAlertController(title: "GFN Rumble",
                                      message: "서명: " + ExpiryMonitor.shared.statusText()
                                        + "\n받은 화질: " + (QualityAlerts.shared.lastSummary ?? "아직 없음 (게임 중에 확인)"),
                                      preferredStyle: .actionSheet)

        sheet.addAction(UIAlertAction(title: "설정", style: .default) { [weak self] _ in
            self?.openSettings()
        })
        sheet.addAction(UIAlertAction(title: "진동 테스트 1: 컨트롤러 직접", style: .default) { [weak self] _ in
            if !RumbleManager.shared.runTest() {
                self?.showInfo("진동 가능한 컨트롤러가 없어요",
                               RumbleManager.shared.controllerStatus())
            }
        })
        sheet.addAction(UIAlertAction(title: "진동 테스트 2: 웹페이지 경유", style: .default) { [weak self] _ in
            self?.runWebTest()
        })
        sheet.addAction(UIAlertAction(title: "상태 보기", style: .default) { [weak self] _ in
            self?.showStatus()
        })
        sheet.addAction(UIAlertAction(title: "새로고침", style: .default) { [weak self] _ in
            self?.activeWebView.reload()
        })
        sheet.addAction(UIAlertAction(title: "지포스 나우 처음 화면으로", style: .default) { [weak self] _ in
            self?.closePopup()
            self?.webView.load(URLRequest(url: Self.homeURL))
        })
        sheet.addAction(UIAlertAction(title: "이 버튼 숨기기 (앱을 다시 켜면 나타남)", style: .destructive) { [weak self] _ in
            self?.menuButton.isHidden = true
        })
        sheet.addAction(UIAlertAction(title: "닫기", style: .cancel))

        sheet.popoverPresentationController?.sourceView = menuButton
        sheet.popoverPresentationController?.sourceRect = menuButton.bounds
        present(sheet, animated: true)
    }

    private var activeWebView: WKWebView { popup ?? webView }

    /// 웹페이지 → 브리지 → 컨트롤러 전체 경로를 시험합니다.
    private func runWebTest() {
        let script = """
        (function () {
          var pads = Array.prototype.slice.call(navigator.getGamepads ? navigator.getGamepads() : []).filter(Boolean);
          if (!pads.length) return 'no-gamepad';
          var actuator = pads[0].vibrationActuator;
          if (!actuator) return 'no-actuator';
          actuator.playEffect('dual-rumble', { startDelay: 0, duration: 600, weakMagnitude: 1.0, strongMagnitude: 1.0 });
          return 'ok';
        })()
        """
        activeWebView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self = self else { return }
            switch result as? String {
            case "ok":
                break
            case "no-gamepad":
                self.showInfo("웹페이지가 컨트롤러를 아직 못 찾았어요",
                              "컨트롤러 버튼을 아무거나 한 번 누른 다음 다시 시도해 주세요.")
            case "no-actuator":
                self.showInfo("진동 브리지가 연결되지 않았어요", "'상태 보기'의 내용을 알려주세요.")
            default:
                self.showInfo("테스트 실패", error?.localizedDescription ?? "알 수 없는 오류")
            }
        }
    }

    private func showStatus() {
        let manager = RumbleManager.shared
        let lines = [
            "브리지 파일: " + (bridgeScriptLoaded ? "있음" : "없음 (빌드 문제)"),
            "브리지 실행: " + (bridgeReady ? (bridgeInstalled ? "정상" : "실행됐지만 설치 실패") : "아직 안 됨"),
            "지포스 나우가 진동 기능을 확인함: " + (pageCheckedRumble ? "예" : "아직 아니오"),
            "웹에서 받은 진동 명령: \(manager.webCommandCount)회",
            "마지막 명령: \(manager.lastWebCommand)",
            "",
            "컨트롤러",
            manager.controllerStatus(),
            "",
            "현재 주소: \(activeWebView.url?.host ?? "없음")"
        ]
        showInfo("상태", lines.joined(separator: "\n"))
    }

    private func showInfo(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }

    // MARK: - 팝업 창

    @objc private func closePopup() {
        popup?.removeFromSuperview()
        popup = nil
        popupCloseButton.isHidden = true
        // 웹킷은 '선택된' 웹뷰에만 컨트롤러 입력을 줘서, 로그인 창을 닫은 뒤 다시 선택합니다.
        webView.becomeFirstResponder()
    }
}

// MARK: - TV 모드 (실험)

extension WebViewController: ExternalDisplayHost {

    func externalDisplayDidConnect(_ container: UIView) {
        closePopup()
        webView.removeFromSuperview()
        webView.frame = container.bounds
        container.addSubview(webView)
        WarningCenter.shared.attach(to: container)
        tvLabel.isHidden = false
        DispatchQueue.main.async { [weak self] in self?.webView.becomeFirstResponder() }
    }

    func externalDisplayDidDisconnect() {
        webView.removeFromSuperview()
        webView.frame = view.bounds
        view.insertSubview(webView, aboveSubview: tvLabel)
        WarningCenter.shared.attach(to: view)
        tvLabel.isHidden = true
        DispatchQueue.main.async { [weak self] in self?.webView.becomeFirstResponder() }
    }
}

// MARK: - 웹에서 오는 진동 명령

extension WebViewController: WKScriptMessageHandler {

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        func number(_ key: String) -> Double {
            (body[key] as? NSNumber)?.doubleValue ?? 0
        }
        let index = Int(number("index"))
        let id = body["id"] as? String

        switch type {
        case "ready":
            bridgeReady = true
            bridgeInstalled = (body["installed"] as? Bool) ?? false
        case "probe":
            pageCheckedRumble = true
        case "play":
            RumbleManager.shared.handleWebPlay(webIndex: index, id: id,
                                               strong: number("strong"), weak: number("weak"),
                                               leftTrigger: number("leftTrigger"),
                                               rightTrigger: number("rightTrigger"),
                                               durationMs: number("duration"),
                                               delayMs: number("delay"))
        case "stop":
            RumbleManager.shared.handleWebStop(webIndex: index, id: id)
        case "stopAll":
            RumbleManager.shared.stopAll()
        default:
            break
        }
    }
}

// MARK: - 웹뷰 동작

extension WebViewController: WKUIDelegate, WKNavigationDelegate {

    /// 로그인처럼 새 창을 여는 경우: 화면 위에 팝업 웹뷰를 띄웁니다.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        closePopup()
        let popup = WKWebView(frame: view.bounds, configuration: configuration)
        popup.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        popup.customUserAgent = webView.customUserAgent
        popup.uiDelegate = self
        popup.navigationDelegate = self
        popup.scrollView.contentInsetAdjustmentBehavior = .never
        view.insertSubview(popup, belowSubview: menuButton)
        self.popup = popup
        popupCloseButton.isHidden = false
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView === popup {
            closePopup()
        }
    }

    /// 메모리 부족 등으로 웹 화면이 죽으면 다시 불러옵니다.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        RumbleManager.shared.stopAll()
        webView.reload()
    }
}
