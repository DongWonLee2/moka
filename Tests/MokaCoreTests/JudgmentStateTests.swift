import Foundation
import MokaCore
import Testing

private let today = Fake.day("2027-01-13")

private func context(_ id: ContextID, _ name: String, _ date: String, _ impact: ContextImpact) -> MokaContext {
    MokaContext(id: id, name: name, date: Fake.day(date), impact: impact)
}

private func checkpoint(_ id: Int64, task: TaskID, _ done: String, _ next: String) -> Checkpoint {
    Checkpoint(
        id: id, taskID: task, notes: Fake.notes(done, next), trigger: .quantum, elapsedMin: 10,
        createdAt: Fake.noon)
}

private let fullTask = Fake.task(1, deadline: Fake.day("2027-01-15"), estMin: 30, firstAction: "가짜 첫 행동")
private let fullContexts = [
    context(2, "가짜 시험 B", "2027-01-20", .critical),
    context(1, "가짜 시험 A", "2027-01-20", .normal),
    context(3, "가짜 발표", "2027-01-14", .high),
]
private let fullCheckpoints = [
    checkpoint(5, task: 1, "가짜 한 일", "가짜 다음"),
    checkpoint(7, task: 1, "", ""),
    checkpoint(6, task: 1, "", "가짜 다음 2"),
    checkpoint(9, task: 2, "다른 할 일", "다른 할 일"),
]

private let fullBytes =
    #"{"today":"2027-01-13 (수)","context":[{"name":"가짜 발표","date":"2027-01-14","impact":"꽤"},"#
    + #"{"name":"가짜 시험 A","date":"2027-01-20","impact":"조금"},{"name":"가짜 시험 B","date":"2027-01-20","impact":"아주"}],"#
    + #""task":{"title":"가짜 할 일 1","deadline":"2027-01-15","est_min":30,"first_action":"가짜 첫 행동"},"#
    + #""checkpoint":{"done":"","next":"가짜 다음 2"}}"#

private func build(
    _ task: MokaTask, contexts: [MokaContext] = [], checkpoints: [Checkpoint] = [], today: LocalDay = today
) -> JudgmentState {
    JudgmentState.build(task: task, contexts: contexts, checkpoints: checkpoints, today: today, calendar: Fake.seoul)
}

private func text(_ state: JudgmentState) -> String {
    String(decoding: state.bytes, as: UTF8.self)
}

@Suite struct JudgmentStateTests {
    @Test("FR-03 R-201: 판단 입력은 오늘·일정·할 일·체크포인트를 정한 순서의 정준 바이트로 만든다")
    func fullBytesInOrder() {
        #expect(text(build(fullTask, contexts: fullContexts, checkpoints: fullCheckpoints)) == fullBytes)
    }

    @Test("FR-03 R-201: 값이 없는 칸은 키를 빼고, 일정이 없으면 빈 배열")
    func omitsMissingValues() {
        #expect(text(build(Fake.task(2))) == #"{"today":"2027-01-13 (수)","context":[],"task":{"title":"가짜 할 일 2"}}"#)
    }

    @Test("FR-03 R-201 SC-202: 키 집합이 표와 정확히 같고 금지 필드가 없다")
    func keySetIsExact() throws {
        let object = try #require(
            JSONSerialization.jsonObject(
                with: Data(build(fullTask, contexts: fullContexts, checkpoints: fullCheckpoints).bytes))
                as? [String: Any])
        #expect(Set(object.keys) == ["today", "context", "task", "checkpoint"])
        let task = try #require(object["task"] as? [String: Any])
        #expect(Set(task.keys) == ["title", "deadline", "est_min", "first_action"])
        let contexts = try #require(object["context"] as? [[String: Any]])
        #expect(contexts.allSatisfy { Set($0.keys) == ["name", "date", "impact"] })
        let checkpoint = try #require(object["checkpoint"] as? [String: Any])
        #expect(Set(checkpoint.keys) == ["done", "next"])
    }

    @Test("FR-03 R-201 SC-202: 상태·미룬 횟수·연속 기록·반복·만든 시각·id는 판단 입력을 바꾸지 않는다")
    func forbiddenFieldsDoNotChangeBytes() {
        var other = fullTask
        other.status = .active
        other.skipCount = 3
        other.streak = 2
        other.recurrence = .daily
        other.cycleDay = today
        other.createdAt = Fake.noon
        let base = build(fullTask, contexts: fullContexts, checkpoints: fullCheckpoints)
        let changed = build(other, contexts: fullContexts, checkpoints: fullCheckpoints)
        #expect(base.bytes == changed.bytes)
        #expect(base.hash == changed.hash)
    }

    @Test("FR-03 R-201: 체크포인트는 그 할 일 것 가운데 두 줄 중 하나라도 적힌 id 최대의 것")
    func picksLatestWrittenCheckpoint() {
        let onlyEmpty = build(fullTask, checkpoints: [checkpoint(7, task: 1, "", ""), checkpoint(9, task: 2, "a", "b")])
        #expect(!text(onlyEmpty).contains("checkpoint"))
        let doneOnly = build(Fake.task(2), checkpoints: [checkpoint(3, task: 2, "가짜 한 일", "")])
        #expect(text(doneOnly).hasSuffix(#","checkpoint":{"done":"가짜 한 일","next":""}}"#))
    }

    @Test(
        "FR-03 R-201: 오늘은 YYYY-MM-DD와 요일 한 글자",
        arguments: [
            ("2027-01-10", "일"), ("2027-01-11", "월"), ("2027-01-12", "화"), ("2027-01-13", "수"),
            ("2027-01-14", "목"), ("2027-01-15", "금"), ("2027-01-16", "토"),
        ])
    func todayText(day: String, weekday: String) {
        let state = build(Fake.task(2), today: Fake.day(day))
        #expect(text(state).hasPrefix(#"{"today":"\#(day) (\#(weekday))","#))
        #expect(state.weekday == Fake.day(day).weekday(calendar: Fake.seoul))
    }

    @Test("FR-03 R-201: 문자열은 따옴표·역슬래시·제어 문자만 이스케이프하고 나머지는 UTF-8 그대로")
    func escapesStrings() {
        var task = Fake.task(2)
        task.title = "가짜 \"따옴표\" \\ 줄\n탭\t\u{01}끝"
        #expect(
            text(build(task))
                == #"{"today":"2027-01-13 (수)","context":[],"task":{"title":"가짜 \"따옴표\" \\ 줄\n탭\t\u0001끝"}}"#)
    }

    @Test("FR-03 R-201: 판단 입력 해시는 정준 바이트의 FNV-1a 64 소문자 16자리(golden)")
    func hashGolden() {
        #expect(build(fullTask, contexts: fullContexts, checkpoints: fullCheckpoints).hash == "5507ff40d96c342e")
        #expect(build(Fake.task(2)).hash == "247436edbc3b5d9b")
        var task = Fake.task(2)
        task.title = "가짜 \"따옴표\" \\ 줄\n탭\t\u{01}끝"
        #expect(build(task).hash == "f366f528777a6a83")
    }

    @Test("FR-03 R-201: FNV-1a 64 표준 시험값")
    func fnvVectors() {
        #expect(JudgmentState.fnv1a64([]) == "cbf29ce484222325")
        #expect(JudgmentState.fnv1a64(Array("a".utf8)) == "af63dc4c8601ec8c")
    }
}
