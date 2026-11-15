import UIKit

/// L2 또는 R2 방아쇠 상세 설정. 값을 바꾸면 바로 컨트롤러에 적용돼서 당겨 보며 맞출 수 있어요.
final class TriggerDetailViewController: UITableViewController {

    private let left: Bool
    private var timer: Timer?
    private let bar = UIProgressView(progressViewStyle: .default)
    private let barLabel = UILabel()

    private enum SectionKind { case presets, live, mode, params, zones, haptic }
    private var kinds: [SectionKind] = []

    private var config: TriggerConfig {
        get { left ? AppSettings.shared.leftTrigger : AppSettings.shared.rightTrigger }
        set {
            if left { AppSettings.shared.leftTrigger = newValue } else { AppSettings.shared.rightTrigger = newValue }
        }
    }

    init(left: Bool) {
        self.left = left
        super.init(style: .insetGrouped)
        title = left ? "L2 방아쇠" : "R2 방아쇠"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        rebuild()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            self?.updateBar()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        timer = nil
    }

    private func rebuild() {
        let c = config
        kinds = [.presets, .live, .mode]
        if c.mode != .off && c.mode != .zoneFeedback { kinds.append(.params) }
        if c.mode == .zoneFeedback || c.mode == .zoneVibration { kinds.append(.zones) }
        kinds.append(.haptic)
        tableView.reloadData()
    }

    private func updateBar() {
        if let value = TriggerEffects.shared.currentValue(left: left) {
            bar.progress = value
            barLabel.text = "\(Int((value * 100).rounded()))%"
        } else {
            bar.progress = 0
            barLabel.text = "컨트롤러 없음"
        }
    }

    // MARK: - 행 정의

    private struct SliderSpec {
        let title: String
        let range: ClosedRange<Double>
        let format: (Double) -> String
        let key: WritableKeyPath<TriggerConfig, Double>
    }

    private static func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    private func paramSliders() -> [SliderSpec] {
        switch config.mode {
        case .feedback:
            return [SliderSpec(title: "시작 위치", range: 0...1, format: Self.pct, key: \.start),
                    SliderSpec(title: "세기", range: 0...1, format: Self.pct, key: \.strength)]
        case .slope:
            return [SliderSpec(title: "시작 위치", range: 0...1, format: Self.pct, key: \.start),
                    SliderSpec(title: "끝 위치", range: 0...1, format: Self.pct, key: \.end),
                    SliderSpec(title: "시작 세기", range: 0...1, format: Self.pct, key: \.strength),
                    SliderSpec(title: "끝 세기", range: 0...1, format: Self.pct, key: \.endStrength)]
        case .weapon:
            return [SliderSpec(title: "걸리기 시작", range: 0...1, format: Self.pct, key: \.start),
                    SliderSpec(title: "풀리는 위치", range: 0...1, format: Self.pct, key: \.end),
                    SliderSpec(title: "세기", range: 0...1, format: Self.pct, key: \.strength)]
        case .vibration:
            return [SliderSpec(title: "시작 위치", range: 0...1, format: Self.pct, key: \.start),
                    SliderSpec(title: "세기", range: 0...1, format: Self.pct, key: \.strength),
                    SliderSpec(title: "빠르기", range: 0...1, format: Self.pct, key: \.frequency)]
        case .zoneVibration:
            return [SliderSpec(title: "빠르기", range: 0...1, format: Self.pct, key: \.frequency)]
        case .off, .zoneFeedback:
            return []
        }
    }

    private func hapticSliders() -> [SliderSpec] {
        var specs = [
            SliderSpec(title: "시작 위치", range: 0...1, format: Self.pct, key: \.hapticThreshold),
            SliderSpec(title: "세기", range: 0...1, format: Self.pct, key: \.hapticStrength),
            SliderSpec(title: "한 번 길이", range: 15...200, format: { "\(Int($0))ms" }, key: \.hapticLengthMs)
        ]
        if config.haptic == .rapid {
            specs.insert(SliderSpec(title: "연사 속도", range: 2...25, format: { "초당 \(Int($0))발" }, key: \.hapticRate), at: 2)
        }
        return config.haptic == .off ? [] : specs
    }

    // MARK: - 표

