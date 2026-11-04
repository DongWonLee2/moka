import Foundation
import MokaCore
import Testing

/// 할 일 탭 줄 글자(R-102, 시안 7번, #42 원칙). 할 일은 가짜 예시만 쓴다.
private func task(
    deadline: String? = nil, estMin: Int? = nil, recurrence: Recurrence = .none, weekday: Int? = nil,
    status: TaskStatus = .todo, skipCount: Int = 0, streak: Int = 0
) -> MokaTask {
    MokaTask(
        id: 1, title: "가짜 할 일", deadline: deadline.flatMap(LocalDay.init(text:)), estMin: estMin,
        recurrence: recurrence, weekday: weekday.flatMap(Weekday.init(rawValue:)),
        cycleDay: recurrence == .none ? nil : LocalDay(text: "2026-11-04"), firstAction: nil, status: status,
        skipCount: skipCount, streak: streak, createdAt: Date(timeIntervalSince1970: 1_800_000_000))
}

@Test("R-102 #42: 보조 줄은 마감 · 예상 순서로 잇는다")
func metaDeadlineAndEstimate() {
    #expect(TaskRowText.meta(task(deadline: "2026-11-05", estMin: 50)) == "마감 11월 5일 · 예상 50분")
}

@Test("R-102 #42: 매일 반복은 매일")
func metaDaily() {
    #expect(TaskRowText.meta(task(recurrence: .daily)) == "매일")
}

@Test(
    "R-102 #42: 매주 반복은 요일 이름, 미룬 횟수는 뒤에 붙인다",
    arguments: [(1, "매주 일요일"), (4, "매주 수요일"), (7, "매주 토요일")])
func metaWeeklyWithSkips(weekday: Int, expected: String) {
    #expect(TaskRowText.meta(task(recurrence: .weekly, weekday: weekday, skipCount: 2)) == "\(expected) · 2번 미뤘어요")
}

@Test("R-102 #42: 보일 것이 없으면 —")
func metaEmptyIsDash() {
    #expect(TaskRowText.meta(task()) == "—")
}

@Test("R-102 #42: 완료한 할 일의 보조 줄은 완료(시안 7번, 2026-11-04 사용자 결정)")
func metaDoneIsCompleted() {
    #expect(TaskRowText.meta(task(deadline: "2026-11-05", estMin: 50, status: .done)) == "완료")
}

@Test("R-102 #42: 연속 기록 배지는 매일 N일, 매주 N주, 0이면 없음")
func streakBadge() {
    #expect(TaskRowText.streakBadge(task(recurrence: .daily, streak: 3)) == "3일 연속 진행")
    #expect(TaskRowText.streakBadge(task(recurrence: .weekly, weekday: 4, streak: 2)) == "2주 연속 진행")
    #expect(TaskRowText.streakBadge(task(recurrence: .daily, streak: 0)) == nil)
    #expect(TaskRowText.streakBadge(task(streak: 5)) == nil)
}

@Test("R-102 #42: 상태 배지는 대기, 진행 중, 완료")
func statusLabel() {
    #expect(TaskRowText.status(.todo) == "대기")
    #expect(TaskRowText.status(.active) == "진행 중")
    #expect(TaskRowText.status(.done) == "완료")
}
