import Foundation
import MokaCore
import Testing

// MARK: - 열거형 저장 값(data-model §2, §7 CHECK 목록과 같아야 한다)

@Test("FR-01 R-101: 할 일 상태와 반복의 저장 값")
func taskEnumRawValues() {
    #expect(TaskStatus.allCases.map(\.rawValue) == ["todo", "active", "done", "dropped"])
    #expect(Recurrence.allCases.map(\.rawValue) == ["none", "daily", "weekly"])
}

@Test("FR-02 R-115: 컨텍스트 중요도의 저장 값은 normal/high/critical")
func contextImpactRawValues() {
    #expect(ContextImpact.allCases.map(\.rawValue) == ["normal", "high", "critical"])
}

@Test("FR-07 R-108: 체크포인트 계기는 여덟 값을 모두 받는다")
func checkpointTriggerRawValues() {
    #expect(
        CheckpointTrigger.allCases.map(\.rawValue)
            == ["quantum", "switch", "skip", "urgent", "pause", "quit", "sleep", "day_end"])
    #expect(CheckpointTrigger(rawValue: "switch") == .switch)
    #expect(CheckpointTrigger(rawValue: "day_end") == .dayEnd)
    #expect(CheckpointTrigger(rawValue: "dayEnd") == nil)
}

@Test("FR-11 R-112: 행동 로그의 사용자 행동과 고른 규칙 이름")
func decisionLogRawValues() {
    #expect(UserAction.allCases.map(\.rawValue) == ["done", "skip", "switch"])
    #expect(SchedulerChoice.allCases.map(\.rawValue) == ["rotate_by_id_v0"])
    #expect(SchedulerChoice.rotateByIDV0.rawValue == "rotate_by_id_v0")
    #expect(UserAction(rawValue: "undo") == nil)
}

// MARK: - Weekday

@Test("FR-01 R-101: 요일은 1(일)~7(토)만 만들어진다", arguments: 1...7)
func weekdayAcceptsOneToSeven(value: Int) throws {
    #expect(try #require(Weekday(rawValue: value)).rawValue == value)
}

@Test("FR-01 R-101: 요일 범위 밖은 nil", arguments: [-1, 0, 8, 100])
func weekdayRejectsOutOfRange(value: Int) {
    #expect(Weekday(rawValue: value) == nil)
}

// MARK: - LocalDay

@Test(
    "FR-09 R-114: 지역 날짜는 YYYY-MM-DD 그레고리력 날짜만 받는다",
    arguments: [
        ("2026-11-02", 2026, 11, 2),
        ("2028-02-29", 2028, 2, 29),
        ("2000-02-29", 2000, 2, 29),
        ("2026-12-31", 2026, 12, 31),
        ("0001-01-01", 1, 1, 1),
        ("9999-12-31", 9999, 12, 31),
    ])
func localDayParsesValidText(text: String, year: Int, month: Int, day: Int) throws {
    let parsed = try #require(LocalDay(text: text))
    #expect(parsed.year == year)
    #expect(parsed.month == month)
    #expect(parsed.day == day)
    #expect(parsed.text == text)
}

@Test(
    "FR-09 R-114: 형식이나 달력 날짜가 틀린 지역 날짜는 nil",
    arguments: [
        "", "2026-2-01", "2026-02-1", "26-02-01", "2026/02/01", "2026-02-01 ", " 2026-02-01", "2026-02-01T00:00:00Z",
        "2026-00-10", "2026-13-01", "2026-01-00", "2026-01-32", "2026-02-29", "1900-02-29", "2026-04-31",
        "0000-01-01", "+026-01-01", "２０２６-01-01",
    ])
func localDayRejectsInvalidText(text: String) {
    #expect(LocalDay(text: text) == nil)
}

@Test("FR-09 R-114: 지역 날짜는 날짜 순서로 비교한다")
func localDayIsComparable() throws {
    let days = try ["2025-12-31", "2026-01-01", "2026-01-02", "2026-02-01", "2027-01-01"].map {
        try #require(LocalDay(text: $0))
    }
    #expect(days == days.sorted())
    #expect(days[0] < days[1])
    #expect(try #require(LocalDay(text: "2026-01-01")) == days[1])
}

@Test(
    "FR-09 R-114: 날짜 더하기는 월말·연말·윤년을 넘는다",
    arguments: [
        ("2026-01-31", 1, "2026-02-01"),
        ("2026-12-31", 1, "2027-01-01"),
        ("2028-02-28", 1, "2028-02-29"),
        ("2026-02-28", 1, "2026-03-01"),
        ("2026-03-01", -1, "2026-02-28"),
        ("2027-01-01", -1, "2026-12-31"),
        ("2026-11-02", 7, "2026-11-09"),
        ("2026-11-02", 0, "2026-11-02"),
        ("2026-11-02", -366, "2025-11-01"),
    ])
func localDayAddingDays(start: String, days: Int, expected: String) throws {
    let calendar = GregorianCalendar.make(timeZone: try #require(TimeZone(identifier: "Asia/Seoul")))
    let day = try #require(LocalDay(text: start))
    #expect(day.adding(days: days, calendar: calendar).text == expected)
}

@Test("FR-01 R-101: 지역 날짜의 요일은 Foundation 그레고리력 번호와 같다")
func localDayWeekdayMatchesFoundation() throws {
    let zone = try #require(TimeZone(identifier: "America/New_York"))
    let calendar = GregorianCalendar.make(timeZone: zone)
    #expect(try #require(LocalDay(text: "2026-11-02")).weekday(calendar: calendar).rawValue == 2)  // 월요일
    #expect(try #require(LocalDay(text: "2026-11-01")).weekday(calendar: calendar).rawValue == 1)  // 일요일
    #expect(try #require(LocalDay(text: "2026-11-07")).weekday(calendar: calendar).rawValue == 7)  // 토요일

    var day = try #require(LocalDay(text: "2027-12-25"))
    for _ in 0..<800 {
        let noon = try #require(
            calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)))
        #expect(day.weekday(calendar: calendar).rawValue == calendar.component(.weekday, from: noon))
        let next = try #require(calendar.date(byAdding: .day, value: 1, to: noon))
        let parts = calendar.dateComponents([.year, .month, .day], from: next)
        let expected = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        day = day.adding(days: 1, calendar: calendar)
        #expect(day.text == expected)
        if day.text != expected { break }
    }
}

