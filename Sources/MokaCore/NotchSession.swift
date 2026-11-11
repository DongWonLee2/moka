import Foundation

/// 노치 세션(data-model §4.2). 메모리에만 두고 저장하지 않는다.
public struct NotchSession: Equatable, Sendable {
    /// spec 001 값 타입. 타입과 기존 golden은 바꾸지 않는다.
    public var timer: NotchTimer
    /// 초안·도는 중·시간 끝이 가리키는 할 일.
    public var taskID: TaskID?
    /// 고르기 커서(§5.1). 저장하지 않음.
    public var previousTaskID: TaskID?
    /// running·expired 동안만 값. 저장하지 않음.
    public var run: RunInfo?

    public init(timer: NotchTimer, taskID: TaskID?, previousTaskID: TaskID?, run: RunInfo?) {
        self.timer = timer
        self.taskID = taskID
        self.previousTaskID = previousTaskID
        self.run = run
    }
}

/// 시작한 순간의 값. 시간 끝(`expired`)이 되면 spec 001 타이머는 작업 시간을 버리므로 세션이 따로 든다.
public struct RunInfo: Equatable, Sendable {
    public var startedAt: Date
    public var quantumMin: Int

    public init(startedAt: Date, quantumMin: Int) {
        self.startedAt = startedAt
        self.quantumMin = quantumMin
    }
}

/// 동작마다 넣는 입력. 호출자(앱 `AppState`, `moka-sim`)가 채운다.
public struct SessionInput: Sendable {
    /// 저장소의 지금 목록(`tasks()`).
    public var tasks: [MokaTask]
    public var now: Date
    public var defaultQuantumMin: Int
    /// `GregorianCalendar.make(timeZone:)`.
    public var calendar: Calendar
    /// 노치 순서에 쓸 판단 결과(spec 003 data-model §1). nil이면 모든 할 일이 점수 없음(마감 순).
    public var scoring: SessionScoring?

    public init(
        tasks: [MokaTask], now: Date, defaultQuantumMin: Int, calendar: Calendar, scoring: SessionScoring? = nil
    ) {
        self.tasks = tasks
        self.now = now
        self.defaultQuantumMin = defaultQuantumMin
        self.calendar = calendar
        self.scoring = scoring
    }
}

/// 노치 순서가 기대는 판단 결과. `usable`은 `ScoreRules.usable`로 거른 사전, `today`는 고르는 날(spec 002 R-114).
/// `thresholds`는 기준 모델의 임계값이고 순서 계산이 `ScoreRules.priority`에 넘긴다(spec 006 R-609).
public struct SessionScoring: Sendable {
    public var usable: [TaskID: TaskScore]
    public var questions: QuestionSet
    public var thresholds: ModelThresholds?
    public var today: LocalDay

    public init(usable: [TaskID: TaskScore], questions: QuestionSet, thresholds: ModelThresholds?, today: LocalDay) {
        self.usable = usable
        self.questions = questions
        self.thresholds = thresholds
        self.today = today
    }
}

/// 쓰기가 있는 동작의 결과. 호출자가 `batch`를 `apply`하고 성공한 뒤에만 `session`으로 바꾼다.
public struct SessionStep: Equatable, Sendable {
    public var session: NotchSession
    public var batch: StoreBatch

    public init(session: NotchSession, batch: StoreBatch) {
        self.session = session
        self.batch = batch
    }
}

/// data-model §4.2 표의 "거부".
public enum SessionError: Error, Equatable, Sendable { case notAllowed }

extension NotchSession {
    /// empty(nil), 나머지 nil.
    public static let initial = NotchSession(timer: .empty(draft: nil), taskID: nil, previousTaskID: nil, run: nil)

    /// 고르기(spec 003 R-209). empty(nil)일 때만 바뀐다. 초안의 칩은 그 순간의 기본값이다.
    public func picked(_ input: SessionInput) -> NotchSession {
        guard timer == .empty(draft: nil),
            let task = PriorityRotateRule.pick(order: PriorityOrder.order(input), after: previousTaskID)
        else { return self }
        return drafting(task, input)
    }

