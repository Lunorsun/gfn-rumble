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
    /// '끝을 부드럽게' 줄이는 중간 단계들
    var pendingSteps: [DispatchWorkItem] = []

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
        // 추가 햅틱이 더 크면 그 날카로움을, 아니면 설정의 기본 날카로움(기본 0.5)을 씁니다.
        let base = Float(AppSettings.shared.rumbleSharpness)
        let ss: Float = extra.s > game.s ? extraSharp.s : base
        let ws: Float = extra.w > game.w ? extraSharp.w : base
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
        pendingSteps.forEach { $0.cancel() }
        pendingSteps.removeAll()
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

/// 설정 화면의 진동 시험 패턴.
enum TestPattern: Int, CaseIterable {
    case soft, medium, strong, leftRight, heartbeat, triggers

    var title: String {
        switch self {
        case .soft: return "약하게"
        case .medium: return "중간"
        case .strong: return "강하게"
        case .leftRight: return "왼쪽 → 오른쪽"
        case .heartbeat: return "심장박동"
        case .triggers: return "방아쇠 (L2·R2)"
        }
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
    private(set) var ignoredByOff = 0           // 진동을 꺼 둬서 무시
    private(set) var noControllerCount = 0      // 대상 컨트롤러를 못 찾음
    private(set) var noRigCount = 0             // 컨트롤러가 진동을 지원하지 않음
    private(set) var driveCount = 0             // 모터까지 전달됨
    private(set) var lastTarget = "없음"        // 마지막으로 울린 컨트롤러 이름
    var pipelineText: String {
        "명령 \(webCommandCount) → 컨트롤러 못 찾음 \(noControllerCount) · 소리모드로 무시 \(ignoredByAudioMode) · 꺼서 무시 \(ignoredByOff) · 진동 미지원 \(noRigCount) → 모터 전달 \(driveCount) → 세기 요청 \(Motor.setCalls) · 장치 생성 \(Motor.enginesMade) · 시작 \(Motor.playsStarted)"
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
        // 설정에서 진동을 끄면 울리던 진동을 바로 멈춥니다.
        center.addObserver(forName: AppSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            let s = AppSettings.shared
            if !s.rumbleEnabled || !s.gameRumbleEnabled || !s.triggerHapticsEnabled { self?.stopAll() }
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
        if !settings.rumbleEnabled || !settings.gameRumbleEnabled {
            ignoredByOff += 1
            return
        }
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
        runPattern(.leftRight)
    }

    /// 시험용 진동 패턴. 설정(세기·곡선·좌우 등)이 그대로 적용돼서 지금 설정을 느껴볼 수 있어요.
    /// 진동을 꺼 둬도 시험은 울립니다. 진동 가능한 컨트롤러가 없으면 false.
    @discardableResult
    func runPattern(_ pattern: TestPattern) -> Bool {
        guard let controller = controller(webIndex: 0, id: nil), rig(for: controller) != nil else {
            return false
        }
        func play(_ at: Double, _ leftLevel: Double, _ rightLevel: Double, ms: Double,
                  lt: Double = 0, rt: Double = 0) {
            let run: () -> Void = { [weak self, weak controller] in
                guard let self = self, let controller = controller else { return }
                self.drive(controller, strong: leftLevel, weak: rightLevel, leftTrigger: lt, rightTrigger: rt,
                           durationMs: ms, delayMs: 0, force: true)
            }
            if at <= 0 { run() } else { DispatchQueue.main.asyncAfter(deadline: .now() + at, execute: run) }
        }
        switch pattern {
        case .soft:      play(0, 0.25, 0.25, ms: 600)
        case .medium:    play(0, 0.55, 0.55, ms: 600)
        case .strong:    play(0, 1, 1, ms: 600)
        case .leftRight:
            play(0, 1, 0, ms: 500)
            play(0.8, 0, 1, ms: 500)
        case .heartbeat:
            for beat in 0..<3 {
                let t = Double(beat) * 0.9
                play(t, 0.9, 0.5, ms: 110)
                play(t + 0.2, 0.7, 0.35, ms: 110)
            }
        case .triggers:
            play(0, 0, 0, ms: 500, lt: 1, rt: 1)
        }
        return true
    }

    /// 알림용 짧은 진동 (대기열 끝 등). 현재 컨트롤러를 울립니다.
    func pulse(strong: Double, weak: Double, durationMs: Double) {
        guard AppSettings.shared.rumbleEnabled else { return }
        guard let controller = controller(webIndex: 0, id: nil) else { return }
        drive(controller, strong: strong, weak: weak, leftTrigger: 0, rightTrigger: 0,
              durationMs: durationMs, delayMs: 0)
    }

    /// 방아쇠 햅틱용: 특정 컨트롤러 손잡이를 짧게 울립니다.
    /// 게임 진동을 끊지 않고 그 위에 더해집니다(더 큰 쪽이 느껴짐).
    func kick(_ controller: GCController, strong: Double, weak: Double, durationMs: Double) {
        let settings = AppSettings.shared
        guard settings.rumbleEnabled, settings.triggerHapticsEnabled else { return }
        guard let rig = rig(for: controller) else { return }
        rig.pendingExtraStop?.cancel()
        rig.applyExtra(strong: extraLevel(strong, left: true), weak: extraLevel(weak, left: false))
        let stop = DispatchWorkItem { [weak rig] in rig?.applyExtra(strong: 0, weak: 0) }
        rig.pendingExtraStop = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + min(max(durationMs, 10), 1000) / 1000, execute: stop)
    }

    /// 게임 소리 햅틱: 왼·오른쪽 세기와 날카로움. 다음 값이 오지 않으면 holdMs 뒤 멈춤.
    func audioFrame(_ controller: GCController, left: Double, right: Double,
                    sharpLeft: Double, sharpRight: Double, holdMs: Double) {
        guard AppSettings.shared.rumbleEnabled else { return }
        guard let rig = rig(for: controller) else { return }
        rig.pendingExtraStop?.cancel()
        rig.applyExtra(strong: extraLevel(left, left: true), weak: extraLevel(right, left: false),
                       sharpStrong: Float(sharpLeft), sharpWeak: Float(sharpRight))
        let stop = DispatchWorkItem { [weak rig] in rig?.applyExtra(strong: 0, weak: 0) }
        rig.pendingExtraStop = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + holdMs / 1000, execute: stop)
    }

