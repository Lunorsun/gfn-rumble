import CoreHaptics
import GameController
import UIKit

/// 컨트롤러 안의 진동 모터 하나.
/// 계속 울리는 패턴을 하나 만들어 두고, 세기만 실시간으로 바꿉니다.
private final class Motor {

    private weak var controller: GCController?
    private let locality: GCHapticsLocality
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?
    private var isPlaying = false

    /// 진단용: 마지막으로 난 오류 (상태 보기에 표시)
    static var lastError = "없음"
    /// 진단용 카운터: 0이 아닌 세기 요청 / 진동 장치(엔진) 만든 횟수 / 실제 시작한 횟수
    static var setCalls = 0
    static var enginesMade = 0
    static var playsStarted = 0

    init(controller: GCController, locality: GCHapticsLocality) {
        self.controller = controller
        self.locality = locality
    }

    /// 세기 0.0 ~ 1.0. 0이면 멈춥니다. 날카로움 0.0(묵직) ~ 1.0(또렷)
    func set(_ amplitude: Float, sharpness: Float = 0.5) {
        let value = max(0, min(1, amplitude))

        if value < 0.005 {
            if isPlaying {
                try? player?.stop(atTime: CHHapticTimeImmediate)
                isPlaying = false
            }
            return
        }
        Motor.setCalls += 1

        do {
            if engine == nil {
                engine = makeEngine()
                player = nil
                isPlaying = false
            }
            guard let engine = engine else { return }

            if player == nil {
                // 기본 세기는 1.0으로 두고, 실제 세기는 아래 동적 파라미터로 곱해집니다.
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
                let event = CHHapticEvent(eventType: .hapticContinuous,
                                          parameters: [intensity],
                                          relativeTime: 0,
                                          duration: TimeInterval(GCHapticDurationInfinite))
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                player = try engine.makePlayer(with: pattern)
            }
            guard let player = player else { return }

            let control = CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                                   value: value,
                                                   relativeTime: 0)
            // 세기는 반드시 먼저, 단독으로 보냅니다 (날카로움 때문에 진동 전체가 막히지 않게).
            try player.sendParameters([control], atTime: CHHapticTimeImmediate)
            if !isPlaying {
                try player.start(atTime: CHHapticTimeImmediate)
                isPlaying = true
                Motor.playsStarted += 1
                try player.sendParameters([control], atTime: CHHapticTimeImmediate)
            }
            // 날카로움은 기본에서 많이 벗어날 때만, 실패해도 무시합니다.
            if abs(sharpness - 0.5) > 0.02 {
                let sharp = CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                                     value: max(0, min(1, sharpness)) - 0.5,
                                                     relativeTime: 0)
                try? player.sendParameters([sharp], atTime: CHHapticTimeImmediate)
            }
        } catch {
            Motor.lastError = "\(locality.rawValue): \(error.localizedDescription)"
            invalidate()
        }
    }

    /// 짧고 또렷한 '탁' 한 번 (계속 울리는 진동과 따로 겹쳐 울림)
    func tap(_ amplitude: Float, sharpness: Float) {
        let value = max(0, min(1, amplitude))
        guard value > 0.01 else { return }
        if engine == nil {
            engine = makeEngine()
            player = nil
            isPlaying = false
        }
        guard let engine = engine else { return }
        do {
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: value),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: max(0, min(1, sharpness)))
            ], relativeTime: 0)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {}
    }

    func shutdown() {
        if isPlaying {
            try? player?.stop(atTime: CHHapticTimeImmediate)
        }
        engine?.stop(completionHandler: nil)
        invalidate()
    }

    private func makeEngine() -> CHHapticEngine? {
        guard let engine = controller?.haptics?.createEngine(withLocality: locality) else {
            Motor.lastError = "\(locality.rawValue): 엔진을 만들지 못함"
            return nil
        }

        // 엔진이 멈추거나 초기화되면 버리고, 다음 진동 때 새로 만듭니다.
        engine.stoppedHandler = { [weak self, weak engine] _ in
            DispatchQueue.main.async {
                guard let self = self, self.engine === engine else { return }
                self.invalidate()
            }
        }
        engine.resetHandler = { [weak self, weak engine] in
            DispatchQueue.main.async {
                guard let self = self, self.engine === engine else { return }
                self.invalidate()
            }
        }

        do {
            try engine.start()
        } catch {
            Motor.lastError = "\(locality.rawValue): 엔진 시작 실패 \(error.localizedDescription)"
            return nil
        }
        Motor.enginesMade += 1
        return engine
    }

    private func invalidate() {
        player = nil
        engine = nil
        isPlaying = false
    }
}

