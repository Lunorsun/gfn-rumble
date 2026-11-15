import GameController
import UIKit

/// 방아쇠 효과 두 가지를 담당합니다. 게임과 상관없이 설정대로 동작합니다.
/// 1) 듀얼센스 방아쇠 자체 효과 (저항·경사·총·진동·구간)
/// 2) 방아쇠를 당길 때 손잡이 모터로 주는 햅틱 (단발 '퉁' / 연사 '투투투') — 진동 모터가 있는 모든 컨트롤러
/// 앱이 뒤로 가면 효과를 끕니다. 메인 스레드에서만 사용합니다.
final class TriggerEffects: NSObject {

    static let shared = TriggerEffects()

    private var started = false
    private var link: CADisplayLink?
    private var active = true

    /// 컨트롤러·방아쇠별 햅틱 상태
    private struct HapticState {
        var pressed = false
        var nextFire: CFTimeInterval = 0
    }
    private var states: [String: HapticState] = [:]

    private override init() {
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            self?.applyAll()
        }
        center.addObserver(forName: AppSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.applyAll()
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.active = true
            self?.applyAll()
        }
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.active = false
            self?.resetAll()
        }
        applyAll()
    }

    /// 모든 듀얼센스의 방아쇠 효과를 끄고 햅틱 감시를 멈춥니다.
    func resetAll() {
        for pad in dualSenses() {
            pad.leftTrigger.setModeOff()
            pad.rightTrigger.setModeOff()
        }
        link?.invalidate()
        link = nil
        states.removeAll()
    }

    /// 지금 연결된 컨트롤러에서 방아쇠를 얼마나 당겼는지 (0~1). 설정 화면의 막대용.
    func currentValue(left: Bool) -> Float? {
        guard let pad = (GCController.current ?? GCController.controllers().first)?.extendedGamepad else { return nil }
        return left ? pad.leftTrigger.value : pad.rightTrigger.value
    }

    // MARK: - 방아쇠 자체 효과

    private func applyAll() {
        let settings = AppSettings.shared
        let left = settings.leftTrigger, right = settings.rightTrigger
        for pad in dualSenses() {
            apply(left, to: pad.leftTrigger)
            apply(right, to: pad.rightTrigger)
        }
        updateHapticLoop(needed: active && (left.haptic != .off || right.haptic != .off))
    }

    private func apply(_ c: TriggerConfig, to trigger: GCDualSenseAdaptiveTrigger) {
        let start = Float(c.start), end = Float(c.end)
        let strength = Float(c.strength), endStrength = Float(c.endStrength), frequency = Float(c.frequency)
        switch c.mode {
        case .off:
            trigger.setModeOff()
        case .feedback:
            trigger.setModeFeedbackWithStartPosition(start, resistiveStrength: strength)
        case .weapon:
            trigger.setModeWeaponWithStartPosition(start, endPosition: max(end, start + 0.05), resistiveStrength: strength)
        case .vibration:
            trigger.setModeVibrationWithStartPosition(start, amplitude: strength, frequency: frequency)
        case .slope:
            if #available(iOS 15.4, *) {
                trigger.setModeSlopeFeedback(startPosition: start, endPosition: max(end, start + 0.05),
                                             startStrength: strength, endStrength: endStrength)
            } else {
                trigger.setModeFeedbackWithStartPosition(start, resistiveStrength: strength)
            }
        case .zoneFeedback:
            if #available(iOS 15.4, *) {
                let z = tenZones(c.zones)
                trigger.setModeFeedback(resistiveStrengths: GCDualSenseAdaptiveTrigger.PositionalResistiveStrengths(
                    values: (z[0], z[1], z[2], z[3], z[4], z[5], z[6], z[7], z[8], z[9])))
            } else {
                trigger.setModeFeedbackWithStartPosition(start, resistiveStrength: strength)
            }
        case .zoneVibration:
            if #available(iOS 15.4, *) {
                let z = tenZones(c.zones)
                trigger.setModeVibration(amplitudes: GCDualSenseAdaptiveTrigger.PositionalAmplitudes(
                    values: (z[0], z[1], z[2], z[3], z[4], z[5], z[6], z[7], z[8], z[9])), frequency: frequency)
            } else {
                trigger.setModeVibrationWithStartPosition(start, amplitude: strength, frequency: frequency)
            }
        }
    }

    private func tenZones(_ zones: [Double]) -> [Float] {
        var z = zones.prefix(10).map { Float($0) }
        while z.count < 10 { z.append(0) }
        return z
    }

    private func dualSenses() -> [GCDualSenseGamepad] {
        GCController.controllers().compactMap { $0.physicalInputProfile as? GCDualSenseGamepad }
    }

    // MARK: - 손잡이 햅틱 (단발 / 연사)

    private func updateHapticLoop(needed: Bool) {
        if needed && link == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            self.link = link
        } else if !needed {
            link?.invalidate()
            link = nil
            states.removeAll()
        }
    }

    @objc private func tick() {
        let settings = AppSettings.shared
        let now = CACurrentMediaTime()
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            let id = String(describing: ObjectIdentifier(controller))
            handle(settings.leftTrigger, value: pad.leftTrigger.value, key: id + "L",
                   left: true, controller: controller, now: now)
            handle(settings.rightTrigger, value: pad.rightTrigger.value, key: id + "R",
                   left: false, controller: controller, now: now)
        }
    }

    private func handle(_ c: TriggerConfig, value: Float, key: String, left: Bool,
                        controller: GCController, now: CFTimeInterval) {
        guard c.haptic != .off else { states[key] = nil; return }
        var state = states[key] ?? HapticState()
        let threshold = Float(c.hapticThreshold)
        let isPressed = state.pressed ? value >= threshold - 0.05 : value >= max(0.02, threshold)

        if isPressed {
            let fire: Bool
            switch c.haptic {
            case .single: fire = !state.pressed
            case .rapid: fire = !state.pressed || now >= state.nextFire
            case .off: fire = false
            }
            if fire {
                let s = c.hapticStrength
                RumbleManager.shared.kick(controller,
                                          strong: left ? s : s * 0.7,
                                          weak: left ? s * 0.7 : s,
                                          durationMs: c.hapticLengthMs)
                state.nextFire = now + 1.0 / c.hapticRate
            }
        }
        state.pressed = isPressed
        states[key] = state
    }
}
