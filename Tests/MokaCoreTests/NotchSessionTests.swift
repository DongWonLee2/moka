import Foundation
import MokaCore
import Testing

// data-model §4.1·§4.2. 가짜 할 일만 쓴다.

private let t0 = Fake.noon

/// 저장소 목록에 묶음의 할 일 갱신을 덮어쓴 목록(시험용).
private func applying(_ batch: StoreBatch, to tasks: [MokaTask]) -> [MokaTask] {
    tasks.map { task in batch.updatedTasks.first { $0.id == task.id } ?? task }
}

/// 할 일 `tasks`에서 고르고(칩을 `chip`으로 바꿔) `at`에 시작한 세션과 그 뒤 목록.
private func started(_ tasks: [MokaTask], chip: Int? = nil, defaultMin: Int = 25, at start: Date = t0) throws -> (
    NotchSession, [MokaTask]
) {
    var drafted = NotchSession.initial.picked(Fake.input(tasks, now: start, defaultQuantumMin: defaultMin))
    if let chip {
        #expect(drafted.timer.apply(.chooseQuantum(chip), at: start, defaultQuantumMin: defaultMin) == .applied)
    }
    let step = try drafted.start(Fake.input(tasks, now: start, defaultQuantumMin: defaultMin))
    return (step.session, applying(step.batch, to: tasks))
}

private func draft(_ title: String, chip: Int = 25, picked: Bool = false) -> NotchTimer {
    .empty(draft: Draft(title: title, chipMin: chip, chipPicked: picked))
}

private func decision(_ taskID: TaskID, _ action: UserAction, at now: Date) -> NewDecisionLogEntry {
    NewDecisionLogEntry(
        taskID: taskID, judgment: nil, modelSnapshot: nil, schedulerChoice: .rotateByIDV0, userAction: action,
        createdAt: now)
}

// MARK: - 할 일 연결 몫(T020)

@Suite struct NotchSessionPickTests {
    @Test("FR-05 R-104: 처음 세션은 빈 상태이고 할 일·커서·회차가 없다")
    func initialIsEmpty() {
        #expect(
            NotchSession.initial == NotchSession(timer: .empty(draft: nil), taskID: nil, previousTaskID: nil, run: nil))
    }

    @Test("FR-05 R-104: 빈 상태에서 고르면 가장 작은 id의 대기 할 일이 제목이 채워진 초안이 된다")
    func pickMakesDraft() {
        let session = NotchSession.initial.picked(Fake.input([Fake.task(2), Fake.task(1)]))
        #expect(session.timer == draft("가짜 할 일 1"))
        #expect(session.taskID == 1)
        #expect(session.previousTaskID == nil)
        #expect(session.run == nil)
    }

    @Test("FR-05 R-104: 초안의 칩은 고르는 순간의 기본값이다")
    func draftChipIsCurrentDefault() {
        let session = NotchSession.initial.picked(Fake.input([Fake.task(1)], defaultQuantumMin: 45))
        #expect(session.timer == draft("가짜 할 일 1", chip: 45))
    }

    @Test("FR-05 R-104: 대기 할 일이 없으면 고르기 뒤에도 빈 상태")
    func pickWithoutCandidates() {
        let tasks = [Fake.task(1, status: .done), Fake.task(2, status: .dropped)]
        #expect(NotchSession.initial.picked(Fake.input(tasks)) == .initial)
    }

    @Test("FR-05 R-104: 고르기는 빈 상태에서만 돈다(초안·도는 중은 그대로)")
    func pickOnlyWhenEmpty() throws {
        let tasks = Fake.todos(1...3)
        let drafted = NotchSession.initial.picked(Fake.input(tasks))
        #expect(drafted.picked(Fake.input(Array(tasks.dropFirst()))) == drafted)
        let (running, after) = try started(tasks)
        #expect(running.picked(Fake.input(after)) == running)
    }

    @Test("FR-05 R-104: 고르기는 커서 다음 할 일을 고른다")
    func pickFollowsCursor() {
        let session = NotchSession(timer: .empty(draft: nil), taskID: nil, previousTaskID: 2, run: nil)
        #expect(session.picked(Fake.input(Fake.todos(1...3))).taskID == 3)
    }
}

