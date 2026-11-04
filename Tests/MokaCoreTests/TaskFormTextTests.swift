import Foundation
import MokaCore
import Testing

/// 할 일 시트 문구와 칸 해석(R-101, 시안 8번, #42 원칙).
@Test("R-101 #42: 제목이 비거나 공백뿐이면 저장 이유는 제목을 넣어 주세요.", arguments: ["", "   "])
func titleIssueWhenBlank(title: String) {
    #expect(TaskFormText.titleIssue(title) == "제목을 넣어 주세요.")
}

@Test("R-101 #42: 제목이 있으면 이유 없음")
func titleIssueNoneWhenFilled() {
    #expect(TaskFormText.titleIssue(" 가짜 할 일 ") == nil)
}

@Test("R-101 #42: 예상 소요는 비워도 되고 1 이상 정수만 받는다", arguments: [("", nil), ("40", 40), ("1", 1)] as [(String, Int?)])
func estMinAccepted(text: String, minutes: Int?) {
    #expect(TaskFormText.estMinIssue(text) == nil)
    #expect(TaskFormText.estMin(text) == minutes)
}

@Test("R-101 #42: 예상 소요가 1 이상 정수가 아니면 1분 이상으로 넣어 주세요.", arguments: ["0", "-1", "abc", "4.5", " 40"])
func estMinRejected(text: String) {
    #expect(TaskFormText.estMinIssue(text) == "1분 이상으로 넣어 주세요.")
    #expect(TaskFormText.estMin(text) == nil)
}

@Test(
    "R-101: 마감 날짜는 날짜 고르기의 Date와 오가도 같다(일광절약시간 바뀌는 날 포함)",
    arguments: ["2026-01-01", "2026-03-08", "2026-11-01", "2026-11-11", "2027-03-14"])
func localDayRoundTripsThroughDate(text: String) throws {
    let calendar = GregorianCalendar.make(timeZone: try #require(TimeZone(identifier: "America/New_York")))
    let day = try #require(LocalDay(text: text))
    #expect(LocalDay(date: day.date(calendar: calendar), calendar: calendar) == day)
}

@Test("R-101 #42: 마감 버튼은 없으면 마감 없음, 있으면 년 월 일(2026-11-04 사용자 결정)")
func deadlineLabel() throws {
    #expect(TaskFormText.deadlineLabel(nil) == "마감 없음")
    #expect(TaskFormText.deadlineLabel(try #require(LocalDay(text: "2026-11-11"))) == "2026년 11월 11일")
}
