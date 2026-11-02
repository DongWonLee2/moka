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