@Suite struct NotchSessionQuickInputTests {
    @Test("FR-01 R-103: 빈 상태에서 빠른 입력으로 만든 할 일이 초안이 되고 칩은 기본값")
    func addFromEmpty() {
        let added = Fake.task(7)
        let session = NotchSession.initial.addedTask(added, Fake.input([added], defaultQuantumMin: 15))
        #expect(session.timer == draft("가짜 할 일 7", chip: 15))
        #expect(session.taskID == 7)
        #expect(session.previousTaskID == nil)
    }

    @Test("FR-01 R-103: 초안에서 빠른 입력이면 새 할 일이 초안이 되고 고른 칩은 그대로, 커서도 그대로")
    func addFromDraftKeepsChip() {
        let session = NotchSession(
            timer: draft("가짜 할 일 1", chip: 60, picked: true), taskID: 1, previousTaskID: 4, run: nil)
        let added = Fake.task(9)
        let next = session.addedTask(added, Fake.input([Fake.task(1), added]))
        #expect(next.timer == draft("가짜 할 일 9", chip: 60, picked: true))
        #expect(next.taskID == 9)
        #expect(next.previousTaskID == 4)
    }

    @Test("FR-01 R-103: 도는 중·시간 끝에서는 빠른 입력을 받지 않는다(세션 그대로)")
    func addRejectedWhileRunning() throws {
        let (running, tasks) = try started([Fake.task(1)])
        #expect(running.addedTask(Fake.task(2), Fake.input(tasks)) == running)
        let afterEnd = t0.addingTimeInterval(25 * 60)
        #expect(running.addedTask(Fake.task(2), Fake.input(tasks, now: afterEnd)) == running)
    }
}

@Suite struct NotchSessionNextDraftTests {
    @Test("FR-05 R-104: 다른 할 일은 커서를 지금 초안으로 두고 다음 후보로 초안을 바꾼다(칩 유지)")
    func nextDraftAdvances() {
        let session = NotchSession(
            timer: draft("가짜 할 일 1", chip: 45, picked: true), taskID: 1, previousTaskID: nil, run: nil)
        let next = session.nextDraft(Fake.input(Fake.todos(1...3)))
        #expect(next.timer == draft("가짜 할 일 2", chip: 45, picked: true))
        #expect(next.taskID == 2)
        #expect(next.previousTaskID == 1)
        #expect(next.run == nil)
    }

    @Test("FR-05 R-104: 다른 할 일을 이어 누르면 1 → 2 → 3 → 1")
    func nextDraftCycles() {
        let tasks = Fake.todos(1...3)
        var session = NotchSession.initial.picked(Fake.input(tasks))
        var seen = [session.taskID!]
        for _ in 0..<3 {
            session = session.nextDraft(Fake.input(tasks))
            seen.append(session.taskID!)
        }
        #expect(seen == [1, 2, 3, 1])
    }

    @Test("FR-05 R-104: 다른 할 일은 초안에서만 된다(빈 상태·도는 중은 그대로)")
    func nextDraftOnlyInDraft() throws {
        #expect(NotchSession.initial.nextDraft(Fake.input(Fake.todos(1...2))) == .initial)
        let (running, tasks) = try started(Fake.todos(1...2))
        #expect(running.nextDraft(Fake.input(tasks)) == running)
    }
}