    /// 빠른 입력 둘째 단계. 빈 상태·초안에서만 받는다(초안이면 칩 유지). 도는 중·시간 끝은 그대로.
    public func addedTask(_ task: MokaTask, _ input: SessionInput) -> NotchSession {
        guard case .empty = timer else { return self }
        return drafting(task, input)
    }

    /// "다른 할 일" 목록에서 고름(초안만, R-104). 커서를 지금 초안으로 두고 고른 대기 할 일로 초안을 바꾼다(칩 유지).
    /// 기록하지 않는다. 없는·대기 아닌·지금 할 일이면 그대로.
    public func chosenDraft(_ id: TaskID, _ input: SessionInput) -> NotchSession {
        guard case .empty(.some) = timer, let current = taskID, id != current,
            let chosen = input.tasks.first(where: { $0.id == id && $0.status == .todo })
        else { return self }
        var moved = self
        moved.previousTaskID = current
        return moved.drafting(chosen, input)
    }

    /// 노치의 할 일을 고쳤을 때 타이머 안 제목 사본만 바꾼다. 칩·시간 값은 그대로.
    public func edited(_ task: MokaTask) -> NotchSession {
        guard task.id == taskID else { return self }
        var renamed = self
        switch timer {
        case .empty(nil):
            return self
        case .empty(.some(let draft)):
            renamed.timer = .empty(
                draft: Draft(title: task.title, chipMin: draft.chipMin, chipPicked: draft.chipPicked))
        case .running(_, let quantumMin, let startedAt, let endsAt):
            renamed.timer = .running(title: task.title, quantumMin: quantumMin, startedAt: startedAt, endsAt: endsAt)
        case .expired(_, let chipMin, let chipPicked):
            renamed.timer = .expired(title: task.title, chipMin: chipMin, chipPicked: chipPicked)
        }
        return renamed
    }

    /// 초안에서 시작. 할 일은 진행 중, `run`은 (지금, 칩).
    public func start(_ input: SessionInput) throws(SessionError) -> SessionStep {
        guard case .empty(.some) = timer, let id = taskID,
            let task = input.tasks.first(where: { $0.id == id }), task.status == .todo
        else { throw .notAllowed }
        var next = self
        guard next.timer.apply(.start, at: input.now, defaultQuantumMin: input.defaultQuantumMin) == .applied,
            case .running(_, let quantumMin, let startedAt, _) = next.timer
        else { throw .notAllowed }
        next.run = RunInfo(startedAt: startedAt, quantumMin: quantumMin)
        var active = task
        active.status = .active
        return SessionStep(session: next, batch: StoreBatch(updatedTasks: [active]))
    }

    /// 완료. 도는 중이면 `notes`는 nil이어야 하고 체크포인트가 없다. 시간 끝이면 두 줄(nil이면 빈 두 줄)을 계기
    /// `quantum` 체크포인트로 남긴다. 커서는 nil.
    public func complete(_ notes: CheckpointNotes?, _ input: SessionInput) throws(SessionError) -> SessionStep {
        let button = try buttonContext(input)
        if !button.expired, notes != nil { throw .notAllowed }
        var done = button.task
        done.status = .done
        if done.recurrence != .none {
            done.streak += 1
        }
        var checkpoints: [NewCheckpoint] = []
        if button.expired {
            let notes = notes ?? .empty
            done.takeNextNote(notes)
            checkpoints = [
                NewCheckpoint(
                    taskID: done.id, notes: notes, trigger: .quantum, elapsedMin: button.run.quantumMin,
                    createdAt: input.now)
            ]
        }
        return SessionStep(
            session: finished(cursor: nil, input),
            batch: StoreBatch(
                updatedTasks: [done], newCheckpoints: checkpoints, newDecisions: [Self.logLine(done.id, .done, input)]))
    }

