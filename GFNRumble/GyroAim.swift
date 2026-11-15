import GameController
import UIKit
import WebKit

/// 자이로 조준: 듀얼센스를 기울이거나 돌리면 오른쪽 스틱처럼 움직입니다.
/// 컨트롤러 센서 값만 읽어 웹페이지(gamepad-tweaks.js)의 오른쪽 스틱에 더합니다. 메인 스레드에서만 사용합니다.
final class GyroAim: NSObject {

    private let webView: () -> WKWebView?
    private var link: CADisplayLink?
    private var x: Double = 0
    private var y: Double = 0
    private var lastSentZero = true
    private var lastSent: (x: Double, y: Double) = (0, 0)
    private var inFlight = false

    init(webView: @escaping () -> WKWebView?) {
        self.webView = webView
        super.init()
    }

    func start() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(update), name: AppSettings.didChange, object: nil)
        center.addObserver(self, selector: #selector(update), name: .GCControllerDidConnect, object: nil)
        center.addObserver(self, selector: #selector(update), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(pause), name: UIApplication.willResignActiveNotification, object: nil)
        update()
    }

    /// 설정에 맞춰 센서를 켜거나 끕니다.
    @objc private func update() {
        let enabled = AppSettings.shared.gyroEnabled
        for controller in GCController.controllers() {
            guard let motion = controller.motion, motion.sensorsRequireManualActivation else { continue }
            motion.sensorsActive = enabled
        }
        if enabled && link == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            self.link = link
        } else if !enabled {
            pause()
        }
    }

    @objc private func pause() {
        link?.invalidate()
        link = nil
        x = 0
        y = 0
        send(0, 0, force: true)
    }

    @objc private func tick() {
        let s = AppSettings.shared
        guard let controller = GCController.controllers().first(where: { $0.motion?.hasRotationRate == true && $0.physicalInputProfile is GCDualSenseGamepad }),
              let motion = controller.motion else {
            x = 0; y = 0
            if !lastSentZero { send(0, 0, force: true) }
            return
        }

        // 켜지는 조건
        var on = true
        if s.gyroActivation == 1 {
            on = (controller.extendedGamepad?.leftTrigger.value ?? 0) > 0.3
        } else if s.gyroActivation == 2 {
            on = (controller.physicalInputProfile as? GCDualSenseGamepad)?.touchpadButton.isPressed ?? false
        }

        var targetX = 0.0, targetY = 0.0
        if on {
            let rate = motion.rotationRate   // 라디안/초
            let horizontal = s.gyroUseRoll ? -rate.z : -rate.y
            targetX = horizontal * 0.35 * s.gyroSensitivityX
            targetY = rate.x * 0.35 * s.gyroSensitivityY * (s.gyroInvertY ? 1 : -1)
            // 아주 작은 떨림은 무시
            if abs(targetX) < 0.02 { targetX = 0 }
            if abs(targetY) < 0.02 { targetY = 0 }
        }
        // 떨림 줄이기 (부드럽게). 조준 버튼을 놓으면 바로 0으로 (남은 값 때문에 계속 도는 것 방지)
        if on {
            let k = 1 - s.gyroSmoothing
            x += (targetX - x) * k
            y += (targetY - y) * k
        } else {
            x = 0
            y = 0
        }
        x = min(1, max(-1, x))
        y = min(1, max(-1, y))
        send(x, y)
    }

    private var lastSendTime: CFTimeInterval = 0

    private func send(_ x: Double, _ y: Double, force: Bool = false) {
        let zero = abs(x) < 0.001 && abs(y) < 0.001
        if zero && lastSentZero && !force { return }
        let now = CACurrentMediaTime()
        // 0이 아니면 최소 0.08초마다 다시 보내 웹페이지 쪽 값이 만료되지 않게 합니다.
        let stale = now - lastSendTime > 0.08
        // 거의 안 바뀌었으면 보내지 않아 게임 화면의 부담을 줄입니다.
        if !force && !stale && !zero && !lastSentZero && abs(x - lastSent.x) < 0.004 && abs(y - lastSent.y) < 0.004 { return }
        guard (!inFlight || force), let webView = webView() else { return }
        lastSendTime = now
        lastSentZero = zero
        lastSent = (x, y)
        inFlight = true
        let script = String(format: "window.__gfnGyro&&window.__gfnGyro.set(%.4f,%.4f)", zero ? 0 : x, zero ? 0 : y)
        webView.evaluateJavaScript(script) { [weak self] _, _ in self?.inFlight = false }
    }
}