    override func numberOfSections(in tableView: UITableView) -> Int { kinds.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch kinds[section] {
        case .presets: return "프리셋"
        case .live: return "당긴 정도 (당겨 보며 맞추세요)"
        case .mode: return "방아쇠 자체 효과 (듀얼센스)"
        case .params: return "효과 설정"
        case .zones: return "구간별 세기 (1칸 = 방아쇠 10%)"
        case .haptic: return "손잡이 햅틱 (모든 진동 컨트롤러)"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch kinds[section] {
        case .presets: return "프리셋을 고른 뒤 숫자를 바꿔 내 취향에 맞출 수 있어요."
        case .haptic: return "단발: 당길 때 한 번 '퉁'. 연사: 누르고 있는 동안 '투투투'. 게임의 실제 발사와는 맞춰지지 않아요."
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch kinds[section] {
        case .presets: return TriggerPreset.all.count
        case .live: return 1
        case .mode: return TriggerMode.allCases.count
        case .params: return paramSliders().count
        case .zones: return 10
        case .haptic: return 1 + hapticSliders().count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.selectionStyle = .none
        let row = indexPath.row

        switch kinds[indexPath.section] {
        case .presets:
            cell.textLabel?.text = TriggerPreset.all[row].name
            cell.textLabel?.textColor = .systemBlue
            cell.selectionStyle = .default

        case .live:
            cell.textLabel?.text = " "
            bar.frame = CGRect(x: 0, y: 0, width: 260, height: 8)
            barLabel.frame = CGRect(x: 270, y: -8, width: 110, height: 24)
            barLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
            let holder = UIView(frame: CGRect(x: 0, y: 0, width: 380, height: 8))
            holder.addSubview(bar)
            holder.addSubview(barLabel)
            cell.accessoryView = holder
            updateBar()

        case .mode:
            let mode = TriggerMode.allCases[row]
            cell.textLabel?.text = mode.title
            cell.accessoryType = config.mode == mode ? .checkmark : .none
            cell.selectionStyle = .default

        case .params:
            configureSlider(cell, paramSliders()[row])

        case .zones:
            cell.textLabel?.text = "\(row * 10)~\(row * 10 + 10)%"
            cell.detailTextLabel?.text = Self.pct(config.zones[row])
            let slider = UISlider(frame: CGRect(x: 0, y: 0, width: 220, height: 30))
            slider.value = Float(config.zones[row])
            let label = cell.detailTextLabel
            slider.addAction(UIAction { [weak self] action in
                guard let self = self, let s = action.sender as? UISlider else { return }
                var c = self.config
                c.zones[row] = Double(s.value)
                self.config = c
                label?.text = Self.pct(Double(s.value))
            }, for: .valueChanged)
            cell.accessoryView = slider

        case .haptic:
            if row == 0 {
                cell.textLabel?.text = "방식"
                let control = UISegmentedControl(items: HapticMode.allCases.map { $0.title })
                control.selectedSegmentIndex = config.haptic.rawValue
                control.addAction(UIAction { [weak self] action in
                    guard let self = self, let c = action.sender as? UISegmentedControl else { return }
                    var value = self.config
                    value.haptic = HapticMode(rawValue: c.selectedSegmentIndex) ?? .off
                    self.config = value
                    self.rebuild()
                }, for: .valueChanged)
                cell.accessoryView = control
            } else {
                configureSlider(cell, hapticSliders()[row - 1])
            }
        }
        return cell
    }

    private func configureSlider(_ cell: UITableViewCell, _ spec: SliderSpec) {
        cell.textLabel?.text = spec.title
        let current = config[keyPath: spec.key]
        cell.detailTextLabel?.text = spec.format(current)
        let slider = UISlider(frame: CGRect(x: 0, y: 0, width: 220, height: 30))
        slider.minimumValue = Float(spec.range.lowerBound)
        slider.maximumValue = Float(spec.range.upperBound)
        slider.value = Float(current)
        let label = cell.detailTextLabel
        slider.addAction(UIAction { [weak self] action in
            guard let self = self, let s = action.sender as? UISlider else { return }
            var c = self.config
            c[keyPath: spec.key] = Double(s.value)
            self.config = c
            label?.text = spec.format(Double(s.value))
        }, for: .valueChanged)
        cell.accessoryView = slider
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch kinds[indexPath.section] {
        case .presets:
            config = TriggerPreset.all[indexPath.row].config
            rebuild()
        case .mode:
            var c = config
            c.mode = TriggerMode.allCases[indexPath.row]
            config = c
            rebuild()
        default:
            break
        }
    }
}