    /// 미루기(등록·안 적기). 미룬 횟수 + 1, 대기로, 커서 = 그 할 일.
    public func skip(_ notes: CheckpointNotes, _ input: SessionInput) throws(SessionError) -> SessionStep {
        try setAside(notes, action: .skip, input)
    }

    /// 바꾸기(등록·안 적기). 대기로, 커서 = 그 할 일.
    public func switchTask(_ notes: CheckpointNotes, _ input: SessionInput) throws(SessionError) -> SessionStep {
        try setAside(notes, action: .switch, input)
    }

    /// 시간 끝에서 같은 할 일을 고른 칩으로 다시 시작한다. 계기 `quantum` 체크포인트, 로그 없음.
    public func restart(_ notes: CheckpointNotes, quantumMin: Int, _ input: SessionInput) throws(SessionError)
        -> SessionStep
    {
        let button = try buttonContext(input)
        guard button.expired else { throw .notAllowed }
        var next = self
        next.timer = ticked(input)
        guard
            next.timer.apply(.chooseQuantum(quantumMin), at: input.now, defaultQuantumMin: input.defaultQuantumMin)
                == .applied,
            next.timer.apply(.start, at: input.now, defaultQuantumMin: input.defaultQuantumMin) == .applied
        else { throw .notAllowed }
        next.run = RunInfo(startedAt: input.now, quantumMin: quantumMin)
        var updated = button.task
        updated.takeNextNote(notes)
        return SessionStep(
            session: next,
            batch: StoreBatch(
                updatedTasks: updated == button.task ? [] : [updated],
                newCheckpoints: [
                    NewCheckpoint(
                        taskID: updated.id, notes: notes, trigger: .quantum, elapsedMin: button.run.quantumMin,
                        createdAt: input.now)
                ]))
    }

    /// 잠자기·종료(`.sleep`/`.quit`) 체크포인트. 도는 중일 때만 값이고, 할 일 상태와 타이머는 그대로다.
    public func lifecycleCheckpoint(_ trigger: CheckpointTrigger, _ input: SessionInput) -> StoreBatch? {
        guard trigger == .sleep || trigger == .quit, let id = taskID, let run, case .running = ticked(input) else {
            return nil
        }
        let elapsed = Checkpoint.elapsedMinutes(startedAt: run.startedAt, now: input.now, quantumMin: run.quantumMin)
        return StoreBatch(
            newCheckpoints: [
                NewCheckpoint(taskID: id, notes: .empty, trigger: trigger, elapsedMin: elapsed, createdAt: input.now)
            ])
    }

    /// 노치의 할 일이면 empty(nil), run nil. 커서는 그대로.
    public func taskDropped(_ id: TaskID) -> NotchSession {
        guard id == taskID else { return self }
        return NotchSession(timer: .empty(draft: nil), taskID: nil, previousTaskID: previousTaskID, run: nil)
    }

    /// 할 일 탭 "다음" 표시(R-102). 초안이면 그 할 일, 도는 중·시간 끝이면 지금 할 일을 끝냈을 때 뜰 할 일.
    public func nextMark(_ input: SessionInput) -> TaskID? {
        switch timer {
        case .empty(nil):
            return nil
        case .empty(.some):
            return taskID
        case .running, .expired:
            return PriorityRotateRule.pick(order: PriorityOrder.order(input), after: nil)?.id
        }
    }

    // MARK: - 내부

    private func drafting(_ task: MokaTask, _ input: SessionInput) -> NotchSession {
        var next = self
        guard
            next.timer.apply(.enterTitle(task.title), at: input.now, defaultQuantumMin: input.defaultQuantumMin)
                == .applied
        else { return self }
        next.taskID = task.id
        next.run = nil
        return next
    }

    /// 암묵 tick(끝 시각이 지난 running → expired)을 적용한 타이머.
    private func ticked(_ input: SessionInput) -> NotchTimer {
        var timer = self.timer
        _ = timer.apply(.tick, at: input.now, defaultQuantumMin: input.defaultQuantumMin)
        return timer
    }

