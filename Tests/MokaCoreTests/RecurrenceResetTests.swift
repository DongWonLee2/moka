import Foundation
import MokaCore
import Testing

// data-model §5.3. 2027-01-13은 수요일(4). 2027-03-14는 America/New_York 일광절약시간 시작일.

private func reset(_ tasks: [MokaTask], at now: Date, dayStart: DayStart = Fake.sixAM, calendar: Calendar = Fake.seoul)
    -> [MokaTask]
{
    RecurrenceReset.reset(tasks, now: now, dayStart: dayStart, calendar: calendar)
}

/// 바뀐 할 일을 목록에 덮어쓴다(저장소 `apply`와 같은 결과).
private func merged(_ tasks: [MokaTask], _ changed: [MokaTask]) -> [MokaTask] {
    tasks.map { task in changed.first { $0.id == task.id } ?? task }
}

private let wednesday = Fake.weekday(4)

@Suite struct RecurrenceCycleStartTests {
    @Test("FR-09 R-113: 반복 없음은 주기 첫 하루가 없다(nil), 매일은 오늘")
    func noneAndDaily() {
        let today = Fake.day("2027-01-15")
        #expect(RecurrenceReset.cycleStart(for: Fake.task(1), today: today, calendar: Fake.seoul) == nil)
        let daily = Fake.task(2, recurrence: .daily, cycleDay: today)
        #expect(RecurrenceReset.cycleStart(for: daily, today: today, calendar: Fake.seoul) == today)
    }

    @Test(
        "FR-09 R-113: 매주는 오늘에서 (오늘 요일 − 고른 요일 + 7) % 7일 앞",
        arguments: [
            ("2027-01-13", "2027-01-13"), ("2027-01-14", "2027-01-13"), ("2027-01-16", "2027-01-13"),
            ("2027-01-17", "2027-01-13"), ("2027-01-19", "2027-01-13"), ("2027-01-20", "2027-01-20"),
        ])
    func weekly(today: String, expected: String) {
        let task = Fake.task(1, recurrence: .weekly, weekday: wednesday, cycleDay: Fake.day("2027-01-06"))
        #expect(
            RecurrenceReset.cycleStart(for: task, today: Fake.day(today), calendar: Fake.seoul) == Fake.day(expected))
    }
}

@Suite struct RecurrenceResetTests {
    @Test("FR-09 R-113: 어제 완료한 매일 반복은 대기로, 연속 기록 유지, 미룬 횟수 0, cycle_day = 오늘")
    func dailyDoneYesterdayKeepsStreak() {
        let task = Fake.task(
            1, status: .done, recurrence: .daily, cycleDay: Fake.day("2027-01-12"), skipCount: 2, streak: 3)
        let changed = reset([task], at: Fake.at(2027, 1, 13, 6, 0))
        var expected = task
        expected.status = .todo
        expected.skipCount = 0
        expected.cycleDay = Fake.day("2027-01-13")
        #expect(changed == [expected])
    }

    @Test("FR-09 R-113: 어제 하지 않은 매일 반복은 대기 그대로 한 건, 연속 기록 0")
    func dailyMissedResetsStreak() {
        let task = Fake.task(1, recurrence: .daily, cycleDay: Fake.day("2027-01-12"), skipCount: 1, streak: 3)
        let changed = reset([task], at: Fake.at(2027, 1, 13, 9, 0))
        #expect(changed.count == 1)
        #expect(changed.first?.status == .todo)
        #expect(changed.first?.streak == 0)
        #expect(changed.first?.skipCount == 0)
        #expect(changed.first?.cycleDay == Fake.day("2027-01-13"))
    }

    @Test("FR-09 R-113: 더 오래전에 완료한 반복은 대기로 돌아오고 연속 기록 0")
    func olderDoneResetsStreak() {
        let task = Fake.task(1, status: .done, recurrence: .daily, cycleDay: Fake.day("2027-01-10"), streak: 6)
        let changed = reset([task], at: Fake.at(2027, 1, 13, 9, 0))
        #expect(changed.first?.status == .todo)
        #expect(changed.first?.streak == 0)
    }

    @Test("FR-09 R-113: 하루 시작 전(05:59:59)에는 아직 어제라 되돌리지 않는다")
    func beforeDayStartKeeps() {
        let task = Fake.task(1, status: .done, recurrence: .daily, cycleDay: Fake.day("2027-01-12"), streak: 3)
        #expect(reset([task], at: Fake.at(2027, 1, 13, 5, 59, 59)).isEmpty)
    }

    @Test(
        "FR-09 R-113: 매주 수요일은 목~화에는 그대로",
        arguments: [
            (2027, 1, 14, 9, 0), (2027, 1, 16, 9, 0), (2027, 1, 17, 9, 0), (2027, 1, 19, 23, 0), (2027, 1, 20, 5, 59),
        ])
    func weeklyStaysBetween(year: Int, month: Int, day: Int, hour: Int, minute: Int) {
        let task = Fake.task(
            1, status: .done, recurrence: .weekly, weekday: wednesday, cycleDay: Fake.day("2027-01-13"), streak: 2)
        #expect(reset([task], at: Fake.at(year, month, day, hour, minute)).isEmpty)
    }

