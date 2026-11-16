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
    /// 스케줄러 메모리(spec 005 data-model §8). 저장하지 않음.
    public var memory: SchedulerMemory

    public init(
        timer: NotchTimer, taskID: TaskID?, previousTaskID: TaskID?, run: RunInfo?, memory: SchedulerMemory = .empty
    ) {
        self.timer = timer
        self.taskID = taskID
        self.previousTaskID = previousTaskID
        self.run = run
        self.memory = memory
    }
}

/// 시작한 순간의 값. 시간 끝(`expired`)이 되면 spec 001 타이머는 작업 시간을 버리므로 세션이 따로 든다.
public struct RunInfo: Equatable, Sendable {
    public var startedAt: Date
    public var quantumMin: Int
    /// 작업 시간을 시작한 하루(spec 005 data-model §11). "N분 더"는 처음 시작의 값을 물려받는다. 하루를 모르면 nil.
    public var budgetDay: LocalDay?

    public init(startedAt: Date, quantumMin: Int, budgetDay: LocalDay? = nil) {
        self.startedAt = startedAt
        self.quantumMin = quantumMin
        self.budgetDay = budgetDay
    }
}

/// 동작마다 넣는 입력. 호출자(앱 `AppState`, `moka-sim`)가 채운다.
public struct SessionInput: Sendable {
    /// 저장소의 지금 목록(`tasks()`).
    public var tasks: [MokaTask]
    public var now: Date
    public var defaultQuantumMin: Int
    /// 추가 시간. 시간 끝 칩을 채운다(#151).
    public var extendMin: Int
    /// `GregorianCalendar.make(timeZone:)`.
    public var calendar: Calendar
    /// 노치 순서에 쓸 판단 결과(spec 003 data-model §1). nil이면 모든 할 일이 점수 없음(마감 순).
    public var scoring: SessionScoring?
    /// 하루 경계(spec 002 R-114)로 본 오늘. nil이면 하루에 기대는 규칙(몫 상태 비우기, 쓴 시간의 하루)을 쓰지 않는다.
    public var today: LocalDay?
    /// 그 하루에 시작한 작업 시간이 없음(spec 005 R-406).
    public var isWarmup: Bool
    /// 시작 전 칩 상한: 오늘 가용 시간의 남은 분(상한이 걸렸을 때만, R-409·R-421).
    public var draftChipCap: Int?
    /// 시간 끝과 오늘 끝이 겹침(`NotchMode.expiredDayEnd`). 세 버튼의 체크포인트 계기가 `day_end`다(R-422).
    public var dayEndExpired: Bool

    public init(
        tasks: [MokaTask], now: Date, defaultQuantumMin: Int, extendMin: Int, calendar: Calendar,
        scoring: SessionScoring? = nil, today: LocalDay? = nil, isWarmup: Bool = false, draftChipCap: Int? = nil,
        dayEndExpired: Bool = false
    ) {
        self.tasks = tasks
        self.now = now
        self.defaultQuantumMin = defaultQuantumMin
        self.extendMin = extendMin
        self.calendar = calendar
        self.scoring = scoring
        self.today = today
        self.isWarmup = isWarmup
        self.draftChipCap = draftChipCap
        self.dayEndExpired = dayEndExpired
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
    /// 커밋한 뒤 그 하루의 가용 시간 기록에 반영할 쓴 시간(spec 005 data-model §11, Q4-B). 하루를 모르면 nil.
    public var budgetUse: BudgetUse?

    public init(session: NotchSession, batch: StoreBatch, budgetUse: BudgetUse? = nil) {
        self.session = session
        self.batch = batch
        self.budgetUse = budgetUse
    }
}

/// data-model §4.2 표의 "거부".
public enum SessionError: Error, Equatable, Sendable { case notAllowed }

extension NotchSession {
    /// empty(nil), 나머지 nil.
    public static let initial = NotchSession(timer: .empty(draft: nil), taskID: nil, previousTaskID: nil, run: nil)

    /// 고르기(spec 005 R-403·R-406·R-408). empty(nil)일 때만 바뀐다. 바꾸기·미루기 뒤 방금 할 일(`previousTaskID`)은
    /// 그 고르기에서 뺀다. 초안의 칩은 그 순간의 기본값이고 `draftChipCap`이 있으면 그 이하다.
    public func picked(_ input: SessionInput) -> NotchSession {
        guard timer == .empty(draft: nil) else { return self }
        let result = SchedulerPick.pick(pickInput(input, excluded: previousTaskID))
        guard let id = result.taskID, let task = input.tasks.first(where: { $0.id == id }) else { return self }
        var next = drafting(task, input)
        next.memory = result.memory
        next.memory.pickedBy = result.rule
        return next
    }

