import Foundation
import MokaCore
import Testing

private let questions = try! QuestionSet.bundled()
private let today = Fake.day("2027-01-13")

private func judged(_ taskID: TaskID = 1, impact: Double = 0.5, version: String = "v1") -> TaskScore {
    TaskScore(
        taskID: taskID, questionVersion: version, provider: "fake", modelSnapshot: "jev-1.13.0", urgency: 0.5,
        impact: impact, concrete: 0.9, avoiding: 0.3, probsJSON: "{}", stateHash: "0123456789abcdef",
        scoredAt: Fake.noon)
}

private func reason(
    _ task: MokaTask, usable: [TaskID: TaskScore] = [:], set: QuestionSet = questions, on day: LocalDay = today,
    calendar: Calendar = Fake.seoul
) -> ReasonLine {
    ReasonLine.make(task: task, usable: usable, questions: set, today: day, calendar: calendar)
}

@Suite struct ReasonLineDeadlineTests {
    @Test("FR-04 R-302: 마감이 없으면 none, 오늘이면 today, 뒤면 left, 앞이면 overdue다")
    func fourDistances() {
        #expect(reason(Fake.task(1)).deadline == .none)
        #expect(reason(Fake.task(1, deadline: Fake.day("2027-01-13"))).deadline == .today)
        #expect(reason(Fake.task(1, deadline: Fake.day("2027-01-16"))).deadline == .left(3))
        #expect(reason(Fake.task(1, deadline: Fake.day("2027-01-11"))).deadline == .overdue(2))
    }

    @Test("FR-04 R-302: 날 수는 달과 해를 넘어서도 달력 날짜 차다")
    func acrossMonthAndYear() {
        #expect(reason(Fake.task(1, deadline: Fake.day("2027-03-01")), on: Fake.day("2027-02-28")).deadline == .left(1))
        #expect(
            reason(Fake.task(1, deadline: Fake.day("2026-12-31")), on: Fake.day("2027-01-01")).deadline == .overdue(1))
    }

    @Test("FR-04 R-302: 오늘은 하루 시작 시각 경계를 따른다(05:59는 전날, 06:00은 그날)")
    func dayStartBoundary() {
        let task = Fake.task(1, deadline: Fake.day("2027-01-13"))
        let before = DayBoundary.day(
            containing: Fake.at(2027, 1, 14, 5, 59, 59), dayStart: Fake.sixAM, calendar: Fake.seoul)
        let after = DayBoundary.day(containing: Fake.at(2027, 1, 14, 6, 0), dayStart: Fake.sixAM, calendar: Fake.seoul)
        #expect(reason(task, on: before).deadline == .today)
        #expect(reason(task, on: after).deadline == .overdue(1))
    }

    @Test(
        "FR-04 R-302: 일광절약시간 전환일(23시간·25시간인 날)을 끼어도 날 수는 날짜 차다(뉴욕)",
        arguments: [
            ("2027-03-13", "2027-03-15", DeadlineDistance.left(2)),
            ("2027-03-15", "2027-03-13", .overdue(2)),
            ("2027-03-14", "2027-03-15", .left(1)),
            ("2027-11-06", "2027-11-08", .left(2)),
            ("2027-11-08", "2027-11-06", .overdue(2)),
            ("2027-11-07", "2027-11-07", .today),
        ])
    func daylightSavingNewYork(todayText: String, deadlineText: String, expected: DeadlineDistance) {
        let day = DayBoundary.day(
            containing: Fake.at(
                Fake.day(todayText).year, Fake.day(todayText).month, Fake.day(todayText).day, 12, 0,
                calendar: Fake.newYork),
            dayStart: Fake.sixAM, calendar: Fake.newYork)
        #expect(day == Fake.day(todayText))
        let task = Fake.task(1, deadline: Fake.day(deadlineText))
        #expect(reason(task, on: day, calendar: Fake.newYork).deadline == expected)
    }
}

@Suite struct ReasonLineImpactTests {
    @Test(
        "FR-04 R-303: 중요도는 impact에 (옵션 수 - 1)을 곱해 0.5에서 올림한 옵션 번호 0·1·2를 낮음·보통·높음으로 보인다",
        arguments: [
            (0.0, "낮음"), (0.24, "낮음"), (0.25, "보통"), (0.5, "보통"), (0.74, "보통"), (0.75, "높음"), (1.0, "높음"),
        ])
    func roundingBoundaries(impact: Double, expected: String) {
        #expect(reason(Fake.task(1), usable: [1: judged(impact: impact)]).impact == expected)
    }

    @Test("FR-04 R-303: 저장소 값이 0~1 밖이어도 끝 옵션에 머문다")
    func outOfRange() {
        #expect(reason(Fake.task(1), usable: [1: judged(impact: -0.2)]).impact == "낮음")
        #expect(reason(Fake.task(1), usable: [1: judged(impact: 1.3)]).impact == "높음")
    }

