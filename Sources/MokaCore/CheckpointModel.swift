import Foundation

public enum CheckpointTrigger: String, CaseIterable, Sendable {
    case quantum, `switch`, skip, urgent, pause, quit, sleep
    case dayEnd = "day_end"
}

/// 두 줄 입력. 앞뒤 공백을 뺀 값이고 안 적기·빈 칸이면 빈 문자열.
public struct CheckpointNotes: Equatable, Sendable {
    public var doneNote: String
    public var nextNote: String

    public static let empty = CheckpointNotes(doneNote: "", nextNote: "")

    public init(doneNote: String, nextNote: String) {
        self.doneNote = doneNote.trimmingCharacters(in: .whitespacesAndNewlines)
        self.nextNote = nextNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct Checkpoint: Equatable, Sendable {
    public var id: Int64
    public var taskID: TaskID
    public var notes: CheckpointNotes
    public var trigger: CheckpointTrigger
    /// 0...작업 시간.
    public var elapsedMin: Int
    public var createdAt: Date

    public init(
        id: Int64, taskID: TaskID, notes: CheckpointNotes, trigger: CheckpointTrigger, elapsedMin: Int, createdAt: Date
    ) {
        self.id = id
        self.taskID = taskID
        self.notes = notes
        self.trigger = trigger
        self.elapsedMin = elapsedMin
        self.createdAt = createdAt
    }
}

// MARK: - 경과 분과 첫 행동 표시(data-model §5.5)

extension Checkpoint {
    /// `floor((now − startedAt) / 60)`를 `0...quantumMin`으로 자른다. 시계를 되돌려 `now`가 앞이면 0.
    /// `now`는 체크포인트를 저장하는 순간이다(등록·안 적기를 누른 순간, 종료·잠자기는 알림을 받은 순간).
    public static func elapsedMinutes(startedAt: Date, now: Date, quantumMin: Int) -> Int {
        let seconds = now.timeIntervalSince(startedAt)
        guard seconds > 0 else { return 0 }
        return min(Int((seconds / 60).rounded(.down)), quantumMin)
    }
}

/// 이어서 할 일(첫 행동) 표시(R-109). 펼친 화면은 첫 행동이 있으면 늘 보인다.
public enum FirstActionDisplay {
    /// 접힌 화면에 보이는 시간(사용자 결정 2026-11-05, 처음 2초).
    public static let collapsedSeconds: TimeInterval = 3

    /// 접힌 화면은 고른 뒤 `collapsedSeconds`만: `0 ≤ now − pickedAt < 3초`.
    public static func showsInCollapsed(pickedAt: Date, now: Date) -> Bool {
        let seconds = now.timeIntervalSince(pickedAt)
        return seconds >= 0 && seconds < collapsedSeconds
    }
}

public struct NewCheckpoint: Equatable, Sendable {
    public var taskID: TaskID
    public var notes: CheckpointNotes
    public var trigger: CheckpointTrigger
    public var elapsedMin: Int
    public var createdAt: Date

    public init(taskID: TaskID, notes: CheckpointNotes, trigger: CheckpointTrigger, elapsedMin: Int, createdAt: Date) {
        self.taskID = taskID
        self.notes = notes
        self.trigger = trigger
        self.elapsedMin = elapsedMin
        self.createdAt = createdAt
    }
}
