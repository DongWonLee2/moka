import Foundation

public struct StateTask: Equatable, Sendable {
    public let title: String
    public let deadline: LocalDay?
    public let estMin: Int?
    public let firstAction: String?
}

public struct StateContext: Equatable, Sendable {
    public let name: String
    public let date: LocalDay
    public let impact: ContextImpact
}

public struct StateCheckpoint: Equatable, Sendable {
    public let done: String
    public let next: String
}

/// 판단 모델에 보내는 판단 입력(spec R-201, data-model §4). 저장하지 않는다.
/// 다른 할 일, 미룬 횟수, 연속 기록, 상태, 반복, 이전 확률, 할 일 id, 만든 시각은 넣지 않는다(헌법 VIII).
public struct JudgmentState: Equatable, Sendable {
    private static let weekdayNames = ["일", "월", "화", "수", "목", "금", "토"]

    public let today: LocalDay
    public let weekday: Weekday
    public let task: StateTask
    public let contexts: [StateContext]
    public let checkpoint: StateCheckpoint?

    /// `checkpoints`는 모든 할 일의 체크포인트다. 이 할 일 것 가운데 두 줄 중 하나라도 적힌 id 최대의 것을 고른다.
    public static func build(
        task: MokaTask, contexts: [MokaContext], checkpoints: [Checkpoint], today: LocalDay, calendar: Calendar
    ) -> JudgmentState {
        let written = checkpoints.filter {
            $0.taskID == task.id && !($0.notes.doneNote.isEmpty && $0.notes.nextNote.isEmpty)
        }
        return JudgmentState(
            today: today, weekday: today.weekday(calendar: calendar),
            task: StateTask(
                title: task.title, deadline: task.deadline, estMin: task.estMin, firstAction: task.firstAction),
            contexts: contexts.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
                .map { StateContext(name: $0.name, date: $0.date, impact: $0.impact) },
            checkpoint: written.max { $0.id < $1.id }
                .map { StateCheckpoint(done: $0.notes.doneNote, next: $0.notes.nextNote) })
    }

    /// 정준 바이트: 키 순서 고정, 공백 없음, 값이 없는 칸은 키를 뺀다. 해시와 요청 본문 `state`가 이 바이트를 쓴다.
    public var bytes: [UInt8] {
        var task = [("title", Self.quoted(self.task.title))]
        if let deadline = self.task.deadline { task.append(("deadline", Self.quoted(deadline.text))) }
        if let estMin = self.task.estMin { task.append(("est_min", String(estMin))) }
        if let firstAction = self.task.firstAction { task.append(("first_action", Self.quoted(firstAction))) }
        let contexts = contexts.map {
            Self.object([
                ("name", Self.quoted($0.name)), ("date", Self.quoted($0.date.text)),
                ("impact", Self.quoted(ContextText.impact($0.impact))),
            ])
        }
        var root = [
            ("today", Self.quoted("\(today.text) (\(Self.weekdayNames[weekday.rawValue - 1]))")),
            ("context", "[" + contexts.joined(separator: ",") + "]"),
            ("task", Self.object(task)),
        ]
        if let checkpoint {
            root.append(
                (
                    "checkpoint",
                    Self.object([("done", Self.quoted(checkpoint.done)), ("next", Self.quoted(checkpoint.next))])
                ))
        }
        return Array(Self.object(root).utf8)
    }

    /// 판단 입력 해시(data-model §5). 보안용이 아니다.
    public var hash: String {
        Self.fnv1a64(bytes)
    }

    /// FNV-1a 64, 소문자 16진수 16자리.
    public static func fnv1a64(_ bytes: [UInt8]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    private static func object(_ fields: [(String, String)]) -> String {
        "{" + fields.map { quoted($0.0) + ":" + $0.1 }.joined(separator: ",") + "}"
    }

    /// RFC 8259 문자열. `"`, `\`, U+0000~U+001F만 이스케이프한다.
    private static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case _ where scalar.value < 0x20:
                let hex = String(scalar.value, radix: 16)
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
