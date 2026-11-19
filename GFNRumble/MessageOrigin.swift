import WebKit

/// 보안 벽: 앱 통로(진동·알림·소리 햅틱·화질·마우스)는 지포스 나우·NVIDIA 페이지에서 온 메시지만 받습니다.
/// 다른 사이트로 넘어가도 그 사이트는 앱 기능을 건드릴 수 없습니다.
/// scripts/security-check.sh가 모든 통로에 이 확인이 있는지 검사합니다.
enum MessageOrigin {

    /// 허용하는 주소 (이 주소 자신과 그 하위 주소)
    static let trustedDomains = ["geforcenow.com", "nvidia.com", "nvidiagrid.net"]

    /// 진단용: 막은 메시지 수
    private(set) static var rejectedCount = 0
    /// 진단용: 마지막으로 막은 주소 (주소 이름만, 경로·내용은 남기지 않음)
    private(set) static var lastRejectedHost = ""

    static func isTrusted(_ message: WKScriptMessage) -> Bool {
        let origin = message.frameInfo.securityOrigin
        let host = origin.host.lowercased()
        let ok = origin.protocol == "https"
            && trustedDomains.contains { host == $0 || host.hasSuffix("." + $0) }
        if !ok {
            rejectedCount += 1
            let label = host.isEmpty ? (origin.protocol.isEmpty ? "빈 주소" : origin.protocol) : host
            lastRejectedHost = String(label.prefix(60))
        }
        return ok
    }

    /// 상태 보기용 문구. 로그인 팝업(구글·애플 등)에서도 올라가는 게 정상이에요.
    static var statusText: String {
        if rejectedCount == 0 { return "다른 사이트 요청 0회 무시" }
        let whereText = lastRejectedHost.isEmpty ? "알 수 없음" : lastRejectedHost
        return "다른 사이트 요청 \(rejectedCount)회 무시 (정상, 마지막: \(whereText))"
    }
}
