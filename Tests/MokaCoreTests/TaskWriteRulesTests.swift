import Foundation
import MokaCore
import Testing

// data-model §5.8. 2027-01-13은 수요일(4), 2027-01-12는 화요일(3).

private func newTask(
    _ title: String = "가짜 할 일 A", recurrence: Recurrence = .none, weekday: Weekday? = nil, estMin: Int? = nil,
    deadline: LocalDay? = nil
) -> NewTask {
    NewTask(title: title, deadline: deadline, estMin: estMin, recurrence: recurrence, weekday: weekday)
}

private func prepare(_ task: NewTask, now: Date = Fake.noon, calendar: Calendar = Fake.seoul) -> (
    task: NewTask, cycleDay: LocalDay?
)? {
    TaskWriteRules.prepareNew(task, now: now, dayStart: Fake.sixAM, calendar: calendar)
}

private func edit(_ task: MokaTask, _ change: TaskEdit, now: Date = Fake.noon) -> MokaTask? {
    TaskWriteRules.applyEdit(task, change, now: now, dayStart: Fake.sixAM, calendar: Fake.seoul)
}

@Suite struct PrepareNewTests {
    @Test("FR-01 R-101: 새 할 일 제목은 앞뒤 공백을 빼고, 반복 없음이면 cycleDay는 nil")
    func trimsTitle() throws {
        let prepared = try #require(prepare(newTask("  가짜 할 일 A \n")))
        #expect(prepared.task == newTask("가짜 할 일 A"))
        #expect(prepared.cycleDay == nil)
    }

    @Test("FR-01 R-101: 제목이 비거나 공백뿐이면 저장하지 않는다(nil)", arguments: ["", "   ", "\n\t"])
    func blankTitleRejected(title: String) {
        #expect(prepare(newTask(title)) == nil)
    }

    @Test("FR-01 R-101: 예상 소요는 nil 또는 1 이상만", arguments: [(Int?.none, true), (1, true), (0, false), (-3, false)])
    func estMinValidated(estMin: Int?, accepted: Bool) {
        #expect((prepare(newTask(estMin: estMin)) != nil) == accepted)
    }

    @Test("FR-01 R-101: 반복이 매주가 아닌데 요일이 있으면 저장하지 않는다", arguments: [Recurrence.none, .daily])
    func weekdayOnlyForWeekly(recurrence: Recurrence) {
        #expect(prepare(newTask(recurrence: recurrence, weekday: Fake.weekday(2))) == nil)
    }

    @Test("FR-09 R-113: 매주인데 요일이 없으면 등록 순간이 속한 하루의 요일로 채운다")
    func weeklyFillsWeekday() throws {
        let prepared = try #require(prepare(newTask(recurrence: .weekly)))
        #expect(prepared.task.weekday == Fake.weekday(4))
        #expect(prepared.cycleDay == Fake.day("2027-01-13"))
    }

    @Test("FR-09 R-113: 하루 시작 06:00에 05:00 등록이면 전날의 요일로 채운다")
    func earlyMorningUsesPreviousDay() throws {
        let fiveAM = Fake.at(2027, 1, 13, 5, 0)
        let prepared = try #require(prepare(newTask(recurrence: .weekly), now: fiveAM))
        #expect(prepared.task.weekday == Fake.weekday(3))
        #expect(prepared.cycleDay == Fake.day("2027-01-12"))
    }

    @Test("FR-09 R-113: 매일 반복의 cycleDay는 등록 순간이 속한 하루")
    func dailyCycleDay() throws {
        let prepared = try #require(prepare(newTask(recurrence: .daily)))
        #expect(prepared.cycleDay == Fake.day("2027-01-13"))
        #expect(prepared.task.weekday == nil)
    }

    @Test("FR-09 R-113: 요일을 고른 매주의 cycleDay는 지금 주기의 첫 하루(그 요일의 가장 최근 날)")
    func weeklyCycleDayIsLatestWeekday() throws {
        // 수요일 등록, 월요일(2) 고름 → 2027-01-11(월)
        let monday = try #require(prepare(newTask(recurrence: .weekly, weekday: Fake.weekday(2))))
        #expect(monday.task.weekday == Fake.weekday(2))
        #expect(monday.cycleDay == Fake.day("2027-01-11"))
        // 금요일(6) 고름 → 지난 금요일 2027-01-08
        let friday = try #require(prepare(newTask(recurrence: .weekly, weekday: Fake.weekday(6))))
        #expect(friday.cycleDay == Fake.day("2027-01-08"))
    }

