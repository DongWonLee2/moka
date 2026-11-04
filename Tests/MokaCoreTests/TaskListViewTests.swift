import Foundation
import MokaCore
import Testing

// data-model §5.7. 2027-01-13 수, 01-16 토, 01-17 일, 01-10 일.

private func rows(
    _ tasks: [MokaTask], _ scope: TaskListScope, _ order: TaskListOrder = .created, today: String = "2027-01-13"
) -> [TaskID] {
    TaskListView.rows(tasks, scope: scope, order: order, today: Fake.day(today), calendar: Fake.seoul).map(\.id)
}

private let cycle = Fake.day("2027-01-10")

@Suite struct TaskListViewTests {
    @Test("FR-01 R-118: 전체는 버리지 않은 모든 할 일이고 상태로 거르지 않는다")
    func allExcludesDroppedOnly() {
        let tasks = [
            Fake.task(1), Fake.task(2, status: .active), Fake.task(3, status: .done), Fake.task(4, status: .dropped),
            Fake.task(5, deadline: Fake.day("2027-03-01")),
        ]
        #expect(rows(tasks, .all) == [1, 2, 5, 3])
    }

    @Test("FR-01 R-118: 버린 할 일은 어느 보기에도 없다", arguments: [TaskListScope.all, .today, .thisWeek])
    func droppedNeverShown(scope: TaskListScope) {
        let tasks = [
            Fake.task(1, status: .dropped, deadline: Fake.day("2027-01-13")),
            Fake.task(2, status: .dropped, recurrence: .daily, cycleDay: cycle),
        ]
        #expect(rows(tasks, scope).isEmpty)
    }

    @Test("FR-01 R-118: 오늘은 마감이 오늘 이하, 매일, 오늘 요일의 매주")
    func todayScope() {
        let tasks = [
            Fake.task(1, deadline: Fake.day("2027-01-13")),  // 오늘 마감
            Fake.task(2, deadline: Fake.day("2027-01-05")),  // 지난 마감
            Fake.task(3, deadline: Fake.day("2027-01-14")),  // 내일 마감
            Fake.task(4),  // 마감 없음
            Fake.task(5, recurrence: .daily, cycleDay: cycle),
            Fake.task(6, recurrence: .weekly, weekday: Fake.weekday(4), cycleDay: cycle),  // 수요일 = 오늘
            Fake.task(7, recurrence: .weekly, weekday: Fake.weekday(5), cycleDay: cycle),  // 목요일
            Fake.task(8, status: .done, deadline: Fake.day("2027-01-13")),
        ]
        #expect(rows(tasks, .today) == [1, 2, 5, 6, 8])
    }

    @Test("FR-01 R-118: 이번 주는 마감이 이번 주 토요일 이하 또는 반복이 있음")
    func thisWeekScope() {
        let tasks = [
            Fake.task(1, deadline: Fake.day("2027-01-16")),  // 이번 주 토요일
            Fake.task(2, deadline: Fake.day("2027-01-17")),  // 다음 주 일요일
            Fake.task(3, deadline: Fake.day("2026-12-30")),  // 지난 마감
            Fake.task(4),  // 마감 없음
            Fake.task(5, recurrence: .weekly, weekday: Fake.weekday(1), cycleDay: cycle),
            Fake.task(6, recurrence: .daily, cycleDay: cycle),
        ]
        #expect(rows(tasks, .thisWeek) == [1, 3, 5, 6])
    }

    @Test(
        "FR-01 R-118: 오늘이 토요일이면 이번 주는 그날까지, 일요일이면 그 주 토요일까지",
        arguments: [
            ("2027-01-16", [1]),  // 토요일: 01-16까지
            ("2027-01-17", [1, 2, 3]),  // 일요일: 01-23까지
        ])
    func weekEdges(today: String, expected: [TaskID]) {
        let tasks = [
            Fake.task(1, deadline: Fake.day("2027-01-16")),
            Fake.task(2, deadline: Fake.day("2027-01-17")),
            Fake.task(3, deadline: Fake.day("2027-01-23")),
            Fake.task(4, deadline: Fake.day("2027-01-24")),
        ]
        #expect(rows(tasks, .thisWeek, today: today) == expected)
    }

    @Test("FR-01 R-118: 오늘이 토요일·일요일일 때 오늘 보기의 매주 요일 비교", arguments: [("2027-01-16", 7), ("2027-01-17", 1)])
    func todayWeekdayOnWeekend(today: String, weekday: Int) {
        let tasks = [
            Fake.task(1, recurrence: .weekly, weekday: Fake.weekday(weekday), cycleDay: cycle),
            Fake.task(2, recurrence: .weekly, weekday: Fake.weekday(weekday % 7 + 1), cycleDay: cycle),
        ]
        #expect(rows(tasks, .today, today: today) == [1])
    }

    @Test("FR-01 R-118: 만든 순은 id 오름차순")
    func createdOrder() {
        let tasks = [Fake.task(3), Fake.task(1), Fake.task(2)]
        #expect(rows(tasks, .all, .created) == [1, 2, 3])
    }

    @Test("FR-01 R-118: 마감 순은 마감 오름차순, 마감 없음은 맨 뒤, 같은 마감은 id 오름차순")
    func deadlineOrder() {
        let tasks = [
            Fake.task(1),
            Fake.task(2, deadline: Fake.day("2027-01-20")),
            Fake.task(3, deadline: Fake.day("2027-01-05")),
            Fake.task(4, deadline: Fake.day("2027-01-20")),
            Fake.task(5),
            Fake.task(6, deadline: Fake.day("2027-01-14")),
        ]
        #expect(rows(tasks, .all, .deadline) == [3, 6, 2, 4, 1, 5])
    }

    @Test(
        "FR-01 R-118: 완료한 할 일은 어느 정렬에서도 아래로 모이고, 그 안의 순서는 정렬을 따른다(2026-11-04 사용자 결정)",
        arguments: [(TaskListOrder.created, [TaskID]([2, 4, 1, 3])), (.deadline, [4, 2, 3, 1])])
    func doneSinksToBottom(order: TaskListOrder, expected: [TaskID]) {
        let tasks = [
            Fake.task(1, status: .done),
            Fake.task(2, deadline: Fake.day("2027-01-20")),
            Fake.task(3, status: .done, deadline: Fake.day("2027-01-05")),
            Fake.task(4, status: .active, deadline: Fake.day("2027-01-14")),
        ]
        #expect(rows(tasks, .all, order) == expected)
    }
}
