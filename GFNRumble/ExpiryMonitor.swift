import Foundation
import UserNotifications

/// SideStore 서명 만료 알림.
///
/// 보안 벽 (빌드할 때 scripts/security-check.sh가 검사합니다):
/// - 앱 안의 서명 파일(embedded.mobileprovision)에서 'ExpirationDate' 하나만 읽고, 나머지 내용은 바로 버립니다.
/// - 인터넷, 파일 저장, 기록(로그), 클립보드를 쓰지 않습니다.
/// - 알림 문구에는 개인정보 없이 남은 시간만 넣습니다.
final class ExpiryMonitor: NSObject {

    static let shared = ExpiryMonitor()

    /// 이 앱의 서명이 만료되는 시각. 서명 파일이 없거나(직접 빌드한 앱) 읽을 수 없으면 nil.
    let expirationDate: Date?

    /// 매일 알림을 보내는 시각 (밤 9시)
    private static let dailyHour = 21
    /// 조용한 시간: 밤 11시 ~ 아침 8시에는 알림을 보내지 않습니다.
    private static let quietStartHour = 23
    private static let quietEndHour = 8
    /// 만료 며칠 전부터 알릴지
    private static let warnDays = 3

    /// 이 앱이 예약하는 알림 이름. 다시 예약할 때 이 이름들만 지웁니다.
    private static let identifierPrefix = "gfnrumble.expiry."
    private static let maxNotifications = 10

    private var didStart = false

    private override init() {
        expirationDate = ExpiryMonitor.readExpirationDate()
        super.init()
    }

    // MARK: - 시작

