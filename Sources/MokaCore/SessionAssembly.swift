import Foundation

/// 조립 순서(#72). 켤 때 복구 → 활성화(하루 판정 → 이월 판정 → 모드 → 고르기), 버튼 뒤 커밋 → 다시 읽기 → 모드 → 고르기.
/// 앱 `AppState`와 `moka-sim`이 같이 쓴다. 상태를 들지 않는다. 쓰기가 실패하면 같은 오류를 던지고, 호출자가 세션을
/// 그대로 둔다(R-119). 빈 묶음은 쓰지 않는다. `reload`는 쓴 뒤 `tasks()`를 다시 읽는 호출자의 길이다.
public enum SessionAssembly {
    /// 이월·가용 시간이 켜졌을 때의 하루 값(spec 005 data-model §9·§13). nil이면 꺼짐이고 모드는 늘 세션이다.
    public struct Schedule: Equatable, Sendable {
        public var today: LocalDay
        public var budget: DayBudget?
        public var carryJudgedAt: Date?
        /// 이번 앱 시작에서 R-111이 되돌린 할 일. 이월 판정이 돌면 비운다.
        public var revertedIDs: Set<TaskID>

        public init(today: LocalDay, budget: DayBudget?, carryJudgedAt: Date?, revertedIDs: Set<TaskID>) {
            self.today = today
            self.budget = budget
            self.carryJudgedAt = carryJudgedAt
            self.revertedIDs = revertedIDs
        }
    }

    public struct Activated: Equatable, Sendable {
        public var session: NotchSession
        public var schedule: Schedule?
    }

    /// 켤 때 복구(R-111). 노치에 띄운 할 일(`keeping`)은 빼고 진행 중을 대기로 되돌리고, 되돌린 할 일을 돌려준다.
    public static func recover(
        _ tasks: [MokaTask], keeping notchTaskID: TaskID?, in repository: any TaskRepository,
        reload: () throws -> [MokaTask]
    ) throws -> Set<TaskID> {
        let reverted = LaunchRecovery.revert(tasks.filter { $0.id != notchTaskID })
        _ = try write(StoreBatch(updatedTasks: reverted), over: tasks, in: repository, reload: reload)
        return Set(reverted.map(\.id))
    }

    /// 활성화(research R11): 하루 판정(R-113) → 하루 값이 있으면 이월 판정(R-412) → 모드 → 빈 상태면 고르기.
    /// `input`은 호출자가 채우고, 목록만 쓴 뒤 다시 읽은 것으로 바꾼다.
    public static func activate(
        _ session: NotchSession, _ input: SessionInput, dayStart: DayStart, schedule: Schedule?,
        in repository: any TaskRepository, reload: () throws -> [MokaTask]
    ) throws -> Activated {
        var input = input
        let reset = RecurrenceReset.reset(input.tasks, now: input.now, dayStart: dayStart, calendar: input.calendar)
        input.tasks = try write(StoreBatch(updatedTasks: reset), over: input.tasks, in: repository, reload: reload)
        var schedule = schedule
        if var day = schedule,
            CarryJudgment.needsRun(
                lastJudgedAt: day.carryJudgedAt, now: input.now, dayStart: dayStart, calendar: input.calendar)
        {
            let targets = CarryJudgment.targets(
                CarryJudgmentInput(
                    tasks: input.tasks, checkpoints: try repository.checkpoints(),
                    decisions: try repository.decisions(), lastJudgedAt: day.carryJudgedAt,
                    revertedIDs: day.revertedIDs, now: input.now, dayStart: dayStart, calendar: input.calendar))
            input.tasks = try write(
                CarryJudgment.marking(targets, in: input.tasks), over: input.tasks, in: repository, reload: reload)
            day.carryJudgedAt = input.now
            day.revertedIDs = []
            schedule = day
        }
        return Activated(session: settle(session, input, schedule: schedule), schedule: schedule)
    }

    /// 버튼 뒤 쓰기: `SessionCommit` → `tasks()` 다시 읽기. 고르기(`settle`)는 호출자가 화면 전이를 맞춘 뒤 부른다.
    public static func commit(
        _ step: SessionStep, in repository: any TaskRepository, reload: () throws -> [MokaTask]
    ) throws -> NotchSession {
        let session = try SessionCommit.commit(step, to: repository)
        _ = try reload()
        return session
    }

    /// 모드 판정 → 카드·질문·오늘 끝이면 초안을 비우고, 세션이면 빈 상태에서 고른다(data-model §12).
    public static func settle(_ session: NotchSession, _ input: SessionInput, schedule: Schedule?) -> NotchSession {
        if mode(session.timer, tasks: input.tasks, schedule: schedule).clearsDraft { return session.clearingDraft() }
        return session.picked(input)
    }

    /// 꺼짐이면 늘 세션. 켜짐이면 data-model §12 표.
    public static func mode(_ timer: NotchTimer, tasks: [MokaTask], schedule: Schedule?) -> NotchMode {
        guard let schedule else { return .session }
        return NotchMode.of(
            storageAvailable: true, timer: timer, tasks: tasks, budget: schedule.budget, today: schedule.today)
    }

    private static func write(
        _ batch: StoreBatch, over tasks: [MokaTask], in repository: any TaskRepository,
        reload: () throws -> [MokaTask]
    ) throws -> [MokaTask] {
        guard batch != .empty else { return tasks }
        try repository.apply(batch)
        return try reload()
    }
}
