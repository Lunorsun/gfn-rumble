import WebKit

/// 보안 벽: 앱 통로(진동·알림·소리 햅틱·화질·마우스)는 지포스 나우·NVIDIA 페이지에서 온 메시지만 받습니다.
/// 다른 사이트로 넘어가도 그 사이트는 앱 기능을 건드릴 수 없습니다.
/// scripts/security-check.sh가 모든 통로에 이 확인이 있는지 검사합니다.
enum MessageOrigin {

    /// 허용하는 주소 (이 주소 자신과 그 하위 주소)
    static let trustedDomains = ["geforcenow.com", "nvidia.com", "nvidiagrid.net"]

    /// 진단용: 막은 메시지 수
    private(set) static var rejectedCount = 0

    static func isTrusted(_ message: WKScriptMessage) -> Bool {
        let origin = message.frameInfo.securityOrigin
        let host = origin.host.lowercased()
        let ok = origin.protocol == "https"
            && trustedDomains.contains { host == $0 || host.hasSuffix("." + $0) }
        if !ok { rejectedCount += 1 }
        return ok
    }
}
