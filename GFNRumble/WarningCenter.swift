import Network
import UIKit

/// 화면 위에 잠깐 뜨는 안내 배너와, 배터리·발열·저전력·연결 경고.
/// 상태 표시줄을 숨겨 두었기 때문에 이 배너로 대신 알려 줍니다.
/// 아무것도 기록하거나 보내지 않습니다. 메인 스레드에서만 사용합니다.
final class WarningCenter {

    static let shared = WarningCenter()

    private let banner = UILabel()
    private var hideWork: DispatchWorkItem?
    private var lastShown: [String: Date] = [:]
    private var started = false
    private var pathMonitor: NWPathMonitor?
    private var lastPathStatus: NWPath.Status?
    private var lastWasCellular = false

    private init() {
        banner.numberOfLines = 0
        banner.textAlignment = .center
        banner.textColor = .white
        banner.font = .systemFont(ofSize: 16, weight: .semibold)
        banner.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        banner.layer.cornerRadius = 12
        banner.layer.masksToBounds = true
        banner.alpha = 0
        banner.isUserInteractionEnabled = false
    }

    /// 배너를 올릴 화면을 정합니다. 여러 번 불러도 됩니다.
    func attach(to view: UIView) {
        if banner.superview !== view {
            banner.removeFromSuperview()
            view.addSubview(banner)
        }
        view.bringSubviewToFront(banner)
    }

    /// 안내를 duration초 동안 보여 줍니다. 새 안내가 오면 바꿔 보여 줍니다.
    func show(_ message: String, duration: TimeInterval = 6) {
        guard let container = banner.superview else { return }
        container.bringSubviewToFront(banner)
        banner.text = message
        let maxWidth = min(container.bounds.width - 40, 620)
        let size = banner.sizeThatFits(CGSize(width: maxWidth - 32, height: .greatestFiniteMagnitude))
        let width = min(maxWidth, size.width + 32)
        banner.frame = CGRect(x: (container.bounds.width - width) / 2, y: 20,
                              width: width, height: size.height + 20)
        banner.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleBottomMargin]

        hideWork?.cancel()
        UIView.animate(withDuration: 0.25) { self.banner.alpha = 1 }
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.4) { self?.banner.alpha = 0 }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    /// 같은 경고를 10분 안에 반복하지 않고 보여 줍니다.
    func warn(_ key: String, _ message: String) {
        guard AppSettings.shared.warningsEnabled else { return }
        let now = Date()
        if let last = lastShown[key], now.timeIntervalSince(last) < 600 { return }
        lastShown[key] = now
        show(message)
    }

    // MARK: - 감시 시작

    func start() {
        guard !started else { return }
        started = true

        UIDevice.current.isBatteryMonitoringEnabled = true
        let center = NotificationCenter.default
        center.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.checkBattery()
        }
        center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.checkThermal()
        }
        center.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.checkLowPower()
        }

        // 연결 상태 감시 (어디에도 접속하지 않고 상태만 봅니다)
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let status = path.status
            let cellular = path.usesInterfaceType(.cellular)
            DispatchQueue.main.async { self?.handlePath(status: status, cellular: cellular) }
        }
        monitor.start(queue: DispatchQueue(label: "GFNRumble.path"))
        pathMonitor = monitor

        checkBattery()
        checkThermal()
        checkLowPower()
    }

    private func checkBattery() {
        let device = UIDevice.current
        guard device.batteryState == .unplugged else { return }
        let level = device.batteryLevel
        guard level >= 0 else { return }
        if level <= 0.05 {
            warn("battery5", "아이패드 배터리가 5% 남았어요. 충전기를 연결해 주세요.")
        } else if level <= 0.15 {
            warn("battery15", "아이패드 배터리가 15% 남았어요.")
        }
    }

    private func checkThermal() {
        switch ProcessInfo.processInfo.thermalState {
        case .serious:
            warn("thermal", "아이패드가 뜨거워요. 화질이 떨어지거나 끊길 수 있어요.")
        case .critical:
            warn("thermalCritical", "아이패드가 너무 뜨거워요. 잠시 쉬었다 해 주세요.")
        default:
            break
        }
    }

    private func checkLowPower() {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            warn("lowPower", "저전력 모드가 켜져 있어요. 게임이 끊길 수 있어요.")
        }
    }

    private func handlePath(status: NWPath.Status, cellular: Bool) {
        defer {
            lastPathStatus = status
            lastWasCellular = cellular
        }
        guard lastPathStatus != nil else { return }   // 처음 상태는 알리지 않음
        if status != .satisfied && lastPathStatus == .satisfied {
            warn("offline", "인터넷 연결이 끊겼어요.")
        } else if status == .satisfied && cellular && !lastWasCellular {
            warn("cellular", "셀룰러로 바뀌었어요. 데이터가 많이 쓰일 수 있어요.")
        }
    }
}
