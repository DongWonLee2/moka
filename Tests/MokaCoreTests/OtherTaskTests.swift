import Foundation
import MokaCore
import Testing

/// 시작 전 화면 "다른 할 일" 목록(R-104, 2026-11-04 사용자 결정 C안). 2027-01-13 수요일 기준.
private let today = Fake.day("2027-01-13")

@Test("FR-05 R-104: 다른 할 일 목록은 지금 할 일을 뺀 대기 할 일을 급한 순(지난 마감 → 가까운 마감 → 마감 없음은 만든 순)으로")
func otherTaskRowsOrder() {
    let tasks = [
        Fake.task(1),
        Fake.task(2, deadline: Fake.day("2027-01-20")),
        Fake.task(3, deadline: Fake.day("2027-01-10")),
        Fake.task(4, recurrence: .daily, cycleDay: today),
        Fake.task(5, deadline: Fake.day("2027-01-13")),
        Fake.task(6, status: .done, deadline: Fake.day("2027-01-11")),
        Fake.task(7, status: .dropped),
        Fake.task(8, status: .active),
    ]
    #expect(OtherTaskList.rows(tasks, current: 5, today: today, calendar: Fake.seoul).map(\.id) == [3, 2, 1, 4])
}

@Test(
    "FR-05 R-104 #42: 다른 할 일 줄 보조 글자와 강조",
    arguments: [
        ("2027-01-12", "마감 지남", OtherTaskText.Tone.overdue),
        ("2027-01-13", "오늘 마감", .soon),
        ("2027-01-14", "내일 마감", .soon),
        ("2027-01-20", "1월 20일", .plain),
    ])
func otherTaskDeadlineNote(deadline: String, text: String, tone: OtherTaskText.Tone) {
    let note = OtherTaskText.note(Fake.task(1, deadline: Fake.day(deadline)), today: today, calendar: Fake.seoul)
    #expect(note.text == text)
    #expect(note.tone == tone)
}

@Test("FR-05 R-104 #42: 마감 없는 할 일은 반복이면 매일·매주 요일, 아니면 비움")
func otherTaskRecurrenceNote() {
    let daily = OtherTaskText.note(
        Fake.task(1, recurrence: .daily, cycleDay: today), today: today, calendar: Fake.seoul)
    let weekly = OtherTaskText.note(
        Fake.task(2, recurrence: .weekly, weekday: Fake.weekday(4), cycleDay: today), today: today,
        calendar: Fake.seoul)
    let plain = OtherTaskText.note(Fake.task(3), today: today, calendar: Fake.seoul)
    #expect(daily.text == "매일")
    #expect(weekly.text == "매주 수요일")
    #expect(plain.text == "")
    #expect([daily.tone, weekly.tone, plain.tone] == [.plain, .plain, .plain])
}
