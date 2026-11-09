import Foundation
import MokaCore
import Testing

// data-model §7·§8. 가짜 할 일·가짜 판단 결과만 쓴다.

private let questions = try! QuestionSet.bundled()
private let today = Fake.day("2027-01-13")
private let t0 = Fake.noon

/// 마감이 없고 미룬 횟수가 0이면 priority = urgency + 0.7.
private func score(_ taskID: TaskID, urgency: Double) -> TaskScore {
    TaskScore(
        taskID: taskID, questionVersion: "v1", provider: "fake", modelSnapshot: "가짜-모델-\(taskID)",
        urgency: urgency, impact: 1, concrete: 0.9, avoiding: 0.3, probsJSON: #"{"concrete":{"noul":0.9}}"#,
        stateHash: "00000000000000a\(taskID)", scoredAt: t0)
}

/// spec US1의 A(1.2)·B(0.9)·C(1.5). id는 A 1, B 2, C 3.
private let abc: [TaskID: TaskScore] = [
    1: score(1, urgency: 0.5), 2: score(2, urgency: 0.2), 3: score(3, urgency: 0.8),
]

private func input(_ tasks: [MokaTask], _ usable: [TaskID: TaskScore]? = abc, now: Date = t0) -> SessionInput {
    var input = Fake.input(tasks, now: now)
    input.scoring = usable.map { SessionScoring(usable: $0, questions: questions, today: today) }
    return input
}

private func applying(_ batch: StoreBatch, to tasks: [MokaTask]) -> [MokaTask] {
    tasks.map { task in batch.updatedTasks.first { $0.id == task.id } ?? task }
}

/// 초안에서 시작하고 1분 뒤 `button`을 누른 다음, 버튼 처리 뒤 목록으로 다시 고른다.
private func pressed(
    _ session: NotchSession, _ tasks: [MokaTask], usable: [TaskID: TaskScore]? = abc,
    _ button: (NotchSession, SessionInput) throws(SessionError) -> SessionStep
) throws -> (session: NotchSession, tasks: [MokaTask], step: SessionStep) {
    let start = try session.start(input(tasks, usable))
    let running = applying(start.batch, to: tasks)
    let step = try button(start.session, input(running, usable, now: t0 + 60))
    let after = applying(step.batch, to: running)
    return (step.session.picked(input(after, usable, now: t0 + 60)), after, step)
}

private func switching(_ session: NotchSession, _ input: SessionInput) throws(SessionError) -> SessionStep {
    try session.switchTask(.empty, input)
}

@Suite struct NotchSessionPriorityTests {
    @Test("FR-05 R-209 SC-203: 빈 상태에서 고르면 노치 순서 1위(spec US1-2)")
    func pickTop() {
        #expect(NotchSession.initial.picked(input(Fake.todos(1...3))).taskID == 3)
    }

