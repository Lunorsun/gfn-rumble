import UIKit
import UniformTypeIdentifiers

/// 설정 백업·복원.
///
/// 보안 벽:
/// - 'settings.'로 시작하는 앱 설정 값만 내보내고 가져옵니다. 다른 값(만료 날짜, 계정, 기록)은 다루지 않습니다.
/// - 가져올 때 크기(64KB 이하), 형식, 값 종류(숫자·참거짓·글자·데이터)를 확인하고 나머지는 버립니다.
/// - 인터넷을 쓰지 않습니다. 파일은 사용자가 고른 위치(파일 앱)에만 저장됩니다.
final class SettingsBackup: NSObject, UIDocumentPickerDelegate {

    static let shared = SettingsBackup()

    private static let prefix = "settings."
    private static let marker = "GFNRumbleSettings"
    private static let maxBytes = 64 * 1024
    private static let maxKeys = 500

    private var onImport: ((String) -> Void)?

    // MARK: - 내보내기

    func export(from presenter: UIViewController) {
        let values = UserDefaults.standard.dictionaryRepresentation()
            .filter { $0.key.hasPrefix(Self.prefix) && Self.isAllowedValue($0.value) }
        let root: [String: Any] = ["type": Self.marker, "version": 1, "settings": values]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0) else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GFNRumble-설정-\(formatter.string(from: Date())).plist")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = self
        onImport = nil
        presenter.present(picker, animated: true)
    }

    // MARK: - 가져오기

    /// 끝나면 결과 문구를 `done`으로 알려 줍니다.
    func importFile(from presenter: UIViewController, done: @escaping (String) -> Void) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.propertyList], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        onImport = done
        presenter.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let done = onImport else { return }   // 내보내기 완료
        onImport = nil
        guard let url = urls.first else { return }
        done(Self.restore(from: url))
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onImport = nil
    }

    private static func restore(from url: URL) -> String {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxBytes,
              let data = try? Data(contentsOf: url), data.count <= maxBytes,
              let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              root["type"] as? String == marker,
              let settings = root["settings"] as? [String: Any], settings.count <= maxKeys
        else { return "GFN Rumble 설정 파일이 아니에요." }

        let defaults = UserDefaults.standard
        var count = 0
        for (key, value) in settings where key.hasPrefix(prefix) && key.count <= 100 && isAllowedValue(value) {
            defaults.set(value, forKey: key)
            count += 1
        }
        NotificationCenter.default.post(name: AppSettings.didChange, object: AppSettings.shared)
        return "설정 \(count)개를 되살렸어요. 일부 설정은 앱을 다시 켜야 적용돼요."
    }

    private static func isAllowedValue(_ value: Any) -> Bool {
        switch value {
        case is NSNumber: return true
        case let s as String: return s.count <= 4096
        case let d as Data: return d.count <= 16 * 1024
        default: return false
        }
    }
}
