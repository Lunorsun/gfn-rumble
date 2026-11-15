import Foundation

/// 듀얼센스 방아쇠(L2/R2)에 넣을 흉내 효과.
enum TriggerEffect: Int, CaseIterable {
    case off = 0        // 끔
    case weapon = 1     // 총 방아쇠: 중간에 '딸깍' 걸림
    case vibration = 2  // 끝까지 당기면 '드르르' 떨림
    case resistance = 3 // 당길 때 뻑뻑함

    var title: String {
        switch self {
        case .off: return "끔"
        case .weapon: return "총 방아쇠"
        case .vibration: return "진동"
        case .resistance: return "저항"
        }
    }
}

/// 16:9 게임 화면을 4:3 아이패드 화면에 맞추는 방법.
enum VideoFit: Int, CaseIterable {
    case fit = 0      // 전체 보이기 (위아래 검은 띠)
    case fill = 1     // 꽉 채우기 (양옆이 조금 잘림)
    case stretch = 2  // 늘리기 (비율이 바뀜)

    var title: String {
        switch self {
        case .fit: return "전체 보이기"
        case .fill: return "꽉 채우기"
        case .stretch: return "늘리기"
        }
    }

    var cssValue: String {
        switch self {
        case .fit: return "fit"
        case .fill: return "fill"
        case .stretch: return "stretch"
        }
    }
}

/// 앱 설정. 아이패드 안(UserDefaults)에만 저장되고 어디로도 보내지 않습니다.
/// 메인 스레드에서만 사용합니다. 값이 바뀌면 `AppSettings.didChange` 알림이 갑니다.
final class AppSettings {

    static let shared = AppSettings()
    static let didChange = Notification.Name("GFNRumble.AppSettingsDidChange")

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - 진동

    /// 진동 세기 배율 0.0 ~ 1.5 (기본 1.0 = 원래 세기)
    var rumbleGain: Double {
        get { double("rumbleGain", default: 1.0, range: 0.0...1.5) }
        set { set(newValue, "rumbleGain", range: 0.0...1.5) }
    }

    /// 최소 세기 0.0 ~ 0.3 (기본 0). 아주 약한 진동도 이 세기 이상으로 올려 느껴지게 합니다.
    var rumbleMinimum: Double {
        get { double("rumbleMinimum", default: 0.0, range: 0.0...0.3) }
        set { set(newValue, "rumbleMinimum", range: 0.0...0.3) }
    }

    // MARK: - 듀얼센스 방아쇠

    var leftTriggerEffect: TriggerEffect {
        get { TriggerEffect(rawValue: defaults.integer(forKey: key("leftTriggerEffect"))) ?? .off }
        set { defaults.set(newValue.rawValue, forKey: key("leftTriggerEffect")); notify() }
    }

    var rightTriggerEffect: TriggerEffect {
        get { TriggerEffect(rawValue: defaults.integer(forKey: key("rightTriggerEffect"))) ?? .off }
        set { defaults.set(newValue.rawValue, forKey: key("rightTriggerEffect")); notify() }
    }

    /// 방아쇠 효과 세기 0.1 ~ 1.0 (기본 0.6)
    var triggerStrength: Double {
        get { double("triggerStrength", default: 0.6, range: 0.1...1.0) }
        set { set(newValue, "triggerStrength", range: 0.1...1.0) }
    }

    // MARK: - 화면

    var videoFit: VideoFit {
        get { VideoFit(rawValue: defaults.integer(forKey: key("videoFit"))) ?? .fit }
        set { defaults.set(newValue.rawValue, forKey: key("videoFit")); notify() }
    }

    // MARK: - 알림·경고

    /// 배터리·발열·저전력·연결 경고 배너 (기본 켬)
    var warningsEnabled: Bool {
        get { bool("warningsEnabled", default: true) }
        set { defaults.set(newValue, forKey: key("warningsEnabled")); notify() }
    }

    /// 대기열 끝·잠수 경고 (기본 켬)
    var sessionAlertsEnabled: Bool {
        get { bool("sessionAlertsEnabled", default: true) }
        set { defaults.set(newValue, forKey: key("sessionAlertsEnabled")); notify() }
    }

    // MARK: - 컨트롤러 조정 (실험)

