import Foundation
import MokaCore
import Testing

// MARK: - 재시작 복구 LaunchRecovery(data-model §5.2)

@Suite struct LaunchRecoveryTests {
    @Test("FR-07 R-111: 앱 시작 때 진행 중인 할 일은 모두 대기로 되돌리고 바뀐 것만 돌려준다")
    func revertsActiveOnly() {
        let tasks = [
            Fake.task(1, status: .active, firstAction: "가짜 첫 행동"), Fake.task(2), Fake.task(3, status: .done),
            Fake.task(4, status: .active, recurrence: .daily, cycleDay: Fake.day("2027-01-13"), streak: 3),
            Fake.task(5, status: .dropped),
        ]
        let reverted = LaunchRecovery.revert(tasks)
        var first = tasks[0]
        first.status = .todo
        var fourth = tasks[3]
        fourth.status = .todo
        #expect(reverted == [first, fourth])
    }

    @Test("FR-07 R-111: 진행 중인 할 일이 없으면 빈 목록")
    func nothingToRevert() {
        #expect(LaunchRecovery.revert([Fake.task(1), Fake.task(2, status: .done)]).isEmpty)
        #expect(LaunchRecovery.revert([]).isEmpty)
    }
}

// MARK: - 종료·잠자기 체크포인트 lifecycleCheckpoint(data-model §4.2)

@Suite struct LifecycleCheckpointTests {
    private func runningSession(startedAt: Date, quantumMin: Int = 25) throws -> (NotchSession, [MokaTask]) {
        let tasks = [Fake.task(1), Fake.task(2)]
        let drafted = NotchSession.initial.picked(Fake.input(tasks, now: startedAt))
        let step = try drafted.start(Fake.input(tasks, now: startedAt))
        return (step.session, step.batch.updatedTasks + [tasks[1]])
    }

    @Test(
        "FR-07 R-110: 도는 중 잠자기·종료는 빈 두 줄과 경과 분만 담은 체크포인트 하나를 남긴다",
        arguments: [CheckpointTrigger.sleep, .quit])
    func runningLeavesCheckpoint(trigger: CheckpointTrigger) throws {
        let (session, tasks) = try runningSession(startedAt: Fake.noon)
        let now = Fake.noon.addingTimeInterval(7 * 60 + 59)
        let batch = try #require(session.lifecycleCheckpoint(trigger, Fake.input(tasks, now: now)))
        #expect(batch.updatedTasks.isEmpty)
        #expect(batch.newDecisions.isEmpty)
        #expect(
            batch.newCheckpoints == [
                NewCheckpoint(taskID: 1, notes: .empty, trigger: trigger, elapsedMin: 7, createdAt: now)
            ])
    }

    @Test("FR-07 R-110: 체크포인트를 남겨도 할 일 상태와 타이머는 그대로다")
    func sessionAndTaskUnchanged() throws {
        let (session, tasks) = try runningSession(startedAt: Fake.noon)
        let before = session
        _ = session.lifecycleCheckpoint(.sleep, Fake.input(tasks, now: Fake.noon + 60))
        #expect(session == before)
        #expect(tasks[0].status == .active)
    }

    @Test("FR-07 R-110 #173: 시간 끝 화면에서 종료하면 빈 두 줄과 고른 분을 담은 quit 체크포인트 하나를 남긴다")
    func expiredQuitLeavesCheckpoint() throws {
        let (session, tasks) = try runningSession(startedAt: Fake.noon)
        let now = Fake.noon.addingTimeInterval(40 * 60)
        let batch = try #require(session.lifecycleCheckpoint(.quit, Fake.input(tasks, now: now)))
        #expect(batch.updatedTasks.isEmpty)
        #expect(batch.newDecisions.isEmpty)
        #expect(
            batch.newCheckpoints == [
                NewCheckpoint(taskID: 1, notes: .empty, trigger: .quit, elapsedMin: 25, createdAt: now)
            ])
        #expect(session.lifecycleRefund(.quit, Fake.input(tasks, now: now)) == nil, "시간 끝은 돌려줄 쓴 시간이 없다")
    }

    @Test("spec 005 R-412 #173: 시간 끝에서 종료하고 같은 하루에 다시 켜도 다음 날 판정에서 손댄 할 일로 센다")
    func expiredQuitCountsAsTouchedNextDay() throws {
        let (session, tasks) = try runningSession(startedAt: Fake.noon)
        let quitAt = Fake.noon.addingTimeInterval(40 * 60)
        let batch = try #require(session.lifecycleCheckpoint(.quit, Fake.input(tasks, now: quitAt)))
        let saved = batch.newCheckpoints.enumerated().map { index, new in
            Checkpoint(
                id: Int64(index + 1), taskID: new.taskID, notes: new.notes, trigger: new.trigger,
                elapsedMin: new.elapsedMin, createdAt: new.createdAt)
        }
        let relaunched = tasks.map { task in
            LaunchRecovery.revert([task]).first ?? task
        }
        let judgment = CarryJudgmentInput(
            tasks: relaunched, checkpoints: saved, decisions: [], lastJudgedAt: Fake.at(2027, 1, 13, 7, 0),
            revertedIDs: [], now: Fake.at(2027, 1, 14, 7, 0), dayStart: Fake.sixAM, calendar: Fake.seoul)
        #expect(CarryJudgment.targets(judgment) == [1])
    }

    @Test("FR-07 R-110: 잠자기는 시간 끝에서도, 초안·빈 상태는 종료도 기록하지 않는다(nil)")
    func notRunningLeavesNothing() throws {
        let tasks = [Fake.task(1)]
        #expect(NotchSession.initial.lifecycleCheckpoint(.quit, Fake.input([])) == nil)
        let drafted = NotchSession.initial.picked(Fake.input(tasks))
        #expect(drafted.lifecycleCheckpoint(.quit, Fake.input(tasks)) == nil)
        let (running, active) = try runningSession(startedAt: Fake.noon)
        let afterEnd = Fake.noon.addingTimeInterval(25 * 60)
        #expect(running.lifecycleCheckpoint(.sleep, Fake.input(active, now: afterEnd)) == nil)
    }

    @Test("FR-07 R-110: 잠자기·종료가 아닌 계기는 받지 않는다(nil)", arguments: [CheckpointTrigger.quantum, .skip])
    func otherTriggersRejected(trigger: CheckpointTrigger) throws {
        let (session, tasks) = try runningSession(startedAt: Fake.noon)
        #expect(session.lifecycleCheckpoint(trigger, Fake.input(tasks, now: Fake.noon + 60)) == nil)
    }
}
