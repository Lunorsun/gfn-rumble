import GameController
import UIKit

/// 슬라이더 값의 단위
fileprivate enum SliderUnit { case percent, times, ms }

/// 슬라이더 한 줄의 정의
fileprivate struct SliderSpec {
    let title: String
    let range: ClosedRange<Double>
    let unit: SliderUnit
    let key: String?          // 기본값으로 되돌릴 때 쓰는 설정 이름
    let step: Double
    let fine: Bool            // 낮은 쪽을 더 촘촘하게 (세기 조절용)
    let get: () -> Double
    let set: (Double) -> Void

    func format(_ value: Double) -> String {
        switch unit {
        case .percent:
            let p = value * 100
            return abs(p - p.rounded()) < 0.05 ? "\(Int(p.rounded()))%" : String(format: "%.1f%%", p)
        case .times:
            return String(format: step < 0.1 ? "%.2f×" : "%.1f×", value)
        case .ms:
            return value < 5 ? "끔" : "\(Int(value.rounded()))ms"
        }
    }

    /// 직접 입력한 글자를 값으로 (범위 안으로 맞춤)
    func parse(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "×", with: "")
            .replacingOccurrences(of: "ms", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let number = Double(cleaned) else { return nil }
        let value = unit == .percent ? number / 100 : number
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// 단계에 맞춰 반올림
    func snap(_ value: Double) -> Double {
        let n = ((value - range.lowerBound) / step).rounded()
        let snapped = (range.lowerBound + n * step) * 10000
        return min(max(snapped.rounded() / 10000, range.lowerBound), range.upperBound)
    }
}

/// 슬라이더 줄: 위에는 이름·현재 값(눌러서 직접 입력)·↺, 아래에는 − 슬라이더 +
private final class SliderCell: UITableViewCell {

    private let spec: SliderSpec
    private weak var presenter: UIViewController?
    private let valueButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)
    private let slider = UISlider()

    init(spec: SliderSpec, presenter: UIViewController) {
        self.spec = spec
        self.presenter = presenter
        super.init(style: .default, reuseIdentifier: nil)
        selectionStyle = .none

        let title = UILabel()
        title.text = spec.title
        title.numberOfLines = 0
        title.font = .systemFont(ofSize: 17)
        // 이름은 남는 자리를 채우고(길면 줄바꿈), 값·버튼은 제 크기를 지킵니다.
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        valueButton.titleLabel?.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        valueButton.accessibilityHint = "눌러서 값을 직접 입력"
        valueButton.setContentHuggingPriority(.required, for: .horizontal)
        valueButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueButton.contentHorizontalAlignment = .trailing
        valueButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        valueButton.addAction(UIAction { [weak self] _ in self?.promptValue() }, for: .touchUpInside)

        Self.styleIcon(resetButton, "arrow.counterclockwise", label: "기본값으로 되돌리기")
        resetButton.addAction(UIAction { [weak self] _ in
            guard let self = self, let key = self.spec.key else { return }
            AppSettings.shared.resetKeys([key])
            self.refresh()
        }, for: .touchUpInside)
        resetButton.isHidden = spec.key == nil

        let top = UIStackView(arrangedSubviews: [title, valueButton, resetButton])
        top.axis = .horizontal
        top.spacing = 8
        top.alignment = .center

        let minus = UIButton(type: .system)
        Self.styleIcon(minus, "minus.circle", label: "한 칸 줄이기")
        minus.addAction(UIAction { [weak self] _ in self?.nudge(-1) }, for: .touchUpInside)
        let plus = UIButton(type: .system)
        Self.styleIcon(plus, "plus.circle", label: "한 칸 늘리기")
        plus.addAction(UIAction { [weak self] _ in self?.nudge(1) }, for: .touchUpInside)

        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.spec.set(self.value(for: self.slider.value))
            self.updateTexts()
        }, for: .valueChanged)

        let bottom = UIStackView(arrangedSubviews: [minus, slider, plus])
        bottom.axis = .horizontal
        bottom.spacing = 10
        bottom.alignment = .center

        let stack = UIStackView(arrangedSubviews: [top, bottom])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 아이콘 버튼: 손가락으로 누르기 쉽게 크기를 넉넉하게 잡아요.
    private static func styleIcon(_ button: UIButton, _ symbol: String, label: String) {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        button.accessibilityLabel = label
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
    }

    private func position(for value: Double) -> Float {
        let r = spec.range
        let t = max(0, min(1, (value - r.lowerBound) / (r.upperBound - r.lowerBound)))
        return Float(spec.fine ? t.squareRoot() : t)
    }

    private func value(for position: Float) -> Double {
        let r = spec.range
        let t = Double(position)
        let u = spec.fine ? t * t : t
        return spec.snap(r.lowerBound + u * (r.upperBound - r.lowerBound))
    }

    private func updateTexts() {
        let current = spec.get()
        valueButton.setTitle(spec.format(current), for: .normal)
        if let key = spec.key {
            resetButton.isEnabled = AppSettings.shared.isCustom(key)
        }
    }

    private func refresh() {
        slider.value = position(for: spec.get())
        updateTexts()
    }

    private func nudge(_ direction: Double) {
        let next = spec.snap(spec.get() + direction * spec.step)
        spec.set(next)
        refresh()
    }

    private func promptValue() {
        guard let presenter = presenter else { return }
        let unitText: String
        switch spec.unit {
        case .percent: unitText = "% 단위로 입력 (예: 12.5)"
        case .times: unitText = "배수로 입력 (예: 1.5)"
        case .ms: unitText = "ms 단위로 입력 (0이면 끔)"
        }
        let low = spec.format(spec.range.lowerBound), high = spec.format(spec.range.upperBound)
        let alert = UIAlertController(title: spec.title,
                                      message: "\(unitText)\n범위: \(low) ~ \(high)",
                                      preferredStyle: .alert)
        alert.addTextField { field in
            field.keyboardType = .decimalPad
            let current = self.spec.get()
            let shown = self.spec.unit == .percent ? current * 100 : current
            field.text = String(format: "%g", (shown * 100).rounded() / 100)
        }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "적용", style: .default) { [weak self, weak alert] _ in
            guard let self = self, let text = alert?.textFields?.first?.text,
                  let value = self.spec.parse(text) else { return }
            self.spec.set(value)
            self.refresh()
        })
        presenter.present(alert, animated: true)
    }
}

