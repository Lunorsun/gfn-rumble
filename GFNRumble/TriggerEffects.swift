import GameController
import UIKit

/// 듀얼센스 방아쇠(L2/R2)에 흉내 효과를 넣습니다. 게임과 상관없이 설정대로 동작합니다.
/// 앱이 뒤로 가거나 컨트롤러가 끊기면 효과를 끕니다. 메인 스레드에서만 사용합니다.
final class TriggerEffects {

    static let shared = TriggerEffects()
    private var started = false

    private init() {}

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
            self?.applyAll()
        }
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resetAll()
        }
        applyAll()
    }

    /// 모든 듀얼센스의 방아쇠 효과를 끕니다.
    func resetAll() {
        for pad in dualSenses() {
            pad.leftTrigger.setModeOff()
            pad.rightTrigger.setModeOff()
        }
    }

    private func applyAll() {
        let settings = AppSettings.shared
        let strength = Float(settings.triggerStrength)
        for pad in dualSenses() {
            apply(settings.leftTriggerEffect, to: pad.leftTrigger, strength: strength)
            apply(settings.rightTriggerEffect, to: pad.rightTrigger, strength: strength)
        }
    }

    private func apply(_ effect: TriggerEffect, to trigger: GCDualSenseAdaptiveTrigger, strength: Float) {
        switch effect {
        case .off:
            trigger.setModeOff()
        case .weapon:
            // 중간쯤에서 '딸깍' 걸렸다가 풀림
            trigger.setModeWeaponWithStartPosition(0.25, endPosition: 0.55, resistiveStrength: strength)
        case .vibration:
            // 끝까지 당기면 '드르르'
            trigger.setModeVibrationWithStartPosition(0.7, amplitude: strength, frequency: 0.4)
        case .resistance:
            // 처음부터 뻑뻑함
            trigger.setModeFeedbackWithStartPosition(0.0, resistiveStrength: strength)
        }
    }

    private func dualSenses() -> [GCDualSenseGamepad] {
        GCController.controllers().compactMap { $0.physicalInputProfile as? GCDualSenseGamepad }
    }
}
