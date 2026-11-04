import Foundation
import MokaCore
import Testing

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let title = "가짜 할 일 A"

struct BrokenState: CustomTestStringConvertible, Sendable {
    let name: String
    let timer: NotchTimer
    var testDescription: String { name }
}

let brokenStates: [BrokenState] = [
    BrokenState(
        name: "running, 끝 시각 = 시작 시각",
        timer: .running(title: title, quantumMin: 25, startedAt: t0, endsAt: t0)),
    BrokenState(
        name: "running, 끝 시각이 지남(남은 초 0)",
        timer: .running(title: title, quantumMin: 25, startedAt: t0.addingTimeInterval(-1500), endsAt: t0)),
    BrokenState(
        name: "running, 작업 시간 181",
        timer: .running(title: title, quantumMin: 181, startedAt: t0, endsAt: t0.addingTimeInterval(181 * 60))),
    BrokenState(name: "expired, 칩 0", timer: .expired(title: title, chipMin: 0)),
    BrokenState(name: "empty 초안, 칩 181", timer: .empty(draft: Draft(title: title, chipMin: 181))),
]

@Test("ADR-0003 R-015: 깨진 상태의 불변식 위반은 종료 코드 1", arguments: brokenStates)
func brokenStateMapsToExitCode1(state: BrokenState) throws {
    let error = try #require(SimRunner.checkInvariant(state.timer, at: t0, seq: 3))
    #expect(error.kind == .invariantViolation)
    #expect(error.seq == 3)
    #expect(SimExitCode.code(for: .failure(error)) == 1)
}

@Test("ADR-0003 R-015: 정상 상태는 불변식 위반이 아니다")
func validStatesPassInvariant() {
    let valid: [NotchTimer] = [
        .empty(draft: nil),
        .empty(draft: Draft(title: title, chipMin: 25)),
        .running(title: title, quantumMin: 25, startedAt: t0, endsAt: t0.addingTimeInterval(1500)),
        .expired(title: title, chipMin: 25),
    ]
    for timer in valid {
        #expect(SimRunner.checkInvariant(timer, at: t0, seq: 1) == nil)
    }
}

@Test("ADR-0003 R-015: 종료 코드 매핑 — 성공 0, 입력 오류 2")
func exitCodeMapping() {
    #expect(SimExitCode.code(for: .success("")) == 0)
    for kind in [SimErrorKind.usage, .invalidJSON, .unknownKey, .timeReversed, .notAllowedInPhase, .emptyTitle] {
        #expect(SimExitCode.code(for: .failure(SimError(kind: kind, seq: nil, message: "가짜"))) == 2)
    }
}

// MARK: - spec 002 storage 모드 불변식(contracts/moka-sim-v1-additions.md "오류 덧붙임" 종료 코드 1 줄)

private let day = LocalDay(text: "2026-11-02")!

private func task(
    _ id: TaskID, _ status: TaskStatus, recurrence: Recurrence = .none, weekday: Int? = nil, cycleDay: LocalDay? = nil,
    skipCount: Int = 0, streak: Int = 0
) -> MokaTask {
    MokaTask(
        id: id, title: "가짜 할 일 \(id)", deadline: nil, estMin: nil, recurrence: recurrence,
        weekday: weekday.flatMap(Weekday.init(rawValue:)), cycleDay: cycleDay, firstAction: nil, status: status,
        skipCount: skipCount, streak: streak, createdAt: t0)
}

private func checkpoint(_ id: Int64, elapsed: Int = 3) -> Checkpoint {
    Checkpoint(id: id, taskID: 1, notes: .empty, trigger: .switch, elapsedMin: elapsed, createdAt: t0)
}

private func decision(_ id: Int64, _ action: UserAction = .switch) -> DecisionLogEntry {
    DecisionLogEntry(
        id: id, taskID: 1, judgment: nil, modelSnapshot: nil, schedulerChoice: .rotateByIDV0, userAction: action,
        createdAt: t0)
}

private let running = NotchSession(
    timer: .running(title: title, quantumMin: 25, startedAt: t0, endsAt: t0.addingTimeInterval(1500)), taskID: 1,
    previousTaskID: nil, run: RunInfo(startedAt: t0, quantumMin: 25))
private let expired = NotchSession(
    timer: .expired(title: title, chipMin: 25), taskID: 1, previousTaskID: nil,
    run: RunInfo(startedAt: t0, quantumMin: 25))
private let draft = NotchSession(
    timer: .empty(draft: Draft(title: title, chipMin: 25)), taskID: 1, previousTaskID: nil, run: nil)

private func state(
    _ session: NotchSession?, _ tasks: [MokaTask], checkpoints: [Checkpoint] = [], decisions: [DecisionLogEntry] = []
) -> SimStorageState {
    SimStorageState(session: session, tasks: tasks, checkpoints: checkpoints, decisions: decisions)
}

private let blank = state(.initial, [])

struct BrokenStorageState: CustomTestStringConvertible, Sendable {
    let name: String
    let state: SimStorageState
    var previous: SimStorageState = blank
    var testDescription: String { name }
}