    @Test("FR-01 R-101: 마감과 예상 소요는 그대로 둔다")
    func keepsDeadlineAndEstimate() throws {
        let task = newTask(estMin: 50, deadline: Fake.day("2027-01-20"))
        #expect(try #require(prepare(task)).task == task)
    }
}

@Suite struct ApplyEditTests {
    private let plain = Fake.task(1, deadline: Fake.day("2027-01-20"), estMin: 30)
    private let weeklyWed = Fake.task(
        2, recurrence: .weekly, weekday: Fake.weekday(4), cycleDay: Fake.day("2027-01-13"), skipCount: 2, streak: 3)
    private let daily = Fake.task(3, recurrence: .daily, cycleDay: Fake.day("2027-01-13"), skipCount: 1, streak: 5)

    @Test("FR-01 R-101: 빈 고침은 아무것도 바꾸지 않는다")
    func emptyEditKeepsAll() {
        #expect(edit(plain, TaskEdit()) == plain)
        #expect(edit(weeklyWed, TaskEdit()) == weeklyWed)
    }

    @Test("FR-01 R-101: 제목·마감·예상 소요를 고치고 비울 수 있다")
    func editsFields() throws {
        let changed = try #require(
            edit(plain, TaskEdit(title: "  가짜 할 일 B ", deadline: .set(Fake.day("2027-02-01")), estMin: .set(15))))
        #expect(changed.title == "가짜 할 일 B")
        #expect(changed.deadline == Fake.day("2027-02-01"))
        #expect(changed.estMin == 15)
        let cleared = try #require(edit(plain, TaskEdit(deadline: .clear, estMin: .clear)))
        #expect(cleared.deadline == nil)
        #expect(cleared.estMin == nil)
    }

    @Test("FR-01 R-101: 빈 제목이나 1 미만 예상 소요로 고치면 저장하지 않는다(nil)")
    func invalidEditRejected() {
        #expect(edit(plain, TaskEdit(title: "  ")) == nil)
        #expect(edit(plain, TaskEdit(estMin: .set(0))) == nil)
    }

    @Test("FR-09 R-113: 매주로 바꾸면서 요일이 없으면 그 순간이 속한 하루의 요일로 채운다")
    func toWeeklyFillsWeekday() throws {
        let fiveAM = Fake.at(2027, 1, 13, 5, 0)
        let changed = try #require(edit(plain, TaskEdit(recurrence: .weekly), now: fiveAM))
        #expect(changed.recurrence == .weekly)
        #expect(changed.weekday == Fake.weekday(3))
        #expect(changed.cycleDay == Fake.day("2027-01-12"))
        #expect(changed.streak == 0)
    }

    @Test("FR-09 R-113: 매일·반복 없음으로 바꾸면 요일을 지운다")
    func awayFromWeeklyClearsWeekday() throws {
        let toDaily = try #require(edit(weeklyWed, TaskEdit(recurrence: .daily)))
        #expect(toDaily.weekday == nil)
        #expect(toDaily.cycleDay == Fake.day("2027-01-13"))
        let toNone = try #require(edit(weeklyWed, TaskEdit(recurrence: Recurrence.none)))
        #expect(toNone.weekday == nil)
    }

    @Test("FR-09 R-113: 반복 없음으로 바꾸면 cycle_day를 지운다")
    func toNoneClearsCycleDay() throws {
        let changed = try #require(edit(daily, TaskEdit(recurrence: Recurrence.none)))
        #expect(changed.recurrence == .none)
        #expect(changed.cycleDay == nil)
    }

    @Test("FR-09 R-113: 반복이나 요일이 실제로 바뀌면 cycle_day = 그 순간의 c, streak 0, skip_count 그대로")
    func changeResetsCycleAndStreak() throws {
        let toMonday = try #require(edit(weeklyWed, TaskEdit(weekday: Fake.weekday(2))))
        #expect(toMonday.weekday == Fake.weekday(2))
        #expect(toMonday.cycleDay == Fake.day("2027-01-11"))
        #expect(toMonday.streak == 0)
        #expect(toMonday.skipCount == 2)
        #expect(toMonday.status == .todo)
        let toWeekly = try #require(edit(daily, TaskEdit(recurrence: .weekly, weekday: Fake.weekday(6))))
        #expect(toWeekly.cycleDay == Fake.day("2027-01-08"))
        #expect(toWeekly.streak == 0)
        #expect(toWeekly.skipCount == 1)
    }

    @Test("FR-09 R-113: 같은 반복·요일을 다시 주면 아무것도 바꾸지 않는다")
    func sameRecurrenceKeepsAll() {
        #expect(edit(weeklyWed, TaskEdit(recurrence: .weekly, weekday: Fake.weekday(4))) == weeklyWed)
        #expect(edit(daily, TaskEdit(recurrence: .daily)) == daily)
        #expect(edit(plain, TaskEdit(recurrence: Recurrence.none)) == plain)
    }

    @Test("FR-09 R-113: 매주가 아닌 반복에 요일을 주면 저장하지 않는다(nil)")
    func weekdayWithoutWeeklyRejected() {
        #expect(edit(plain, TaskEdit(weekday: Fake.weekday(2))) == nil)
        #expect(edit(weeklyWed, TaskEdit(recurrence: .daily, weekday: Fake.weekday(2))) == nil)
    }

    @Test("FR-01 R-101: 상태는 바꾸지 않고, 완료한 할 일도 고칠 수 있다")
    func doneTaskEditable() throws {
        let done = Fake.task(4, status: .done, recurrence: .daily, cycleDay: Fake.day("2027-01-13"), streak: 2)
        let changed = try #require(edit(done, TaskEdit(title: "가짜 할 일 C", estMin: .set(20), recurrence: .weekly)))
        #expect(changed.status == .done)
        #expect(changed.title == "가짜 할 일 C")
        #expect(changed.recurrence == .weekly)
        #expect(changed.weekday == Fake.weekday(4))
    }

    @Test("FR-01 R-101: 버린 할 일은 고칠 수 없다(nil)")
    func droppedNotEditable() {
        #expect(edit(Fake.task(5, status: .dropped), TaskEdit(title: "가짜 할 일 D")) == nil)
        #expect(edit(Fake.task(5, status: .dropped), TaskEdit()) == nil)
    }

    @Test("FR-01 R-101: 고침은 id·만든 시각·첫 행동·미룬 횟수를 바꾸지 않는다")
    func keepsIdentityFields() throws {
        let task = Fake.task(6, firstAction: "가짜 첫 행동", skipCount: 4)
        let changed = try #require(edit(task, TaskEdit(title: "가짜 할 일 E", recurrence: .daily)))
        #expect(changed.id == task.id)
        #expect(changed.createdAt == task.createdAt)
        #expect(changed.firstAction == "가짜 첫 행동")
        #expect(changed.skipCount == 4)
    }
}