@Suite struct NotchSessionStartTests {
    @Test("FR-05 R-104: 초안에서 시작하면 도는 중, 할 일은 진행 중, 회차 값은 (지금, 칩)")
    func startFromDraft() throws {
        let tasks = Fake.todos(1...2)
        var drafted = NotchSession.initial.picked(Fake.input(tasks))
        drafted.previousTaskID = 2
        let step = try drafted.start(Fake.input(tasks))
        var active = tasks[0]
        active.status = .active
        #expect(step.batch == StoreBatch(updatedTasks: [active]))
        #expect(
            step.session.timer == .running(title: "가짜 할 일 1", quantumMin: 25, startedAt: t0, endsAt: t0 + 25 * 60))
        #expect(step.session.taskID == 1)
        #expect(step.session.previousTaskID == 2)
        #expect(step.session.run == RunInfo(startedAt: t0, quantumMin: 25))
    }

    @Test("FR-05 R-104: 시작은 고른 칩으로 돈다")
    func startUsesChosenChip() throws {
        let (running, _) = try started([Fake.task(1)], chip: 45)
        #expect(running.run == RunInfo(startedAt: t0, quantumMin: 45))
    }

    @Test("FR-05 R-104: 빈 상태·도는 중·시간 끝에서 시작은 거부")
    func startRejected() throws {
        #expect(throws: SessionError.notAllowed) { try NotchSession.initial.start(Fake.input([Fake.task(1)])) }
        let (running, tasks) = try started([Fake.task(1)])
        #expect(throws: SessionError.notAllowed) { try running.start(Fake.input(tasks)) }
        let afterEnd = t0.addingTimeInterval(25 * 60)
        #expect(throws: SessionError.notAllowed) { try running.start(Fake.input(tasks, now: afterEnd)) }
    }
}

@Suite struct NotchSessionDropEditTests {
    @Test("FR-01 R-102: 노치의 할 일을 지우면 빈 상태, 회차 없음, 커서 그대로")
    func dropNotchTask() throws {
        var drafted = NotchSession.initial.picked(Fake.input(Fake.todos(1...2)))
        drafted.previousTaskID = 2
        let dropped = drafted.taskDropped(1)
        #expect(dropped == NotchSession(timer: .empty(draft: nil), taskID: nil, previousTaskID: 2, run: nil))
        let (running, _) = try started(Fake.todos(1...2))
        #expect(
            running.taskDropped(1)
                == NotchSession(timer: .empty(draft: nil), taskID: nil, previousTaskID: nil, run: nil))
    }

    @Test("FR-01 R-102: 노치에 없는 할 일을 지우면 세션 그대로")
    func dropOtherTask() throws {
        let (running, _) = try started(Fake.todos(1...2))
        #expect(running.taskDropped(2) == running)
        #expect(NotchSession.initial.taskDropped(1) == .initial)
    }

    @Test("FR-01 R-102: 노치의 할 일을 고치면 제목 사본만 바뀌고 칩·시간 값은 그대로")
    func editReplacesTitleOnly() throws {
        var renamed = Fake.task(1)
        renamed.title = "가짜 할 일 새 이름"

        let drafted = NotchSession(
            timer: draft("가짜 할 일 1", chip: 60, picked: true), taskID: 1, previousTaskID: 3, run: nil)
        #expect(drafted.edited(renamed).timer == draft("가짜 할 일 새 이름", chip: 60, picked: true))
        #expect(drafted.edited(renamed).previousTaskID == 3)

        let (running, _) = try started([Fake.task(1)], chip: 45)
        let editedRunning = running.edited(renamed)
        #expect(
            editedRunning.timer
                == .running(title: "가짜 할 일 새 이름", quantumMin: 45, startedAt: t0, endsAt: t0 + 45 * 60))
        #expect(editedRunning.run == running.run)

        let expired = NotchSession(
            timer: .expired(title: "가짜 할 일 1", chipMin: 15, chipPicked: true), taskID: 1, previousTaskID: nil,
            run: RunInfo(startedAt: t0, quantumMin: 45))
        let editedExpired = expired.edited(renamed)
        #expect(editedExpired.timer == .expired(title: "가짜 할 일 새 이름", chipMin: 15, chipPicked: true))
        #expect(editedExpired.run == expired.run)
    }

    @Test("FR-01 R-102: 노치에 없는 할 일을 고치면 세션 그대로")
    func editOtherTask() {
        let drafted = NotchSession.initial.picked(Fake.input(Fake.todos(1...2)))
        #expect(drafted.edited(Fake.task(2)) == drafted)
        #expect(NotchSession.initial.edited(Fake.task(1)) == .initial)
    }
}

