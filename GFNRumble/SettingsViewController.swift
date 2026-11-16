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

    private static func fade(_ value: Double) -> String { value < 5 ? "끔" : "\(Int(value.rounded()))ms" }

    private func buildSections() {
        let s = AppSettings.shared

        // 켜기·끄기: 듀얼센스 전용 항목은 듀얼센스가 연결됐을 때만 보여 줍니다.
        var powerRows: [Row] = [
            .toggle(title: "진동 켜기", get: { s.rumbleEnabled }, set: { s.rumbleEnabled = $0 }, confirmOn: nil),
            .toggle(title: "게임 진동", get: { s.gameRumbleEnabled }, set: { s.gameRumbleEnabled = $0 }, confirmOn: nil)
        ]
        if TriggerEffects.isDualSenseConnected {
            powerRows += [
                .toggle(title: "방아쇠 햅틱", get: { s.triggerHapticsEnabled }, set: { s.triggerHapticsEnabled = $0 }, confirmOn: nil),
                .toggle(title: "게임 소리 → 햅틱 (실험)", get: { s.audioHapticsEnabled }, set: { s.audioHapticsEnabled = $0 }, confirmOn: nil)
            ]
        }

        // 진동 시험 패턴 + 기본값으로 되돌리기
        var testRows: [Row] = []
        for pattern in TestPattern.allCases {
            testRows.append(.action(title: pattern.title) { [weak self] in
                if !RumbleManager.shared.runPattern(pattern) {
                    self?.alert("진동 가능한 컨트롤러가 없어요", RumbleManager.shared.controllerStatus())
                }
            })
        }
        testRows.append(.action(title: "진동 세부 설정 기본값으로 되돌리기") { [weak self] in
            s.resetRumbleDetails()
            self?.buildSections()
            self?.tableView.reloadData()
        })

        // 저장 칸 3개 (진동 세부 설정 + L2·R2)
        let slotRows: [Row] = (0..<3).flatMap { slot -> [Row] in
            [
                .action(title: "저장 칸 \(slot + 1)에 지금 설정 저장" + (s.isTriggerSlotSaved(slot) ? " (덮어쓰기)" : "")) { [weak self] in
                    s.saveTriggerSlot(slot)
                    self?.buildSections()
                    self?.tableView.reloadData()
                    self?.alert("저장했어요", "저장 칸 \(slot + 1)에 진동 설정을 저장했어요.")
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
        }

        sections = [
            Section(title: "서명 만료",
                    footer: "만료 전에 LocalDevVPN을 켜고 SideStore → My Apps → Refresh All을 눌러 주세요. 만료 3일 전부터 매일 밤 9시에 알려 드려요.",
                    rows: [.info(ExpiryMonitor.shared.statusText())]),

            Section(title: "진동 켜기·끄기",
                    footer: "끄면 게임 진동과 추가 햅틱이 모두 멈춰요. 아래 '진동 시험'은 꺼 둬도 울려요. 화면 왼쪽 아래 톱니바퀴 메뉴에서도 바로 켜고 끌 수 있어요.",
                    rows: powerRows),

            Section(title: "진동 세기", footer: "전체 세기에 왼쪽·오른쪽·방아쇠 배율이 곱해져요. 상한은 아무리 세게 와도 넘지 않는 세기예요.", rows: [
                .slider(title: "전체 세기", range: 0...1.5, format: Self.percent,
                        get: { s.rumbleGain }, set: { s.rumbleGain = $0 }),
                .slider(title: "왼쪽 손잡이 (묵직)", range: 0...1.5, format: Self.percent,
                        get: { s.leftMotorGain }, set: { s.leftMotorGain = $0 }),
                .slider(title: "오른쪽 손잡이 (가벼움)", range: 0...1.5, format: Self.percent,
                        get: { s.rightMotorGain }, set: { s.rightMotorGain = $0 }),
                .slider(title: "방아쇠 진동 (L2·R2)", range: 0...1.5, format: Self.percent,
                        get: { s.triggerMotorGain }, set: { s.triggerMotorGain = $0 }),
                .slider(title: "세기 상한", range: 0.2...1.0, format: Self.percent,
                        get: { s.rumbleCeiling }, set: { s.rumbleCeiling = $0 }),
                .slider(title: "작은 진동 무시", range: 0...0.5, format: Self.percent,
                        get: { s.rumbleDeadzone }, set: { s.rumbleDeadzone = $0 }),
                .slider(title: "최소 세기", range: 0...0.3, format: Self.percent,
                        get: { s.rumbleMinimum }, set: { s.rumbleMinimum = $0 })
            ]),

            Section(title: "진동 느낌",
                    footer: "반응 곡선: 1보다 크면 약한 진동이 더 약해지고(세게 울릴 때만 느껴짐), 작으면 약한 진동도 또렷해져요. 날카로움은 낮으면 묵직하고 높으면 또렷해요(컨트롤러에 따라 차이가 없을 수 있어요).",
                    rows: [
                .slider(title: "반응 곡선", range: 0.5...2.0, format: Self.times,
                        get: { s.rumbleCurve }, set: { s.rumbleCurve = $0 }),
                .slider(title: "날카로움", range: 0...1, format: Self.percent,
                        get: { s.rumbleSharpness }, set: { s.rumbleSharpness = $0 }),
                .slider(title: "진동 길이", range: 0.5...2.0, format: Self.times,
                        get: { s.rumbleLengthScale }, set: { s.rumbleLengthScale = $0 }),
                .slider(title: "끝 부드럽게 줄이기", range: 0...300, format: Self.fade,
                        get: { s.rumbleFadeMs }, set: { s.rumbleFadeMs = $0 })
            ]),

            Section(title: "좌우 설정", footer: "'합치기'는 한쪽에서만 오는 진동도 양쪽이 같이 울리게 해요.", rows: [
                .segmented(title: "사용할 쪽", items: ["둘 다", "왼쪽만", "오른쪽만", "합치기"],
                           get: { s.rumbleSide }, set: { s.rumbleSide = $0 }),
                .toggle(title: "왼쪽·오른쪽 바꾸기", get: { s.swapMotors }, set: { s.swapMotors = $0 }, confirmOn: nil)
            ]),

            Section(title: "진동 시험",
                    footer: "지금 설정(세기·곡선·좌우 등)이 그대로 적용돼서 울려요. 마음에 안 들면 슬라이더를 움직이고 다시 눌러 보세요.",
                    rows: testRows),

            Section(title: "내 설정 저장 칸",
                    footer: "진동 세부 설정과 (듀얼센스 연결 시) L2·R2 설정을 한 칸에 같이 저장해요. 게임마다 칸을 나눠 쓰세요. 진동 켜기·끄기 스위치는 저장되지 않아요.",
                    rows: slotRows),

            Section(title: "방아쇠 효과·햅틱",
                    footer: "게임과 상관없이 직접 정한 효과예요. 듀얼센스 전용이에요. 게임 진동과 섞여서 함께 느껴져요. 게임별 설정은 아래 '내 설정 저장 칸'에 저장하세요.",
                    rows: [
                        .action(title: "L2 상세 설정 — " + s.leftTrigger.mode.title) { [weak self] in
                            self?.navigationController?.pushViewController(TriggerDetailViewController(left: true), animated: true)
                        },
                        .action(title: "R2 상세 설정 — " + s.rightTrigger.mode.title) { [weak self] in
                            self?.navigationController?.pushViewController(TriggerDetailViewController(left: false), animated: true)
                        }
                    ]),

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
                    footer: "게임 소리를 앱 안에서만 5개 음역으로 나눠 1초에 120번 분석하고, 킥드럼·폭발은 '쿠웅', 총소리·스네어는 '탁'으로 따로 울려요. 폭발은 묵직하게, 총소리는 또렷하게, 왼쪽 소리는 왼쪽 손잡이로 울려요. 녹음·저장·전송은 없어요. 안 울리면 게임 화면을 한 번 터치해 주세요.",
                    rows: [
                        .toggle(title: "게임 소리 → 햅틱", get: { s.audioHapticsEnabled },
                                set: { s.audioHapticsEnabled = $0 }, confirmOn: nil),
                        .action(title: "프리셋: 액션") { [weak self] in s.applyAudioPreset(0); self?.controllersChanged() },
                        .action(title: "프리셋: 레이싱") { [weak self] in s.applyAudioPreset(1); self?.controllersChanged() },
                        .action(title: "프리셋: FPS") { [weak self] in s.applyAudioPreset(2); self?.controllersChanged() },
                        .action(title: "프리셋: 음악처럼") { [weak self] in s.applyAudioPreset(3); self?.controllersChanged() },
                        .slider(title: "전체 세기", range: 0.2...3.0, format: Self.times,
                                get: { s.audioHapticsGain }, set: { s.audioHapticsGain = $0 }),
                        .slider(title: "초저음 (폭발·엔진)", range: 0...2, format: Self.percent,
                                get: { s.audioSubGain }, set: { s.audioSubGain = $0 }),
                        .slider(title: "저음 (충격·발소리)", range: 0...2, format: Self.percent,
                                get: { s.audioBassGain }, set: { s.audioBassGain = $0 }),
                        .slider(title: "중음 (목소리·악기)", range: 0...2, format: Self.percent,
                                get: { s.audioLowMidGain }, set: { s.audioLowMidGain = $0 }),
                        .slider(title: "중고음 (총소리·스네어)", range: 0...2, format: Self.percent,
                                get: { s.audioMidGain }, set: { s.audioMidGain = $0 }),
                        .slider(title: "고음 (하이햇·금속)", range: 0...2, format: Self.percent,
                                get: { s.audioHighGain }, set: { s.audioHighGain = $0 }),
                        .slider(title: "날카로움 차이", range: 0...1, format: Self.percent,
                                get: { s.audioSharpness }, set: { s.audioSharpness = $0 }),
                        .slider(title: "타격감 (쿠웅·탁)", range: 0...2, format: Self.percent,
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
