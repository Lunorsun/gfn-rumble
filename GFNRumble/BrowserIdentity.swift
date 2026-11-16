import Foundation

/// 브라우저 표시 (실험).
/// 웹페이지에 보여 주는 브라우저 이름표(User-Agent 글자)만 바꿉니다. 실제 엔진은 그대로 Safari(WebKit)입니다.
/// 기본은 Safari. Chrome으로 바꾸면 지포스 나우가 진동을 보내는지 시험할 수 있지만,
/// NVIDIA 약관상 '클라이언트 수정'으로 볼 수 있고, Chrome 전용 기능을 쓰려다 오류가 날 수 있습니다.
/// 보안 벽: 이름표 글자 외의 기기 정보(navigator.platform, 터치 수 등)는 바꾸지 않습니다.
enum BrowserIdentity {

    private static let key = "settings.chromeUserAgent"

    /// Chrome으로 보이기 (기본 끔). 바꾼 뒤 앱을 다시 켜야 적용됩니다.
    static var chromeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var currentName: String { chromeEnabled ? "Chrome (실험)" : "Safari (기본)" }

    static func userAgent() -> String {
        chromeEnabled ? chromeUserAgent() : safariUserAgent()
    }

    /// Mac Safari와 같은 이름표
    static func safariUserAgent() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "Version/\(version.majorVersion).\(version.minorVersion) Safari/605.1.15"
    }

    /// Mac Chrome과 같은 이름표
    static func chromeUserAgent() -> String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) "
            + "Chrome/142.0.0.0 Safari/537.36"
    }
}