    @Test("FR-09 R-113: 매주 수요일은 다음 수요일 06:00 뒤 대기로, 지난주 완료면 연속 기록 유지")
    func weeklyResetsNextWednesday() {
        let task = Fake.task(
            1, status: .done, recurrence: .weekly, weekday: wednesday, cycleDay: Fake.day("2027-01-13"), streak: 2)
        let changed = reset([task], at: Fake.at(2027, 1, 20, 6, 0))
        #expect(changed.first?.status == .todo)
        #expect(changed.first?.streak == 2)
        #expect(changed.first?.cycleDay == Fake.day("2027-01-20"))
        #expect(changed.first?.weekday == wednesday)
    }

    @Test("FR-09 R-113: 매주를 한 주 넘게 하지 않았으면 연속 기록 0")
    func weeklySkippedWeekResetsStreak() {
        let task = Fake.task(
            1, status: .done, recurrence: .weekly, weekday: wednesday, cycleDay: Fake.day("2027-01-06"), streak: 2)
        let changed = reset([task], at: Fake.at(2027, 1, 20, 9, 0))
        #expect(changed.first?.streak == 0)
        #expect(changed.first?.cycleDay == Fake.day("2027-01-20"))
    }

    @Test("FR-09 R-113: 진행 중·버린 반복과 반복 없는 할 일은 건드리지 않는다")
    func leavesActiveDroppedAndPlain() {
        let old = Fake.day("2027-01-01")
        let tasks = [
            Fake.task(1, status: .active, recurrence: .daily, cycleDay: old),
            Fake.task(2, status: .dropped, recurrence: .daily, cycleDay: old),
            Fake.task(3, status: .done),
            Fake.task(4),
        ]
        #expect(reset(tasks, at: Fake.at(2027, 1, 13, 9, 0)).isEmpty)
    }

    @Test("FR-09 R-113: 하루 판정을 두 번 돌린 결과는 한 번 돌린 결과와 같고 할 일 수가 그대로(SC-104)")
    func idempotent() {
        let tasks = [
            Fake.task(1, status: .done, recurrence: .daily, cycleDay: Fake.day("2027-01-12"), streak: 1),
            Fake.task(2, recurrence: .daily, cycleDay: Fake.day("2027-01-11"), streak: 4),
            Fake.task(
                3, status: .done, recurrence: .weekly, weekday: wednesday, cycleDay: Fake.day("2027-01-06"), streak: 1),
            Fake.task(4),
        ]
        let now = Fake.at(2027, 1, 13, 7, 0)
        let once = merged(tasks, reset(tasks, at: now))
        #expect(reset(once, at: now).isEmpty)
        #expect(reset(once, at: now + 3600).isEmpty)
        let twice = merged(once, reset(once, at: now))
        #expect(twice == once)
        #expect(twice.count == tasks.count)
    }

    @Test("FR-09 R-113: 하루 시작 시각을 늦춰 오늘이 앞 하루로 돌아가도 되돌리지 않는다")
    func laterDayStartDoesNotRevert() {
        let task = Fake.task(1, status: .done, recurrence: .daily, cycleDay: Fake.day("2027-01-12"), streak: 1)
        let at0630 = Fake.at(2027, 1, 13, 6, 30)
        let once = merged([task], reset([task], at: at0630))
        #expect(once.first?.cycleDay == Fake.day("2027-01-13"))
        var finished = once
        finished[0].status = .done
        finished[0].streak = 2
        // 06:40에 하루 시작을 07:00으로 바꿈 → 오늘은 2027-01-12
        #expect(reset(finished, at: at0630 + 600, dayStart: DayStart(text: "07:00")!).isEmpty)
    }

    @Test(
        "FR-09 R-113: 두 시간대에서 하루 시작 06:00 앞뒤로 같은 규칙(뉴욕 3월 전환일 포함)",
        arguments: [
            (Fake.seoul, (2027, 3, 14, 5, 59), false), (Fake.seoul, (2027, 3, 14, 6, 0), true),
            (Fake.newYork, (2027, 3, 14, 5, 59), false), (Fake.newYork, (2027, 3, 14, 6, 0), true),
            (Fake.newYork, (2027, 3, 14, 3, 30), false),
        ])
    func twoTimeZones(calendar: Calendar, local: (Int, Int, Int, Int, Int), resets: Bool) {
        let task = Fake.task(1, status: .done, recurrence: .daily, cycleDay: Fake.day("2027-03-13"), streak: 5)
        let now = Fake.at(local.0, local.1, local.2, local.3, local.4, calendar: calendar)
        let changed = reset([task], at: now, calendar: calendar)
        #expect(changed.isEmpty == !resets)
        if resets {
            #expect(changed.first?.streak == 5)
            #expect(changed.first?.cycleDay == Fake.day("2027-03-14"))
        }
    }
}
