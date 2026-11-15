import GameController
import WebKit

/// 게임 소리 → 햅틱 (실험). 웹페이지(audio-haptics.js)가 보내는 저음 세기(왼쪽·오른쪽 숫자)만 받아
/// 듀얼센스 손잡이를 울립니다(듀얼센스 전용).
final class AudioHaptics: NSObject, WKScriptMessageHandler {

    static let shared = AudioHaptics()
    static let handlerName = "audiohaptics"

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        let s = AppSettings.shared
        guard s.audioHapticsEnabled,
              let body = message.body as? [String: Any],
              let l = (body["l"] as? NSNumber)?.doubleValue,
              let r = (body["r"] as? NSNumber)?.doubleValue,
              l.isFinite, r.isFinite,
              let controller = target() else { return }

        func shape(_ v: Double) -> Double {
            let t = s.audioHapticsThreshold
            guard v > t else { return 0 }
            return min(1, (v - t) / max(0.01, 1 - t) * s.audioHapticsGain)
        }
        var left = shape(l), right = shape(r)
        if !s.audioHapticsStereo {
            let both = max(left, right)
            left = both
            right = both
        }
        // 다음 값이 오지 않으면 0.12초 뒤 저절로 멈춥니다.
        RumbleManager.shared.kick(controller, strong: left, weak: right, durationMs: 120)
    }

    private func target() -> GCController? {
        // 듀얼센스에서만 동작합니다.
        GCController.controllers().first(where: { $0.haptics != nil && $0.physicalInputProfile is GCDualSenseGamepad })
    }
}