    /// 완료·미루기·바꾸기·다시 시작이 기대는 값. 도는 중·시간 끝이 아니면 거부.
    private func buttonContext(_ input: SessionInput) throws(SessionError) -> (
        task: MokaTask, run: RunInfo, expired: Bool
    ) {
        guard let id = taskID, let run, let task = input.tasks.first(where: { $0.id == id }) else {
            throw .notAllowed
        }
        switch ticked(input) {
        case .running: return (task, run, false)
        case .expired: return (task, run, true)
        case .empty: throw .notAllowed
        }
    }

    private func setAside(_ notes: CheckpointNotes, action: UserAction, _ input: SessionInput) throws(SessionError)
        -> SessionStep
    {
        let button = try buttonContext(input)
        var aside = button.task
        aside.status = .todo
        if action == .skip {
            aside.skipCount += 1
        }
        aside.takeNextNote(notes)
        let trigger: CheckpointTrigger = button.expired ? .quantum : (action == .skip ? .skip : .switch)
        let elapsed =
            button.expired
            ? button.run.quantumMin
            : Checkpoint.elapsedMinutes(
                startedAt: button.run.startedAt, now: input.now, quantumMin: button.run.quantumMin)
        return SessionStep(
            session: finished(cursor: aside.id, input),
            batch: StoreBatch(
                updatedTasks: [aside],
                newCheckpoints: [
                    NewCheckpoint(
                        taskID: aside.id, notes: notes, trigger: trigger, elapsedMin: elapsed, createdAt: input.now)
                ],
                newDecisions: [Self.logLine(aside.id, action, input)]))
    }

    /// 버튼 뒤 세션: 타이머는 `.complete`로 빈 상태, 할 일·회차 없음.
    private func finished(cursor: TaskID?, _ input: SessionInput) -> NotchSession {
        var timer = self.timer
        _ = timer.apply(.complete, at: input.now, defaultQuantumMin: input.defaultQuantumMin)
        return NotchSession(timer: timer, taskID: nil, previousTaskID: cursor, run: nil)
    }

    /// 로그 한 줄(spec 003 R-212, data-model §8). 쓸 판단 결과가 없으면 공급자 `fallback`만 남긴다.
    private static func logLine(_ taskID: TaskID, _ action: UserAction, _ input: SessionInput) -> NewDecisionLogEntry {
        let score = input.scoring?.usable[taskID]
        let judgment =
            score.map {
                Judgment(
                    provider: $0.provider, questionVersion: $0.questionVersion, probsJSON: $0.probsJSON,
                    stateHash: $0.stateHash)
            } ?? Judgment(provider: "fallback", questionVersion: nil, probsJSON: nil, stateHash: nil)
        return NewDecisionLogEntry(
            taskID: taskID, judgment: judgment, modelSnapshot: score?.modelSnapshot,
            schedulerChoice: PriorityRotateRule.choice, userAction: action, createdAt: input.now)
    }
}

/// 쓰기가 있는 동작을 저장소에 적용한다. 앱과 `moka-sim`이 같이 쓴다.
public enum SessionCommit {
    /// `apply`가 성공하면 `step.session`을 돌려주고, throw하면 같은 오류를 다시 던진다. 호출자는 그때 세션을 그대로 둔다(R-119).
    public static func commit(_ step: SessionStep, to repository: any TaskRepository) throws -> NotchSession {
        try repository.apply(step.batch)
        return step.session
    }
}

extension MokaTask {
    /// 다음 할 일 줄이 비어 있지 않으면 첫 행동을 그 줄로 바꾼다. 비면 이전 값을 둔다(R-109).
    fileprivate mutating func takeNextNote(_ notes: CheckpointNotes) {
        if !notes.nextNote.isEmpty {
            firstAction = notes.nextNote
        }
    }
}
