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

    /// 진단용: 받은 횟수와 마지막 값
    private(set) var frameCount = 0
    private(set) var lastText = "없음"

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        let s = AppSettings.shared
        frameCount += 1
        guard s.audioHapticsEnabled,
              let body = message.body as? [String: Any],
              let raw = body["v"] as? [NSNumber], raw.count == 14,
              let controller = target() else { return }
        let v = raw.map { min(1, max(0, $0.doubleValue.isFinite ? $0.doubleValue : 0)) }
        // v: 음역 5개 × (왼, 오) = 0~9 [초저음, 저음, 중음, 중고음, 고음], 10·11 킥(쿠웅), 12·13 타격(탁)

        // 1) 한쪽의 세기와 날카로움: 음역마다 고유한 날카로움을 섞어 '음색'을 만듭니다.
        let gains = [s.audioSubGain, s.audioBassGain, s.audioLowMidGain, s.audioMidGain, s.audioHighGain]
        let tone: [Double] = [0.05, 0.3, 0.5, 0.8, 1.0]
        func side(_ i: Int) -> (amount: Double, sharpness: Double) {
            var total = 0.0, weighted = 0.0
            for b in 0..<5 {
                let e = v[b * 2 + i] * gains[b]
                total += e
                weighted += e * tone[b]
            }
            guard total > 0.0001 else { return (0, 0.5) }
            let sharpness = 0.5 + (weighted / total - 0.5) * s.audioSharpness
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

        lastText = String(format: "왼 %.2f / 오 %.2f", level.l, level.r)
        RumbleManager.shared.audioFrame(controller, left: level.l, right: level.r,
                                        sharpLeft: sharp.l, sharpRight: sharp.r, holdMs: 80)

        // 5) 킥 '쿠웅'(묵직)과 타격 '탁'(또렷) — 같은 공간 폭 적용
        func spread(_ l: Double, _ r: Double) -> (Double, Double) {
            let c = (l + r) / 2
            return (max(0, c + (l - c) * s.audioWidth) * s.audioImpact,
                    max(0, c + (r - c) * s.audioWidth) * s.audioImpact)
        }
        if v[10] > 0 || v[11] > 0 {
            let k = spread(v[10], v[11])
            RumbleManager.shared.audioTap(controller, left: k.0, right: k.1, sharpness: 0.15)
        }
        if v[12] > 0 || v[13] > 0 {
            let h = spread(v[12], v[13])
            RumbleManager.shared.audioTap(controller, left: h.0 * 0.8, right: h.1 * 0.8,
                                          sharpness: 0.6 + 0.4 * s.audioSharpness)
        }
    }
    private func target() -> GCController? {
        // 듀얼센스에서만 동작합니다.
        GCController.controllers().first(where: { $0.haptics != nil && $0.physicalInputProfile is GCDualSenseGamepad })
    }
}
