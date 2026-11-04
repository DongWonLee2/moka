import Foundation
import MokaCore
import Testing

/// 마감 달력 칸 계산(R-101 "날짜 고르기로만"). 주는 일요일 시작이다(`Weekday` 1 = 일).
@Test(
    "R-101: 달 칸은 첫 요일만큼 앞을 비우고 그 달 날짜를 채운다",
    arguments: [
        (2026, 11, 0, 30),  // 1일 일요일
        (2027, 1, 5, 31),  // 1일 금요일
        (2026, 2, 0, 28),  // 1일 일요일, 평년
        (2028, 2, 2, 29),  // 1일 화요일, 윤년
        (2100, 2, 1, 28),  // 100으로 나뉘어 평년
    ])
func monthCells(year: Int, month: Int, blanks: Int, days: Int) {
    let cells = CalendarMonth(year: year, month: month).cells(calendar: Fake.seoul)
    #expect(cells.prefix(blanks).allSatisfy { $0 == nil })
    #expect(cells.count == blanks + days)
    #expect(cells[blanks]?.text == String(format: "%04d-%02d-01", year, month))
    #expect(cells.last??.day == days)
}

@Test("R-101: 날짜가 든 달에서 시작하고 앞뒤 달로 넘긴다(해 넘김 포함)")
func monthNavigation() throws {
    let start = CalendarMonth(containing: try #require(LocalDay(text: "2026-12-31")))
    #expect(start == CalendarMonth(year: 2026, month: 12))
    #expect(start.adding(months: 1) == CalendarMonth(year: 2027, month: 1))
    #expect(start.adding(months: -12) == CalendarMonth(year: 2025, month: 12))
    #expect(CalendarMonth(year: 2026, month: 1).adding(months: -1) == CalendarMonth(year: 2025, month: 12))
    #expect(CalendarMonth(year: 2026, month: 1).adding(months: 25) == CalendarMonth(year: 2028, month: 2))
}
