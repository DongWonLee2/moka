import Foundation

public enum SimRunner {
    /// 성공이면 출력 줄 전체, 아니면 오류 하나(출력 없음).
    public static func run(_ data: Data) -> Result<String, SimError> {
        do throws(SimError) {
            return .success(try execute(SimScenario.decode(data)))
        } catch {
            return .failure(error)
        }
    }

    public static func checkInvariant(_ timer: NotchTimer, at now: Date, seq: Int) -> SimError? {
        timer.invariantViolation(at: now).map {
            SimError(kind: .invariantViolation, seq: seq, message: "불변식 위반(MokaCore 버그 신호): \($0)")
        }
    }

    private static func execute(_ scenario: SimScenario) throws(SimError) -> String {
        let settings = InMemorySettingsStore()
        if let minutes = scenario.defaultQuantumMin {
            try write(minutes, to: settings, seq: nil)
        }
        var timer = NotchTimer.empty(draft: nil)
        var output = ""
        for event in scenario.events {
            let defaultQuantumMin = QuantumSettings.readDefault(from: settings)
            _ = timer.apply(.tick, at: event.at, defaultQuantumMin: defaultQuantumMin)

            let timerEvent: TimerEvent?
            switch event.kind {
            case .setDefaultQuantum(let minutes):
                try write(minutes, to: settings, seq: event.seq)
                timer.applyDefaultQuantumChange(QuantumSettings.readDefault(from: settings), isEditingCustom: false)
                timerEvent = nil
            case .enterTitle(let title): timerEvent = .enterTitle(title)
            case .chooseQuantum(let minutes): timerEvent = .chooseQuantum(minutes)
            case .start: timerEvent = .start
            case .tick: timerEvent = .tick
            case .complete: timerEvent = .complete
            }
            if let timerEvent,
                case .rejected(let reason) = timer.apply(timerEvent, at: event.at, defaultQuantumMin: defaultQuantumMin)
            {
                throw rejection(reason, event: event)
            }

            if let violation = checkInvariant(timer, at: event.at, seq: event.seq) {
                throw violation
            }
            output += SimOutput.line(event, timer: timer)
        }
        return output
    }

    private static func write(_ minutes: Int, to settings: InMemorySettingsStore, seq: Int?) throws(SimError) {
        do {
            try QuantumSettings.writeDefault(minutes, to: settings)
        } catch {
            throw SimError(kind: .outOfRange, seq: seq, message: "기본 작업 시간 \(minutes)을 저장하지 못했다")
        }
    }

    private static func rejection(_ reason: RejectReason, event: SimEvent) -> SimError {
        switch reason {
        case .emptyTitle:
            SimError(kind: .emptyTitle, seq: event.seq, message: "앞뒤 공백을 뺀 title이 비어 있다")
        case .quantumOutOfRange:
            SimError(kind: .outOfRange, seq: event.seq, message: "quantum_min이 1...180 밖이다")
        case .notAllowedInPhase:
            SimError(kind: .notAllowedInPhase, seq: event.seq, message: "이 단계에서 \(event.kind.name)을 받을 수 없다")
        }
    }
}