/// 반복 할 일은 마감이 없다(2026-11-04 사용자 결정, R-101).
@Suite struct RecurringHasNoDeadlineTests {
    @Test("FR-01 R-101: 반복 할 일에 마감을 주면 저장하지 않는다", arguments: [Recurrence.daily, .weekly])
    func prepareRejectsDeadlineOnRecurring(recurrence: Recurrence) {
        #expect(prepare(newTask(recurrence: recurrence, deadline: Fake.day("2027-01-20"))) == nil)
    }

    @Test("FR-01 R-101: 마감 있는 할 일을 반복으로 바꾸면 마감을 지운다", arguments: [Recurrence.daily, .weekly])
    func editToRecurringClearsDeadline(recurrence: Recurrence) throws {
        let task = Fake.task(1, deadline: Fake.day("2027-01-20"))
        let changed = try #require(edit(task, TaskEdit(recurrence: recurrence)))
        #expect(changed.recurrence == recurrence)
        #expect(changed.deadline == nil)
    }

    @Test("FR-01 R-101: 반복을 없음으로 바꾸면서 마감을 넣으면 저장한다")
    func editToNoneWithDeadline() throws {
        let daily = Fake.task(3, recurrence: .daily, cycleDay: Fake.day("2027-01-13"))
        let changed = try #require(
            edit(daily, TaskEdit(deadline: .set(Fake.day("2027-01-20")), recurrence: Recurrence.none)))
        #expect(changed.recurrence == .none)
        #expect(changed.deadline == Fake.day("2027-01-20"))
    }

    @Test("FR-01 R-101: 마감을 비우면서 반복으로 바꾸면 저장한다")
    func editClearAndRecurring() throws {
        let task = Fake.task(1, deadline: Fake.day("2027-01-20"))
        let changed = try #require(edit(task, TaskEdit(deadline: .clear, recurrence: .weekly)))
        #expect(changed.deadline == nil)
        #expect(changed.recurrence == .weekly)
    }

    @Test("FR-01 R-101: 반복 할 일에 마감을 넣는 고침은 저장하지 않는다")
    func editRejectsDeadlineOnRecurring() {
        let daily = Fake.task(3, recurrence: .daily, cycleDay: Fake.day("2027-01-13"))
        #expect(edit(daily, TaskEdit(deadline: .set(Fake.day("2027-01-20")))) == nil)
    }
}
