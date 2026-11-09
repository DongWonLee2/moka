import Foundation

/// 다시 물을 할 일과 답 받기(spec R-206, data-model §6).
public enum ScoringPlan {
    /// 대기·진행 중 할 일 가운데 판단 결과가 없거나, 질문 버전이 다르거나, 지금 판단 입력의 해시가 다른 것.
    /// 판단 결과가 없는 할 일이 먼저이고 그 안에서 id 오름차순이다. `states`에 없는 할 일은 입력이 바뀐 것으로 본다.
    public static func needsQuery(
        tasks: [MokaTask], scores: [TaskID: TaskScore], states: [TaskID: JudgmentState], questionVersion: String
    ) -> [TaskID] {
        tasks.filter { task in
            guard isOpen(task.status) else { return false }
            guard let score = scores[task.id] else { return true }
            return score.questionVersion != questionVersion || states[task.id]?.hash != score.stateHash
        }
        .map { (hasScore: scores[$0.id] != nil, id: $0.id) }
        .sorted { ($0.hasScore ? 1 : 0, $0.id) < ($1.hasScore ? 1 : 0, $1.id) }
        .map(\.id)
    }

    /// 답이 왔을 때 지금 판단 입력의 해시가 요청 때와 같고 할 일이 대기·진행 중일 때만 받는다.
    public static func accepts(requestHash: String, currentHash: String, taskStatus: TaskStatus) -> Bool {
        requestHash == currentHash && isOpen(taskStatus)
    }

    private static func isOpen(_ status: TaskStatus) -> Bool {
        status == .todo || status == .active
    }
}