@Suite struct NotchSessionNextMarkTests {
    @Test("FR-01 R-102: 다음 표시는 초안이면 그 할 일")
    func draftMarksItself() {
        let tasks = Fake.todos(1...3)
        let drafted = NotchSession.initial.picked(Fake.input(tasks)).nextDraft(Fake.input(tasks))
        #expect(drafted.nextMark(Fake.input(tasks)) == 2)
    }

    @Test("FR-01 R-102: 도는 중·시간 끝이면 지금 할 일을 끝냈을 때 뜰 할 일(진행 중은 후보 아님)")
    func runningMarksNextPick() throws {
        let (running, tasks) = try started(Fake.todos(1...3))
        #expect(running.nextMark(Fake.input(tasks)) == 2)
        #expect(running.nextMark(Fake.input(tasks, now: t0.addingTimeInterval(30 * 60))) == 2)
    }

    @Test("FR-01 R-102: 빈 상태면 다음 표시 없음")
    func emptyMarksNothing() {
        #expect(NotchSession.initial.nextMark(Fake.input(Fake.todos(1...3))) == nil)
    }
}

// MARK: - 버튼(T032)

@Suite struct NotchSessionButtonTests {
    @Test("FR-06 R-105: 도는 중 완료는 할 일을 완료로, 로그 한 줄, 체크포인트 없음, 커서 nil")
    func completeRunning() throws {
        var (running, tasks) = try started(Fake.todos(1...2))
        running.previousTaskID = 2
        let now = t0.addingTimeInterval(10 * 60)
        let step = try running.complete(nil, Fake.input(tasks, now: now))
        var done = tasks[0]
        done.status = .done
        #expect(step.batch == StoreBatch(updatedTasks: [done], newDecisions: [decision(1, .done, at: now)]))
        #expect(step.session == .initial)
    }

    @Test("FR-11 R-112: 로그 줄은 rotate_by_id_v0이고 판단 칸과 model_snapshot은 비어 있다")
    func logLineHasNoJudgment() throws {
        let (running, tasks) = try started([Fake.task(1)])
        let step = try running.complete(nil, Fake.input(tasks, now: t0 + 60))
        let line = try #require(step.batch.newDecisions.first)
        #expect(line.schedulerChoice.rawValue == "rotate_by_id_v0")
        #expect(line.judgment == nil)
        #expect(line.modelSnapshot == nil)
    }

    @Test("FR-06 R-105: 반복 할 일을 완료하면 연속 기록 + 1")
    func completeRecurringBumpsStreak() throws {
        let daily = Fake.task(1, recurrence: .daily, cycleDay: Fake.day("2027-01-13"), streak: 4)
        let (running, tasks) = try started([daily])
        let step = try running.complete(nil, Fake.input(tasks, now: t0 + 60))
        #expect(step.batch.updatedTasks.first?.streak == 5)
        #expect(step.batch.updatedTasks.first?.status == .done)
    }

