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

@Test(
    "R-102 #42: 지우기 확인 제목은 마지막 글자 받침에 맞춰 을/를",
    arguments: [
        ("보고서 1절 쓰기", "\"보고서 1절 쓰기\"를 지울까요?"),
        ("영단어 외우기 30개", "\"영단어 외우기 30개\"를 지울까요?"),
        ("장보기 목록", "\"장보기 목록\"을 지울까요?"),
        ("가짜 할 일 1", "\"가짜 할 일 1\"을 지울까요?"),
        ("가짜 할 일 2", "\"가짜 할 일 2\"를 지울까요?"),
        ("Report", "\"Report\"을(를) 지울까요?"),
    ])
func deleteTitle(title: String, expected: String) {
    #expect(TaskFormText.deleteTitle(title) == expected)
}

@Test("R-102 #42: 지우기 확인 본문은 도는 할 일이면 타이머가 멈춘다는 말이 앞에 붙는다")
func deleteMessage() {
    #expect(TaskFormText.deleteMessage(stopsTimer: false) == "지우면 노치에 다시 뜨지 않아요. 지금까지 남긴 기록은 그대로 둬요.")
    #expect(
        TaskFormText.deleteMessage(stopsTimer: true)
            == "지금 타이머가 도는 할 일이에요. 지우면 타이머가 멈추고 노치에 다시 뜨지 않아요. 지금까지 남긴 기록은 그대로 둬요.")
}

@Test("R-102 #42: 고치기 시트의 이어서 할 일 줄은 읽기만 하고 출처를 붙인다")
func firstActionNote() {
    #expect(TaskFormText.firstActionNote("31번부터") == "31번부터 · 멈출 때 적어 둔 줄이에요.")
}

@Test("FR-01 R-120: 여러 개 지우기 확인 제목은 개수")
func deleteManyTitle() {
    #expect(TaskFormText.deleteManyTitle(count: 3) == "할 일 3개를 지울까요?")
}

@Test("FR-01 R-120: 여러 개 지우기 안내는 도는 중인 할 일이 끼어 있으면 타이머가 멈춘다고 알린다")
func deleteManyMessage() {
    #expect(
        TaskFormText.deleteManyMessage(stopsTimer: false)
            == "지우면 노치에 다시 뜨지 않아요. 지금까지 남긴 기록은 그대로 둬요.")
    #expect(
        TaskFormText.deleteManyMessage(stopsTimer: true)
            == "지금 타이머가 도는 할 일이 들어 있어요. 지우면 타이머가 멈추고 노치에 다시 뜨지 않아요. 지금까지 남긴 기록은 그대로 둬요.")
}
