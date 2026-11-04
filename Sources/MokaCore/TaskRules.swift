import Foundation

/// 노치 고르기(R-104, data-model §5.1). 스케줄러(마일스톤 4) 전 임시 규칙이다.
public enum RotateByIDRule {
    public static let choice = SchedulerChoice.rotateByIDV0

    /// 대기 할 일 가운데 `previous`보다 큰 id 중 가장 작은 것. 없으면 처음(가장 작은 id)으로 돌아간다.
    public static func pick(from tasks: [MokaTask], after previous: TaskID?) -> MokaTask? {
        let candidates = tasks.filter { $0.status == .todo }.sorted { $0.id < $1.id }
        guard let previous else { return candidates.first }
        return candidates.first { $0.id > previous } ?? candidates.first
    }
}

/// 재시작 복구(R-111, data-model §5.2). 앱 시작마다 한 번, 하루 판정보다 먼저 돈다.
public enum LaunchRecovery {
    /// 진행 중인 할 일을 모두 대기로 바꾼 목록(바뀐 것만).
    public static func revert(_ tasks: [MokaTask]) -> [MokaTask] {
        tasks.filter { $0.status == .active }.map { task in
            var reverted = task
            reverted.status = .todo
            return reverted
        }
    }
}

/// 반복 리셋(R-113, data-model §5.3).
public enum RecurrenceReset {
    /// 지금 주기의 첫 하루. 반복 없음이면 nil.
    public static func cycleStart(for task: MokaTask, today: LocalDay, calendar: Calendar) -> LocalDay? {
        cycleStart(recurrence: task.recurrence, weekday: task.weekday, today: today, calendar: calendar)
    }

    /// 바뀐 할 일만 돌려준다.
    public static func reset(_ tasks: [MokaTask], now: Date, dayStart: DayStart, calendar: Calendar) -> [MokaTask] {
        let today = DayBoundary.day(containing: now, dayStart: dayStart, calendar: calendar)
        return tasks.compactMap { task in
            guard task.status == .todo || task.status == .done, let cycleDay = task.cycleDay,
                let current = cycleStart(for: task, today: today, calendar: calendar), cycleDay < current
            else { return nil }
            let previous = current.adding(days: task.recurrence == .weekly ? -7 : -1, calendar: calendar)
            var reset = task
            if !(task.status == .done && cycleDay == previous) {
                reset.streak = 0
            }
            reset.status = .todo
            reset.skipCount = 0
            reset.cycleDay = current
            return reset
        }
    }

    static func cycleStart(recurrence: Recurrence, weekday: Weekday?, today: LocalDay, calendar: Calendar)
        -> LocalDay?
    {
        switch recurrence {
        case .none:
            return nil
        case .daily:
            return today
        case .weekly:
            guard let weekday else { return nil }
            let back = (today.weekday(calendar: calendar).rawValue - weekday.rawValue + 7) % 7
            return today.adding(days: -back, calendar: calendar)
        }
    }
}

/// 할 일 쓰기 규칙(R-101, R-113, data-model §5.8).
public enum TaskWriteRules {
    /// 검증하고(반복 할 일은 마감 없음), .weekly인데 weekday가 nil이면 등록 순간이 속한 하루의 요일로 채우고,
    /// 반복이면 cycleDay = 지금 주기 첫 하루.
    public static func prepareNew(_ task: NewTask, now: Date, dayStart: DayStart, calendar: Calendar) -> (
        task: NewTask, cycleDay: LocalDay?
    )? {
        guard let title = MokaTask.normalizedTitle(task.title), MokaTask.isValidEstMin(task.estMin),
            task.recurrence == .none || task.deadline == nil
        else { return nil }
        let today = DayBoundary.day(containing: now, dayStart: dayStart, calendar: calendar)
        var prepared = task
        prepared.title = title
        if task.recurrence == .weekly, task.weekday == nil {
            prepared.weekday = today.weekday(calendar: calendar)
        }
        guard MokaTask.isValidWeekday(prepared.weekday, recurrence: prepared.recurrence) else { return nil }
        let cycleDay = RecurrenceReset.cycleStart(
            recurrence: prepared.recurrence, weekday: prepared.weekday, today: today, calendar: calendar)
        return (prepared, cycleDay)
    }

    /// 고침 결과. 검증에 실패하면 nil(저장 안 함). dropped는 고칠 수 없다(nil). 반복이 되면 마감을 지운다.
    public static func applyEdit(_ task: MokaTask, _ edit: TaskEdit, now: Date, dayStart: DayStart, calendar: Calendar)
        -> MokaTask?
    {
        guard task.status != .dropped else { return nil }
        var edited = task

        if let rawTitle = edit.title {
            guard let title = MokaTask.normalizedTitle(rawTitle) else { return nil }
            edited.title = title
        }
        switch edit.deadline {
        case .keep: break
        case .set(let day): edited.deadline = day
        case .clear: edited.deadline = nil
        }
        switch edit.estMin {
        case .keep: break
        case .set(let minutes):
            guard MokaTask.isValidEstMin(minutes) else { return nil }
            edited.estMin = minutes
        case .clear: edited.estMin = nil
        }

        let today = DayBoundary.day(containing: now, dayStart: dayStart, calendar: calendar)
        let recurrence = edit.recurrence ?? task.recurrence
        let weekday: Weekday?
        if recurrence == .weekly {
            weekday = edit.weekday ?? task.weekday ?? today.weekday(calendar: calendar)
        } else {
            guard edit.weekday == nil else { return nil }
            weekday = nil
        }
        if recurrence != .none {
            if case .set = edit.deadline { return nil }
            edited.deadline = nil
        }
        if recurrence != task.recurrence || weekday != task.weekday {
            edited.recurrence = recurrence
            edited.weekday = weekday
            edited.cycleDay = RecurrenceReset.cycleStart(
                recurrence: recurrence, weekday: weekday, today: today, calendar: calendar)
            edited.streak = 0
        }
        return edited
    }
}
