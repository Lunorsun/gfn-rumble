import Foundation

/// 새 버전 알림.
///
/// 보안 벽 (scripts/security-check.sh가 검사합니다):
/// - 앱에서 인터넷 요청을 하는 곳은 이 파일 하나뿐이고, 아래 고정 주소(공개 파일) 하나만 읽습니다.
/// - 쿠키·캐시·기록 없이(ephemeral) 요청하고, 아무것도 보내지 않습니다(GET만).
/// - 하루에 한 번만 확인하고, 설정에서 끌 수 있습니다.
final class UpdateCheck {

    static let shared = UpdateCheck()

    /// 확인하는 유일한 주소: GitHub 공개 릴리스의 source.json
    private static let sourceURL = URL(string: "https://github.com/Lunorsun/gfn-rumble/releases/latest/download/source.json")!
    private static let maxBytes = 256 * 1024
    private static let interval: TimeInterval = 24 * 3600

    private let defaults = UserDefaults.standard
    private static let enabledKey = "settings.updateCheck"
    private static let lastCheckKey = "updateCheck.last"

    /// 새 버전 알림 켜기 (기본 켬)
    var enabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) == nil ? true : defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    /// 상태 보기용: 마지막으로 확인한 최신 빌드 번호
    private(set) var latestBuild: Int?
    private(set) var lastResult = "아직 확인 안 함"

    var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    private var running = false

    private init() {}

    /// 앱이 화면에 나올 때 부릅니다. 하루가 안 지났으면 아무것도 하지 않습니다.
    func checkIfDue(force: Bool = false, show: @escaping (String) -> Void) {
        guard enabled || force, !running else { return }
        let last = defaults.double(forKey: Self.lastCheckKey)
        if !force, last > 0, Date().timeIntervalSince1970 - last < Self.interval { return }
        running = true

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config)
        var request = URLRequest(url: Self.sourceURL)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false

        session.dataTask(with: request) { [weak self] data, response, _ in
            let build = Self.parseBuild(data: data, response: response)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.running = false
                session.finishTasksAndInvalidate()
                guard let build = build else {
                    self.lastResult = "확인 실패 (인터넷 또는 파일 문제)"
                    if force { show("새 버전을 확인하지 못했어요. 잠시 뒤 다시 해 주세요.") }
                    return
                }
                self.defaults.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
                self.latestBuild = build
                if build > self.currentBuild {
                    self.lastResult = "새 버전 build-\(build) 있음"
                    show("새 버전 build-\(build)이 나왔어요 (지금 build-\(self.currentBuild)). SideStore 또는 PC iloader로 업데이트해 주세요.")
                } else {
                    self.lastResult = "최신 버전이에요 (build-\(self.currentBuild))"
                    if force { show("최신 버전이에요 (build-\(self.currentBuild)).") }
                }
            }
        }.resume()
    }

    /// source.json에서 첫 앱의 첫 버전 buildVersion 숫자 하나만 꺼냅니다.
    private static func parseBuild(data: Data?, response: URLResponse?) -> Int? {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let host = http.url?.host?.lowercased(),
              host == "github.com" || host.hasSuffix(".githubusercontent.com"),
              let data = data, data.count <= maxBytes,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apps = root["apps"] as? [[String: Any]],
              let versions = apps.first?["versions"] as? [[String: Any]],
              let text = versions.first?["buildVersion"] as? String,
              let build = Int(text), build > 0, build < 1_000_000
        else { return nil }
        return build
    }
}