let brokenStorageStates: [BrokenStorageState] = [
    BrokenStorageState(name: "active 할 일 둘", state: state(running, [task(1, .active), task(2, .active)])),
    BrokenStorageState(name: "도는 중인데 notch_task가 todo", state: state(running, [task(1, .todo)])),
    BrokenStorageState(name: "시간 끝인데 notch_task가 없음", state: state(expired, [])),
    BrokenStorageState(
        name: "도는 중인데 active가 notch_task가 아님", state: state(running, [task(1, .todo), task(2, .active)])),
    BrokenStorageState(name: "빈 상태인데 active가 있음", state: state(.initial, [task(1, .active)])),
    BrokenStorageState(name: "초안인데 active가 있음", state: state(draft, [task(1, .todo), task(2, .active)])),
    BrokenStorageState(name: "초안의 notch_task가 done", state: state(draft, [task(1, .done)])),
    BrokenStorageState(
        name: "초안인데 notch_task가 없음",
        state: state(
            NotchSession(
                timer: .empty(draft: Draft(title: title, chipMin: 25)), taskID: nil, previousTaskID: nil, run: nil),
            [task(1, .todo)])),
    BrokenStorageState(
        name: "weekly인데 weekday 없음", state: state(.initial, [task(1, .todo, recurrence: .weekly, cycleDay: day)])),
    BrokenStorageState(
        name: "daily인데 weekday 있음",
        state: state(.initial, [task(1, .todo, recurrence: .daily, weekday: 4, cycleDay: day)])),
    BrokenStorageState(name: "반복 없음인데 cycle_day 있음", state: state(.initial, [task(1, .todo, cycleDay: day)])),
    BrokenStorageState(name: "반복인데 cycle_day 없음", state: state(.initial, [task(1, .todo, recurrence: .daily)])),
    BrokenStorageState(name: "skip_count 음수", state: state(.initial, [task(1, .done, skipCount: -1)])),
    BrokenStorageState(name: "streak 음수", state: state(.initial, [task(1, .done, streak: -1)])),
    BrokenStorageState(
        name: "체크포인트 수가 줄어듦", state: state(.initial, [task(1, .todo)]),
        previous: state(.initial, [task(1, .todo)], checkpoints: [checkpoint(1)])),
    BrokenStorageState(
        name: "이전 체크포인트가 바뀜", state: state(.initial, [task(1, .todo)], checkpoints: [checkpoint(1, elapsed: 4)]),
        previous: state(.initial, [task(1, .todo)], checkpoints: [checkpoint(1)])),
    BrokenStorageState(
        name: "한 이벤트에 체크포인트 둘",
        state: state(.initial, [task(1, .todo)], checkpoints: [checkpoint(1), checkpoint(2)])),
    BrokenStorageState(
        name: "로그 수가 줄어듦", state: state(.initial, [task(1, .todo)]),
        previous: state(.initial, [task(1, .todo)], decisions: [decision(1)])),
    BrokenStorageState(
        name: "이전 로그가 바뀜", state: state(.initial, [task(1, .todo)], decisions: [decision(1, .skip)]),
        previous: state(.initial, [task(1, .todo)], decisions: [decision(1)])),
    BrokenStorageState(
        name: "한 이벤트에 로그 둘", state: state(.initial, [task(1, .todo)], decisions: [decision(1), decision(2)])),
    BrokenStorageState(
        name: "타이머 불변식 위반(끝 시각 = 시작 시각)",
        state: state(
            NotchSession(
                timer: .running(title: title, quantumMin: 25, startedAt: t0, endsAt: t0), taskID: 1,
                previousTaskID: nil, run: RunInfo(startedAt: t0, quantumMin: 25)),
            [task(1, .active)])),
]

@Test("ADR-0003 R-117: storage 모드의 깨진 상태는 불변식 위반, 종료 코드 1", arguments: brokenStorageStates)
func brokenStorageStateMapsToExitCode1(broken: BrokenStorageState) throws {
    let error = try #require(SimRunner.checkStorageInvariant(broken.state, previous: broken.previous, at: t0, seq: 4))
    #expect(error.kind == .invariantViolation)
    #expect(error.seq == 4)
    #expect(SimExitCode.code(for: .failure(error)) == 1)
    #expect(!error.description.contains("가짜"))
}

@Test("ADR-0003 R-117: storage 모드의 정상 상태는 불변식 위반이 아니다")
func validStorageStatesPassInvariant() {
    let weekly = task(2, .done, recurrence: .weekly, weekday: 4, cycleDay: day, skipCount: 1, streak: 2)
    let valid: [(SimStorageState, SimStorageState)] = [
        (blank, blank),
        (state(draft, [task(1, .todo), weekly]), blank),
        (state(running, [task(1, .active), weekly]), blank),
        (state(expired, [task(1, .active)]), blank),
        // 꺼짐: 도는 중이던 할 일은 active로 남는다
        (state(nil, [task(1, .active)], checkpoints: [checkpoint(1)]), state(running, [task(1, .active)])),
        (
            state(.initial, [task(1, .done)], checkpoints: [checkpoint(1), checkpoint(2)], decisions: [decision(1)]),
            state(.initial, [task(1, .done)], checkpoints: [checkpoint(1)])
        ),
    ]
    for (current, previous) in valid {
        #expect(SimRunner.checkStorageInvariant(current, previous: previous, at: t0, seq: 1) == nil)
    }
}
