import Foundation
import MokaCore
import XCTest

/// #72: 켤 때·활성화·버튼 뒤 순서를 `SessionAssembly`로 옮기기 전후에 같은지 고정한다. 쓰기가 실패하면 고르지 않고,
/// 앱은 이월 판정을 아직 돌리지 않는다(spec 005 plan 단위 3 전). 가짜 할 일만 쓴다(ADR-0006).
@MainActor
final class AppAssemblyTests: XCTestCase {
    private static let noon = AppTestFixture.noon

    private static func insert(
        _ title: String, deadline: LocalDay? = nil, into repository: InMemoryTaskRepository
    ) throws -> MokaTask {
        try repository.insertTask(
            NewTask(title: title, deadline: deadline, estMin: nil, recurrence: .none, weekday: nil), cycleDay: nil,
            at: noon)
    }

    func test_FR07_R111_issue72_failedLaunchRecoveryWriteDoesNotPick() throws {
        let repository = FailingAfterStartRepository()
        var stale = try Self.insert("가짜 할 일 1", into: repository.inner)
        _ = try Self.insert("가짜 할 일 2", into: repository.inner)
        stale.status = .active
        try repository.inner.apply(StoreBatch(updatedTasks: [stale]))
        let state = makeState(repository)
        repository.failsApply = true

        state.launch()

        XCTAssertEqual(state.session, .initial, "복구 쓰기가 실패하면 하루 판정·고르기로 가지 않는다")
        XCTAssertNil(state.pickedAt)
        XCTAssertEqual(try repository.inner.tasks().map(\.status), [.active, .todo])
    }

    func test_FR09_R113_issue72_failedActivateResetWriteDoesNotPickAndKeepsTasks() throws {
        let repository = FailingAfterStartRepository()
        var daily = try repository.inner.insertTask(
            NewTask(title: "가짜 매일 할 일", deadline: nil, estMin: nil, recurrence: .daily, weekday: nil),
            cycleDay: LocalDay(text: "2027-01-13"), at: Self.noon)
        daily.status = .done
        try repository.inner.apply(StoreBatch(updatedTasks: [daily]))
        let clock = TestClock(Self.noon)
        let state = makeState(repository, clock: clock)
        state.launch()
        XCTAssertEqual(state.session, .initial)
        let before = state.tasks

        clock.advance(minutes: 19 * 60)  // 2027-01-14 07:00
        repository.failsApply = true
        state.activate()

        XCTAssertEqual(state.session, .initial, "리셋 쓰기가 실패하면 고르지 않는다")
        XCTAssertNil(state.pickedAt)
        XCTAssertEqual(state.tasks, before, "리셋 쓰기가 실패하면 할 일 목록을 그대로 둔다")
        XCTAssertEqual(try repository.inner.tasks(), before)
    }

    func test_FR05_R104_issue72_failedCompleteCommitKeepsSessionAndDoesNotPick() throws {
        let repository = FailingAfterStartRepository()
        _ = try Self.insert("가짜 할 일 1", into: repository.inner)
        _ = try Self.insert("가짜 할 일 2", into: repository.inner)
        let clock = TestClock(Self.noon)
        let state = makeState(repository, clock: clock)
        state.launch()
        state.start()
        let running = state.session
        let pickedAt = state.pickedAt
        clock.advance(minutes: 10)
        repository.failsApply = true

        state.complete()

        XCTAssertEqual(state.session, running, "커밋이 실패하면 세션을 그대로 두고 다음을 고르지 않는다")
        XCTAssertEqual(state.pickedAt, pickedAt)
        XCTAssertEqual(state.lastRejectReason, .storageFailed)
        XCTAssertEqual(try repository.inner.tasks().map(\.status), [.active, .todo])
    }

    func test_FR07_issue72_launchAndActivateDoNotRunCarryJudgment() throws {
        let repository = InMemoryTaskRepository()
        _ = try Self.insert("가짜 마감 지난 할 일", deadline: LocalDay(text: "2027-01-10"), into: repository)
        var reverted = try Self.insert("가짜 진행 중 할 일", into: repository)
        reverted.status = .active
        try repository.apply(StoreBatch(updatedTasks: [reverted]))
        let clock = TestClock(Self.noon)
        let state = makeState(repository, clock: clock)

        state.launch()
        XCTAssertEqual(try repository.tasks().map(\.dueDecision), [false, false], "켤 때 이월 판정을 돌리지 않는다")

        clock.advance(minutes: 24 * 60)
        state.activate()
        XCTAssertEqual(try repository.tasks().map(\.dueDecision), [false, false], "활성화에서 이월 판정을 돌리지 않는다")
        XCTAssertEqual(state.tasks.map(\.dueDecision), [false, false])
    }
}
