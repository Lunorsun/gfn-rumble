import AudioToolbox
import UIKit
import WebKit

/// 웹페이지(session-watch.js)가 알려 주는 대기열 끝·잠수 경고를 배너·진동·소리로 알립니다.
/// 정해진 모양의 메시지만 받고, 나머지는 무시합니다.
final class SessionAlerts: NSObject, WKScriptMessageHandler {

    static let shared = SessionAlerts()
    static let handlerName = "session"

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              AppSettings.shared.sessionAlertsEnabled else { return }

        switch type {
        case "queueReady":
            WarningCenter.shared.show("게임 준비 완료! 지금 시작할 수 있어요.", duration: 8)
            RumbleManager.shared.pulse(strong: 1, weak: 1, durationMs: 700)
            AudioServicesPlaySystemSound(1007)
        case "idleWarning":
            WarningCenter.shared.show("곧 활동 없음으로 연결이 끊겨요. 컨트롤러를 움직여 주세요.", duration: 8)
            RumbleManager.shared.pulse(strong: 1, weak: 0.5, durationMs: 1000)
            AudioServicesPlaySystemSound(1005)
        default:
            break
        }
    }
}

/// 실험 기능 '2K 요청'을 켰을 때, 실제로 받은 화질을 보고 문제가 있으면 알립니다.
/// 웹페이지(resolution-2k.js)가 5초마다 숫자만 보내 줍니다: 가로, 세로, fps, 손실률.
final class QualityAlerts: NSObject, WKScriptMessageHandler {

    static let shared = QualityAlerts()
    static let handlerName = "quality"

    private var lowFpsCount = 0
    private var lossCount = 0
    private var resolutionWarned = false

    /// 새 게임(스트림)이 시작되면 다시 확인합니다.
    func reset() {
        lowFpsCount = 0
        lossCount = 0
        resolutionWarned = false
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        if type == "streamStarted" { reset(); return }
        guard type == "stats", AppSettings.shared.request2K else { return }

        func number(_ key: String) -> Double { (body[key] as? NSNumber)?.doubleValue ?? 0 }
        let width = Int(number("width")), height = Int(number("height"))
        let fps = number("fps"), loss = number("loss")
        let warnings = WarningCenter.shared

        // 2K가 적용되지 않음 (스트림이 안정된 뒤 한 번만)
        if height > 0 && height < 1300 && !resolutionWarned && number("seconds") >= 20 {
            resolutionWarned = true
            warnings.show("2K가 적용되지 않았어요 (지금 \(width)x\(height)). 멤버십 등급이 안 되거나 서버가 낮춘 거예요.", duration: 8)
        }

        // 끊김: 15초 넘게 45fps 미만
        lowFpsCount = (fps > 0 && fps < 45) ? lowFpsCount + 1 : 0
        if lowFpsCount == 3 {
            warnings.show("화면이 끊기고 있어요 (초당 \(Int(fps))프레임). 2K를 끄거나 지포스 나우 화질을 낮춰 보세요.", duration: 8)
        }

        // 연결 불안정: 15초 넘게 손실 3% 이상
        lossCount = loss >= 3 ? lossCount + 1 : 0
        if lossCount == 3 {
            warnings.show("연결이 불안정해요 (손실 \(Int(loss))%). 2K는 데이터를 많이 써요.", duration: 8)
        }

        // 발열
        let thermal = ProcessInfo.processInfo.thermalState
        if thermal == .serious || thermal == .critical {
            warnings.warn("thermal2K", "2K 때문에 아이패드가 뜨거워요. 2K를 꺼 보세요.")
        }
    }
}
