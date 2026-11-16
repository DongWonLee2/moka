import Foundation
import MokaCore
import Testing

// spec 005 data-model §9, spec US2. 서울 06:00 하루 시작, 주입한 시각만 쓴다. 가짜 할 일만 쓴다.

private func checkpoint(_ id: Int64, task: TaskID, at date: Date, trigger: CheckpointTrigger = .skip) -> Checkpoint {
    Checkpoint(id: id, taskID: task, notes: .empty, trigger: trigger, elapsedMin: 5, createdAt: date)
}

private func line(_ id: Int64, task: TaskID, _ action: UserAction, at date: Date) -> DecisionLogEntry {
    DecisionLogEntry(
        id: id, taskID: task, judgment: nil, modelSnapshot: nil,
        schedulerChoice: action.rawValue.hasPrefix("carry") ? .carryCardV1 : .weightedRotateV1, userAction: action,
        createdAt: date)
}

private func input(
    _ tasks: [MokaTask], checkpoints: [Checkpoint] = [], decisions: [DecisionLogEntry] = [], last: Date?,
    reverted: Set<TaskID> = [], now: Date, calendar: Calendar = Fake.seoul
) -> CarryJudgmentInput {
    CarryJudgmentInput(
        tasks: tasks, checkpoints: checkpoints, decisions: decisions, lastJudgedAt: last, revertedIDs: reverted,
        now: now, dayStart: Fake.sixAM, calendar: calendar)
}

/// 2027-01-13(수) 07:00에 판정했고, 다음 날 07:00에 다시 본다.
private let judged = Fake.at(2027, 1, 13, 7, 0)
private let nextMorning = Fake.at(2027, 1, 14, 7, 0)

@Suite struct CarryJudgmentNeedsRunTests {
    @Test("FR-08 R-412: 판정 기록이 없으면 돈다")
    func firstRun() {
        #expect(CarryJudgment.needsRun(lastJudgedAt: nil, now: judged, dayStart: Fake.sixAM, calendar: Fake.seoul))
    }

    @Test(
        "FR-08 R-412: 같은 하루면 돌지 않고, 하루 시작(06:00)부터 돈다(05:59는 아직 같은 하루)",
        arguments: [
            (Fake.at(2027, 1, 13, 23, 0), false), (Fake.at(2027, 1, 14, 5, 59), false),
            (Fake.at(2027, 1, 14, 6, 0), true), (Fake.at(2027, 1, 17, 9, 0), true),
        ])
    func boundary(now: Date, runs: Bool) {
        #expect(CarryJudgment.needsRun(lastJudgedAt: judged, now: now, dayStart: Fake.sixAM, calendar: Fake.seoul) == runs)
    }

    @Test("FR-08 R-412: 뉴욕 시간대에서도 그 시간대의 06:00이 경계다")
    func newYork() {
        let last = Fake.at(2027, 1, 13, 7, 0, calendar: Fake.newYork)
        let before = Fake.at(2027, 1, 14, 5, 59, calendar: Fake.newYork)
        let after = Fake.at(2027, 1, 14, 6, 0, calendar: Fake.newYork)
        #expect(!CarryJudgment.needsRun(lastJudgedAt: last, now: before, dayStart: Fake.sixAM, calendar: Fake.newYork))
        #expect(CarryJudgment.needsRun(lastJudgedAt: last, now: after, dayStart: Fake.sixAM, calendar: Fake.newYork))
    }
}

@Suite struct CarryJudgmentTargetTests {
    @Test("FR-08 R-412 US2-1: 손댄 A와 마감이 어제인 B만, 손대지 않은 C는 대상이 아니다")
    func scenario1() {
        let tasks = [
            Fake.task(1), Fake.task(2, deadline: Fake.day("2027-01-13")), Fake.task(3, deadline: Fake.day("2027-01-20")),
        ]
        let targets = CarryJudgment.targets(
            input(tasks, checkpoints: [checkpoint(1, task: 1, at: Fake.at(2027, 1, 13, 9, 0))], last: judged,
                now: nextMorning))
        #expect(targets == [1, 2])
    }