    /// 빠른 입력 둘째 단계. 빈 상태·초안에서만 받는다(초안이면 칩 유지). 도는 중·시간 끝은 그대로.
    /// 로그 이름은 앞 초안의 이름, 없으면 `weighted_rotate_v1`이다(research R12).
    public func addedTask(_ task: MokaTask, _ input: SessionInput) -> NotchSession {
        guard case .empty = timer else { return self }
        var next = drafting(task, input)
        next.memory.pickedBy = memory.pickedBy ?? .weightedRotateV1
        return next
    }

    /// 이월 카드·가용 시간 질문·오늘 끝이 되면 초안을 비운다(spec 005 data-model §12). 커서와 몫 상태는 그대로다.
    public func clearingDraft() -> NotchSession {
        guard case .empty(.some) = timer else { return self }
        var next = self
        next.timer = .empty(draft: nil)
        next.taskID = nil
        next.memory.pickedBy = nil
        return next
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
        guard
            next.timer.apply(
                .start, at: input.now, defaultQuantumMin: input.defaultQuantumMin, extendMin: input.extendMin)
                == .applied,
            case .running(_, let quantumMin, let startedAt, _) = next.timer
        else { throw .notAllowed }
        next.run = RunInfo(startedAt: startedAt, quantumMin: quantumMin, budgetDay: input.today)
        var active = task
        active.status = .active
        return SessionStep(
            session: next, batch: StoreBatch(updatedTasks: [active]),
            budgetUse: input.today.map { BudgetUse(day: $0, seconds: quantumMin * 60) })
    }

    /// 완료. 도는 중이면 `notes`는 nil이어야 하고 체크포인트가 없다. 시간 끝이면 두 줄(nil이면 빈 두 줄)을 계기
    /// `quantum`(오늘 끝과 겹치면 `day_end`) 체크포인트로 남긴다. 이월 답 대기 표시를 지운다(R-417). 커서는 nil.
    public func complete(_ notes: CheckpointNotes?, _ input: SessionInput) throws(SessionError) -> SessionStep {
        let button = try buttonContext(input)
        if !button.expired, notes != nil { throw .notAllowed }
        var done = button.task
        done.status = .done
        done.dueDecision = false
        if done.recurrence != .none {
            done.streak += 1
        }
        var checkpoints: [NewCheckpoint] = []
        if button.expired {
            let notes = notes ?? .empty
            done.takeNextNote(notes)
            checkpoints = [
                NewCheckpoint(
                    taskID: done.id, notes: notes, trigger: expiredTrigger(input), elapsedMin: button.run.quantumMin,
                    createdAt: input.now)
            ]
        }
        return SessionStep(
            session: finished(cursor: nil, input),
            batch: StoreBatch(
                updatedTasks: [done], newCheckpoints: checkpoints,
                newDecisions: [Self.logLine(done.id, .done, input, choice: loggedChoice)]),
            budgetUse: refund(button, input))
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
    /// 쓴 시간은 처음 시작한 하루(`budgetDay`)에 더한다. 고르기가 아니라 스케줄러 메모리는 그대로다.
    public func restart(_ notes: CheckpointNotes, quantumMin: Int, _ input: SessionInput) throws(SessionError)
        -> SessionStep
    {
        let button = try buttonContext(input)
        guard button.expired else { throw .notAllowed }
        var next = self
        next.timer = ticked(input)
        guard
            next.timer.apply(
                .chooseQuantum(quantumMin), at: input.now, defaultQuantumMin: input.defaultQuantumMin,
                extendMin: input.extendMin)
                == .applied,
            next.timer.apply(
                .start, at: input.now, defaultQuantumMin: input.defaultQuantumMin, extendMin: input.extendMin)
                == .applied
        else { throw .notAllowed }
        next.run = RunInfo(startedAt: input.now, quantumMin: quantumMin, budgetDay: button.run.budgetDay)
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
                ]),
            budgetUse: button.run.budgetDay.map { BudgetUse(day: $0, seconds: quantumMin * 60) })
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

    /// 도는 중 종료(`.quit`)면 끝 시각까지 남은 초를 돌려준다(spec 005 data-model §11). 잠자기는 타이머가 계속
    /// 도는 것으로 보므로 돌려주지 않는다.
    public func lifecycleRefund(_ trigger: CheckpointTrigger, _ input: SessionInput) -> BudgetUse? {
        guard trigger == .quit, let day = run?.budgetDay, case .running(_, _, _, let endsAt) = ticked(input) else {
            return nil
        }
        return BudgetUse(day: day, seconds: -DayBudget.refundSeconds(endsAt: endsAt, now: input.now))
    }

    /// 노치의 할 일이면 empty(nil), run nil. 커서와 몫 상태는 그대로.
    public func taskDropped(_ id: TaskID) -> NotchSession {
        guard id == taskID else { return self }
        var next = NotchSession(timer: .empty(draft: nil), taskID: nil, previousTaskID: previousTaskID, run: nil)
        next.memory = memory
        next.memory.pickedBy = nil
        return next
    }

