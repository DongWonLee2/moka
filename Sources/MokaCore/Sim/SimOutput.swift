import Foundation

/// 계약 "출력" 절의 한 줄. 키 순서를 고정하려고 `JSONEncoder`를 쓰지 않고 직접 조립한다. 제목·두 줄 본문은 내지 않는다.
enum SimOutput {
    static func line(_ event: SimEvent, timer: NotchTimer) -> String {
        "{" + timerFields(event, timer: timer) + "}\n"
    }

    /// storage 모드: 원본 여섯 키 뒤에 `notch_task`, `has_first_action`, `tasks`, `checkpoint`, `decision`.
    static func storageLine(_ event: SimEvent, state: SimStorageState, previous: SimStorageState) -> String {
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
            + #""checkpoint":\#(checkpoint.map(fields) ?? "null"),"decision":\#(decision.map(fields) ?? "null")}"#
            + "\n"
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

    /// 판단 칸은 늘 비어 있으므로 내지 않는다.
    private static func fields(_ decision: DecisionLogEntry) -> String {
        #"{"task_id":\#(decision.taskID),"user_action":"\#(decision.userAction.rawValue)","scheduler_choice":"\#(decision.schedulerChoice.rawValue)"}"#
    }

    private static func literal(_ value: (some CustomStringConvertible)?) -> String {
        value.map(\.description) ?? "null"
    }
}