    /// 앱이 켜질 때 한 번 부릅니다. 알림 권한을 묻고, 알림을 예약합니다.
    func start() {
        guard !didStart else { return }
        didStart = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        guard expirationDate != nil else { return }
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { self?.reschedule() }
        }
    }

    /// 앱이 화면에 나올 때마다 부릅니다. 새 만료 날짜로 알림을 다시 맞춥니다.
    func refresh() {
        reschedule()
    }

    // MARK: - 표시용

    /// 예: "11월 22일 오후 8:32 만료 · 6일 23시간 남음"
    func statusText(now: Date = Date()) -> String {
        guard let expiry = expirationDate else { return "만료 날짜를 알 수 없어요" }
        let when = Self.dateText(expiry)
        let remaining = expiry.timeIntervalSince(now)
        if remaining <= 0 {
            return "\(when) 만료됨 · SideStore 갱신 또는 PC(iloader)로 다시 설치가 필요해요"
        }
        return "\(when) 만료 · \(Self.remainingText(remaining)) 남음"
    }

    /// 만료까지 3일 이하로 남았으면 화면에 띄울 안내 문구. 아니면 nil.
    func bannerText(now: Date = Date()) -> String? {
        guard let expiry = expirationDate else { return nil }
        let remaining = expiry.timeIntervalSince(now)
        guard remaining > 0, remaining <= TimeInterval(Self.warnDays * 24 * 3600) else { return nil }
        return "서명 만료까지 \(Self.remainingText(remaining)) 남았어요. LocalDevVPN을 켜고 SideStore에서 Refresh All을 눌러 주세요. SideStore가 안 열리면 PC의 iloader로 다시 설치하면 돼요."
    }

    static func remainingText(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return hours > 0 ? "\(days)일 \(hours)시간" : "\(days)일" }
        if hours > 0 { return minutes > 0 ? "\(hours)시간 \(minutes)분" : "\(hours)시간" }
        return "\(max(minutes, 1))분"
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 a h:mm"
        return formatter.string(from: date)
    }

    // MARK: - 알림 예약

    private func reschedule() {
        let center = UNUserNotificationCenter.current()
        let identifiers = (0..<Self.maxNotifications).map { Self.identifierPrefix + String($0) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        guard let expiry = expirationDate else { return }

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async {
                let now = Date()
                let times = Self.reminderTimes(expiry: expiry, now: now, calendar: Calendar.current)
                for (index, fireDate) in times.prefix(Self.maxNotifications).enumerated() {
                    let content = UNMutableNotificationContent()
                    content.title = "GFN Rumble 갱신 알림"
                    content.body = Self.notificationBody(expiry: expiry, fireDate: fireDate)
                    content.sound = .default
                    let interval = max(1, fireDate.timeIntervalSince(now))
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                    let request = UNNotificationRequest(identifier: Self.identifierPrefix + String(index),
                                                        content: content,
                                                        trigger: trigger)
                    center.add(request, withCompletionHandler: nil)
                }
            }
        }
    }

    private static func notificationBody(expiry: Date, fireDate: Date) -> String {
        let remaining = expiry.timeIntervalSince(fireDate)
        if remaining <= 60 {
            return "서명이 만료됐어요. SideStore가 열리면 LocalDevVPN을 켜고 Refresh All을, 안 열리면 PC의 iloader로 다시 설치해 주세요."
        }
        return "서명 만료까지 \(remainingText(remaining)) 남았어요. LocalDevVPN을 켜고 SideStore → My Apps → Refresh All을 눌러 주세요. SideStore가 안 열리면 PC의 iloader로 다시 설치하면 돼요. 이미 갱신했다면 GFN Rumble을 한 번 열어 주세요."
    }

    /// 알림 시각 목록 (시간순).
    /// - 만료 3일 전부터 매일 밤 9시
    /// - 만료 3시간 전, 1시간 전
    /// - 만료되는 순간
    /// 조용한 시간(밤 11시~아침 8시)에 걸리면: 경고는 그 전날 밤 10시로 당기고, 만료 알림은 아침 8시로 미룹니다.
    static func reminderTimes(expiry: Date, now: Date, calendar: Calendar) -> [Date] {
        var times: [Date] = []
        let windowStart = expiry.addingTimeInterval(-TimeInterval(warnDays * 24 * 3600))

        // 1) 매일 밤 9시
        var day = calendar.startOfDay(for: windowStart)
        let lastDay = calendar.startOfDay(for: expiry)
        while day <= lastDay {
            if let nine = calendar.date(bySettingHour: dailyHour, minute: 0, second: 0, of: day),
               nine >= windowStart, nine < expiry {
                times.append(nine)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        // 2) 마지막 경고: 3시간 전, 1시간 전 (조용한 시간이면 앞당김)
        for hoursBefore in [3, 1] {
            let raw = expiry.addingTimeInterval(-TimeInterval(hoursBefore * 3600))
            times.append(moveEarlierOutOfQuietHours(raw, calendar: calendar))
        }

        // 3) 만료 순간 (조용한 시간이면 아침으로 미룸)
        times.append(moveLaterOutOfQuietHours(expiry, calendar: calendar))

        // 지난 시각은 빼고, 30분 안에 겹치는 알림은 하나만 남깁니다.
        let sorted = times.filter { $0 > now }.sorted()
        var result: [Date] = []
        for time in sorted {
            if let last = result.last, time.timeIntervalSince(last) < 30 * 60 { continue }
            result.append(time)
        }
        return result
    }

    private static func isQuiet(_ date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= quietStartHour || hour < quietEndHour
    }

    /// 조용한 시간이면 그 전날(또는 그날) 밤 10시로 앞당깁니다.
    private static func moveEarlierOutOfQuietHours(_ date: Date, calendar: Calendar) -> Date {
        guard isQuiet(date, calendar: calendar) else { return date }
        let hour = calendar.component(.hour, from: date)
        var base = calendar.startOfDay(for: date)
        if hour < quietEndHour, let previous = calendar.date(byAdding: .day, value: -1, to: base) {
            base = previous
        }
        return calendar.date(bySettingHour: quietStartHour - 1, minute: 0, second: 0, of: base) ?? date
    }

    /// 조용한 시간이면 다음 아침 8시로 미룹니다.
    private static func moveLaterOutOfQuietHours(_ date: Date, calendar: Calendar) -> Date {
        guard isQuiet(date, calendar: calendar) else { return date }
        let hour = calendar.component(.hour, from: date)
        var base = calendar.startOfDay(for: date)
        if hour >= quietStartHour, let next = calendar.date(byAdding: .day, value: 1, to: base) {
            base = next
        }
        return calendar.date(bySettingHour: quietEndHour, minute: 0, second: 0, of: base) ?? date
    }

    // MARK: - 서명 파일 읽기 (보안 벽)

    /// embedded.mobileprovision 안의 plist에서 'ExpirationDate' 하나만 꺼냅니다.
    /// 다른 값(팀 이름, 기기 목록, 인증서 등)은 읽지 않고, 함수가 끝나면 메모리에서 버려집니다.
    private static func readExpirationDate() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }

        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
              let dictionary = plist as? [String: Any] else { return nil }
        return dictionary["ExpirationDate"] as? Date
    }
}

// MARK: - 앱이 켜져 있을 때도 알림 보이기

extension ExpiryMonitor: UNUserNotificationCenterDelegate {

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
