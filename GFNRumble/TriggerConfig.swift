import Foundation

/// 듀얼센스 방아쇠 자체의 효과 방식 (아이패드가 제공하는 방식 전부)
enum TriggerMode: Int, Codable, CaseIterable {
    case off = 0          // 끔
    case feedback = 1     // 저항: 시작 위치부터 일정한 뻑뻑함
    case slope = 2        // 경사 저항: 시작→끝으로 갈수록 세기가 바뀜
    case weapon = 3       // 총 방아쇠: 구간에서 걸렸다가 '딸깍'
    case vibration = 4    // 진동: 시작 위치부터 '드르르'
    case zoneFeedback = 5 // 구간 저항: 10칸 각각 세기
    case zoneVibration = 6 // 구간 진동: 10칸 각각 세기 + 빠르기

    var title: String {
        switch self {
        case .off: return "끔"
        case .feedback: return "저항"
        case .slope: return "경사 저항"
        case .weapon: return "총 방아쇠"
        case .vibration: return "진동"
        case .zoneFeedback: return "구간 저항 (10칸)"
        case .zoneVibration: return "구간 진동 (10칸)"
        }
    }
}

/// 방아쇠를 당길 때 손잡이(본체) 진동 모터로 주는 햅틱 피드백
enum HapticMode: Int, Codable, CaseIterable {
    case off = 0    // 끔
    case single = 1 // 단발: 당길 때 한 번 '퉁'
    case rapid = 2  // 연사: 누르고 있는 동안 '투투투'

    var title: String {
        switch self {
        case .off: return "끔"
        case .single: return "단발"
        case .rapid: return "연사 (투투투)"
        }
    }
}

/// 방아쇠 하나(L2 또는 R2)의 모든 설정. 값은 모두 0.0~1.0 (연사 속도·길이만 예외)
struct TriggerConfig: Codable, Equatable {
    var mode: TriggerMode = .off
    var start: Double = 0.2        // 시작 위치
    var end: Double = 0.6          // 끝 위치
    var strength: Double = 0.6     // 세기 (진동이면 진폭)
    var endStrength: Double = 1.0  // 경사 저항의 끝 세기
    var frequency: Double = 0.4    // 진동 빠르기
    var zones: [Double] = Array(repeating: 0.5, count: 10)

    var haptic: HapticMode = .off
    var hapticThreshold: Double = 0.5   // 이만큼 당기면 시작
    var hapticStrength: Double = 0.8
    var hapticRate: Double = 10         // 연사: 초당 횟수 (2~25)
    var hapticLengthMs: Double = 40     // 한 번 울리는 길이 (15~200ms)

    /// 범위를 벗어난 값을 바로잡습니다.
    func clamped() -> TriggerConfig {
        func c(_ v: Double) -> Double { min(1, max(0, v.isFinite ? v : 0)) }
        var t = self
        t.start = c(start)
        t.end = max(t.start, c(end))
        t.strength = c(strength)
        t.endStrength = c(endStrength)
        t.frequency = c(frequency)
        var z = zones.map(c)
        while z.count < 10 { z.append(0) }
        t.zones = Array(z.prefix(10))
        t.hapticThreshold = c(hapticThreshold)
        t.hapticStrength = c(hapticStrength)
        t.hapticRate = min(25, max(2, hapticRate.isFinite ? hapticRate : 10))
        t.hapticLengthMs = min(200, max(15, hapticLengthMs.isFinite ? hapticLengthMs : 40))
        return t
    }
}

/// 미리 만들어 둔 방아쇠 설정
struct TriggerPreset {
    let name: String
    let config: TriggerConfig

    static let all: [TriggerPreset] = {
        func make(_ build: (inout TriggerConfig) -> Void) -> TriggerConfig {
            var c = TriggerConfig()
            build(&c)
            return c
        }
        return [
            TriggerPreset(name: "권총", config: make {
                $0.mode = .weapon; $0.start = 0.3; $0.end = 0.55; $0.strength = 0.8
                $0.haptic = .single; $0.hapticThreshold = 0.55; $0.hapticStrength = 1; $0.hapticLengthMs = 60
            }),
            TriggerPreset(name: "자동 소총", config: make {
                $0.mode = .feedback; $0.start = 0.2; $0.strength = 0.35
                $0.haptic = .rapid; $0.hapticThreshold = 0.5; $0.hapticStrength = 0.8; $0.hapticRate = 11; $0.hapticLengthMs = 35
            }),
            TriggerPreset(name: "기관총", config: make {
                $0.mode = .vibration; $0.start = 0.4; $0.strength = 0.7; $0.frequency = 0.8
                $0.haptic = .rapid; $0.hapticThreshold = 0.4; $0.hapticStrength = 0.9; $0.hapticRate = 18; $0.hapticLengthMs = 25
            }),
            TriggerPreset(name: "활", config: make {
                $0.mode = .slope; $0.start = 0.1; $0.end = 0.9; $0.strength = 0.1; $0.endStrength = 1.0
                $0.haptic = .single; $0.hapticThreshold = 0.95; $0.hapticStrength = 0.7; $0.hapticLengthMs = 80
            }),
            TriggerPreset(name: "브레이크", config: make {
                $0.mode = .slope; $0.start = 0.0; $0.end = 0.7; $0.strength = 0.3; $0.endStrength = 1.0
            }),
            TriggerPreset(name: "가속 페달", config: make {
                $0.mode = .feedback; $0.start = 0.0; $0.strength = 0.25
            }),
            TriggerPreset(name: "말 달리기", config: make {
                $0.mode = .zoneVibration; $0.frequency = 0.15
                $0.zones = [0, 0, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
            })
        ]
    }()
}