    @Test("FR-07 R-107: 칩 45분·기본값 25분으로 시간 끝에서 완료하면 elapsed_min 45, 두 줄은 시간 끝 체크포인트")
    func completeExpiredUsesRunQuantum() throws {
        let (running, tasks) = try started([Fake.task(1)], chip: 45, defaultMin: 25)
        let now = t0.addingTimeInterval(50 * 60)
        let step = try running.complete(Fake.notes(" 가짜 한 일 ", "가짜 다음 줄"), Fake.input(tasks, now: now))
        #expect(
            step.batch.newCheckpoints == [
                NewCheckpoint(
                    taskID: 1, notes: Fake.notes("가짜 한 일", "가짜 다음 줄"), trigger: .quantum, elapsedMin: 45,
                    createdAt: now)
            ])
        #expect(step.batch.newDecisions == [decision(1, .done, at: now)])
        #expect(step.batch.updatedTasks.first?.status == .done)
        #expect(step.batch.updatedTasks.first?.firstAction == "가짜 다음 줄")
        #expect(step.session == .initial)
    }

    @Test("FR-07 R-107: 시간 끝 화면(타이머가 이미 expired)에서도 경과 분은 회차의 작업 시간")
    func completeAfterExplicitTick() throws {
        var (running, tasks) = try started([Fake.task(1)], chip: 45, defaultMin: 25)
        let end = t0.addingTimeInterval(45 * 60)
        _ = running.timer.apply(.tick, at: end, defaultQuantumMin: 25)
        #expect(running.timer == .expired(title: "가짜 할 일 1", chipMin: 25))
        let step = try running.complete(.empty, Fake.input(tasks, now: end + 120))
        #expect(step.batch.newCheckpoints.first?.elapsedMin == 45)
        #expect(step.batch.newCheckpoints.first?.notes == .empty)
    }

    @Test("FR-07 R-107: 시간 끝 완료에서 두 줄을 주지 않아도(nil) 빈 두 줄 체크포인트를 남긴다")
    func completeExpiredWithoutNotes() throws {
        let (running, tasks) = try started([Fake.task(1)])
        let step = try running.complete(nil, Fake.input(tasks, now: t0.addingTimeInterval(26 * 60)))
        #expect(step.batch.newCheckpoints.map(\.notes) == [.empty])
        #expect(step.batch.newCheckpoints.map(\.trigger) == [.quantum])
    }

    @Test("FR-07 R-106: 도는 중 완료에 두 줄을 주면 거부(도는 중 완료는 체크포인트가 없다)")
    func completeRunningWithNotesRejected() throws {
        let (running, tasks) = try started([Fake.task(1)])
        #expect(throws: SessionError.notAllowed) { try running.complete(.empty, Fake.input(tasks, now: t0 + 60)) }
    }

    @Test(
        "FR-07 R-106: 도는 중 미루기는 미룬 횟수 + 1, 대기로, 계기 skip 체크포인트(경과 분), 로그 skip, 커서 = 그 할 일")
    func skipRunning() throws {
        let (running, tasks) = try started(Fake.todos(1...2))
        let now = t0.addingTimeInterval(12 * 60 + 30)
        let step = try running.skip(Fake.notes("가짜 한 일", "가짜 다음 줄"), Fake.input(tasks, now: now))
        var skipped = tasks[0]
        skipped.status = .todo
        skipped.skipCount = 1
        skipped.firstAction = "가짜 다음 줄"
        #expect(
            step.batch
                == StoreBatch(
                    updatedTasks: [skipped],
                    newCheckpoints: [
                        NewCheckpoint(
                            taskID: 1, notes: Fake.notes("가짜 한 일", "가짜 다음 줄"), trigger: .skip, elapsedMin: 12,
                            createdAt: now)
                    ],
                    newDecisions: [decision(1, .skip, at: now)]))
        #expect(step.session == NotchSession(timer: .empty(draft: nil), taskID: nil, previousTaskID: 1, run: nil))
    }

    @Test("FR-07 R-106: 도는 중 바꾸기는 미룬 횟수 그대로, 대기로, 계기 switch, 로그 switch, 커서 = 그 할 일")
    func switchRunning() throws {
        let (running, tasks) = try started(Fake.todos(1...2))
        let now = t0.addingTimeInterval(3 * 60)
        let step = try running.switchTask(.empty, Fake.input(tasks, now: now))
        var switched = tasks[0]
        switched.status = .todo
        #expect(
            step.batch
                == StoreBatch(
                    updatedTasks: [switched],
                    newCheckpoints: [
                        NewCheckpoint(taskID: 1, notes: .empty, trigger: .switch, elapsedMin: 3, createdAt: now)
                    ],
                    newDecisions: [decision(1, .switch, at: now)]))
        #expect(step.session.previousTaskID == 1)
        #expect(step.session.timer == .empty(draft: nil))
    }

    @Test("FR-07 R-107: 시간 끝 미루기·바꾸기는 계기 quantum, 경과 분 = 회차 작업 시간")
    func skipSwitchExpired() throws {
        let (running, tasks) = try started([Fake.task(1)], chip: 15)
        let now = t0.addingTimeInterval(40 * 60)
        let skipped = try running.skip(.empty, Fake.input(tasks, now: now))
        #expect(skipped.batch.newCheckpoints.map(\.trigger) == [.quantum])
        #expect(skipped.batch.newCheckpoints.map(\.elapsedMin) == [15])
        #expect(skipped.batch.updatedTasks.first?.skipCount == 1)
        #expect(skipped.batch.newDecisions.map(\.userAction) == [.skip])
        let switched = try running.switchTask(.empty, Fake.input(tasks, now: now))
        #expect(switched.batch.newCheckpoints.map(\.trigger) == [.quantum])
        #expect(switched.batch.newCheckpoints.map(\.elapsedMin) == [15])
        #expect(switched.batch.newDecisions.map(\.userAction) == [.switch])
    }

    @Test("FR-07 R-109: 다음 할 일 줄이 비면 이전 첫 행동을 둔다")
    func emptyNextKeepsFirstAction() throws {
        let (running, tasks) = try started([Fake.task(1, firstAction: "가짜 이전 첫 행동")])
        let step = try running.switchTask(Fake.notes("가짜 한 일", "   "), Fake.input(tasks, now: t0 + 60))
        #expect(step.batch.updatedTasks.first?.firstAction == "가짜 이전 첫 행동")
        #expect(step.batch.newCheckpoints.first?.notes == Fake.notes("가짜 한 일", ""))
    }

    @Test("FR-07 R-107: 시간 끝 다시 시작은 계기 quantum 체크포인트, 로그 없음, 고른 칩으로 다시 돈다")
    func restartExpired() throws {
        let (running, tasks) = try started([Fake.task(1)], chip: 45)
        let now = t0.addingTimeInterval(47 * 60)
        let step = try running.restart(Fake.notes("가짜 한 일", "가짜 다음 줄"), quantumMin: 15, Fake.input(tasks, now: now))
        #expect(
            step.batch.newCheckpoints == [
                NewCheckpoint(
                    taskID: 1, notes: Fake.notes("가짜 한 일", "가짜 다음 줄"), trigger: .quantum, elapsedMin: 45,
                    createdAt: now)
            ])
        #expect(step.batch.newDecisions.isEmpty)
        #expect(step.batch.updatedTasks.map(\.status) == [.active])
        #expect(step.batch.updatedTasks.map(\.firstAction) == ["가짜 다음 줄"])
        #expect(
            step.session.timer == .running(title: "가짜 할 일 1", quantumMin: 15, startedAt: now, endsAt: now + 15 * 60))
        #expect(step.session.run == RunInfo(startedAt: now, quantumMin: 15))
        #expect(step.session.taskID == 1)
    }

    @Test("FR-07 R-107: 다시 시작에서 다음 할 일 줄이 비면 할 일 갱신이 없다")
    func restartWithoutNextNote() throws {
        let (running, tasks) = try started([Fake.task(1)])
        let step = try running.restart(.empty, quantumMin: 25, Fake.input(tasks, now: t0.addingTimeInterval(30 * 60)))
        #expect(step.batch.updatedTasks.isEmpty)
        #expect(step.batch.newCheckpoints.count == 1)
    }

    @Test("FR-07 R-107: 다시 시작은 시간 끝에서만, 칩은 1~180만")
    func restartRejected() throws {
        let (running, tasks) = try started([Fake.task(1)])
        #expect(throws: SessionError.notAllowed) {
            try running.restart(.empty, quantumMin: 25, Fake.input(tasks, now: t0 + 60))
        }
        let drafted = NotchSession.initial.picked(Fake.input([Fake.task(1)]))
        #expect(throws: SessionError.notAllowed) {
            try drafted.restart(.empty, quantumMin: 25, Fake.input([Fake.task(1)]))
        }
        let afterEnd = t0.addingTimeInterval(26 * 60)
        for invalid in [0, 181] {
            #expect(throws: SessionError.notAllowed) {
                try running.restart(.empty, quantumMin: invalid, Fake.input(tasks, now: afterEnd))
            }
        }
    }

    @Test("FR-06 R-105: 빈 상태·초안에서 완료·미루기·바꾸기는 거부")
    func buttonsRejectedWithoutRun() {
        let tasks = [Fake.task(1)]
        let drafted = NotchSession.initial.picked(Fake.input(tasks))
        for session in [NotchSession.initial, drafted] {
            #expect(throws: SessionError.notAllowed) { try session.complete(nil, Fake.input(tasks)) }
            #expect(throws: SessionError.notAllowed) { try session.skip(.empty, Fake.input(tasks)) }
            #expect(throws: SessionError.notAllowed) { try session.switchTask(.empty, Fake.input(tasks)) }
        }
    }

    @Test("FR-06 R-105: 버튼은 세션의 할 일이 목록에 없으면 거부")
    func buttonsRejectedWhenTaskMissing() throws {
        let (running, _) = try started([Fake.task(1)])
        #expect(throws: SessionError.notAllowed) { try running.complete(nil, Fake.input([], now: t0 + 60)) }
        #expect(throws: SessionError.notAllowed) { try running.skip(.empty, Fake.input([], now: t0 + 60)) }
    }
}