/// 컨트롤러 한 대의 모터 묶음.
private final class Rig {

    private let strong: Motor?        // 왼쪽 손잡이 (묵직한 진동)
    private let weak: Motor?          // 오른쪽 손잡이 (가벼운 진동)
    private let combined: Motor?      // 좌우 구분이 안 되는 컨트롤러용
    private let leftTrigger: Motor?
    private let rightTrigger: Motor?

    var pendingStart: DispatchWorkItem?
    var pendingStop: DispatchWorkItem?

    init?(controller: GCController) {
        guard let haptics = controller.haptics else { return nil }
        let supported = haptics.supportedLocalities

        func motor(_ locality: GCHapticsLocality) -> Motor? {
            supported.contains(locality) ? Motor(controller: controller, locality: locality) : nil
        }

        if supported.contains(.leftHandle) && supported.contains(.rightHandle) {
            strong = motor(.leftHandle)
            weak = motor(.rightHandle)
            combined = nil
        } else {
            strong = nil
            weak = nil
            combined = motor(.handles) ?? motor(.default)
        }
        leftTrigger = motor(.leftTrigger)
        rightTrigger = motor(.rightTrigger)

        if strong == nil && combined == nil { return nil }
    }

    // 두 층을 섞어서(더 큰 값) 울립니다: 게임 진동 층 + 추가 햅틱 층(방아쇠 햅틱·게임 소리 햅틱)
    private var game: (s: Float, w: Float, lt: Float, rt: Float) = (0, 0, 0, 0)
    private var extra: (s: Float, w: Float) = (0, 0)
    private var extraSharp: (s: Float, w: Float) = (0.5, 0.5)
    var pendingExtraStop: DispatchWorkItem?

    /// 게임 진동 층
    func apply(strong s: Float, weak w: Float, leftTrigger lt: Float, rightTrigger rt: Float) {
        game = (s, w, lt, rt)
        output()
    }

    /// 추가 햅틱 층
    func applyExtra(strong s: Float, weak w: Float, sharpStrong: Float = 0.5, sharpWeak: Float = 0.5) {
        extra = (s, w)
        extraSharp = (sharpStrong, sharpWeak)
        output()
    }

    /// 왼쪽(strong)·오른쪽(weak) 손잡이에 '탁' 한 번
    func tap(left: Float, right: Float, sharpness: Float) {
        if let strong = strong, let weak = weak {
            strong.tap(left, sharpness: sharpness)
            weak.tap(right, sharpness: sharpness)
        } else {
            combined?.tap(max(left, right), sharpness: sharpness)
        }
    }

    private func output() {
        let s = max(game.s, extra.s), w = max(game.w, extra.w)
        // 추가 햅틱이 더 크면 그 날카로움을, 아니면 기본(0.5)을 씁니다.
        let ss: Float = extra.s > game.s ? extraSharp.s : 0.5
        let ws: Float = extra.w > game.w ? extraSharp.w : 0.5
        strong?.set(s, sharpness: ss)
        weak?.set(w, sharpness: ws)
        combined?.set(max(s, w), sharpness: max(s, w) == s ? ss : ws)
        leftTrigger?.set(game.lt)
        rightTrigger?.set(game.rt)
    }

    func cancelPending() {
        pendingStart?.cancel()
        pendingStart = nil
        pendingStop?.cancel()
        pendingStop = nil
    }

    func stop() {
        cancelPending()
        pendingExtraStop?.cancel()
        pendingExtraStop = nil
        extra = (0, 0)
        apply(strong: 0, weak: 0, leftTrigger: 0, rightTrigger: 0)
    }

    func shutdown() {
        cancelPending()
        pendingExtraStop?.cancel()
        [strong, weak, combined, leftTrigger, rightTrigger].forEach { $0?.shutdown() }
    }
}

/// 웹에서 온 진동 명령을 실제 컨트롤러 진동으로 바꿉니다. 메인 스레드에서만 사용합니다.
final class RumbleManager {

    static let shared = RumbleManager()

    private var rigs: [ObjectIdentifier: Rig] = [:]

    /// 진단용: 웹에서 받은 진동 명령 수와 마지막 명령
    private(set) var webCommandCount = 0
    private(set) var lastWebCommand = "없음"
    private(set) var nonZeroWebCommands = 0
    private(set) var peakWebCommand = 0.0
    var lastError: String { Motor.lastError }

