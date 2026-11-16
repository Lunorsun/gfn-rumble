import GameController
import UIKit
import WebKit

/// 마우스·키보드 모드(실험): 블루투스 마우스 움직임을 받아 웹페이지(pointer-lock.js)에 넣어 줍니다.
/// 공개 API(GCMouse, prefersPointerLocked)만 씁니다. 메인 스레드에서만 사용합니다.
final class MouseInput: NSObject, WKScriptMessageHandler {

    static let handlerName = "pointer"

    private weak var viewController: UIViewController?
    private let webView: () -> WKWebView?
    private(set) var isLocked = false

    private var pending: [[Any]] = []
    private var dx: Float = 0
    private var dy: Float = 0
    private var displayLink: CADisplayLink?
    private var inFlight = false
    private var observers: [NSObjectProtocol] = []

    init(viewController: UIViewController, webView: @escaping () -> WKWebView?) {
        self.viewController = viewController
        self.webView = webView
        super.init()
    }

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) { [weak self] note in
            if let mouse = note.object as? GCMouse { self?.attach(mouse) }
        })
        GCMouse.mice().forEach(attach)

        let link = CADisplayLink(target: self, selector: #selector(flush))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        setLocked(false)
    }

    // MARK: - 웹페이지에서 오는 잠금 요청

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard MessageOrigin.isTrusted(message),
              let text = message.body as? String else { return }
        if text == "lock" { setLocked(true) }
        if text == "unlock" { setLocked(false) }
    }

    private func setLocked(_ locked: Bool) {
        guard isLocked != locked else { return }
        isLocked = locked
        if #available(iOS 14.0, *) {
            viewController?.setNeedsUpdateOfPrefersPointerLocked()
        }
        if !locked { pending.removeAll(); dx = 0; dy = 0 }
    }

    /// 잠금 풀기 (세 손가락 탭 등)
    func unlock() {
        webView()?.evaluateJavaScript("window.__gfnPointer&&window.__gfnPointer.unlock()", completionHandler: nil)
        setLocked(false)
    }

    // MARK: - 마우스 입력

    private func attach(_ mouse: GCMouse) {
        guard let input = mouse.mouseInput else { return }
        input.mouseMovedHandler = { [weak self] _, deltaX, deltaY in
            DispatchQueue.main.async {
                guard let self = self, self.isLocked else { return }
                self.dx += deltaX
                self.dy -= deltaY   // GCMouse는 위가 +, 웹은 아래가 +
            }
        }
        button(input.leftButton, index: 0)
        if let right = input.rightButton { button(right, index: 2) }
        if let middle = input.middleButton { button(middle, index: 1) }
        input.scroll.valueChangedHandler = { [weak self] _, x, y in
            DispatchQueue.main.async {
                guard let self = self, self.isLocked else { return }
                self.pending.append(["w", Double(-x * 10), Double(-y * 10)])
            }
        }
    }

    private func button(_ button: GCControllerButtonInput, index: Int) {
        button.pressedChangedHandler = { [weak self] _, _, pressed in
            DispatchQueue.main.async {
                guard let self = self, self.isLocked else { return }
                self.flushMove()
                self.pending.append(["b", index, pressed ? 1 : 0])
            }
        }
    }

    private func flushMove() {
        if dx != 0 || dy != 0 {
            pending.append(["m", Double(dx), Double(dy)])
            dx = 0
            dy = 0
        }
    }

    /// 한 프레임에 한 번, 모인 입력을 웹페이지로 보냅니다. 이전 것이 끝나기 전에는 보내지 않습니다.
    @objc private func flush() {
        guard isLocked, !inFlight else { return }
        flushMove()
        guard !pending.isEmpty,
              JSONSerialization.isValidJSONObject(pending),
              let data = try? JSONSerialization.data(withJSONObject: pending),
              let json = String(data: data, encoding: .utf8),
              let webView = webView() else { return }
        pending.removeAll()
        inFlight = true
        webView.evaluateJavaScript("window.__gfnPointer&&window.__gfnPointer.batch(\(json))") { [weak self] _, _ in
            self?.inFlight = false
        }
    }
}
