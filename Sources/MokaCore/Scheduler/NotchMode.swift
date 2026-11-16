import Foundation

/// 노치 화면 모드(spec 005 data-model §12). 표의 순서대로 첫 조건이 정한다.
public enum NotchMode: Equatable, Sendable {
    /// 1. 앱 DB를 열 수 없음(spec 002 R-119).
    case storageUnavailable
    /// 2·6. 도는 중·시간 끝, 또는 빈 상태·초안(빈 상태면 고르기).
    case session
    /// 3. 카드에 오를 할 일이 있음. `left`는 지금 것을 포함한 수.
    case carryCard(taskID: TaskID, left: Int, reason: CarryCardReason)
    /// 4. 오늘 가용 시간 기록이 없음.
    case askBudget
    /// 5. 상한이 걸렸고 남은 분이 1 미만.
    case dayEnd

    /// `budget`은 저장된 기록이다(어느 하루든). 오늘 기록만 본다.
    public static func of(
        storageAvailable: Bool, timer: NotchTimer, tasks: [MokaTask], budget: DayBudget?, today: LocalDay
    ) -> NotchMode {
        guard storageAvailable else { return .storageUnavailable }
        switch timer {
        case .running, .expired: return .session
        case .empty: break
        }
        let cards = CarryAnswer.cards(tasks)
        if let first = cards.first {
            return .carryCard(
                taskID: first.id, left: cards.count, reason: CarryCardReason.of(task: first, today: today))
        }
        guard let record = DayBudget.record(budget, for: today) else { return .askBudget }
        if let cap = DayBudget.capMinutes(record), cap < 1 { return .dayEnd }
        return .session
    }

    /// 이 모드가 되면 초안을 비운다(R-413 Edge Case, R-419, R-422).
    public var clearsDraft: Bool {
        switch self {
        case .carryCard, .askBudget, .dayEnd: true
        case .storageUnavailable, .session: false
        }
    }

    /// 시간 끝과 오늘 끝이 겹침: "N분 더"를 끄고 세 버튼의 체크포인트 계기가 `day_end`다(R-422, research R11).
    /// `budgetDayRecord`는 그 작업 시간을 시작한 하루의 기록이다.
    public static func expiredDayEnd(timer: NotchTimer, budgetDayRecord: DayBudget?) -> Bool {
        guard case .expired = timer, let cap = DayBudget.capMinutes(budgetDayRecord) else { return false }
        return cap < 1
    }
}