/// 설정 화면. 모든 값은 AppSettings(이 아이패드 안)에만 저장됩니다.
/// 첫 화면에는 자주 쓰는 것과 분류 목록만 있고, 분류를 누르면 그 안쪽 화면으로 들어가요.
final class SettingsViewController: UITableViewController {

    fileprivate enum Row {
        case info(String)
        case slider(SliderSpec)
        case segmented(title: String, items: [String], get: () -> Int, set: (Int) -> Void)
        case toggle(title: String, get: () -> Bool, set: (Bool) -> Void, confirmOn: (title: String, message: String)?)
        case action(title: String, run: () -> Void)
        /// 안쪽 화면으로 들어가는 줄. detail은 오른쪽에 보이는 현재 상태 요약.
        case link(title: String, detail: () -> String, warn: Bool, make: () -> UIViewController)
    }

    fileprivate struct Section {
        let title: String?
        let footer: String?
        let rows: [Row]
    }

    private var sections: [Section] = []
    private var provider: ((SettingsViewController) -> [Section])!
    private var extraResetKeys: [String] = []
    private var showsResetAll = false

    /// 첫 화면
    init() {
        super.init(style: .insetGrouped)
        title = "설정"
        provider = { $0.rootSections() }
    }

    /// 안쪽 화면
    fileprivate init(title: String, extraResetKeys: [String] = [], showsResetAll: Bool = true,
                     provider: @escaping (SettingsViewController) -> [Section]) {
        super.init(style: .insetGrouped)
        self.title = title
        self.provider = provider
        self.extraResetKeys = extraResetKeys
        self.showsResetAll = showsResetAll
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "닫기", style: .done,
                                                            target: self, action: #selector(close))
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(controllersChanged), name: .GCControllerDidConnect, object: nil)
        center.addObserver(self, selector: #selector(controllersChanged), name: .GCControllerDidDisconnect, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        buildSections()
        tableView.reloadData()
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func controllersChanged() {
        reloadScreen()
    }

    private func reloadScreen() {
        buildSections()
        tableView.reloadData()
    }

    // MARK: - 화면 만들기

    private func buildSections() {
        sections = provider(self)
        guard showsResetAll else { return }
        var keys = extraResetKeys
        for section in sections {
            for case .slider(let spec) in section.rows {
                if let key = spec.key { keys.append(key) }
            }
        }
        guard !keys.isEmpty else { return }
        let resetKeys = keys
        let count = resetKeys.count
        sections.append(Section(
            title: nil,
            footer: "줄마다 있는 ↺는 그 항목만 기본값으로 되돌려요. 아래 버튼은 이 창의 조절 값을 한꺼번에 되돌려요. 켜고 끄는 스위치는 그대로예요.",
            rows: [
                .action(title: "이 창의 조절 값 전부 기본값으로") { [weak self] in
                    self?.ask("이 창의 조절 값을 기본값으로 되돌릴까요?",
                              "조절 값 \(count)개(슬라이더·선택 항목)가 처음 상태로 돌아가요. 켜고 끄는 스위치는 바뀌지 않아요.",
                              yes: "되돌리기") {
                        AppSettings.shared.resetKeys(resetKeys)
                        self?.reloadScreen()
                    }
                }
            ]))
    }

    /// 슬라이더 줄 만들기. 세기처럼 아주 약하게 쓰는 값은 fine: true로 낮은 쪽을 촘촘하게 해요.
    fileprivate func sl(_ title: String, _ key: String, _ range: ClosedRange<Double>,
                        _ unit: SliderUnit = .percent, step: Double? = nil, fine: Bool = false,
                        get: @escaping () -> Double, set: @escaping (Double) -> Void) -> Row {
        let defaultStep: Double
        switch unit {
        case .percent: defaultStep = 0.01
        case .times: defaultStep = 0.1
        case .ms: defaultStep = 5
        }
        return .slider(SliderSpec(title: title, range: range, unit: unit, key: key,
                                  step: step ?? defaultStep, fine: fine, get: get, set: set))
    }

    private func percentText(_ value: Double) -> String {
        SliderSpec(title: "", range: 0...1, unit: .percent, key: nil, step: 0.01, fine: false,
                   get: { 0 }, set: { _ in }).format(value)
    }

    /// 첫 화면: 자주 쓰는 것 + 분류 목록
    private func rootSections() -> [Section] {
        let s = AppSettings.shared
        return [
            Section(title: "서명 만료",
                    footer: "만료 전에 LocalDevVPN을 켜고 SideStore → My Apps → Refresh All을 눌러 주세요. 만료 3일 전부터 매일 밤 9시에 알려 드려요.",
                    rows: [.info(ExpiryMonitor.shared.statusText())]),

            Section(title: "자주 쓰는 것",
                    footer: "숫자를 누르면 직접 입력할 수 있고, ↺는 그 항목을 기본값으로 되돌려요. 화면 왼쪽 아래 톱니바퀴 메뉴에서도 진동을 바로 켜고 끌 수 있어요.",
                    rows: [
                .toggle(title: "진동 켜기", get: { s.rumbleEnabled }, set: { s.rumbleEnabled = $0 }, confirmOn: nil),
                sl("전체 세기", "rumbleGain", 0...1.5, fine: true,
                   get: { s.rumbleGain }, set: { s.rumbleGain = $0 }),
                .link(title: "진동 시험", detail: { "" }, warn: false, make: { [unowned self] in self.testScreen() })
            ]),

            Section(title: "분류", footer: nil, rows: [
                .link(title: "진동", detail: { [unowned self] in s.rumbleEnabled ? "켜짐 · 세기 \(self.percentText(s.rumbleGain))" : "꺼짐" },
                      warn: false, make: { [unowned self] in self.vibrationScreen() }),
                .link(title: "컨트롤러", detail: { s.gyroEnabled ? "자이로 켜짐" : "" },
                      warn: false, make: { [unowned self] in self.controllerScreen() }),
                .link(title: "화면", detail: { s.videoFit.title },
                      warn: false, make: { [unowned self] in self.displayScreen() }),
                .link(title: "알림·경고", detail: { s.warningsEnabled || s.sessionAlertsEnabled ? "켜짐" : "꺼짐" },
                      warn: false, make: { [unowned self] in self.alertsScreen() }),
                .link(title: "내 설정 저장 칸", detail: { "" },
                      warn: false, make: { [unowned self] in self.slotsScreen() })
            ]),

            Section(title: "실험실", footer: "아직 확인 중인 기능이에요. 이상하면 끄고 알려 주세요.", rows: [
                .link(title: "실험 기능", detail: { "" }, warn: true, make: { [unowned self] in self.labScreen() })
            ]),

            Section(title: "정보", footer: nil, rows: [
                .info("설정은 이 아이패드에만 저장돼요. 이 앱은 지포스 나우 외의 인터넷 주소에 접속하지 않고, 개인정보를 모으거나 보내지 않아요.")
            ])
        ]
    }

    // MARK: 진동

    private func vibrationScreen() -> UIViewController {
        SettingsViewController(title: "진동", showsResetAll: false) { screen in
            let s = AppSettings.shared
            var power: [Row] = [
                .toggle(title: "진동 켜기", get: { s.rumbleEnabled }, set: { s.rumbleEnabled = $0 }, confirmOn: nil),
                .toggle(title: "게임 진동", get: { s.gameRumbleEnabled }, set: { s.gameRumbleEnabled = $0 }, confirmOn: nil)
            ]
            if TriggerEffects.isDualSenseConnected {
                power += [
                    .toggle(title: "방아쇠 햅틱", get: { s.triggerHapticsEnabled }, set: { s.triggerHapticsEnabled = $0 }, confirmOn: nil),
                    .toggle(title: "게임 소리 → 햅틱 (실험)", get: { s.audioHapticsEnabled }, set: { s.audioHapticsEnabled = $0 }, confirmOn: nil)
                ]
            }
            return [
                Section(title: "켜기·끄기",
                        footer: "끄면 게임 진동과 추가 햅틱이 모두 멈춰요. 진동 시험은 꺼 둬도 울려요. 게임 소리 햅틱을 켜면 게임 진동이 묻힐 수 있어요.",
                        rows: power),

                Section(title: "기본",
                        footer: "숫자를 누르면 직접 입력할 수 있고(예: 2.5), − / +는 1%씩 움직여요. ↺는 그 항목만 기본값으로 되돌려요. 슬라이더는 낮은 쪽이 더 촘촘해서 약한 세기를 맞추기 쉬워요.",
                        rows: [
                    screen.sl("전체 세기", "rumbleGain", 0...1.5, fine: true,
                              get: { s.rumbleGain }, set: { s.rumbleGain = $0 }),
                    screen.sl("방아쇠 진동 (L2·R2)", "triggerMotorGain", 0...1.5, fine: true,
                              get: { s.triggerMotorGain }, set: { s.triggerMotorGain = $0 }),
                    screen.sl("세기 상한", "rumbleCeiling", 0.05...1.0, fine: true,
                              get: { s.rumbleCeiling }, set: { s.rumbleCeiling = $0 }),
                    .segmented(title: "사용할 쪽", items: ["둘 다", "왼쪽만", "오른쪽만", "합치기"],
                               get: { s.rumbleSide }, set: { s.rumbleSide = $0 }),
                    .toggle(title: "왼쪽·오른쪽 바꾸기", get: { s.swapMotors }, set: { s.swapMotors = $0 }, confirmOn: nil)
                ]),

                Section(title: nil, footer: nil, rows: [
                    .link(title: "진동 시험", detail: { "" }, warn: false, make: { [unowned screen] in screen.testScreen() }),
                    .link(title: "세밀 설정", detail: { "손잡이별·곡선·좌우" }, warn: false, make: { [unowned screen] in screen.vibrationDetailScreen() })
                ]),

                Section(title: nil,
                        footer: "진동이 이상해졌을 때 한 번에 처음 상태로 돌아가는 버튼이에요. 누르면 한 번 더 물어봐요.",
                        rows: [
                    .action(title: "진동 설정 전부 처음 상태로") { [weak screen] in
                        screen?.ask("진동 설정을 전부 처음 상태로 되돌릴까요?",
                                    "세기·세밀 설정·좌우 설정이 모두 기본값으로 돌아가요. '게임 진동'과 '방아쇠 햅틱' 스위치도 켜짐으로 돌아가요. '진동 켜기' 스위치와 저장 칸은 그대로예요.",
                                    yes: "되돌리기") {
                            s.resetRumbleDetails()
                            screen?.reloadScreen()
                        }
                    }
                ])
            ]
        }
    }

    private func vibrationDetailScreen() -> UIViewController {
        SettingsViewController(title: "진동 세밀 설정") { screen in
            let s = AppSettings.shared
            return [
                Section(title: "왼쪽 손잡이 (묵직한 진동)",
                        footer: "곡선이 1보다 크면 약한 진동이 더 약해지고, 작으면 약한 진동도 또렷해져요.",
                        rows: [
                    screen.sl("세기", "leftMotorGain", 0...1.5, fine: true,
                              get: { s.leftMotorGain }, set: { s.leftMotorGain = $0 }),
                    screen.sl("상한", "leftCeiling", 0.05...1.0, fine: true,
                              get: { s.leftCeiling }, set: { s.leftCeiling = $0 }),
                    screen.sl("반응 곡선", "leftCurve", 0.5...2.0, .times,
                              get: { s.leftCurve }, set: { s.leftCurve = $0 }),
                    screen.sl("작은 진동 무시", "leftDeadzone", 0...0.5,
                              get: { s.leftDeadzone }, set: { s.leftDeadzone = $0 })
                ]),

                Section(title: "오른쪽 손잡이 (가벼운 진동)", footer: nil, rows: [
                    screen.sl("세기", "rightMotorGain", 0...1.5, fine: true,
                              get: { s.rightMotorGain }, set: { s.rightMotorGain = $0 }),
                    screen.sl("상한", "rightCeiling", 0.05...1.0, fine: true,
                              get: { s.rightCeiling }, set: { s.rightCeiling = $0 }),
                    screen.sl("반응 곡선", "rightCurve", 0.5...2.0, .times,
                              get: { s.rightCurve }, set: { s.rightCurve = $0 }),
                    screen.sl("작은 진동 무시", "rightDeadzone", 0...0.5,
                              get: { s.rightDeadzone }, set: { s.rightDeadzone = $0 })
                ]),

                Section(title: "좌우 차이",
                        footer: "0%는 양쪽이 같게, 100%는 원래대로, 200%는 센 쪽을 더 세게·약한 쪽을 더 약하게 해요.",
                        rows: [
                    screen.sl("좌우 차이", "rumbleWidth", 0...2,
                              get: { s.rumbleWidth }, set: { s.rumbleWidth = $0 })
                ]),

                Section(title: "전체 느낌",
                        footer: "날카로움은 낮으면 묵직하고 높으면 또렷해요(컨트롤러에 따라 차이가 없을 수 있어요). 최소 세기는 아주 약한 진동도 이 세기까지 올려 줘요.",
                        rows: [
                    screen.sl("반응 곡선", "rumbleCurve", 0.5...2.0, .times,
                              get: { s.rumbleCurve }, set: { s.rumbleCurve = $0 }),
                    screen.sl("날카로움", "rumbleSharpness", 0...1,
                              get: { s.rumbleSharpness }, set: { s.rumbleSharpness = $0 }),
                    screen.sl("진동 길이", "rumbleLengthScale", 0.5...2.0, .times,
                              get: { s.rumbleLengthScale }, set: { s.rumbleLengthScale = $0 }),
                    screen.sl("끝 부드럽게 줄이기", "rumbleFadeMs", 0...300, .ms,
                              get: { s.rumbleFadeMs }, set: { s.rumbleFadeMs = $0 }),
                    screen.sl("작은 진동 무시", "rumbleDeadzone", 0...0.5,
                              get: { s.rumbleDeadzone }, set: { s.rumbleDeadzone = $0 }),
                    screen.sl("최소 세기", "rumbleMinimum", 0...0.3, fine: true,
                              get: { s.rumbleMinimum }, set: { s.rumbleMinimum = $0 })
                ])
            ]
        }
    }

    private func testScreen() -> UIViewController {
        SettingsViewController(title: "진동 시험", showsResetAll: false) { screen in
            var rows: [Row] = []
            for pattern in TestPattern.allCases {
                rows.append(.action(title: pattern.title) { [weak screen] in
                    if !RumbleManager.shared.runPattern(pattern) {
                        screen?.alert("진동 가능한 컨트롤러가 없어요", RumbleManager.shared.controllerStatus())
                    }
                })
            }
            return [Section(title: "눌러서 느껴 보기",
                            footer: "지금 설정(세기·곡선·좌우 등)이 그대로 적용돼서 울려요. 마음에 안 들면 뒤로 가서 조절하고 다시 눌러 보세요.",
                            rows: rows)]
        }
    }

    private func slotsScreen() -> UIViewController {
        SettingsViewController(title: "내 설정 저장 칸", showsResetAll: false) { screen in
            let s = AppSettings.shared
            let rows: [Row] = (0..<3).flatMap { slot -> [Row] in
                [
                    .action(title: "저장 칸 \(slot + 1)에 지금 설정 저장" + (s.isTriggerSlotSaved(slot) ? " (덮어쓰기)" : "")) { [weak screen] in
                        s.saveTriggerSlot(slot)
                        screen?.reloadScreen()
                        screen?.alert("저장했어요", "저장 칸 \(slot + 1)에 진동 설정을 저장했어요.")
                    },
                    .action(title: "저장 칸 \(slot + 1) 불러오기" + (s.isTriggerSlotSaved(slot) ? "" : " (비어 있음)")) { [weak screen] in
                        if s.loadTriggerSlot(slot) {
                            screen?.reloadScreen()
                        } else {
                            screen?.alert("비어 있어요", "먼저 저장 칸 \(slot + 1)에 설정을 저장해 주세요.")
                        }
                    }
                ]
            }
            return [Section(title: "저장 칸",
                            footer: "진동 세밀 설정과 (듀얼센스 연결 시) L2·R2 설정을 한 칸에 같이 저장해요. 게임마다 칸을 나눠 쓰세요. 진동 켜기·끄기 스위치는 저장되지 않아요.",
                            rows: rows)]
        }
    }

    // MARK: 컨트롤러

    private func controllerScreen() -> UIViewController {
        SettingsViewController(title: "컨트롤러", showsResetAll: false) { screen in
            let s = AppSettings.shared
            var sections: [Section] = []
            if TriggerEffects.isDualSenseConnected {
                sections.append(Section(
                    title: "방아쇠 효과·햅틱",
                    footer: "게임과 상관없이 직접 정한 효과예요. 듀얼센스 전용이에요. 게임별 설정은 '내 설정 저장 칸'에 저장하세요.",
                    rows: [
                        .action(title: "L2 상세 설정 — " + s.leftTrigger.mode.title) { [weak screen] in
                            screen?.navigationController?.pushViewController(TriggerDetailViewController(left: true), animated: true)
                        },
                        .action(title: "R2 상세 설정 — " + s.rightTrigger.mode.title) { [weak screen] in
                            screen?.navigationController?.pushViewController(TriggerDetailViewController(left: false), animated: true)
                        }
                    ]))
            } else {
                sections.append(Section(title: "듀얼센스 전용", footer: nil, rows: [
                    .info("듀얼센스를 연결하면 방아쇠 효과·햅틱 설정이 나타나요.")
                ]))
            }
            sections.append(Section(title: "자이로 조준", footer: nil, rows: [
                .link(title: "자이로 조준", detail: { s.gyroEnabled ? "켜짐" : "꺼짐" }, warn: false,
                      make: { [unowned screen] in screen.gyroScreen() })
            ]))
            return sections
        }
    }

    private func gyroScreen() -> UIViewController {
        SettingsViewController(title: "자이로 조준", extraResetKeys: ["gyroSource", "gyroActivation"]) { screen in
            let s = AppSettings.shared
            return [
                Section(title: "기본",
                        footer: "기울이거나 돌리면 오른쪽 스틱처럼 움직여요. '컨트롤러'는 자이로가 있는 패드(듀얼센스·스위치 프로 등)에서, '아이패드'는 아이패드를 직접 기울여서 조준하고 어떤 패드와도 쓸 수 있어요(실험: 방향이 반대면 반전을 바꿔 보세요). 8BitDo처럼 값을 못 받는 패드는 아래 표시가 '없음'이에요. 터치패드는 듀얼센스만 돼요.",
                        rows: [
                    .toggle(title: "자이로 조준", get: { s.gyroEnabled }, set: { s.gyroEnabled = $0 }, confirmOn: nil),
                    .info("자이로 센서 확인\n" + GyroAim.statusText()),
                    .segmented(title: "센서", items: ["컨트롤러", "아이패드"],
                               get: { s.gyroSource }, set: { s.gyroSource = $0 }),
                    .segmented(title: "켜지는 때", items: ["항상", "L2", "터치패드", "L1"],
                               get: { s.gyroActivation }, set: { s.gyroActivation = $0 })
                ]),
                Section(title: "세밀 설정", footer: nil, rows: [
                    screen.sl("가로 감도", "gyroSensitivityX", 0.1...4.0, .times,
                              get: { s.gyroSensitivityX }, set: { s.gyroSensitivityX = $0 }),
                    screen.sl("세로 감도", "gyroSensitivityY", 0.1...4.0, .times,
                              get: { s.gyroSensitivityY }, set: { s.gyroSensitivityY = $0 }),
                    screen.sl("떨림 줄이기", "gyroSmoothing", 0...0.9,
                              get: { s.gyroSmoothing }, set: { s.gyroSmoothing = $0 }),
                    .toggle(title: "가로 반전 (아이패드 센서)", get: { s.gyroPadInvertX },
                            set: { s.gyroPadInvertX = $0 }, confirmOn: nil),
                    .toggle(title: "세로 반전", get: { s.gyroInvertY }, set: { s.gyroInvertY = $0 }, confirmOn: nil),
                    .toggle(title: "가로를 기울이기로 (기본: 돌리기)", get: { s.gyroUseRoll },
                            set: { s.gyroUseRoll = $0 }, confirmOn: nil)
                ])
            ]
        }
    }

    // MARK: 화면·알림

    private func displayScreen() -> UIViewController {
        SettingsViewController(title: "화면", showsResetAll: false) { screen in
            let s = AppSettings.shared
            return [Section(title: "화면 맞춤", footer: "16:9 게임 화면을 4:3 아이패드에 어떻게 맞출지 골라요.", rows: [
                .segmented(title: "화면 맞춤", items: VideoFit.allCases.map { $0.title },
                           get: { s.videoFit.rawValue },
                           set: { s.videoFit = VideoFit(rawValue: $0) ?? .fit }),
                .action(title: "화질 최대 설정 방법") { [weak screen] in
                    screen?.navigationController?.pushViewController(QualityGuideViewController(), animated: true)
                }
            ])]
        }
    }

    private func alertsScreen() -> UIViewController {
        SettingsViewController(title: "알림·경고", showsResetAll: false) { _ in
            let s = AppSettings.shared
            return [Section(title: "알림·경고", footer: "대기열·잠수 경고는 앱이 화면에 켜져 있을 때만 동작해요.", rows: [
                .toggle(title: "배터리·발열·연결 경고", get: { s.warningsEnabled },
                        set: { s.warningsEnabled = $0 }, confirmOn: nil),
                .toggle(title: "대기열 끝·잠수 경고", get: { s.sessionAlertsEnabled },
                        set: { s.sessionAlertsEnabled = $0 }, confirmOn: nil)
            ])]
        }
    }

    // MARK: 실험실

    private func labScreen() -> UIViewController {
        SettingsViewController(title: "실험 기능") { screen in
            let s = AppSettings.shared
            var sections: [Section] = [
                Section(title: "⚠️ 실험 기능",
                        footer: "실제 기기에서 확인 중인 기능이에요. 이상하면 끄고 알려 주세요.",
                        rows: [
                    .toggle(title: "TV 모드 (HDMI·AirPlay)", get: { s.tvModeEnabled },
                            set: { s.tvModeEnabled = $0 }, confirmOn: nil),
                    .info("TV를 연결하면 게임을 TV에 꽉 채워 보여 줘요(최대 1080p). AirPlay는 지연이 있어요."),
                    .toggle(title: "A↔B · X↔Y 바꾸기", get: { s.swapFaceButtons },
                            set: { s.swapFaceButtons = $0 }, confirmOn: nil),
                    .toggle(title: "오른쪽 스틱 상하 반전", get: { s.invertRightStickY },
                            set: { s.invertRightStickY = $0 }, confirmOn: nil)
                ]),
                Section(title: "스틱", footer: nil, rows: [
                    screen.sl("스틱 데드존", "stickDeadzone", 0...0.3,
                              get: { s.stickDeadzone }, set: { s.stickDeadzone = $0 }),
                    screen.sl("스틱 반응 곡선", "stickCurve", 0.5...2.0, .times,
                              get: { s.stickCurve }, set: { s.stickCurve = $0 })
                ]),
                Section(title: "마우스·키보드",
                        footer: "마우스·키보드는 앱을 완전히 껐다 켜야 적용돼요. 블루투스 마우스가 필요해요.",
                        rows: [
                    .toggle(title: "마우스·키보드", get: { s.mouseModeEnabled },
                            set: { s.mouseModeEnabled = $0 }, confirmOn: nil),
                    screen.sl("마우스 감도", "mouseSensitivity", 0.2...3.0, .times,
                              get: { s.mouseSensitivity }, set: { s.mouseSensitivity = $0 })
                ]),
                Section(title: "해상도 (위험)",
                        footer: "2048×1536과 2160×1620은 4:3이라 아이패드 화면에 꽉 차요. 실제로 받은 화질은 톱니바퀴 메뉴에서 볼 수 있어요.",
                        rows: [
                    .toggle(title: "해상도 강제 요청 (위험)", get: { s.request2K },
                            set: { s.request2K = $0 },
                            confirmOn: (title: "해상도 강제 요청을 켤까요?",
                                        message: "• 지포스 나우에 보내는 요청을 고치는 기능이라 NVIDIA 약관 위반으로 계정이 정지될 수 있어요.\n• 멤버십 등급보다 높으면 서버가 알아서 낮춰요.\n• 발열·데이터 사용이 늘어요.\n• 서버가 거부하면 자동으로 꺼지고, 해상도가 안 맞거나 끊김·발열이 생기면 화면에 알려 드려요.\n• 다음 게임을 시작할 때부터 적용돼요.")),
                    .segmented(title: "목표 해상도", items: ["1080p", "2048×1536", "2160×1620", "2K"],
                               get: { s.resolutionPreset }, set: { s.resolutionPreset = $0 })
                ])
            ]
            if TriggerEffects.isDualSenseConnected {
                sections.append(Section(title: "게임 소리 → 햅틱", footer: nil, rows: [
                    .link(title: "게임 소리 → 햅틱", detail: { s.audioHapticsEnabled ? "켜짐" : "꺼짐" }, warn: true,
                          make: { [unowned screen] in screen.audioScreen() })
                ]))
            }
            return sections
        }
    }

    private func audioScreen() -> UIViewController {
        SettingsViewController(title: "게임 소리 → 햅틱") { screen in
            let s = AppSettings.shared
            return [
                Section(title: "⚠️ 실험",
                        footer: "게임 소리를 앱 안에서만 5개 음역으로 나눠 1초에 120번 분석하고, 킥드럼·폭발은 '쿠웅', 총소리·스네어는 '탁'으로 따로 울려요. 녹음·저장·전송은 없어요. 켜 두면 게임 진동이 묻힐 수 있어요. 안 울리면 게임 화면을 한 번 터치해 주세요.",
                        rows: [
                    .toggle(title: "게임 소리 → 햅틱", get: { s.audioHapticsEnabled },
                            set: { s.audioHapticsEnabled = $0 }, confirmOn: nil),
                    .toggle(title: "게임 진동도 같이 쓰기", get: { s.audioHapticsWithRumble },
                            set: { s.audioHapticsWithRumble = $0 }, confirmOn: nil),
                    .action(title: "프리셋: 액션") { [weak screen] in s.applyAudioPreset(0); screen?.reloadScreen() },
                    .action(title: "프리셋: 레이싱") { [weak screen] in s.applyAudioPreset(1); screen?.reloadScreen() },
                    .action(title: "프리셋: FPS") { [weak screen] in s.applyAudioPreset(2); screen?.reloadScreen() },
                    .action(title: "프리셋: 음악처럼") { [weak screen] in s.applyAudioPreset(3); screen?.reloadScreen() }
                ]),
                Section(title: "세밀 설정", footer: nil, rows: [
                    screen.sl("전체 세기", "audioHapticsGain", 0.2...3.0, .times, step: 0.05, fine: true,
                              get: { s.audioHapticsGain }, set: { s.audioHapticsGain = $0 }),
                    screen.sl("초저음 (폭발·엔진)", "audioSubGain", 0...2,
                              get: { s.audioSubGain }, set: { s.audioSubGain = $0 }),
                    screen.sl("저음 (충격·발소리)", "audioBassGain", 0...2,
                              get: { s.audioBassGain }, set: { s.audioBassGain = $0 }),
                    screen.sl("중음 (목소리·악기)", "audioLowMidGain", 0...2,
                              get: { s.audioLowMidGain }, set: { s.audioLowMidGain = $0 }),
                    screen.sl("중고음 (총소리·스네어)", "audioMidGain", 0...2,
                              get: { s.audioMidGain }, set: { s.audioMidGain = $0 }),
                    screen.sl("고음 (하이햇·금속)", "audioHighGain", 0...2,
                              get: { s.audioHighGain }, set: { s.audioHighGain = $0 }),
                    screen.sl("날카로움 차이", "audioSharpness", 0...1,
                              get: { s.audioSharpness }, set: { s.audioSharpness = $0 }),
                    screen.sl("타격감 (쿠웅·탁)", "audioImpact", 0...2,
                              get: { s.audioImpact }, set: { s.audioImpact = $0 }),
                    screen.sl("공간 폭 (좌우)", "audioWidth", 0...2,
                              get: { s.audioWidth }, set: { s.audioWidth = $0 }),
                    screen.sl("튀는 속도", "audioAttack", 0...1,
                              get: { s.audioAttack }, set: { s.audioAttack = $0 }),
                    screen.sl("사라지는 속도", "audioRelease", 0...1,
                              get: { s.audioRelease }, set: { s.audioRelease = $0 }),
                    screen.sl("작은 소리 무시", "audioHapticsThreshold", 0...0.5,
                              get: { s.audioHapticsThreshold }, set: { s.audioHapticsThreshold = $0 })
                ])
            ]
        }
    }

    // MARK: - 표

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        sections[section].footer
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]
        if case .slider(let spec) = row {
            return SliderCell(spec: spec, presenter: self)
        }

        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.textLabel?.numberOfLines = 0