    @Test("FR-04 R-303: 화면 말은 질문 파일 impact 옵션 말과 따로다")
    func wordsNotFromQuestionFile() throws {
        let renamed = try QuestionSet(
            json: questionsJSON { root in
                editQuestions(&root) {
                    $0["impact"] = ["type": "score", "instructions": "가짜", "criteria": ["가", "나", "다"]]
                }
            })
        #expect(reason(Fake.task(1), usable: [1: judged(impact: 0.5)], set: renamed).impact == "보통")
    }

    @Test(
        "FR-04 R-303: impact 옵션 수가 3이 아닌 질문 파일이면 중요도가 없다",
        arguments: [["가", "나"], ["가", "나", "다", "라", "마"]])
    func notThreeOptions(criteria: [String]) throws {
        let set = try QuestionSet(
            json: questionsJSON { root in
                editQuestions(&root) {
                    $0["impact"] = ["type": "score", "instructions": "가짜", "criteria": criteria]
                }
            })
        #expect(reason(Fake.task(1), usable: [1: judged(impact: 0.5)], set: set).impact == nil)
    }

    @Test("FR-04 R-303 SC-302: 키가 없어 쓰는 판단 결과가 비면 중요도가 없다")
    func noKey() {
        let usable = ScoreRules.usable(scores: [1: judged()], hasKey: false, questionVersion: "v1", provider: "fake")
        #expect(reason(Fake.task(1), usable: usable).impact == nil)
    }

    @Test("FR-04 R-303 SC-302: 그 할 일의 판단 결과가 없으면 중요도가 없다(다른 할 일 결과는 쓰지 않는다)")
    func noScore() {
        let usable = ScoreRules.usable(scores: [2: judged(2)], hasKey: true, questionVersion: "v1", provider: "fake")
        #expect(reason(Fake.task(1), usable: usable).impact == nil)
    }

    @Test("FR-04 R-303 SC-302: 질문 버전이 다른 판단 결과면 중요도가 없다")
    func otherVersion() {
        let usable = ScoreRules.usable(
            scores: [1: judged(version: "v0")], hasKey: true, questionVersion: "v1", provider: "fake")
        #expect(reason(Fake.task(1), usable: usable).impact == nil)
    }
}

@Suite struct ReasonLineSkipTests {
    @Test("FR-04 R-304: 미룬 횟수는 할 일의 skip_count 그대로이고 0도 담는다")
    func skipCount() {
        #expect(reason(Fake.task(1)).skipCount == 0)
        #expect(reason(Fake.task(1, skipCount: 2)).skipCount == 2)
    }
}

@Suite struct ReasonTextTests {
    @Test(
        "FR-04 R-302 R-303 R-304: 한 줄은 남은 날 · 중요도 · 미룬 횟수다",
        arguments: [
            (DeadlineDistance.left(3), "보통", 2, "D-3 · 중요도 보통 · 미룬 2번"),
            (.today, "높음", 0, "D-day · 중요도 높음 · 미룬 0번"),
            (.overdue(2), "낮음", 1, "D+2 · 중요도 낮음 · 미룬 1번"),
            (.none, "보통", 0, "마감 없음 · 중요도 보통 · 미룬 0번"),
        ])
    func line(deadline: DeadlineDistance, impact: String, skipCount: Int, expected: String) {
        #expect(ReasonText.line(ReasonLine(deadline: deadline, impact: impact, skipCount: skipCount)) == expected)
    }

    @Test("FR-04 R-303 SC-302: 중요도가 없으면 중요도 칸과 그 구분자를 뺀다")
    func lineWithoutImpact() {
        #expect(ReasonText.line(ReasonLine(deadline: .left(3), impact: nil, skipCount: 0)) == "D-3 · 미룬 0번")
        #expect(ReasonText.line(ReasonLine(deadline: .none, impact: nil, skipCount: 4)) == "마감 없음 · 미룬 4번")
    }

    @Test("FR-04 R-302 R-303 R-304 SC-301: 할 일과 판단 결과에서 노치에 보일 한 줄을 만든다")
    func endToEnd() {
        let task = Fake.task(1, deadline: Fake.day("2027-01-16"), skipCount: 2)
        #expect(ReasonText.line(reason(task, usable: [1: judged(impact: 0.6)])) == "D-3 · 중요도 보통 · 미룬 2번")
        #expect(ReasonText.line(reason(task)) == "D-3 · 미룬 2번")
    }

    @Test(
        "R-705: 마감 칸 표기는 도움말이 인용하는 화면 글자다",
        arguments: [
            (DeadlineDistance.none, "마감 없음"), (.today, "D-day"), (.left(3), "D-3"), (.overdue(2), "D+2"),
        ])
    func deadlineTextQuotedByHelp(distance: DeadlineDistance, expected: String) {
        #expect(ReasonText.deadline(distance) == expected)
    }
}
