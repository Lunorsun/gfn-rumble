import Foundation

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

    /// L2 / R2 방아쇠 설정 (JSON으로 이 아이패드에만 저장)
    var leftTrigger: TriggerConfig {
        get { triggerConfig("leftTrigger") }
        set { setTriggerConfig(newValue, "leftTrigger") }
    }

    var rightTrigger: TriggerConfig {
        get { triggerConfig("rightTrigger") }
        set { setTriggerConfig(newValue, "rightTrigger") }
    }

    /// 내 설정 저장 칸 (0, 1, 2). L2·R2를 함께 저장합니다.
    func saveTriggerSlot(_ slot: Int) {
        guard (0..<3).contains(slot) else { return }
        defaults.set(encode(leftTrigger), forKey: key("slot\(slot).left"))
        defaults.set(encode(rightTrigger), forKey: key("slot\(slot).right"))
        notify()
    }

    /// 저장 칸을 불러옵니다. 비어 있으면 false.
    @discardableResult
    func loadTriggerSlot(_ slot: Int) -> Bool {
        guard (0..<3).contains(slot),
              let l = decode(defaults.data(forKey: key("slot\(slot).left"))),
              let r = decode(defaults.data(forKey: key("slot\(slot).right"))) else { return false }
        defaults.set(encode(l), forKey: key("leftTrigger"))
        defaults.set(encode(r), forKey: key("rightTrigger"))
        notify()
        return true
    }

    func isTriggerSlotSaved(_ slot: Int) -> Bool {
        defaults.data(forKey: key("slot\(slot).left")) != nil
    }

    private func triggerConfig(_ name: String) -> TriggerConfig {
        decode(defaults.data(forKey: key(name))) ?? TriggerConfig()
    }

    private func setTriggerConfig(_ value: TriggerConfig, _ name: String) {
        defaults.set(encode(value.clamped()), forKey: key(name))
        notify()
    }

    private func encode(_ value: TriggerConfig) -> Data? {
        try? JSONEncoder().encode(value.clamped())
    }

    private func decode(_ data: Data?) -> TriggerConfig? {
        guard let data = data, let value = try? JSONDecoder().decode(TriggerConfig.self, from: data) else { return nil }
        return value.clamped()
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

    /// 강제로 요청할 해상도 (request2K가 켜졌을 때)
    static let resolutionPresets: [(title: String, width: Int, height: Int)] = [
        ("1920x1080 (16:9)", 1920, 1080),
        ("2048x1536 (4:3, 꽉 참)", 2048, 1536),
        ("2160x1620 (아이패드 원래 해상도)", 2160, 1620),
        ("2560x1440 (2K)", 2560, 1440)
    ]

    var resolutionPreset: Int {
        get { min(max(defaults.object(forKey: key("resolutionPreset")) == nil ? 3 : defaults.integer(forKey: key("resolutionPreset")), 0), 3) }
        set { defaults.set(min(max(newValue, 0), 3), forKey: key("resolutionPreset")); notify() }
    }

    // MARK: - 자이로 조준 (듀얼센스)

    var gyroEnabled: Bool {
        get { bool("gyroEnabled", default: false) }
        set { defaults.set(newValue, forKey: key("gyroEnabled")); notify() }
    }

    /// 0 = 항상, 1 = L2 누를 때만, 2 = 터치패드 누를 때만
    var gyroActivation: Int {
        get { min(max(defaults.integer(forKey: key("gyroActivation")), 0), 2) }
        set { defaults.set(min(max(newValue, 0), 2), forKey: key("gyroActivation")); notify() }
    }

    var gyroSensitivityX: Double {
        get { double("gyroSensitivityX", default: 1.0, range: 0.1...4.0) }
        set { set(newValue, "gyroSensitivityX", range: 0.1...4.0) }
    }

    var gyroSensitivityY: Double {
        get { double("gyroSensitivityY", default: 1.0, range: 0.1...4.0) }
        set { set(newValue, "gyroSensitivityY", range: 0.1...4.0) }
    }

    var gyroInvertY: Bool {
        get { bool("gyroInvertY", default: false) }
        set { defaults.set(newValue, forKey: key("gyroInvertY")); notify() }
    }

    /// 가로 조준에 쓸 축: false = 좌우로 돌리기, true = 좌우로 기울이기
    var gyroUseRoll: Bool {
        get { bool("gyroUseRoll", default: false) }
        set { defaults.set(newValue, forKey: key("gyroUseRoll")); notify() }
    }

    /// 떨림 줄이기 0.0 ~ 0.9
    var gyroSmoothing: Double {
        get { double("gyroSmoothing", default: 0.3, range: 0.0...0.9) }
        set { set(newValue, "gyroSmoothing", range: 0.0...0.9) }
    }

    // MARK: - 게임 소리 → 햅틱 (실험)

    var audioHapticsEnabled: Bool {
        get { bool("audioHapticsEnabled", default: false) }
        set { defaults.set(newValue, forKey: key("audioHapticsEnabled")); notify() }
    }

    /// 세기 0.2 ~ 3.0 (기본 1.0)
    var audioHapticsGain: Double {
        get { double("audioHapticsGain", default: 1.0, range: 0.2...3.0) }
        set { set(newValue, "audioHapticsGain", range: 0.2...3.0) }
    }

    /// 민감도: 이보다 작은 소리는 무시 0.0 ~ 0.5 (기본 0.08)
    var audioHapticsThreshold: Double {
        get { double("audioHapticsThreshold", default: 0.08, range: 0.0...0.5) }
        set { set(newValue, "audioHapticsThreshold", range: 0.0...0.5) }
    }

    /// 음역: 0 = 저음만, 1 = 저음+중음
    var audioHapticsBand: Int {
        get { min(max(defaults.integer(forKey: key("audioHapticsBand")), 0), 1) }
        set { defaults.set(min(max(newValue, 0), 1), forKey: key("audioHapticsBand")); notify() }
    }

    /// 좌우 분리: 왼쪽 소리 → 왼쪽 손잡이 (기본 켬)
    var audioHapticsStereo: Bool {
        get { bool("audioHapticsStereo", default: true) }
        set { defaults.set(newValue, forKey: key("audioHapticsStereo")); notify() }
    }

    /// 음역별 세기 0 ~ 2: 초저음(묵직), 저음(충격), 중고음(총소리·금속)
    var audioSubGain: Double {
        get { double("audioSubGain", default: 1.0, range: 0...2) }
        set { set(newValue, "audioSubGain", range: 0...2) }
    }
    var audioBassGain: Double {
        get { double("audioBassGain", default: 0.8, range: 0...2) }
        set { set(newValue, "audioBassGain", range: 0...2) }
    }
    var audioMidGain: Double {
        get { double("audioMidGain", default: 0.6, range: 0...2) }
        set { set(newValue, "audioMidGain", range: 0...2) }
    }

    /// 중음(목소리·악기 몸통, 기본 0 = 대화에 안 떨리게), 고음(하이햇·금속)
    var audioLowMidGain: Double {
        get { double("audioLowMidGain", default: 0.0, range: 0...2) }
        set { set(newValue, "audioLowMidGain", range: 0...2) }
    }
    var audioHighGain: Double {
        get { double("audioHighGain", default: 0.3, range: 0...2) }
        set { set(newValue, "audioHighGain", range: 0...2) }
    }

    /// 날카로움 차이 0 ~ 1 (0 = 모두 같은 느낌, 1 = 폭발은 묵직·총소리는 또렷)
    var audioSharpness: Double {
        get { double("audioSharpness", default: 0.7, range: 0...1) }
        set { set(newValue, "audioSharpness", range: 0...1) }
    }

    /// 타격감 0 ~ 2 ('탁' 세기)
    var audioImpact: Double {
        get { double("audioImpact", default: 1.0, range: 0...2) }
        set { set(newValue, "audioImpact", range: 0...2) }
    }

    /// 공간 폭 0 ~ 2 (0 = 양쪽 똑같이, 1 = 소리 그대로, 2 = 좌우 차이 크게)
    var audioWidth: Double {
        get { double("audioWidth", default: 1.0, range: 0...2) }
        set { set(newValue, "audioWidth", range: 0...2) }
    }

    /// 튀는 속도 0 ~ 1 (1 = 즉시), 사라지는 속도 0 ~ 1 (1 = 즉시)
    var audioAttack: Double {
        get { double("audioAttack", default: 0.85, range: 0...1) }
        set { set(newValue, "audioAttack", range: 0...1) }
    }
    var audioRelease: Double {
        get { double("audioRelease", default: 0.35, range: 0...1) }
        set { set(newValue, "audioRelease", range: 0...1) }
    }

    /// 프리셋: 0 = 액션, 1 = 레이싱, 2 = FPS, 3 = 음악처럼
    func applyAudioPreset(_ preset: Int) {
        let values: (sub: Double, bass: Double, lowMid: Double, mid: Double, high: Double, sharp: Double, impact: Double, width: Double, attack: Double, release: Double)
        switch preset {
        case 1:  values = (1.4, 0.9, 0.0, 0.3, 0.0, 0.4, 0.4, 0.8, 0.6, 0.2)   // 레이싱: 엔진 몸통 위주, 부드럽게
        case 2:  values = (0.6, 0.8, 0.0, 1.2, 0.6, 1.0, 1.6, 1.4, 1.0, 0.6)   // FPS: 총소리 또렷, 방향감 크게
        case 3:  values = (1.2, 1.0, 0.6, 0.8, 0.7, 1.0, 1.2, 1.0, 1.0, 0.7)   // 음악처럼: 모든 음역, 빠르게
        default: values = (1.1, 1.0, 0.0, 0.7, 0.3, 0.7, 1.1, 1.0, 0.85, 0.35) // 액션
        }
        audioLowMidGain = values.lowMid; audioHighGain = values.high
        audioSubGain = values.sub; audioBassGain = values.bass; audioMidGain = values.mid
        audioSharpness = values.sharp; audioImpact = values.impact; audioWidth = values.width
        audioAttack = values.attack; audioRelease = values.release
    }

    /// 게임이 보내는 진동도 같이 쓰기 (기본 켬)
    var audioHapticsWithRumble: Bool {
        get { bool("audioHapticsWithRumble", default: true) }
        set { defaults.set(newValue, forKey: key("audioHapticsWithRumble")); notify() }
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
            "request2K": request2K,
            "resWidth": Self.resolutionPresets[resolutionPreset].width,
            "resHeight": Self.resolutionPresets[resolutionPreset].height,
            "gyro": gyroEnabled,
            "audioHaptics": audioHapticsEnabled,
            "audioHapticsBand": audioHapticsBand
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