        switch row {
        case .info(let text):
            cell.textLabel?.text = text
            cell.textLabel?.font = .systemFont(ofSize: 15)
            cell.textLabel?.textColor = .secondaryLabel

        case .slider:
            break

        case let .segmented(title, items, get, set):
            cell.textLabel?.text = title
            let control = UISegmentedControl(items: items)
            control.selectedSegmentIndex = get()
            control.addAction(UIAction { action in
                guard let control = action.sender as? UISegmentedControl else { return }
                set(control.selectedSegmentIndex)
            }, for: .valueChanged)
            cell.accessoryView = control

        case let .toggle(title, get, set, confirmOn):
            cell.textLabel?.text = title
            let toggle = UISwitch()
            toggle.isOn = get()
            toggle.addAction(UIAction { [weak self] action in
                guard let toggle = action.sender as? UISwitch else { return }
                if toggle.isOn, let confirm = confirmOn {
                    self?.confirm(confirm.title, confirm.message, onYes: { set(true) },
                                  onNo: { toggle.setOn(false, animated: true) })
                } else {
                    set(toggle.isOn)
                }
            }, for: .valueChanged)
            cell.accessoryView = toggle

        case .action(let title, _):
            cell.textLabel?.text = title
            cell.textLabel?.textColor = .systemBlue
            cell.selectionStyle = .default

        case let .link(title, detail, warn, _):
            cell.textLabel?.text = title
            cell.textLabel?.textColor = warn ? .systemOrange : .label
            cell.detailTextLabel?.text = detail()
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].rows[indexPath.row] {
        case .action(_, let run):
            run()
        case .link(_, _, _, let make):
            navigationController?.pushViewController(make(), animated: true)
        default:
            break
        }
    }

    // MARK: - 알림창

    fileprivate func alert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }

    private func confirm(_ title: String, _ message: String, onYes: @escaping () -> Void, onNo: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in onNo() })
        alert.addAction(UIAlertAction(title: "위험을 알고 켜기", style: .destructive) { _ in onYes() })
        present(alert, animated: true)
    }

    private func ask(_ title: String, _ message: String, yes: String, onYes: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: yes, style: .destructive) { _ in onYes() })
        present(alert, animated: true)
    }
}