// MARK: - 저장소와 함께(수용 기준)

@Suite struct NotchSessionFlowTests {
    @Test("FR-05 R-104: 대기 할 일 넷에서 시작·바꾸기를 이어 누르면 1 → 2 → 3 → 4 → 1, 로그는 바꾸기 수만큼")
    func switchRotationWithRepository() throws {
        let repository = try InMemoryTaskRepository.seeded(4)
        var session = NotchSession.initial.picked(Fake.input(try repository.tasks()))
        var seen: [TaskID] = []
        var now = t0
        for _ in 0..<5 {
            seen.append(try #require(session.taskID))
            now += 60
            session = try SessionCommit.commit(
                session.start(Fake.input(try repository.tasks(), now: now)), to: repository)
            now += 60
            session = try SessionCommit.commit(
                session.switchTask(.empty, Fake.input(try repository.tasks(), now: now)), to: repository)
            session = session.picked(Fake.input(try repository.tasks(), now: now))
        }
        #expect(seen == [1, 2, 3, 4, 1])
        #expect(try repository.decisions().count == 5)
        #expect(try repository.checkpoints().count == 5)
        #expect(try repository.tasks().allSatisfy { $0.status == .todo })
    }

    @Test("FR-05 R-104: 시작 전 화면 다른 할 일은 기록 없이 커서만 옮긴다")
    func nextDraftWritesNothing() throws {
        let repository = try InMemoryTaskRepository.seeded(3)
        let before = try repository.tasks()
        let session = NotchSession.initial.picked(Fake.input(before)).nextDraft(Fake.input(before))
        #expect(session.previousTaskID == 1)
        #expect(session.taskID == 2)
        #expect(try repository.tasks() == before)
        #expect(try repository.checkpoints().isEmpty)
        #expect(try repository.decisions().isEmpty)
    }

    @Test("FR-11 R-112: 완료 한 번, 미루기 등록 한 번, 바꾸기 안 적기 한 번은 각각 로그 한 줄, 돌아가기는 0줄")
    func oneLogLinePerButton() throws {
        let repository = try InMemoryTaskRepository.seeded(3)
        var session = NotchSession.initial.picked(Fake.input(try repository.tasks()))
        var now = t0

        func startNext() throws {
            now += 60
            session = try SessionCommit.commit(
                session.start(Fake.input(try repository.tasks(), now: now)), to: repository)
        }
        func pickNext() throws {
            session = session.picked(Fake.input(try repository.tasks(), now: now))
        }

        try startNext()
        // 돌아가기: 앱 화면 상태만 되돌리고 세션 함수를 부르지 않는다(data-model §4.1).
        #expect(try repository.decisions().isEmpty)

        now += 60
        session = try SessionCommit.commit(
            session.complete(nil, Fake.input(try repository.tasks(), now: now)), to: repository)
        #expect(try repository.decisions().count == 1)
        try pickNext()

        try startNext()
        now += 60
        session = try SessionCommit.commit(
            session.skip(Fake.notes("가짜 한 일", ""), Fake.input(try repository.tasks(), now: now)), to: repository)
        #expect(try repository.decisions().count == 2)
        try pickNext()

        try startNext()
        now += 60
        session = try SessionCommit.commit(
            session.switchTask(.empty, Fake.input(try repository.tasks(), now: now)), to: repository)
        #expect(try repository.decisions().map(\.userAction) == [.done, .skip, .switch])
    }

    @Test("FR-05 R-104: 완료 뒤 고르기는 처음부터(가장 작은 id), 미루기 뒤는 다음 차례")
    func pickAfterButtons() throws {
        let repository = try InMemoryTaskRepository.seeded(3)
        var session = NotchSession.initial.picked(Fake.input(try repository.tasks())).nextDraft(
            Fake.input(try repository.tasks()))
        #expect(session.taskID == 2)
        session = try SessionCommit.commit(session.start(Fake.input(try repository.tasks())), to: repository)
        session = try SessionCommit.commit(
            session.complete(nil, Fake.input(try repository.tasks(), now: t0 + 60)), to: repository)
        session = session.picked(Fake.input(try repository.tasks()))
        #expect(session.taskID == 1)
        session = try SessionCommit.commit(session.start(Fake.input(try repository.tasks())), to: repository)
        session = try SessionCommit.commit(
            session.skip(.empty, Fake.input(try repository.tasks(), now: t0 + 60)), to: repository)
        session = session.picked(Fake.input(try repository.tasks()))
        #expect(session.taskID == 3)
    }

    @Test("FR-09 R-113: 하루 시작을 넘겨 끝낸 매일 반복은 그 주기 몫 완료, 다음 판정에서 대기로 연속 기록 유지")
    func recurringCompletedAcrossDayStart() throws {
        let repository = InMemoryTaskRepository()
        let startAt = Fake.at(2027, 1, 13, 5, 50)  // 하루 2027-01-12에 속함
        let new = try #require(
            TaskWriteRules.prepareNew(
                NewTask(title: "가짜 할 일 매일", deadline: nil, estMin: nil, recurrence: .daily, weekday: nil),
                now: startAt, dayStart: Fake.sixAM, calendar: Fake.seoul))
        #expect(new.cycleDay == Fake.day("2027-01-12"))
        _ = try repository.insertTask(new.task, cycleDay: new.cycleDay, at: startAt)

        var session = NotchSession.initial.picked(Fake.input(try repository.tasks(), now: startAt))
        session = try SessionCommit.commit(
            session.start(Fake.input(try repository.tasks(), now: startAt)), to: repository)
        let doneAt = Fake.at(2027, 1, 13, 6, 10)
        session = try SessionCommit.commit(
            session.complete(nil, Fake.input(try repository.tasks(), now: doneAt)), to: repository)
        let done = try #require(try repository.tasks().first)
        #expect(done.status == .done)
        #expect(done.streak == 1)
        #expect(done.cycleDay == Fake.day("2027-01-12"))

        let activation = Fake.at(2027, 1, 13, 9, 0)
        let changed = RecurrenceReset.reset(
            try repository.tasks(), now: activation, dayStart: Fake.sixAM, calendar: Fake.seoul)
        try repository.apply(StoreBatch(updatedTasks: changed))
        let reset = try #require(try repository.tasks().first)
        #expect(reset.status == .todo)
        #expect(reset.streak == 1)
        #expect(reset.cycleDay == Fake.day("2027-01-13"))
        let again = RecurrenceReset.reset(
            try repository.tasks(), now: activation + 3600, dayStart: Fake.sixAM, calendar: Fake.seoul)
        #expect(again.isEmpty)
    }
}