    /// 할 일 탭 "다음" 표시(spec 005 R-434, research R15). 초안이면 그 할 일, 도는 중·시간 끝이면 지금 할 일을 뺀
    /// 다음 고르기를 상태를 바꾸지 않고 미리 돌린 결과. 빈 상태는 nil(고를 후보가 있으면 이미 초안이다).
    public func nextMark(_ input: SessionInput) -> TaskID? {
        switch timer {
        case .empty(nil):
            return nil
        case .empty(.some):
            return taskID
        case .running, .expired:
            return SchedulerPick.pick(pickInput(input, excluded: taskID)).taskID
        }
    }

    // MARK: - 내부

    private func pickInput(_ input: SessionInput, excluded: TaskID?) -> PickInput {
        let order = PriorityOrder.order(input)
        var priorities: [TaskID: Double] = [:]
        if let scoring = input.scoring {
            for task in order {
                guard let score = scoring.usable[task.id] else { continue }
                priorities[task.id] = ScoreRules.priority(
                    score, task: task, today: scoring.today, thresholds: scoring.thresholds, calendar: input.calendar)
            }
        }
        return PickInput(
            order: order, scores: input.scoring?.usable ?? [:], priorities: priorities, excluded: excluded,
            isWarmup: input.isWarmup, memory: memory.on(input.today))
    }

    /// 버튼 줄의 `scheduler_choice`. 노치에 띄운 규칙이 없으면 가중 순환이다.
    private var loggedChoice: SchedulerChoice { memory.pickedBy ?? .weightedRotateV1 }

    private func expiredTrigger(_ input: SessionInput) -> CheckpointTrigger {
        input.dayEndExpired ? .dayEnd : .quantum
    }

    /// 도는 중에 끝낸 작업 시간이 돌려줄 쓴 시간. 시간 끝이면 없다.
    private func refund(_ button: (task: MokaTask, run: RunInfo, expired: Bool), _ input: SessionInput) -> BudgetUse? {
        guard !button.expired, let day = button.run.budgetDay, case .running(_, _, _, let endsAt) = timer else {
            return nil
        }
        return BudgetUse(day: day, seconds: -DayBudget.refundSeconds(endsAt: endsAt, now: input.now))
    }

    private func drafting(_ task: MokaTask, _ input: SessionInput) -> NotchSession {
        var next = self
        let chip = QuantumChip.cap(chipMin: input.defaultQuantumMin, remainingMinutes: input.draftChipCap)
        guard
            next.timer.apply(.enterTitle(task.title), at: input.now, defaultQuantumMin: chip, extendMin: input.extendMin)
                == .applied
        else { return self }
        next.taskID = task.id
        next.run = nil
        return next
    }

    /// 암묵 tick(끝 시각이 지난 running → expired)을 적용한 타이머.
    private func ticked(_ input: SessionInput) -> NotchTimer {
        var timer = self.timer
        _ = timer.apply(.tick, at: input.now, defaultQuantumMin: input.defaultQuantumMin, extendMin: input.extendMin)
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
        let trigger: CheckpointTrigger = button.expired ? expiredTrigger(input) : (action == .skip ? .skip : .switch)
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
                newDecisions: [Self.logLine(aside.id, action, input, choice: loggedChoice)]),
            budgetUse: refund(button, input))
    }

    /// 버튼 뒤 세션: 타이머는 `.complete`로 빈 상태, 할 일·회차 없음. 몫 상태는 남기고 띄운 규칙은 내린다.
    private func finished(cursor: TaskID?, _ input: SessionInput) -> NotchSession {
        var timer = self.timer
        _ = timer.apply(
            .complete, at: input.now, defaultQuantumMin: input.defaultQuantumMin, extendMin: input.extendMin)
        var next = NotchSession(timer: timer, taskID: nil, previousTaskID: cursor, run: nil, memory: memory)
        next.memory.pickedBy = nil
        return next
    }

    /// 로그 한 줄(spec 003 R-212, data-model §8). 쓸 판단 결과가 없으면 공급자 `fallback`만 남긴다.
    static func logLine(_ taskID: TaskID, _ action: UserAction, _ input: SessionInput, choice: SchedulerChoice)
        -> NewDecisionLogEntry
    {
        let score = input.scoring?.usable[taskID]
        let judgment =
            score.map {
                Judgment(
                    provider: $0.provider, questionVersion: $0.questionVersion, probsJSON: $0.probsJSON,
                    stateHash: $0.stateHash)
            } ?? Judgment(provider: "fallback", questionVersion: nil, probsJSON: nil, stateHash: nil)
        return NewDecisionLogEntry(
            taskID: taskID, judgment: judgment, modelSnapshot: score?.modelSnapshot,
            schedulerChoice: choice, userAction: action, createdAt: input.now)
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