// MARK: - DayStart

@Test(
    "FR-09 R-114: 하루 시작 시각은 HH:MM 24시간 두 자리만 받는다",
    arguments: [("06:00", 6, 0), ("00:00", 0, 0), ("23:59", 23, 59), ("02:30", 2, 30), ("07:05", 7, 5)])
func dayStartParsesValidText(text: String, hour: Int, minute: Int) throws {
    let parsed = try #require(DayStart(text: text))
    #expect(parsed.hour == hour)
    #expect(parsed.minute == minute)
    #expect(parsed.text == text)
}

@Test(
    "FR-09 R-114: 틀린 하루 시작 시각은 nil",
    arguments: [
        "", "6:00", "06:0", "24:00", "12:60", "06:00:00", "06-00", " 06:00", "06:00 ", "-1:00", "０６:00", "ab:cd",
    ])
func dayStartRejectsInvalidText(text: String) {
    #expect(DayStart(text: text) == nil)
}

// MARK: - TaskEdit

@Test("FR-01 R-101: 빈 고침 입력은 모든 칸을 그대로 둔다")
func emptyTaskEditKeepsEverything() {
    let edit = TaskEdit()
    #expect(edit.title == nil)
    #expect(edit.deadline == .keep)
    #expect(edit.estMin == .keep)
    #expect(edit.recurrence == nil)
    #expect(edit.weekday == nil)
}

@Test("FR-01 R-101: 고침 칸은 그대로·값·비우기를 구분한다")
func taskEditFieldDistinguishesCases() throws {
    let day = try #require(LocalDay(text: "2026-11-30"))
    let fields: [TaskEdit.Field<LocalDay>] = [.keep, .set(day), .clear]
    for (i, a) in fields.enumerated() {
        for (j, b) in fields.enumerated() {
            #expect((a == b) == (i == j))
        }
    }
    #expect(TaskEdit.Field<Int>.set(30) != .set(45))
    let edit = TaskEdit(
        title: "가짜 할 일 B", deadline: .clear, estMin: .set(30), recurrence: .weekly, weekday: Weekday(rawValue: 4))
    #expect(edit.deadline == .clear)
    #expect(edit.estMin == .set(30))
}

// MARK: - 값 검증(data-model §5.6)

@Test(
    "FR-01 R-101: 제목은 앞뒤 공백을 빼고 저장하고 비면 저장 안 함",
    arguments: [
        ("가짜 할 일 A", "가짜 할 일 A"),
        ("  가짜 할 일 A  ", "가짜 할 일 A"),
        ("\n\t가짜 할 일 A\n", "가짜 할 일 A"),
        ("가짜  할 일", "가짜  할 일"),
    ] as [(String, String?)])
func taskTitleIsTrimmed(raw: String, expected: String?) {
    #expect(MokaTask.normalizedTitle(raw) == expected)
}

@Test("FR-01 R-101: 공백뿐인 제목은 저장 안 함", arguments: ["", " ", "\n\t ", "\u{3000}"])
func blankTaskTitleIsRejected(raw: String) {
    #expect(MokaTask.normalizedTitle(raw) == nil)
}

@Test("FR-02 R-115: 컨텍스트 이름은 앞뒤 공백을 빼고 비면 저장 안 함")
func contextNameIsTrimmed() {
    #expect(MokaContext.normalizedName("  가짜 일정 A ") == "가짜 일정 A")
    #expect(MokaContext.normalizedName("   ") == nil)
    #expect(MokaContext.normalizedName("") == nil)
}

@Test(
    "FR-01 R-101: 예상 소요는 nil 또는 1 이상",
    arguments: [(nil, true), (1, true), (180, true), (0, false), (-5, false)] as [(Int?, Bool)])
func estimatedMinutesValidation(value: Int?, valid: Bool) {
    #expect(MokaTask.isValidEstMin(value) == valid)
}

@Test("FR-01 R-101: 요일은 매주일 때만 값이 있다")
func weekdayPairsWithWeekly() {
    let wednesday = Weekday(rawValue: 4)
    #expect(MokaTask.isValidWeekday(wednesday, recurrence: .weekly))
    #expect(!MokaTask.isValidWeekday(nil, recurrence: .weekly))
    #expect(!MokaTask.isValidWeekday(wednesday, recurrence: .daily))
    #expect(!MokaTask.isValidWeekday(wednesday, recurrence: .none))
    #expect(MokaTask.isValidWeekday(nil, recurrence: .daily))
    #expect(MokaTask.isValidWeekday(nil, recurrence: .none))
}

@Test("FR-07 R-108: 두 줄은 앞뒤 공백을 빼고 비면 빈 문자열")
func checkpointNotesAreTrimmed() {
    let notes = CheckpointNotes(doneNote: "  가짜 한 일 \n", nextNote: " \t ")
    #expect(notes.doneNote == "가짜 한 일")
    #expect(notes.nextNote == "")
    #expect(CheckpointNotes.empty == CheckpointNotes(doneNote: "", nextNote: ""))
    #expect(CheckpointNotes(doneNote: "\n", nextNote: "") == .empty)
}
