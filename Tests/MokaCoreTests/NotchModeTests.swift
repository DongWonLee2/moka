import Foundation
import MokaCore
import Testing

// spec 005 data-model §12. 가짜 할 일만 쓴다.

private let today = Fake.day("2027-01-13")
private let draft = NotchTimer.empty(draft: Draft(title: "가짜 할 일 1", chipMin: 25))
private let running = NotchTimer.running(
    title: "가짜 할 일 1", quantumMin: 25, startedAt: Fake.noon, endsAt: Fake.noon.addingTimeInterval(1500))
private let expired = NotchTimer.expired(title: "가짜 할 일 1", chipMin: 10)

private func budget(_ minutes: Int, used: Int = 0, more: Bool = false, day: LocalDay = today) -> DayBudget {
    DayBudget(day: day, minutes: minutes, extendedMinutes: 0, usedSeconds: used, more: more)
}

private func mode(
    available: Bool = true, _ timer: NotchTimer, _ tasks: [MokaTask] = [], budget: DayBudget? = nil
) -> NotchMode {
    NotchMode.of(storageAvailable: available, timer: timer, tasks: tasks, budget: budget, today: today)
}

private let dueTasks = [
    Fake.task(1, dueDecision: true), Fake.task(2, deadline: Fake.day("2027-01-11"), dueDecision: true),
]

@Suite struct NotchModeTests {
    @Test("FR-10 R-422: 1 앱 DB를 열 수 없으면 무엇보다 앞선다")
    func storageUnavailable() {
        #expect(mode(available: false, running, dueTasks) == .storageUnavailable)
    }

    @Test("FR-08 R-417: 2 도는 중·시간 끝이면 카드·질문·오늘 끝보다 세션이 앞선다", arguments: [running, expired])
    func sessionWhileRunning(timer: NotchTimer) {
        #expect(mode(timer, dueTasks) == .session)
        #expect(mode(timer, [], budget: budget(60, used: 3600)) == .session)
        #expect(mode(timer, []) == .session)
    }

    @Test("FR-08 R-414: 3 카드에 오를 할 일이 있으면 첫 카드, 남은 개수, 까닭", arguments: [NotchTimer.empty(draft: nil), draft])
    func carryCard(timer: NotchTimer) {
        #expect(mode(timer, dueTasks, budget: budget(60)) == .carryCard(taskID: 2, left: 2, reason: .overdue(days: 2)))
    }

    @Test("FR-08 R-417: 진행 중 할 일의 표시만 있으면 카드가 아니다")
    func activeDueIsNotCard() {
        #expect(mode(.empty(draft: nil), [Fake.task(1, status: .active, dueDecision: true)]) == .askBudget)
    }

    @Test("FR-10 R-419: 4 오늘 기록이 없으면(어제 기록 포함) 가용 시간 질문")
    func askBudget() {
        #expect(mode(.empty(draft: nil), [Fake.task(1)]) == .askBudget)
        #expect(mode(draft, [Fake.task(1)], budget: budget(60, day: Fake.day("2027-01-12"))) == .askBudget)
    }

    @Test("FR-10 R-422: 5 상한이 걸렸고 남은 분이 1 미만이면 오늘 끝", arguments: [7200, 7141, 7300])
    func dayEnd(used: Int) {
        #expect(mode(.empty(draft: nil), [Fake.task(1)], budget: budget(120, used: used)) == .dayEnd)
    }

    @Test("FR-10 R-422: 6 남은 분이 있거나 더 할래요 뒤면 세션")
    func session() {
        #expect(mode(.empty(draft: nil), [Fake.task(1)], budget: budget(120, used: 7140)) == .session)
        #expect(mode(draft, [Fake.task(1)], budget: budget(120, used: 7200, more: true)) == .session)
    }

    @Test("FR-08 R-413 FR-10 R-419 R-422: 카드·질문·오늘 끝은 초안을 비우는 모드다")
    func clearsDraft() {
        #expect(NotchMode.carryCard(taskID: 1, left: 1, reason: .touched).clearsDraft)
        #expect(NotchMode.askBudget.clearsDraft)
        #expect(NotchMode.dayEnd.clearsDraft)
        #expect(!NotchMode.session.clearsDraft)
        #expect(!NotchMode.storageUnavailable.clearsDraft)
    }

    @Test("FR-10 R-422: 시간 끝이고 그 작업 시간의 하루 기록이 상한이 걸린 채 남은 분 1 미만이면 N분 더를 끈다")
    func expiredDayEnd() {
        #expect(NotchMode.expiredDayEnd(timer: expired, budgetDayRecord: budget(120, used: 7200)))
        #expect(!NotchMode.expiredDayEnd(timer: expired, budgetDayRecord: budget(120, used: 7140)))
        #expect(!NotchMode.expiredDayEnd(timer: expired, budgetDayRecord: budget(120, used: 7200, more: true)))
        #expect(!NotchMode.expiredDayEnd(timer: expired, budgetDayRecord: nil))
        #expect(!NotchMode.expiredDayEnd(timer: running, budgetDayRecord: budget(120, used: 7200)))
    }
}
