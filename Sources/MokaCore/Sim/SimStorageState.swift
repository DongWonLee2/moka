import Foundation

/// storage 모드에서 이벤트 하나를 적용한 뒤의 상태. 불변식 검사와 출력이 읽는다.
public struct SimStorageState: Equatable, Sendable {
    /// nil이면 꺼짐(`quit` 뒤).
    public var session: NotchSession?
    /// 버림 포함, id 오름차순.
    public var tasks: [MokaTask]
    public var checkpoints: [Checkpoint]
    public var decisions: [DecisionLogEntry]

    public init(session: NotchSession?, tasks: [MokaTask], checkpoints: [Checkpoint], decisions: [DecisionLogEntry]) {
        self.session = session
        self.tasks = tasks
        self.checkpoints = checkpoints
        self.decisions = decisions
    }
}