    @Test("FR-08 R-412: 마감이 오늘이면 지난 것이 아니다")
    func deadlineTodayIsNotOverdue() {
        let tasks = [Fake.task(1, deadline: Fake.day("2027-01-14"))]
        #expect(CarryJudgment.targets(input(tasks, last: judged, now: nextMorning)).isEmpty)
    }

    @Test("FR-08 R-412: 체크포인트는 계기와 상관없이 센다", arguments: CheckpointTrigger.allCases)
    func anyTrigger(trigger: CheckpointTrigger) {
        let targets = CarryJudgment.targets(
            input(
                [Fake.task(1)], checkpoints: [checkpoint(1, task: 1, at: Fake.at(2027, 1, 13, 9, 0), trigger: trigger)],
                last: judged, now: nextMorning))
        #expect(targets == [1])
    }

    @Test("FR-08 R-412: 이월 답이 아닌 로그 줄은 손댄 것, 이월 답 줄은 손댄 것이 아니다")
    func logLines() {
        let at = Fake.at(2027, 1, 13, 9, 0)
        let decisions = [
            line(1, task: 1, .done, at: at), line(2, task: 2, .carryToday, at: at), line(3, task: 3, .carryMove, at: at),
            line(4, task: 4, .carryDrop, at: at), line(5, task: 5, .switch, at: at),
        ]
        let targets = CarryJudgment.targets(
            input(Fake.todos(1...5), decisions: decisions, last: judged, now: nextMorning))
        #expect(targets == [1, 5])
    }

    @Test("FR-08 R-412: 지난 판정 전 줄은 세지 않는다")
    func beforeSinceIgnored() {
        let targets = CarryJudgment.targets(
            input(
                [Fake.task(1)], checkpoints: [checkpoint(1, task: 1, at: Fake.at(2027, 1, 13, 6, 59, 59))], last: judged,
                now: nextMorning))
        #expect(targets.isEmpty)
    }

    @Test("FR-08 R-412: 지난 판정과 같은 초의 체크포인트·로그 줄은 손댄 것으로 센다(초로 내려 비교)")
    func sameSecondCounts() {
        let last = judged.addingTimeInterval(0.7)
        let targets = CarryJudgment.targets(
            input(
                [Fake.task(1), Fake.task(2)], checkpoints: [checkpoint(1, task: 1, at: judged)],
                decisions: [line(1, task: 2, .skip, at: judged)], last: last, now: nextMorning))
        #expect(targets == [1, 2])
    }

    @Test("FR-08 R-412 US2-5: 날짜를 사흘 뒤로 바꾸고 손대지 않았으면 다음 날 대상이 아니다")
    func scenario5() {
        let moved = Fake.task(2, deadline: Fake.day("2027-01-16"))
        let decisions = [line(1, task: 2, .carryMove, at: Fake.at(2027, 1, 13, 7, 1))]
        #expect(CarryJudgment.targets(input([moved], decisions: decisions, last: judged, now: nextMorning)).isEmpty)
    }

    @Test("FR-08 R-412 US2-6a: 바꾼 마감 다음 날에는 마감이 지나 다시 대상이다")
    func scenario6a() {
        let moved = Fake.task(2, deadline: Fake.day("2027-01-16"))
        let last = Fake.at(2027, 1, 16, 7, 0)
        #expect(CarryJudgment.targets(input([moved], last: last, now: Fake.at(2027, 1, 17, 7, 0))) == [2])
    }

    @Test("FR-08 R-412 US2-6: 사흘 앱을 켜지 않아도 지난 판정 뒤 손댄 할 일이 대상이다")
    func scenario6() {
        let targets = CarryJudgment.targets(
            input(
                [Fake.task(1)], checkpoints: [checkpoint(1, task: 1, at: Fake.at(2027, 1, 13, 20, 0))], last: judged,
                now: Fake.at(2027, 1, 17, 7, 0)))
        #expect(targets == [1])
    }