    /// 스틱 데드존 0.0 ~ 0.3 (기본 0 = 끔)
    var stickDeadzone: Double {
        get { double("stickDeadzone", default: 0.0, range: 0.0...0.3) }
        set { set(newValue, "stickDeadzone", range: 0.0...0.3) }
    }

    /// 스틱 반응 곡선 0.5 ~ 2.0 (기본 1.0 = 그대로, 1보다 크면 가운데가 더 섬세)
    var stickCurve: Double {
        get { double("stickCurve", default: 1.0, range: 0.5...2.0) }
        set { set(newValue, "stickCurve", range: 0.5...2.0) }
    }

    /// 오른쪽 스틱 상하 반전 (기본 끔)
    var invertRightStickY: Bool {
        get { bool("invertRightStickY", default: false) }
        set { defaults.set(newValue, forKey: key("invertRightStickY")); notify() }
    }

    /// A↔B, X↔Y 자리 바꾸기 (8BitDo 닌텐도 배치용, 기본 끔)
    var swapFaceButtons: Bool {
        get { bool("swapFaceButtons", default: false) }
        set { defaults.set(newValue, forKey: key("swapFaceButtons")); notify() }
    }

    // MARK: - 실험 기능

    /// TV 모드: 외부 화면이 연결되면 게임을 TV로 보냅니다 (기본 끔)
    var tvModeEnabled: Bool {
        get { bool("tvModeEnabled", default: false) }
        set { defaults.set(newValue, forKey: key("tvModeEnabled")); notify() }
    }

    /// 마우스·키보드 모드 (기본 끔). 바꾸면 앱을 다시 시작해야 적용됩니다.
    var mouseModeEnabled: Bool {
        get { bool("mouseModeEnabled", default: false) }
        set { defaults.set(newValue, forKey: key("mouseModeEnabled")); notify() }
    }

    /// 마우스 감도 0.2 ~ 3.0 (기본 1.0)
    var mouseSensitivity: Double {
        get { double("mouseSensitivity", default: 1.0, range: 0.2...3.0) }
        set { set(newValue, "mouseSensitivity", range: 0.2...3.0) }
    }

    /// 실험: 지포스 나우에 2K(2560x1440) 화질을 요청 (기본 끔). NVIDIA 약관 위험이 있습니다.
    /// 바꾸면 다음 게임 시작부터 적용됩니다.
    var request2K: Bool {
        get { bool("request2K", default: false) }
        set { defaults.set(newValue, forKey: key("request2K")); notify() }
    }

    // MARK: - 웹페이지로 넘기는 설정

    /// 웹페이지(JS)에 넘길 설정. 개인정보는 들어가지 않습니다.
    /// 키: deadzone, curve, invertY, swapAB, videoFit, sessionAlerts, mouseMode, mouseSensitivity, request2K
    func jsConfig() -> [String: Any] {
        [
            "deadzone": stickDeadzone,
            "curve": stickCurve,
            "invertY": invertRightStickY,
            "swapAB": swapFaceButtons,
            "videoFit": videoFit.cssValue,
            "sessionAlerts": sessionAlertsEnabled,
            "mouseMode": mouseModeEnabled,
            "mouseSensitivity": mouseSensitivity,
            "request2K": request2K
        ]
    }

    /// jsConfig()를 JSON 문자열로. 실패하면 "{}".
    func jsConfigJSON() -> String {
        guard JSONSerialization.isValidJSONObject(jsConfig()),
              let data = try? JSONSerialization.data(withJSONObject: jsConfig(), options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    // MARK: - 내부

    private func key(_ name: String) -> String { "settings." + name }

    private func double(_ name: String, default value: Double, range: ClosedRange<Double>) -> Double {
        guard defaults.object(forKey: key(name)) != nil else { return value }
        return min(max(defaults.double(forKey: key(name)), range.lowerBound), range.upperBound)
    }

    private func bool(_ name: String, default value: Bool) -> Bool {
        guard defaults.object(forKey: key(name)) != nil else { return value }
        return defaults.bool(forKey: key(name))
    }

    private func set(_ value: Double, _ name: String, range: ClosedRange<Double>) {
        defaults.set(min(max(value, range.lowerBound), range.upperBound), forKey: key(name))
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: AppSettings.didChange, object: self)
    }
}
