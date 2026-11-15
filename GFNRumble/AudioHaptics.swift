import GameController
import WebKit

/// 게임 소리 → 햅틱 (실험, 듀얼센스 전용).
/// 웹페이지(audio-haptics.js)가 보내는 숫자 8개(음역 3개 × 좌우 + 타격 좌우)만 받아
/// 세기·날카로움·좌우 위치를 계산해 듀얼센스 손잡이를 울립니다.
final class AudioHaptics: NSObject, WKScriptMessageHandler {

    static let shared = AudioHaptics()
    static let handlerName = "audiohaptics"

    // 부드럽게 따라가는 현재 값 (왼, 오)
    private var level: (l: Double, r: Double) = (0, 0)
    private var sharp: (l: Double, r: Double) = (0.5, 0.5)

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        let s = AppSettings.shared
        guard s.audioHapticsEnabled,
              let body = message.body as? [String: Any],
              let raw = body["v"] as? [NSNumber], raw.count == 8,
              let controller = target() else { return }
        let v = raw.map { min(1, max(0, $0.doubleValue.isFinite ? $0.doubleValue : 0)) }
        // v: 0,1 초저음 / 2,3 저음 / 4,5 중고음 / 6,7 타격  (짝수 = 왼쪽, 홀수 = 오른쪽)

        // 1) 한쪽의 세기와 날카로움: 초저음은 묵직(0.1), 저음은 중간(0.4), 중고음은 또렷(0.95)
        func side(_ i: Int) -> (amount: Double, sharpness: Double) {
            let sub = v[0 + i] * s.audioSubGain
            let bass = v[2 + i] * s.audioBassGain
            let mid = v[4 + i] * s.audioMidGain
            let total = sub + bass + mid
            guard total > 0.0001 else { return (0, 0.5) }
            let mixed = (sub * 0.1 + bass * 0.4 + mid * 0.95) / total
            let sharpness = 0.5 + (mixed - 0.5) * s.audioSharpness
            return (total, sharpness)
        }
        var left = side(0), right = side(1)

        // 2) 공간 폭: 가운데 값을 기준으로 좌우 차이를 줄이거나 키움
        let center = (left.amount + right.amount) / 2
        left.amount = max(0, center + (left.amount - center) * s.audioWidth)
        right.amount = max(0, center + (right.amount - center) * s.audioWidth)

        // 3) 작은 소리 무시 + 전체 세기
        func shape(_ x: Double) -> Double {
            let t = s.audioHapticsThreshold
            guard x > t else { return 0 }
            return min(1, (x - t) / max(0.01, 1 - t) * s.audioHapticsGain)
        }
        let targetL = shape(left.amount), targetR = shape(right.amount)

        // 4) 튀는 속도 / 사라지는 속도
        func follow(_ current: Double, _ target: Double) -> Double {
            let k = target > current ? 0.15 + 0.85 * s.audioAttack : 0.05 + 0.6 * s.audioRelease
            return current + (target - current) * k
        }
        level = (follow(level.l, targetL), follow(level.r, targetR))
        sharp = (sharp.l + (left.sharpness - sharp.l) * 0.5, sharp.r + (right.sharpness - sharp.r) * 0.5)

        RumbleManager.shared.audioFrame(controller, left: level.l, right: level.r,
                                        sharpLeft: sharp.l, sharpRight: sharp.r, holdMs: 120)

        // 5) 타격음 '탁' (같은 공간 폭 적용)
        let hitL = v[6], hitR = v[7]
        if hitL > 0 || hitR > 0 {
            let hc = (hitL + hitR) / 2
            let tl = max(0, hc + (hitL - hc) * s.audioWidth) * s.audioImpact
            let tr = max(0, hc + (hitR - hc) * s.audioWidth) * s.audioImpact
            RumbleManager.shared.audioTap(controller, left: tl, right: tr,
                                          sharpness: 0.6 + 0.4 * s.audioSharpness)
        }
    }

    private func target() -> GCController? {
        // 듀얼센스에서만 동작합니다.
        GCController.controllers().first(where: { $0.haptics != nil && $0.physicalInputProfile is GCDualSenseGamepad })
    }
}