    @Test("FR-08 R-412 R-417 US2-6b: 판정 때 진행 중인 할 일은 대상이다")
    func scenario6b() {
        let targets = CarryJudgment.targets(input([Fake.task(1, status: .active)], last: judged, now: nextMorning))
        #expect(targets == [1])
    }

    @Test("FR-08 R-412 US2-6d: 이번 시작에서 R-111이 되돌린 할 일은 대상이다")
    func scenario6d() {
        let targets = CarryJudgment.targets(
            input([Fake.task(1), Fake.task(2)], last: judged, reverted: [2], now: nextMorning))
        #expect(targets == [2])
    }

    @Test("FR-08 R-412 US2-9: 반복 할 일과 완료·버림은 대상이 아니다")
    func scenario9() {
        let at = Fake.at(2027, 1, 13, 9, 0)
        let tasks = [
            Fake.task(1, recurrence: .daily, cycleDay: Fake.day("2027-01-13")),
            Fake.task(2, status: .done, deadline: Fake.day("2027-01-10")),
            Fake.task(3, status: .dropped, deadline: Fake.day("2027-01-10")),
        ]
        let targets = CarryJudgment.targets(
            input(
                tasks, checkpoints: [checkpoint(1, task: 1, at: at)], decisions: [line(1, task: 2, .done, at: at)],
                last: judged, reverted: [1], now: nextMorning))
        #expect(targets.isEmpty)
    }

    @Test("FR-08 R-412: 처음 판정은 바로 앞 하루 시작부터 본다")
    func firstJudgmentWindow() {
        let tasks = Fake.todos(1...2)
        let checkpoints = [
            checkpoint(1, task: 1, at: Fake.at(2027, 1, 13, 6, 0)), checkpoint(2, task: 2, at: Fake.at(2027, 1, 13, 5, 59)),
        ]
        #expect(CarryJudgment.targets(input(tasks, checkpoints: checkpoints, last: nil, now: nextMorning)) == [1])
    }

    @Test("FR-08 R-412: 판정 쓰기가 실패해 시각이 남지 않으면 다음 판정이 이전 판정 시각부터 본다")
    func retryUsesPreviousSince() {
        let checkpoints = [checkpoint(1, task: 1, at: Fake.at(2027, 1, 13, 9, 0))]
        let first = CarryJudgment.targets(input([Fake.task(1)], checkpoints: checkpoints, last: judged, now: nextMorning))
        let retry = CarryJudgment.targets(
            input([Fake.task(1)], checkpoints: checkpoints, last: judged, now: nextMorning.addingTimeInterval(600)))
        #expect(first == [1])
        #expect(retry == first)
    }
}

@Suite struct CarryJudgmentMarkingTests {
    @Test("FR-08 R-412: 대상만 이월 답 대기로 표시하고, 이미 대기인 표시는 지우지 않는다")
    func marksTargetsKeepsExisting() {
        let tasks = [Fake.task(1), Fake.task(2, dueDecision: true), Fake.task(3)]
        let batch = CarryJudgment.marking([1], in: tasks)
        #expect(batch.updatedTasks == [Fake.task(1, dueDecision: true)])
        #expect(batch.newCheckpoints.isEmpty)
        #expect(batch.newDecisions.isEmpty)
    }

    @Test("FR-08 R-412: 같은 판정을 여러 번 돌려도 결과가 같다")
    func idempotent() throws {
        let repository = try InMemoryTaskRepository.seeded(2)
        try repository.apply(CarryJudgment.marking([1], in: try repository.tasks()))
        let once = try repository.tasks()
        try repository.apply(CarryJudgment.marking([1], in: once))
        #expect(try repository.tasks() == once)
        #expect(CarryJudgment.marking([1], in: once).updatedTasks.isEmpty)
    }

    @Test("FR-08 R-417: 진행 중 할 일은 상태를 그대로 두고 표시만 붙인다")
    func activeKeepsStatus() {
        let batch = CarryJudgment.marking([1], in: [Fake.task(1, status: .active)])
        #expect(batch.updatedTasks == [Fake.task(1, status: .active, dueDecision: true)])
    }
}
