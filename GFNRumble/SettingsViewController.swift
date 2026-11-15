import GameController
import UIKit

/// 설정 화면. 모든 값은 AppSettings(이 아이패드 안)에만 저장됩니다.
final class SettingsViewController: UITableViewController {

    private enum Row {
        case info(String)
        case slider(title: String, range: ClosedRange<Double>, format: (Double) -> String,
                    get: () -> Double, set: (Double) -> Void)
        case segmented(title: String, items: [String], get: () -> Int, set: (Int) -> Void)
        case toggle(title: String, get: () -> Bool, set: (Bool) -> Void, confirmOn: (title: String, message: String)?)
        case action(title: String, run: () -> Void)
    }

    private struct Section {
        let title: String?
        let footer: String?
        let rows: [Row]
    }

    private var sections: [Section] = []

    init() {
        super.init(style: .insetGrouped)
        title = "설정"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "닫기", style: .done,
                                                            target: self, action: #selector(close))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
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

    private static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    private static func times(_ value: Double) -> String { String(format: "%.1f×", value) }

    private func buildSections() {
        let s = AppSettings.shared
        sections = [
            Section(title: "서명 만료",
                    footer: "만료 전에 LocalDevVPN을 켜고 SideStore → My Apps → Refresh All을 눌러 주세요. 만료 3일 전부터 매일 밤 9시에 알려 드려요.",
                    rows: [.info(ExpiryMonitor.shared.statusText())]),

            Section(title: "진동", footer: nil, rows: [
                .slider(title: "진동 세기", range: 0...1.5, format: Self.percent,
                        get: { s.rumbleGain }, set: { s.rumbleGain = $0 }),
                .slider(title: "최소 세기", range: 0...0.3, format: Self.percent,
                        get: { s.rumbleMinimum }, set: { s.rumbleMinimum = $0 }),
                .action(title: "진동 테스트") { [weak self] in
                    if !RumbleManager.shared.runTest() {
                        self?.alert("진동 가능한 컨트롤러가 없어요", RumbleManager.shared.controllerStatus())
                    }
                }
            ]),

            Section(title: "방아쇠 효과·햅틱",
                    footer: "게임과 상관없이 직접 정한 효과예요. 듀얼센스 전용이에요. 게임 진동과 섞여서 함께 느껴져요. 저장 칸에 게임별 설정을 넣어 두고 바꿔 끼세요.",
                    rows: [
                        .action(title: "L2 상세 설정 — " + s.leftTrigger.mode.title) { [weak self] in
                            self?.navigationController?.pushViewController(TriggerDetailViewController(left: true), animated: true)
                        },
                        .action(title: "R2 상세 설정 — " + s.rightTrigger.mode.title) { [weak self] in
                            self?.navigationController?.pushViewController(TriggerDetailViewController(left: false), animated: true)
                        }
                    ] + (0..<3).flatMap { slot -> [Row] in
                        [
                            .action(title: "저장 칸 \(slot + 1)에 지금 설정 저장") { [weak self] in
                                s.saveTriggerSlot(slot)
                                self?.alert("저장했어요", "저장 칸 \(slot + 1)에 L2·R2 설정을 저장했어요.")
                            },
                            .action(title: "저장 칸 \(slot + 1) 불러오기" + (s.isTriggerSlotSaved(slot) ? "" : " (비어 있음)")) { [weak self] in
                                if s.loadTriggerSlot(slot) {
                                    self?.buildSections()
                                    self?.tableView.reloadData()
                                } else {
                                    self?.alert("비어 있어요", "먼저 저장 칸 \(slot + 1)에 설정을 저장해 주세요.")
                                }
                            }
                        ]
                    }),

            Section(title: "화면", footer: "16:9 게임 화면을 4:3 아이패드에 어떻게 맞출지 골라요.", rows: [
                .segmented(title: "화면 맞춤", items: VideoFit.allCases.map { $0.title },
                           get: { s.videoFit.rawValue },
                           set: { s.videoFit = VideoFit(rawValue: $0) ?? .fit }),
                .action(title: "화질 최대 설정 방법") { [weak self] in
                    self?.navigationController?.pushViewController(QualityGuideViewController(), animated: true)
                }
            ]),

            Section(title: "알림·경고", footer: "대기열·잠수 경고는 앱이 화면에 켜져 있을 때만 동작해요.", rows: [
                .toggle(title: "배터리·발열·연결 경고", get: { s.warningsEnabled },
                        set: { s.warningsEnabled = $0 }, confirmOn: nil),
                .toggle(title: "대기열 끝·잠수 경고", get: { s.sessionAlertsEnabled },
                        set: { s.sessionAlertsEnabled = $0 }, confirmOn: nil)
            ]),

            Section(title: "실험 기능",
                    footer: "실제 기기에서 확인 중인 기능이에요. 이상하면 끄고 알려 주세요.",
                    rows: [
                        .toggle(title: "TV 모드 (HDMI·AirPlay)", get: { s.tvModeEnabled },
                                set: { s.tvModeEnabled = $0 }, confirmOn: nil),
                        .info("TV를 연결하면 게임을 TV에 꽉 채워 보여 줘요(최대 1080p). AirPlay는 지연이 있어요."),
                        .slider(title: "스틱 데드존", range: 0...0.3, format: Self.percent,
                                get: { s.stickDeadzone }, set: { s.stickDeadzone = $0 }),
                        .slider(title: "스틱 반응 곡선", range: 0.5...2.0, format: Self.times,
                                get: { s.stickCurve }, set: { s.stickCurve = $0 }),
                        .toggle(title: "오른쪽 스틱 상하 반전", get: { s.invertRightStickY },
                                set: { s.invertRightStickY = $0 }, confirmOn: nil),
                        .toggle(title: "A↔B · X↔Y 바꾸기", get: { s.swapFaceButtons },
                                set: { s.swapFaceButtons = $0 }, confirmOn: nil),
                        .toggle(title: "마우스·키보드", get: { s.mouseModeEnabled },
                                set: { s.mouseModeEnabled = $0 }, confirmOn: nil),
                        .slider(title: "마우스 감도", range: 0.2...3.0, format: Self.times,
                                get: { s.mouseSensitivity }, set: { s.mouseSensitivity = $0 }),
                        .info("마우스·키보드는 앱을 완전히 껐다 켜야 적용돼요. 블루투스 마우스가 필요해요."),
                        .toggle(title: "해상도 강제 요청 (위험)", get: { s.request2K },
                                set: { s.request2K = $0 },
                                confirmOn: (title: "해상도 강제 요청을 켤까요?",
                                            message: "• 지포스 나우에 보내는 요청을 고치는 기능이라 NVIDIA 약관 위반으로 계정이 정지될 수 있어요.\n• 멤버십 등급보다 높으면 서버가 알아서 낮춰요.\n• 발열·데이터 사용이 늘어요.\n• 서버가 거부하면 자동으로 꺼지고, 해상도가 안 맞거나 끊김·발열이 생기면 화면에 알려 드려요.\n• 다음 게임을 시작할 때부터 적용돼요.")),
                        .segmented(title: "목표 해상도", items: ["1080p", "2048×1536", "2160×1620", "2K"],
                                   get: { s.resolutionPreset }, set: { s.resolutionPreset = $0 }),
                        .info("2048×1536과 2160×1620은 4:3이라 아이패드 화면에 꽉 차요. 실제로 받은 화질은 톱니바퀴 메뉴에서 볼 수 있어요.")
                    ]),

            Section(title: "자이로 조준 (듀얼센스)",
                    footer: "듀얼센스를 기울이거나 돌리면 오른쪽 스틱처럼 움직여요. Xbox·8BitDo는 자이로가 없어요. 방향이 반대면 반전·축을 바꿔 보세요.",
                    rows: [
                        .toggle(title: "자이로 조준", get: { s.gyroEnabled }, set: { s.gyroEnabled = $0 }, confirmOn: nil),
                        .segmented(title: "켜지는 때", items: ["항상", "L2 누를 때", "터치패드 누를 때"],
                                   get: { s.gyroActivation }, set: { s.gyroActivation = $0 }),
                        .slider(title: "가로 감도", range: 0.1...4.0, format: Self.times,
                                get: { s.gyroSensitivityX }, set: { s.gyroSensitivityX = $0 }),
                        .slider(title: "세로 감도", range: 0.1...4.0, format: Self.times,
                                get: { s.gyroSensitivityY }, set: { s.gyroSensitivityY = $0 }),
                        .toggle(title: "세로 반전", get: { s.gyroInvertY }, set: { s.gyroInvertY = $0 }, confirmOn: nil),
                        .toggle(title: "가로를 기울이기로 (기본: 돌리기)", get: { s.gyroUseRoll },
                                set: { s.gyroUseRoll = $0 }, confirmOn: nil),
                        .slider(title: "떨림 줄이기", range: 0...0.9, format: Self.percent,
                                get: { s.gyroSmoothing }, set: { s.gyroSmoothing = $0 })
                    ]),

            Section(title: "게임 소리 → 햅틱 (실험)",
                    footer: "게임 소리를 앱 안에서만 초저음·저음·중고음으로 나눠 분석해요. 폭발은 묵직하게, 총소리는 또렷하게, 왼쪽 소리는 왼쪽 손잡이로 울려요. 녹음·저장·전송은 없어요. 안 울리면 게임 화면을 한 번 터치해 주세요.",
                    rows: [
                        .toggle(title: "게임 소리 → 햅틱", get: { s.audioHapticsEnabled },
                                set: { s.audioHapticsEnabled = $0 }, confirmOn: nil),
                        .action(title: "프리셋: 액션") { [weak self] in s.applyAudioPreset(0); self?.controllersChanged() },
                        .action(title: "프리셋: 레이싱") { [weak self] in s.applyAudioPreset(1); self?.controllersChanged() },
                        .action(title: "프리셋: FPS") { [weak self] in s.applyAudioPreset(2); self?.controllersChanged() },
                        .slider(title: "전체 세기", range: 0.2...3.0, format: Self.times,
                                get: { s.audioHapticsGain }, set: { s.audioHapticsGain = $0 }),
                        .slider(title: "초저음 (폭발·엔진)", range: 0...2, format: Self.percent,
                                get: { s.audioSubGain }, set: { s.audioSubGain = $0 }),
                        .slider(title: "저음 (충격·발소리)", range: 0...2, format: Self.percent,
                                get: { s.audioBassGain }, set: { s.audioBassGain = $0 }),
                        .slider(title: "중고음 (총소리·금속)", range: 0...2, format: Self.percent,
                                get: { s.audioMidGain }, set: { s.audioMidGain = $0 }),
                        .slider(title: "날카로움 차이", range: 0...1, format: Self.percent,
                                get: { s.audioSharpness }, set: { s.audioSharpness = $0 }),
                        .slider(title: "타격감 ('탁')", range: 0...2, format: Self.percent,
                                get: { s.audioImpact }, set: { s.audioImpact = $0 }),
                        .slider(title: "공간 폭 (좌우)", range: 0...2, format: Self.percent,
                                get: { s.audioWidth }, set: { s.audioWidth = $0 }),
                        .slider(title: "튀는 속도", range: 0...1, format: Self.percent,
                                get: { s.audioAttack }, set: { s.audioAttack = $0 }),
                        .slider(title: "사라지는 속도", range: 0...1, format: Self.percent,
                                get: { s.audioRelease }, set: { s.audioRelease = $0 }),
                        .slider(title: "작은 소리 무시", range: 0...0.5, format: Self.percent,
                                get: { s.audioHapticsThreshold }, set: { s.audioHapticsThreshold = $0 }),
                        .toggle(title: "게임 진동도 같이 쓰기", get: { s.audioHapticsWithRumble },
                                set: { s.audioHapticsWithRumble = $0 }, confirmOn: nil)
                    ]),

            Section(title: "보안", footer: nil, rows: [
                .info("설정은 이 아이패드에만 저장돼요. 이 앱은 지포스 나우 외의 인터넷 주소에 접속하지 않고, 개인정보를 모으거나 보내지 않아요.")
            ])
        ]

        // 듀얼센스 전용 설정은 듀얼센스가 연결됐을 때만 보여 줍니다.
        if !TriggerEffects.isDualSenseConnected {
            let dualSenseOnly: Set<String> = ["방아쇠 효과·햅틱", "자이로 조준 (듀얼센스)", "게임 소리 → 햅틱 (실험)"]
            sections = sections.filter { !dualSenseOnly.contains($0.title ?? "") }
            sections.insert(Section(title: "듀얼센스 전용", footer: nil, rows: [
                .info("듀얼센스를 연결하면 방아쇠 효과·햅틱, 자이로 조준, 게임 소리 햅틱 설정이 나타나요.")
            ]), at: min(2, sections.count))
        }
    }

    @objc private func controllersChanged() {
        buildSections()
        tableView.reloadData()
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
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.textLabel?.numberOfLines = 0

        switch sections[indexPath.section].rows[indexPath.row] {
        case .info(let text):
            cell.textLabel?.text = text
            cell.textLabel?.font = .systemFont(ofSize: 15)
            cell.textLabel?.textColor = .secondaryLabel

        case let .slider(title, range, format, get, set):
            cell.textLabel?.text = title
            cell.detailTextLabel?.text = format(get())
            let slider = UISlider(frame: CGRect(x: 0, y: 0, width: 220, height: 30))
            slider.minimumValue = Float(range.lowerBound)
            slider.maximumValue = Float(range.upperBound)
            slider.value = Float(get())
            let label = cell.detailTextLabel
            slider.addAction(UIAction { action in
                guard let slider = action.sender as? UISlider else { return }
                set(Double(slider.value))
                label?.text = format(Double(slider.value))
            }, for: .valueChanged)
            cell.accessoryView = slider

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
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if case .action(_, let run) = sections[indexPath.section].rows[indexPath.row] {
            run()
        }
    }

    // MARK: - 알림창

    private func alert(_ title: String, _ message: String) {
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
