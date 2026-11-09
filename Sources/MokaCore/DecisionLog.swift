import Foundation

public enum UserAction: String, CaseIterable, Sendable { case done, skip, `switch` }
/// `rotateByIDV0`은 spec 002 로그 줄을 읽으려고 남긴다. 새 로그 줄은 `priorityRotateV0`(spec 003 R-212).
public enum SchedulerChoice: String, CaseIterable, Sendable {
    case rotateByIDV0 = "rotate_by_id_v0"
    case priorityRotateV0 = "priority_rotate_v0"
}

/// 판단 칸(spec 003 R-212). 공급자가 있을 때만 존재하고, 나머지는 폴백 줄에서 비어도 된다(F5).
public struct Judgment: Equatable, Sendable {
    public var provider: String
    public var questionVersion: String?
    public var probsJSON: String?
    public var stateHash: String?

    public init(provider: String, questionVersion: String?, probsJSON: String?, stateHash: String?) {
        self.provider = provider
        self.questionVersion = questionVersion
        self.probsJSON = probsJSON
        self.stateHash = stateHash
    }
}

public struct DecisionLogEntry: Equatable, Sendable {
    public var id: Int64
    public var taskID: TaskID
    public var judgment: Judgment?
    /// judgment가 nil이면 nil.
    public var modelSnapshot: String?
    public var schedulerChoice: SchedulerChoice
    public var userAction: UserAction
    public var createdAt: Date

    public init(
        id: Int64, taskID: TaskID, judgment: Judgment?, modelSnapshot: String?, schedulerChoice: SchedulerChoice,
        userAction: UserAction, createdAt: Date
    ) {
        self.id = id
        self.taskID = taskID
        self.judgment = judgment
        self.modelSnapshot = modelSnapshot
        self.schedulerChoice = schedulerChoice
        self.userAction = userAction
        self.createdAt = createdAt
    }
}

public struct NewDecisionLogEntry: Equatable, Sendable {
    public var taskID: TaskID
    public var judgment: Judgment?
    public var modelSnapshot: String?
    public var schedulerChoice: SchedulerChoice
    public var userAction: UserAction
    public var createdAt: Date

    public init(
        taskID: TaskID, judgment: Judgment?, modelSnapshot: String?, schedulerChoice: SchedulerChoice,
        userAction: UserAction, createdAt: Date
    ) {
        self.taskID = taskID
        self.judgment = judgment
        self.modelSnapshot = modelSnapshot
        self.schedulerChoice = schedulerChoice
        self.userAction = userAction
        self.createdAt = createdAt
    }
}