/// 지포스 나우 자체 설정으로 화질을 최대로 올리는 방법 안내.
final class QualityGuideViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "화질 최대 설정 방법"
        view.backgroundColor = .systemGroupedBackground
        let text = UITextView(frame: view.bounds)
        text.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        text.isEditable = false
        text.backgroundColor = .clear
        text.font = .systemFont(ofSize: 17)
        text.textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        text.text = """
        지포스 나우 자체 설정만으로 화질을 올리는 방법이에요. 계정 위험이 없어요.

        1. 지포스 나우 화면에서 설정(톱니바퀴)을 열어요.
        2. 스트리밍 품질 → 사용자 지정(Custom)을 골라요.
        3. 해상도: 1600x1200을 골라요. 아이패드 화면(4:3)에 꽉 차요.
           • 16:9 해상도(예: 1920x1080)를 고르면 위아래 검은 띠가 생겨요. 이때는 앱 설정 → 화면 맞춤으로 채울 수 있어요.
           • 목록에 1600x1200이 없으면 멤버십 등급이나 서버에 따라 다를 수 있어요.
        4. 프레임: 60 FPS.
        5. 끊기면 한 단계 낮춰 보세요.

        이 아이패드에서 의미가 없는 것
        • 120 FPS: 화면이 60Hz라 보이지 않아요.
        • 4K·HDR·AV1: 화면·칩이 지원하지 않아요.
        • VRR·V-Sync·Reflex: 지포스 나우 PC 앱 기능이라 브라우저판에는 없어요.
        """
        view.addSubview(text)
    }
}
