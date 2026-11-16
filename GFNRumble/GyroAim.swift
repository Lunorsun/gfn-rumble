import CoreMotion
import GameController
import UIKit
import WebKit

/// 자이로 조준: 기울이거나 돌리면 오른쪽 스틱처럼 움직입니다.
/// 센서는 둘 중 하나를 골라 씁니다.
///  - 컨트롤러: 자이로가 있는 모든 패드 (듀얼센스, 스위치 프로, 듀얼쇼크4 등)
///  - 아이패드: 아이패드 자체 자이로 (아이패드를 기울여 조준, 어떤 패드와도 같이 쓸 수 있음)
/// 센서 값만 읽어 웹페이지(gamepad-tweaks.js)의 오른쪽 스틱에 더합니다. 메인 스레드에서만 사용합니다.
final class GyroAim: NSObject {

    private let webView: () -> WKWebView?
    private var link: CADisplayLink?
    private var x: Double = 0
    private var y: Double = 0
    private var lastSentZero = true
    private var lastSent: (x: Double, y: Double) = (0, 0)
    private var inFlight = false

    private let padMotion = CMMotionManager()
    private var padMotionRunning = false

    /// 상태 보기용으로 센서 유무만 물어보는 관리자
    private static let probe = CMMotionManager()

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

    /// 컨트롤러별 자이로 유무 (설정·상태 화면에 표시)
    static func statusText() -> String {
        var lines: [String] = []
        for controller in GCController.controllers() {
            let name = controller.vendorName ?? "이름 없음"
            if let motion = controller.motion {
                lines.append("• \(name): " + (motion.hasRotationRate ? "자이로 있음" : "모션 센서만 있음 (자이로 없음)"))
            } else {
                lines.append("• \(name): 자이로 없음")
            }
        }
        if lines.isEmpty { lines.append("• 연결된 컨트롤러 없음") }
        lines.append("• 아이패드 자체 자이로: " + (probe.isDeviceMotionAvailable ? "있음" : "없음"))
        return lines.joined(separator: "\n")
    }

    /// 설정에 맞춰 센서를 켜거나 끕니다.
    @objc private func update() {
        let s = AppSettings.shared
        let enabled = s.gyroEnabled
        for controller in GCController.controllers() {
            guard let motion = controller.motion, motion.sensorsRequireManualActivation else { continue }
            motion.sensorsActive = enabled && s.gyroSource == 0
        }
        setPadMotion(enabled && s.gyroSource == 1)
        if enabled && link == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            self.link = link
        } else if !enabled {
            pause()
        }
    }

    private func setPadMotion(_ on: Bool) {
        if on && !padMotionRunning && padMotion.isDeviceMotionAvailable {
            padMotion.deviceMotionUpdateInterval = 1.0 / 60.0
            padMotion.startDeviceMotionUpdates()
            padMotionRunning = true
        } else if !on && padMotionRunning {
            padMotion.stopDeviceMotionUpdates()
            padMotionRunning = false
        }
    }

    @objc private func pause() {
        link?.invalidate()
        link = nil
        setPadMotion(false)
        x = 0
        y = 0
        send(0, 0, force: true)
    }

    private var interfaceOrientation: UIInterfaceOrientation {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation ?? .landscapeRight
    }

    @objc private func tick() {
        let s = AppSettings.shared

        // 센서 고르기
        var rate = CMRotationRate(x: 0, y: 0, z: 0)
        var padForButtons: GCController?
        var hasSensor = false
        let fromPad = s.gyroSource == 1
        if fromPad {
            if let motion = padMotion.deviceMotion {
                rate = motion.rotationRate
                hasSensor = true
            }
            padForButtons = GCController.controllers().first(where: { $0.extendedGamepad != nil })
        } else if let controller = GCController.controllers().first(where: { $0.motion?.hasRotationRate == true }),
                  let motion = controller.motion {
            let r = motion.rotationRate
            rate = CMRotationRate(x: r.x, y: r.y, z: r.z)
            hasSensor = true
            padForButtons = controller
        }
        guard hasSensor else {
            x = 0; y = 0
            if !lastSentZero { send(0, 0, force: true) }
            return
        }

        // 켜지는 조건
        var on = true
        switch s.gyroActivation {
        case 1: on = (padForButtons?.extendedGamepad?.leftTrigger.value ?? 0) > 0.3
        case 2: on = (padForButtons?.physicalInputProfile as? GCDualSenseGamepad)?.touchpadButton.isPressed ?? false
        case 3: on = padForButtons?.extendedGamepad?.leftShoulder.isPressed ?? false
        default: break
        }

        var targetX = 0.0, targetY = 0.0
        if on {
            let horizontal: Double
            let vertical: Double
            if fromPad {
                // 아이패드를 가로로 든 상태 기준: 좌우로 돌리면 가로, 앞뒤로 기울이면 세로.
                // 가로 방향(왼쪽/오른쪽으로 든 경우)에 따라 부호가 달라서, 맞지 않으면 설정의 반전 스위치를 쓰세요.
                let flip = interfaceOrientation == .landscapeLeft ? -1.0 : 1.0
                horizontal = (s.gyroUseRoll ? -rate.z : rate.x * flip) * (s.gyroPadInvertX ? -1 : 1)
                vertical = rate.y * flip
            } else {
                horizontal = s.gyroUseRoll ? -rate.z : -rate.y
                vertical = rate.x
            }
            targetX = horizontal * 0.35 * s.gyroSensitivityX
            targetY = vertical * 0.35 * s.gyroSensitivityY * (s.gyroInvertY ? 1 : -1)
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