    @Test("FR-05 R-209 SC-203: 바꾸기 뒤에는 다음 순위, 끝이면 1위(spec US1-3)")
    func switchRotates() throws {
        var tasks = Fake.todos(1...3)
        var session = NotchSession.initial.picked(input(tasks))
        var shown = [try #require(session.taskID)]
        for _ in 0..<3 {
            (session, tasks, _) = try pressed(session, tasks, switching)
            shown.append(try #require(session.taskID))
        }
        #expect(shown == [3, 1, 2, 3])
    }

    @Test("FR-05 R-209 SC-203: 미루기 뒤에는 버튼 처리 뒤 다시 계산한 순서에서 다음(spec US1-4)")
    func skipUsesRecomputedOrder() throws {
        // C 뒤 바꾸기로 A가 떠 있다. A를 미루면 A는 2.0이 되어 A, C, B 순이므로 C.
        let tasks = Fake.todos(1...3)
        let onA = NotchSession(timer: .empty(draft: nil), taskID: nil, previousTaskID: 3, run: nil).picked(
            input(tasks))
        #expect(onA.taskID == 1)
        let (next, after, _) = try pressed(onA, tasks) { (session, input) throws(SessionError) in
            try session.skip(.empty, input)
        }
        #expect(after.first { $0.id == 1 }?.skipCount == 1)
        #expect(next.taskID == 3)
    }

    @Test("FR-05 R-209 SC-203: 완료 뒤에는 남은 할 일 가운데 1위(spec US1-5)")
    func completePicksTop() throws {
        let tasks = Fake.todos(1...3)
        let onB = NotchSession(timer: .empty(draft: nil), taskID: nil, previousTaskID: 1, run: nil).picked(
            input(tasks))
        #expect(onB.taskID == 2)
        let (next, _, _) = try pressed(onB, tasks) { (session, input) throws(SessionError) in
            try session.complete(nil, input)
        }
        #expect(next.taskID == 3)
    }

    @Test("FR-05 R-209: 커서의 할 일을 버렸으면 1위를 고른다(spec 002의 그다음 큰 id가 아님)")
    func droppedCursorPicksTop() {
        let tasks = [Fake.task(1), Fake.task(2, status: .dropped), Fake.task(3)]
        let session = NotchSession(timer: .empty(draft: nil), taskID: nil, previousTaskID: 2, run: nil)
        #expect(session.picked(Fake.input(tasks)).taskID == 1)
    }

    @Test("FR-05 R-209: 키가 없으면(scoring nil) 마감 순으로 고른다")
    func keylessPicksByDeadline() {
        let tasks = [Fake.task(1), Fake.task(2, deadline: Fake.day("2027-01-20")), Fake.task(3)]
        #expect(NotchSession.initial.picked(Fake.input(tasks)).taskID == 2)
        let after2 = NotchSession(timer: .empty(draft: nil), taskID: nil, previousTaskID: 2, run: nil)
        #expect(after2.picked(Fake.input(tasks)).taskID == 1)
    }

    @Test("FR-05 R-209: 초안·도는 중·시간 끝은 판단 결과가 바뀌어도 그대로")
    func draftAndRunningKeepTask() throws {
        let tasks = Fake.todos(1...3)
        let flipped: [TaskID: TaskScore] = [2: score(2, urgency: 1)]
        let drafted = NotchSession.initial.picked(input(tasks))
        #expect(drafted.taskID == 3)
        #expect(drafted.picked(input(tasks, flipped)) == drafted)
        let start = try drafted.start(input(tasks))
        let running = applying(start.batch, to: tasks)
        #expect(start.session.picked(input(running, flipped)) == start.session)
        let expired = input(running, flipped, now: t0 + 26 * 60)
        #expect(start.session.picked(expired) == start.session)
    }

    @Test("FR-01 R-209: 다음 표시는 초안이면 그 할 일, 도는 중이면 같은 노치 순서의 1위")
    func nextMarkFollowsOrder() throws {
        let tasks = Fake.todos(1...3)
        let drafted = NotchSession.initial.picked(input(tasks)).chosenDraft(2, input(tasks))
        #expect(drafted.nextMark(input(tasks)) == 2)
        let start = try drafted.start(input(tasks))
        let running = applying(start.batch, to: tasks)
        #expect(start.session.nextMark(input(running)) == 3)
        #expect(start.session.nextMark(input(running, [1: score(1, urgency: 1)])) == 1)
        #expect(start.session.nextMark(input(running, nil)) == 1)
    }

    @Test("FR-11 R-212: 점수 있는 할 일의 로그 줄은 저장된 판단 결과와 응답 모델 이름, priority_rotate_v0")
    func logLineWithScore() throws {
        let tasks = Fake.todos(1...3)
        let (_, _, step) = try pressed(NotchSession.initial.picked(input(tasks)), tasks) {
            (session, input) throws(SessionError) in try session.complete(nil, input)
        }
        let stored = try #require(abc[3])
        #expect(
            step.batch.newDecisions == [
                NewDecisionLogEntry(
                    taskID: 3,
                    judgment: Judgment(
                        provider: "fake", questionVersion: "v1", probsJSON: stored.probsJSON,
                        stateHash: "00000000000000a3"),
                    modelSnapshot: "가짜-모델-3", schedulerChoice: .priorityRotateV0, userAction: .done,
                    createdAt: t0 + 60)
            ])
    }

    @Test("FR-11 R-212: 점수 없는 할 일의 로그 줄은 공급자 fallback만, 나머지와 model_snapshot은 비움")
    func logLineWithoutScore() throws {
        let tasks = Fake.todos(1...3)
        let fallback = Judgment(provider: "fallback", questionVersion: nil, probsJSON: nil, stateHash: nil)
        for usable in [[:], nil] as [[TaskID: TaskScore]?] {
            let (_, _, step) = try pressed(NotchSession.initial.picked(input(tasks, usable)), tasks, usable: usable) {
                (session, input) throws(SessionError) in try session.skip(.empty, input)
            }
            #expect(
                step.batch.newDecisions == [
                    NewDecisionLogEntry(
                        taskID: 1, judgment: fallback, modelSnapshot: nil, schedulerChoice: .priorityRotateV0,
                        userAction: .skip, createdAt: t0 + 60)
                ])
        }
    }

    @Test("FR-11 R-212: 점수가 섞여도 버튼을 누른 할 일의 판단 결과만 남는다")
    func logLineUsesPressedTask() throws {
        let tasks = Fake.todos(1...3)
        let only2: [TaskID: TaskScore] = [2: score(2, urgency: 0.2)]
        let drafted = NotchSession.initial.picked(input(tasks, only2)).chosenDraft(1, input(tasks, only2))
        let (_, _, step) = try pressed(drafted, tasks, usable: only2, switching)
        let line = try #require(step.batch.newDecisions.first)
        #expect(line.taskID == 1)
        #expect(line.judgment?.provider == "fallback")
        #expect(line.modelSnapshot == nil)
        #expect(line.schedulerChoice.rawValue == "priority_rotate_v0")
    }
}
