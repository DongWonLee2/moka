import Foundation

/// 계약 "출력" 절의 한 줄. 키 순서를 고정하려고 `JSONEncoder`를 쓰지 않고 직접 조립한다. 제목·두 줄 본문은 내지 않는다.
enum SimOutput {
    static func line(_ event: SimEvent, timer: NotchTimer) -> String {
        "{" + timerFields(event, timer: timer) + "}\n"
    }

    /// storage 모드: 원본 여섯 키 뒤에 `notch_task`, `has_first_action`, `tasks`, `checkpoint`, `decision`.
    /// `judgment`가 있으면(시나리오에 `judge`·`key`가 있음) 뒤에 `order`, `has_key`를 붙이고 `decision`에 `provider`를 넣는다.
    static func storageLine(
        _ event: SimEvent, state: SimStorageState, previous: SimStorageState, judgment: SimJudgmentFields?
    ) -> String {
        let notchTask = state.session?.taskID
        let hasFirstAction = notchTask.map { id in state.tasks.contains { $0.id == id && $0.firstAction != nil } }
        let tasks = state.tasks.map {
            #"{"id":\#($0.id),"status":"\#($0.status.rawValue)","skip_count":\#($0.skipCount),"streak":\#($0.streak)}"#
        }
        let checkpoint = state.checkpoints.count > previous.checkpoints.count ? state.checkpoints.last : nil
        let decision = state.decisions.count > previous.decisions.count ? state.decisions.last : nil
        return "{" + timerFields(event, timer: state.session?.timer ?? .empty(draft: nil))
            + #","notch_task":\#(literal(notchTask)),"has_first_action":\#(literal(hasFirstAction)),"#
            + #""tasks":[\#(tasks.joined(separator: ","))],"#
            + #""checkpoint":\#(checkpoint.map(fields) ?? "null"),"#
            + #""decision":\#(decision.map { fields($0, showsProvider: judgment != nil) } ?? "null")"#
            + (judgment.map(fields) ?? "") + "}\n"
    }

    private static func fields(_ judgment: SimJudgmentFields) -> String {
        #","order":[\#(judgment.order.map(String.init).joined(separator: ","))],"has_key":\#(judgment.hasKey)"#
    }

    private static func timerFields(_ event: SimEvent, timer: NotchTimer) -> String {
        let state: String
        let chipMin: Int?
        switch timer {
        case .empty(let draft):
            state = "empty"
            chipMin = draft?.chipMin
        case .running(_, let quantumMin, _, _):
            state = "running"
            chipMin = quantumMin
        case .expired(_, let chip, _):
            state = "expired"
            chipMin = chip
        }
        let remaining = timer.remainingSeconds(at: event.at)
        return
            #""seq":\#(event.seq),"at":"\#(SimTimestamp.formatUTC(event.epochSeconds))","event":"\#(event.kind.name)","#
            + #""timer_state":"\#(state)","chip_min":\#(literal(chipMin)),"remaining_s":\#(literal(remaining))"#
    }

    /// 두 줄은 비어 있지 않은지만 낸다.
    private static func fields(_ checkpoint: Checkpoint) -> String {
        #"{"task_id":\#(checkpoint.taskID),"trigger":"\#(checkpoint.trigger.rawValue)","elapsed_min":\#(checkpoint.elapsedMin),"#
            + #""has_done_note":\#(!checkpoint.notes.doneNote.isEmpty),"has_next_note":\#(!checkpoint.notes.nextNote.isEmpty)}"#
    }

    /// 판단 칸 가운데 `showsProvider`일 때 공급자만 낸다.
    private static func fields(_ decision: DecisionLogEntry, showsProvider: Bool) -> String {
        let provider = showsProvider ? #""provider":"\#(decision.judgment?.provider ?? "fallback")","# : ""
        return #"{"task_id":\#(decision.taskID),"user_action":"\#(decision.userAction.rawValue)","#
            + provider + #""scheduler_choice":"\#(decision.schedulerChoice.rawValue)"}"#
    }

    private static func literal(_ value: (some CustomStringConvertible)?) -> String {
        value.map(\.description) ?? "null"
    }
}

/// spec 003 조건부 출력 칸의 값.
struct SimJudgmentFields {
    /// 노치 후보 순서(data-model §7)의 할 일 id.
    var order: [TaskID]
    var hasKey: Bool
}
