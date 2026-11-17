import Foundation
import MokaCore
import Testing

// spec 005 data-model §19: 이월 카드·날짜 고르기·접힌 노치의 값을 끼우는 글자(확정 시안 005 1~3·10-1번).

private let seoul = GregorianCalendar.make(timeZone: TimeZone(identifier: "Asia/Seoul")!)
private func day(_ text: String) -> LocalDay { LocalDay(text: text)! }

@Test(
    "FR-08 R-414: 카드 위 줄 까닭은 하다 만 할 일, 마감이 지났으면 지난 날수(D+N)",
    arguments: [
        (CarryCardReason.touched, "하다 만 할 일이에요"),
        (.overdue(days: 2), "마감이 지난 할 일이에요 · D+2"),
        (.overdue(days: 1), "마감이 지난 할 일이에요 · D+1"),
    ])
func carryReason(reason: CarryCardReason, expected: String) {
    #expect(CarryText.reason(reason) == expected)
}

@Test("FR-08 R-414: 남은 개수와 접힌 노치 글자는 지금 것을 포함한 수")
func carryCounts() {
    #expect(CarryText.left(3) == "남은 3개")
    #expect(CarryText.left(1) == "남은 1개")
    #expect(CarryText.collapsed(3) == "정할 일 3개")
}

@Test("FR-08 R-415: 날짜 고르기 안내는 지금 마감을 보이고, 마감이 없으면 뒷문장만(시안 밖, 사용자 결정 2026-11-17)")
func carryMoveNote() {
    #expect(
        CarryText.moveNote(deadline: day("2026-11-14"), calendar: seoul)
            == "지금 마감은 11월 14일(토)이에요. 고른 날이 새 마감이 되고, 오늘도 노치에 뜰 수 있어요.")
    #expect(CarryText.moveNote(deadline: nil, calendar: seoul) == "고른 날이 새 마감이 되고, 오늘도 노치에 뜰 수 있어요.")
}

@Test("FR-08 R-415: 확인 버튼은 고른 날을 적는다")
func carryMoveConfirm() {
    #expect(CarryText.moveConfirm(day("2026-11-19")) == "19일로 바꿀래요")
}

@Test(
    "FR-08 R-415: 빠른 날짜는 내일, 모레, 오늘 뒤 첫 월요일(오늘이 월요일이면 이레 뒤)",
    arguments: [
        ("2026-11-16", ["2026-11-17", "2026-11-18", "2026-11-23"]),  // 월
        ("2026-11-18", ["2026-11-19", "2026-11-20", "2026-11-23"]),  // 수
        ("2026-11-22", ["2026-11-23", "2026-11-24", "2026-11-23"]),  // 일
    ])
func carryQuickDays(today: String, expected: [String]) {
    #expect(CarryText.quickDays(after: day(today), calendar: seoul) == expected.map(day))
}

@Test("FR-08 R-414: 펼친 판 오른쪽 귀는 카드면 오늘 정하기, 날짜 고르기면 날짜 바꾸기")
func carryEarLabel() {
    #expect(NotchStatus.carryLabel(pickingDate: false) == "오늘 정하기")
    #expect(NotchStatus.carryLabel(pickingDate: true) == "날짜 바꾸기")
}

@Test("FR-08 R-415: 달력은 고른 날의 달을 보이고, 다음 달로 넘긴 뒤 날짜를 골라도 그 달에 남는다")
func carryMonthPageStaysOnPick() {
    var page = CarryMonthPage(selected: day("2026-11-17"), today: day("2026-11-16"))
    #expect(page.month == CalendarMonth(year: 2026, month: 11))
    #expect(!page.canGoBack, "내일이 든 달보다 앞으로는 가지 않는다")
    page.next()
    #expect(page.month == CalendarMonth(year: 2026, month: 12))
    #expect(page.canGoBack)
    page.pick(day("2026-12-03"))
    #expect(page.month == CalendarMonth(year: 2026, month: 12))
    page.pick(day("2026-11-18"))
    #expect(page.month == CalendarMonth(year: 2026, month: 11), "빠른 날짜가 다른 달이면 그 달로 간다")
    page.previous()
    #expect(page.month == CalendarMonth(year: 2026, month: 11), "내일이 든 달에서 앞으로 가지 않는다")
}
