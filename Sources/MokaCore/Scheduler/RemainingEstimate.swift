import Foundation

/// 남은 예상 시간(spec 005 data-model §5, R-405·R-409).
public enum RemainingEstimate {
    /// 예상 소요 − 그 할 일 체크포인트 경과 분 합. 예상 소요가 없으면 nil이고, 0 이하도 그대로 돌려준다.
    public static func minutes(task: MokaTask, checkpoints: [Checkpoint]) -> Int? {
        guard let est = task.estMin else { return nil }
        return est - checkpoints.filter { $0.taskID == task.id }.reduce(0) { $0 + $1.elapsedMin }
    }
}
