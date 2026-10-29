import Foundation

/// 계약 "출력" 절의 한 줄. 키 순서를 고정하려고 `JSONEncoder`를 쓰지 않고 직접 조립한다. 제목은 내지 않는다.
enum SimOutput {
    static func line(_ event: SimEvent, timer: NotchTimer) -> String {
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
            #"{"seq":\#(event.seq),"at":"\#(SimTimestamp.formatUTC(event.epochSeconds))","event":"\#(event.kind.name)","#
            + #""timer_state":"\#(state)","chip_min":\#(literal(chipMin)),"remaining_s":\#(literal(remaining))}"#
            + "\n"
    }

    private static func literal(_ value: Int?) -> String {
        value.map(String.init) ?? "null"
    }
}
