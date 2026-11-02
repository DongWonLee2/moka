import Foundation
import MokaCore

/// spec 002 단위 1b 시험이 함께 쓰는 가짜 값. 가짜 할 일만 쓴다.
enum Fake {
    static let seoulZone = TimeZone(identifier: "Asia/Seoul")!
    static let newYorkZone = TimeZone(identifier: "America/New_York")!
    static let seoul = GregorianCalendar.make(timeZone: seoulZone)
    static let newYork = GregorianCalendar.make(timeZone: newYorkZone)
    static let sixAM = DayStart(text: "06:00")!

    /// 지역 시각(초 단위). 시험 달력의 시간대로 읽는다.
    static func at(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0,
        calendar: Calendar = seoul
    ) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    static func day(_ text: String) -> LocalDay {
        LocalDay(text: text)!
    }

    static func weekday(_ number: Int) -> Weekday {
        Weekday(rawValue: number)!
    }

    /// 2027-01-13(수) 12:00 서울.
    static let noon = at(2027, 1, 13, 12, 0)

    static func task(
        _ id: TaskID, status: TaskStatus = .todo, recurrence: Recurrence = .none, weekday: Weekday? = nil,
        cycleDay: LocalDay? = nil, deadline: LocalDay? = nil, estMin: Int? = nil, firstAction: String? = nil,
        skipCount: Int = 0, streak: Int = 0
    ) -> MokaTask {
        MokaTask(
            id: id, title: "가짜 할 일 \(id)", deadline: deadline, estMin: estMin, recurrence: recurrence,
            weekday: weekday, cycleDay: cycleDay, firstAction: firstAction, status: status, skipCount: skipCount,
            streak: streak, createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(id)))
    }

    static func todos(_ ids: ClosedRange<TaskID>) -> [MokaTask] {
        ids.map { task($0) }
    }

    static func input(
        _ tasks: [MokaTask], now: Date = noon, defaultQuantumMin: Int = 25, calendar: Calendar = seoul
    ) -> SessionInput {
        SessionInput(tasks: tasks, now: now, defaultQuantumMin: defaultQuantumMin, calendar: calendar)
    }

    static func notes(_ done: String, _ next: String) -> CheckpointNotes {
        CheckpointNotes(doneNote: done, nextNote: next)
    }
}

/// `apply`가 늘 throw하는 가짜 저장소. 읽기는 안쪽 메모리 저장소를 그대로 보인다.
final class FailingTaskRepository: TaskRepository {
    struct Failure: Error, Equatable {}

    let inner = InMemoryTaskRepository()

    func tasks() throws -> [MokaTask] { try inner.tasks() }
    func insertTask(_ task: NewTask, cycleDay: LocalDay?, at: Date) throws -> MokaTask {
        try inner.insertTask(task, cycleDay: cycleDay, at: at)
    }
    func checkpoints() throws -> [Checkpoint] { try inner.checkpoints() }
    func decisions() throws -> [DecisionLogEntry] { try inner.decisions() }
    func apply(_ batch: StoreBatch) throws { throw Failure() }
}

extension InMemoryTaskRepository {
    /// 가짜 할 일 `count`개를 넣는다(id 1부터, 반복 없음).
    static func seeded(_ count: Int) throws -> InMemoryTaskRepository {
        let repository = InMemoryTaskRepository()
        for index in 1...count {
            _ = try repository.insertTask(
                NewTask(title: "가짜 할 일 \(index)", deadline: nil, estMin: nil, recurrence: .none, weekday: nil),
                cycleDay: nil, at: Fake.noon)
        }
        return repository
    }
}