    /// 게임 소리 햅틱: 타격음 '탁'
    func audioTap(_ controller: GCController, left: Double, right: Double, sharpness: Double) {
        guard AppSettings.shared.rumbleEnabled else { return }
        guard let rig = rig(for: controller) else { return }
        rig.tap(left: extraLevel(left, left: true), right: extraLevel(right, left: false), sharpness: Float(sharpness))
    }

    /// 추가 햅틱(방아쇠·소리)에 전체 세기·좌우 세기·상한을 적용합니다.
    private func extraLevel(_ value: Double, left: Bool) -> Float {
        guard value > 0.005 else { return 0 }
        let s = AppSettings.shared
        let side = left ? s.leftMotorGain : s.rightMotorGain
        return Float(min(s.rumbleCeiling, max(0, value * s.rumbleGain * side)))
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
                       durationMs: Double, delayMs: Double, force: Bool = false) {
        let settings = AppSettings.shared
        // 진동을 꺼 뒀으면 울리지 않습니다. (시험 진동만 예외)
        if !force && !settings.rumbleEnabled { return }
        guard let rig = rig(for: controller) else {
            noRigCount += 1
            return
        }
        driveCount += 1
        rig.cancelPending()

        let delay = min(max(delayMs, 0), 5000) / 1000
        // 진동 길이 배율 (0.5 ~ 2배)
        let duration = min(max(durationMs, 0) * settings.rumbleLengthScale, 8000) / 1000

        // 1) 왼쪽·오른쪽 바꾸기 / 한쪽만 / 합치기
        var left = strong, right = weak
        if settings.swapMotors { swap(&left, &right) }
        switch settings.rumbleSide {
        case 1: right = 0
        case 2: left = 0
        case 3: let both = max(left, right); left = both; right = both
        default: break
        }

        // 2) 세기 가공: 작은 진동 무시 → 반응 곡선 → 세기 배율 → 최소 세기 → 상한
        func shaped(_ value: Double, sideGain: Double) -> Float {
            guard value > 0.005 else { return 0 }
            let gain = settings.rumbleGain * sideGain
            guard gain > 0, value >= settings.rumbleDeadzone else { return 0 }
            let curved = pow(min(1, value), settings.rumbleCurve)
            return Float(min(settings.rumbleCeiling, max(0, max(settings.rumbleMinimum, curved * gain))))
        }
        let s = shaped(left, sideGain: settings.leftMotorGain)
        let w = shaped(right, sideGain: settings.rightMotorGain)
        let lt = shaped(leftTrigger, sideGain: settings.triggerMotorGain)
        let rt = shaped(rightTrigger, sideGain: settings.triggerMotorGain)

        let start = DispatchWorkItem { [weak rig] in
            rig?.apply(strong: s, weak: w, leftTrigger: lt, rightTrigger: rt)
        }
        if delay > 0 {
            rig.pendingStart = start
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: start)
        } else {
            start.perform()
        }

        // 3) 끝 부드럽게: 끝나는 시점부터 단계적으로 줄이고 마지막에 0
        let fade = settings.rumbleFadeMs / 1000
        let end = delay + duration
        if fade > 0.005 {
            let steps = 4
            for k in 1...steps {
                let factor = 1 - Float(k) / Float(steps + 1)
                let item = DispatchWorkItem { [weak rig] in
                    rig?.apply(strong: s * factor, weak: w * factor,
                               leftTrigger: lt * factor, rightTrigger: rt * factor)
                }
                rig.pendingSteps.append(item)
                DispatchQueue.main.asyncAfter(deadline: .now() + end + fade * Double(k - 1) / Double(steps), execute: item)
            }
        }
        let stop = DispatchWorkItem { [weak rig] in
            rig?.apply(strong: 0, weak: 0, leftTrigger: 0, rightTrigger: 0)
        }
        rig.pendingStop = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + end + (fade > 0.005 ? fade : 0), execute: stop)
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