    // 진단용: 웹 명령이 진동까지 가는 단계별 횟수 (어디서 끊기는지 보려고)
    private(set) var ignoredByAudioMode = 0     // 소리 햅틱 전용 설정 때문에 무시
    private(set) var noControllerCount = 0      // 대상 컨트롤러를 못 찾음
    private(set) var noRigCount = 0             // 컨트롤러가 진동을 지원하지 않음
    private(set) var driveCount = 0             // 모터까지 전달됨
    private(set) var lastTarget = "없음"        // 마지막으로 울린 컨트롤러 이름
    var pipelineText: String {
        "명령 \(webCommandCount) → 컨트롤러 못 찾음 \(noControllerCount) · 소리모드로 무시 \(ignoredByAudioMode) · 진동 미지원 \(noRigCount) → 모터 전달 \(driveCount) → 세기 요청 \(Motor.setCalls) · 장치 생성 \(Motor.enginesMade) · 시작 \(Motor.playsStarted)"
    }

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            if let controller = note.object as? GCController {
                self?.configure(controller)
            }
        }
        center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            if let controller = note.object as? GCController {
                self?.rigs.removeValue(forKey: ObjectIdentifier(controller))?.shutdown()
            }
        }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stopAll()
        }
        GCController.controllers().forEach(configure)
    }

    // MARK: - 웹에서 온 명령

    func handleWebPlay(webIndex: Int, id: String?,
                       strong: Double, weak: Double,
                       leftTrigger: Double, rightTrigger: Double,
                       durationMs: Double, delayMs: Double) {
        webCommandCount += 1
        if max(strong, weak, leftTrigger, rightTrigger) > 0.005 {
            nonZeroWebCommands += 1
            peakWebCommand = max(peakWebCommand, strong, weak, leftTrigger, rightTrigger)
        }
        lastWebCommand = String(format: "강 %.2f / 약 %.2f / %.0fms", strong, weak, durationMs)
        // '게임 소리 → 햅틱'만 쓰도록 설정했으면 게임 진동은 무시합니다.
        let settings = AppSettings.shared
        if settings.audioHapticsEnabled && !settings.audioHapticsWithRumble {
            ignoredByAudioMode += 1
            return
        }
        guard let controller = controller(webIndex: webIndex, id: id) else {
            noControllerCount += 1
            return
        }
        lastTarget = controller.vendorName ?? "이름 없음"
        drive(controller,
              strong: strong, weak: weak,
              leftTrigger: leftTrigger, rightTrigger: rightTrigger,
              durationMs: durationMs, delayMs: delayMs)
    }

    func handleWebStop(webIndex: Int, id: String?) {
        guard let controller = controller(webIndex: webIndex, id: id) else { return }
        rigs[ObjectIdentifier(controller)]?.stop()
    }

    func stopAll() {
        rigs.values.forEach { $0.stop() }
    }

    // MARK: - 진단

    /// 컨트롤러를 직접 울려봅니다: 왼쪽(묵직) → 오른쪽(가벼움).
    /// 진동 가능한 컨트롤러가 없으면 false.
    func runTest() -> Bool {
        guard let controller = controller(webIndex: 0, id: nil), rig(for: controller) != nil else {
            return false
        }
        drive(controller, strong: 1, weak: 0, leftTrigger: 0, rightTrigger: 0, durationMs: 500, delayMs: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, weak controller] in
            guard let self = self, let controller = controller else { return }
            self.drive(controller, strong: 0, weak: 1, leftTrigger: 0, rightTrigger: 0, durationMs: 500, delayMs: 0)
        }
        return true
    }

    /// 알림용 짧은 진동 (대기열 끝 등). 현재 컨트롤러를 울립니다.
    func pulse(strong: Double, weak: Double, durationMs: Double) {
        guard let controller = controller(webIndex: 0, id: nil) else { return }
        drive(controller, strong: strong, weak: weak, leftTrigger: 0, rightTrigger: 0,
              durationMs: durationMs, delayMs: 0)
    }

    /// 방아쇠 햅틱용: 특정 컨트롤러 손잡이를 짧게 울립니다.
    /// 게임 진동을 끊지 않고 그 위에 더해집니다(더 큰 쪽이 느껴짐).
    func kick(_ controller: GCController, strong: Double, weak: Double, durationMs: Double) {
        guard let rig = rig(for: controller) else { return }
        let gain = AppSettings.shared.rumbleGain
        func scaled(_ v: Double) -> Float { v > 0.005 ? Float(min(1, v * gain)) : 0 }
        rig.pendingExtraStop?.cancel()
        rig.applyExtra(strong: scaled(strong), weak: scaled(weak))
        let stop = DispatchWorkItem { [weak rig] in rig?.applyExtra(strong: 0, weak: 0) }
        rig.pendingExtraStop = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + min(max(durationMs, 10), 1000) / 1000, execute: stop)
    }

    /// 게임 소리 햅틱: 왼·오른쪽 세기와 날카로움. 다음 값이 오지 않으면 holdMs 뒤 멈춤.
    func audioFrame(_ controller: GCController, left: Double, right: Double,
                    sharpLeft: Double, sharpRight: Double, holdMs: Double) {
        guard let rig = rig(for: controller) else { return }
        let gain = AppSettings.shared.rumbleGain
        func scaled(_ v: Double) -> Float { v > 0.005 ? Float(min(1, v * gain)) : 0 }
        rig.pendingExtraStop?.cancel()
        rig.applyExtra(strong: scaled(left), weak: scaled(right),
                       sharpStrong: Float(sharpLeft), sharpWeak: Float(sharpRight))
        let stop = DispatchWorkItem { [weak rig] in rig?.applyExtra(strong: 0, weak: 0) }
        rig.pendingExtraStop = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + holdMs / 1000, execute: stop)
    }

    /// 게임 소리 햅틱: 타격음 '탁'
    func audioTap(_ controller: GCController, left: Double, right: Double, sharpness: Double) {
        guard let rig = rig(for: controller) else { return }
        let gain = AppSettings.shared.rumbleGain
        rig.tap(left: Float(min(1, left * gain)), right: Float(min(1, right * gain)), sharpness: Float(sharpness))
    }

    func controllerStatus() -> String {
        let all = GCController.controllers()
        if all.isEmpty { return "연결된 컨트롤러 없음" }
        return all.map { controller -> String in
            let name = controller.vendorName ?? "이름 없음"
            guard let haptics = controller.haptics else {
                return "• \(name): 진동 지원 안 함"
            }
            let places = haptics.supportedLocalities.map { $0.rawValue }.sorted().joined(separator: ", ")
            return "• \(name): 진동 지원 (\(places))"
        }.joined(separator: "\n")
    }

    // MARK: - 내부

    private func configure(_ controller: GCController) {
        // 홈/공유 버튼이 iOS 기능(스크린샷 등) 대신 게임으로 전달되게 합니다.
        for element in controller.physicalInputProfile.allElements {
            element.preferredSystemGestureState = .disabled
        }
    }

    private func drive(_ controller: GCController,
                       strong: Double, weak: Double,
                       leftTrigger: Double, rightTrigger: Double,
                       durationMs: Double, delayMs: Double) {
        guard let rig = rig(for: controller) else {
            noRigCount += 1
            return
        }
        driveCount += 1
        rig.cancelPending()

        let duration = min(max(durationMs, 0), 5000) / 1000
        let delay = min(max(delayMs, 0), 5000) / 1000

        // 설정의 진동 세기·최소 세기를 적용합니다.
        let settings = AppSettings.shared
        let gain = settings.rumbleGain
        let minimum = settings.rumbleMinimum
        func scaled(_ value: Double) -> Float {
            guard value > 0.005, gain > 0 else { return 0 }
            return Float(min(1, max(minimum, value * gain)))
        }
        let s = scaled(strong), w = scaled(weak), lt = scaled(leftTrigger), rt = scaled(rightTrigger)

        let start = DispatchWorkItem { [weak rig] in
            rig?.apply(strong: s, weak: w, leftTrigger: lt, rightTrigger: rt)
        }
        if delay > 0 {
            rig.pendingStart = start
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: start)
        } else {
            start.perform()
        }

        let stop = DispatchWorkItem { [weak rig] in
            rig?.apply(strong: 0, weak: 0, leftTrigger: 0, rightTrigger: 0)
        }
        rig.pendingStop = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + duration, execute: stop)
    }

    private func rig(for controller: GCController) -> Rig? {
        let key = ObjectIdentifier(controller)
        if let rig = rigs[key] { return rig }
        guard let rig = Rig(controller: controller) else { return nil }
        rigs[key] = rig
        return rig
    }

    /// 웹의 게임패드 번호/이름에 해당하는 실제 컨트롤러를 찾습니다.
    private func controller(webIndex: Int, id: String?) -> GCController? {
        let all = GCController.controllers().filter { $0.extendedGamepad != nil }
        if let id = id, !id.isEmpty {
            let matches = all.filter { controller in
                guard let name = controller.vendorName, !name.isEmpty else { return false }
                return id.hasPrefix(name)
            }
            if matches.count == 1 { return matches[0] }
        }
        if all.indices.contains(webIndex) { return all[webIndex] }
        return GCController.current ?? all.first
    }
}
