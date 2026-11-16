import Foundation

/// 이월 카드의 답 셋(R-415).
public enum CarryAnswerKind: Equatable, Sendable {
    case today
    case drop
    case move(LocalDay)
}

public enum CarryAnswerError: Error, Equatable, Sendable {
    /// "날짜 바꿀래요"의 날이 오늘보다 뒤가 아니다.
    case dateNotAfterToday
    /// 카드에 오르는 할 일(이월 답 대기인 대기 할 일)이 아니다.
    case notOnCard
}

/// 카드 위 줄의 까닭. 마감이 지났으면 지난 날 수가 앞선다.
public enum CarryCardReason: Equatable, Sendable {
    case touched
    case overdue(days: Int)

    public static func of(task: MokaTask, today: LocalDay) -> CarryCardReason {
        guard let deadline = task.deadline, deadline < today else { return .touched }
        return .overdue(days: deadline.days(until: today))
    }
}

/// 이월 답(spec 005 data-model §10). 순수 함수이고, 호출자가 돌려받은 묶음을 `apply`한다.
public enum CarryAnswer {
    /// 할 일 하나의 갱신과 로그 한 줄(`carry_card_v1`, 판단 칸은 spec 003 R-212). 체크포인트는 없다.
    public static func apply(_ answer: CarryAnswerKind, task: MokaTask, today: LocalDay, input: SessionInput)
        throws(CarryAnswerError) -> StoreBatch
    {
        guard task.dueDecision, task.status == .todo else { throw .notOnCard }
        var updated = task
        updated.dueDecision = false
        let action: UserAction
        switch answer {
        case .today:
            updated.carryCount += 1
            action = .carryToday
        case .drop:
            updated.status = .dropped
            action = .carryDrop
        case .move(let day):
            guard today < day else { throw .dateNotAfterToday }
            updated.deadline = day
            action = .carryMove
        }
        return StoreBatch(
            updatedTasks: [updated], newDecisions: [NotchSession.logLine(task.id, action, input, choice: .carryCardV1)])
    }

    /// 카드에 오를 할 일, 마감 순(지난 마감 → 가까운 마감 → 마감 없음, 동점은 id).
    public static func cards(_ tasks: [MokaTask]) -> [MokaTask] {
        tasks.filter { $0.dueDecision && $0.status == .todo }.sorted(by: TaskListView.deadlineFirst)
    }
}
