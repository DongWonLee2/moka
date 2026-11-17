import AppKit
import Foundation
import MokaCore
import XCTest

/// spec 005 단위 6: 3초 뒤 자동 시작(R-410)과 "내일" 표시(R-423, US3-7). T041.
/// 시각은 주입한 시계로만 앞으로 돌리고 실제 3초를 기다리지 않는다. 메모리 저장소와 가짜 할 일만 쓴다(ADR-0006).
@MainActor
final class AppAutoStartTests: XCTestCase {
    private static let jan13 = LocalDay(text: "2027-01-13")!
    private static let created = AppTestFixture.at(2027, 1, 12, 12, 0)

    private struct Harness {
        let state: AppState
        let repository: FailingAfterStartRepository
        let settings: BudgetWriteFailingSettings
        let clock: TestClock
        let budget: DayBudget?

        /// 같은 저장소로 앱을 다시 켠다.
        @MainActor func relaunched() -> AppState {
            let state = makeState(repository, settings: settings, clock: clock, budgetAnswered: budget == nil)
            state.launch()
            return state
        }
    }

    /// 가짜 할 일을 넣고 켠다. `budget`이 nil이면 그날 상한 없는 하루다. `autoStart`면 켜기 전에 설정을 켜 둔다.
    private static func launched(
        autoStart: Bool = true, budget: DayBudget? = nil, estimates: [Int?] = [nil, nil, nil],
        deadlines: [String?]? = nil
    ) throws -> Harness {
        let repository = FailingAfterStartRepository()
        for (index, estimate) in estimates.enumerated() {
            _ = try repository.insertTask(
                NewTask(
                    title: "가짜 할 일 \(index + 1)", deadline: deadlines?[index].flatMap(LocalDay.init(text:)),
                    estMin: estimate, recurrence: .none, weekday: nil),
                cycleDay: nil, at: created)
        }
        let settings = BudgetWriteFailingSettings()
        if let budget { try CoreSettings.writeDayBudget(budget, to: settings) }
        if autoStart { try CoreSettings.writeAutoStart(true, to: settings) }
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(repository, settings: settings, clock: clock, budgetAnswered: budget == nil)
        state.launch()
        return Harness(state: state, repository: repository, settings: settings, clock: clock, budget: budget)
    }

    private static func record(_ minutes: Int, used: Int) -> DayBudget {
        DayBudget(day: jan13, minutes: minutes, extendedMinutes: 0, usedSeconds: used, more: false)
    }

    private static func draftChip(_ state: AppState) -> Int? {
        guard case .empty(.some(let draft)) = state.timer else { return nil }
        return draft.chipMin
    }

    private static func runningQuantum(_ state: AppState) -> Int? {
        guard case .running(_, let quantumMin, _, _) = state.timer else { return nil }
        return quantumMin
    }

    /// 주입한 시계를 `seconds`만큼 돌리고 자동 시작 일정이 도는 자리를 부른다.
    private static func wait(_ h: Harness, _ seconds: TimeInterval) {
        h.clock.advance(seconds: seconds)
        h.state.autoStartIfDue()
    }

    // MARK: - 3초 뒤 한 번

    func test_FR05_R410_startsOnceThreeSecondsAfterDraft() throws {
        let h = try Self.launched()
        XCTAssertEqual(Self.draftChip(h.state), 25)

        Self.wait(h, 2.9)
        XCTAssertEqual(Self.draftChip(h.state), 25, "3초가 되기 전에는 시작하지 않는다")

        Self.wait(h, 0.1)
        XCTAssertEqual(Self.runningQuantum(h.state), 25, "3초 뒤 칩 값으로 시작한다")
        XCTAssertEqual(h.state.session.run?.startedAt, AppTestFixture.noon.addingTimeInterval(3))

        let started = h.state.session
        Self.wait(h, 10)
        XCTAssertEqual(h.state.session.run, started.run, "도는 중에는 다시 시작하지 않는다")
    }

    func test_FR05_R410_offByDefault() throws {
        let h = try Self.launched(autoStart: false)
        XCTAssertFalse(h.state.autoStartOn)
        Self.wait(h, 60)
        XCTAssertEqual(Self.draftChip(h.state), 25, "기본은 꺼짐이라 시작하지 않는다")
    }

    func test_FR05_R410_inputRearmsDelay() throws {
        let h = try Self.launched()
        Self.wait(h, 2)
        h.state.chooseQuantum(15)

        Self.wait(h, 2.9)
        XCTAssertEqual(Self.draftChip(h.state), 15, "입력부터 다시 3초를 센다")

        Self.wait(h, 0.1)
        XCTAssertEqual(Self.runningQuantum(h.state), 15, "고른 칩 값으로 시작한다")
    }

    func test_FR05_R410_newTitleFieldOrOtherTaskListHoldsAutoStart() throws {
        let h = try Self.launched()
        h.state.beginNewTitle()
        Self.wait(h, 10)
        XCTAssertNotNil(Self.draftChip(h.state), "새 할 일 칸이 열린 동안 시작하지 않는다")
        h.state.cancelNewTitle()

        h.state.beginOtherTask()
        Self.wait(h, 10)
        XCTAssertNotNil(Self.draftChip(h.state), "다른 할 일 목록이 열린 동안 시작하지 않는다")
        h.state.cancelOtherTask()

        Self.wait(h, 3)
        XCTAssertEqual(Self.runningQuantum(h.state), 25, "닫은 뒤 3초가 지나면 시작한다")
    }

    func test_FR05_R410_wakeRestartsCount() throws {
        let center = NotificationCenter()
        let repository = FailingAfterStartRepository()
        _ = try repository.insertTask(
            NewTask(title: "가짜 할 일 1", deadline: nil, estMin: nil, recurrence: .none, weekday: nil), cycleDay: nil,
            at: Self.created)
        let settings = BudgetWriteFailingSettings()
        try CoreSettings.writeAutoStart(true, to: settings)
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(repository, settings: settings, clock: clock, workspaceCenter: center)
        state.launch()
        let h = Harness(state: state, repository: repository, settings: settings, clock: clock, budget: nil)

        h.clock.advance(seconds: 2)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        Self.wait(h, 2.9)
        XCTAssertNotNil(Self.draftChip(state), "깨어나면 다시 3초를 센다")
        Self.wait(h, 0.1)
        XCTAssertEqual(Self.runningQuantum(state), 25)
    }

    func test_FR05_R410_defaultQuantumChangeRestartsCount() throws {
        let h = try Self.launched()
        Self.wait(h, 2)
        try QuantumSettings.writeDefault(15, to: h.settings)
        h.state.defaultQuantumChanged()
        Self.wait(h, 2.9)
        XCTAssertNotNil(Self.draftChip(h.state), "설정에서 기본 작업 시간을 바꾸면 다시 3초를 센다")
        Self.wait(h, 0.1)
        XCTAssertEqual(Self.runningQuantum(h.state), 15)
    }

    // MARK: - 일정(autoStartDue)

    func test_FR05_R410_dueIsDraftShownPlusDelayAndRearmsOnInput() throws {
        let h = try Self.launched()
        XCTAssertEqual(h.state.autoStartDue, AppTestFixture.noon.addingTimeInterval(3), "초안이 뜬 시각 + 3초")
        h.clock.advance(seconds: 1)
        h.state.chooseQuantum(15)
        XCTAssertEqual(h.state.autoStartDue, AppTestFixture.noon.addingTimeInterval(4), "입력하면 다시 건다")
    }

    func test_FR05_R410_dueIsNilWhileConfirmOrFailedOrTried() throws {
        let h = try Self.launched(budget: Self.record(60, used: 50 * 60))
        XCTAssertNotNil(h.state.autoStartDue)
        h.state.chooseQuantum(25)
        XCTAssertNil(h.state.autoStartDue, "늘리기 확인 줄이 열리면 걸지 않는다")

        h.repository.failsApply = true
        XCTAssertFalse(h.state.extendAndStart())
        XCTAssertNil(h.state.autoStartDue, "시작 실패 문구가 떠 있으면 걸지 않는다")

        h.state.chooseQuantum(25)
        XCTAssertNotNil(h.state.autoStartDue)
        Self.wait(h, 3)
        XCTAssertNotNil(Self.draftChip(h.state), "시작 커밋이 실패해 초안에 머문다")
        XCTAssertNil(h.state.autoStartDue, "이미 시도했으면 입력이 있을 때까지 걸지 않는다")
    }

    func test_FR05_R410_dueIsNilWhenOff() throws {
        let h = try Self.launched(autoStart: false)
        XCTAssertNil(h.state.autoStartDue)
    }

    // MARK: - 모드: 카드·질문·오늘 끝

    func test_FR05_R410_noAutoStartOnBudgetQuestionThenStartsAfterAnswer() throws {
        let repository = FailingAfterStartRepository()
        _ = try repository.insertTask(
            NewTask(title: "가짜 할 일 1", deadline: nil, estMin: nil, recurrence: .none, weekday: nil), cycleDay: nil,
            at: Self.created)
        let settings = BudgetWriteFailingSettings()
        try CoreSettings.writeAutoStart(true, to: settings)
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(repository, settings: settings, clock: clock, budgetAnswered: false)
        state.launch()
        let h = Harness(state: state, repository: repository, settings: settings, clock: clock, budget: nil)
        XCTAssertEqual(state.notchMode, .askBudget)

        Self.wait(h, 60)
        XCTAssertEqual(state.notchMode, .askBudget)
        XCTAssertEqual(state.timer, .empty(draft: nil), "가용 시간 질문 중에는 시작하지 않는다")

        XCTAssertTrue(state.answerBudget(120))
        Self.wait(h, 2.9)
        XCTAssertNotNil(Self.draftChip(state), "답한 뒤 뜬 초안에서 다시 3초를 센다")
        Self.wait(h, 0.1)
        XCTAssertEqual(Self.runningQuantum(state), 25)
    }

    func test_FR05_R410_noAutoStartOnDayEnd() throws {
        let h = try Self.launched(budget: Self.record(60, used: 60 * 60))
        XCTAssertEqual(h.state.notchMode, .dayEnd)
        Self.wait(h, 60)
        XCTAssertEqual(h.state.timer, .empty(draft: nil), "오늘 끝에서는 시작하지 않는다")
    }

    func test_FR05_R410_noAutoStartOnCarryCardThenStartsAfterAnswer() throws {
        let h = try Self.launched(estimates: [nil], deadlines: ["2027-01-12"])
        guard case .carryCard(let id, _, _) = h.state.notchMode else {
            return XCTFail("마감이 지난 할 일은 이월 카드에 오른다: \(h.state.notchMode)")
        }
        Self.wait(h, 60)
        XCTAssertEqual(h.state.timer, .empty(draft: nil), "이월 카드 중에는 시작하지 않는다")

        XCTAssertTrue(h.state.answerCarry(.today, for: id))
        Self.wait(h, 2.9)
        XCTAssertNotNil(Self.draftChip(h.state))
        Self.wait(h, 0.1)
        XCTAssertEqual(Self.runningQuantum(h.state), 25, "카드에 답한 뒤 뜬 초안에서 3초 뒤 시작한다")
    }

    // MARK: - 늘리기 확인 줄과 시작 실패(R-421, data-model §11·§17)

    func test_FR05_R410_R421_extendConfirmHoldsAutoStart() throws {
        let h = try Self.launched(budget: Self.record(60, used: 50 * 60))
        XCTAssertEqual(Self.draftChip(h.state), 10, "남은 10분이 칩 처음 값이다")
        h.state.chooseQuantum(25)
        XCTAssertEqual(h.state.extendNeeded, 15)

        Self.wait(h, 60)
        XCTAssertEqual(Self.draftChip(h.state), 25, "확인 줄이 열린 동안에는 시작하지 않는다")
        XCTAssertEqual(h.state.extendNeeded, 15, "확인 줄이 그대로 남는다")
        XCTAssertEqual(CoreSettings.readDayBudget(from: h.settings)?.minutes, 60, "늘리기는 사용자가 눌러야 한다")
    }

    func test_FR05_R410_R421_keepRemainingThenStartsWithRemaining() throws {
        let h = try Self.launched(budget: Self.record(60, used: 50 * 60))
        h.state.chooseQuantum(25)
        Self.wait(h, 5)
        h.state.keepRemaining()
        XCTAssertNil(h.state.extendNeeded)

        Self.wait(h, 2.9)
        XCTAssertEqual(Self.draftChip(h.state), 10)
        Self.wait(h, 0.1)
        XCTAssertEqual(Self.runningQuantum(h.state), 10, "\"10분만 할래요\" 뒤에는 3초 뒤 10분으로 시작한다")
    }

    func test_FR05_R410_startFailedLineHoldsAutoStartUntilUserActs() throws {
        let h = try Self.launched(budget: Self.record(60, used: 50 * 60))
        h.state.chooseQuantum(25)
        h.repository.failsApply = true
        XCTAssertFalse(h.state.extendAndStart())
        XCTAssertTrue(h.state.startFailed)
        XCTAssertNil(h.state.extendNeeded)

        h.repository.failsApply = false
        Self.wait(h, 60)
        XCTAssertEqual(Self.draftChip(h.state), 25, "실패 문구가 떠 있는 동안 다시 시작하지 않는다")
        XCTAssertTrue(h.state.startFailed, "문구가 그대로 남는다")

        h.state.chooseQuantum(25)
        XCTAssertFalse(h.state.startFailed, "사용자가 누르면 문구가 사라진다")
        Self.wait(h, 2.9)
        XCTAssertNotNil(Self.draftChip(h.state))
        Self.wait(h, 0.1)
        XCTAssertEqual(Self.runningQuantum(h.state), 25, "누른 뒤 다시 3초를 세어 시작한다")
    }

    func test_FR05_R410_failedAutoStartDoesNotRetryUntilInput() throws {
        let h = try Self.launched()
        h.repository.failsApply = true
        Self.wait(h, 3)
        XCTAssertNotNil(Self.draftChip(h.state), "시작 커밋이 실패하면 초안에 머문다")

        h.repository.failsApply = false
        Self.wait(h, 60)
        XCTAssertNotNil(Self.draftChip(h.state), "입력이 있을 때까지 다시 시도하지 않는다")

        h.state.chooseQuantum(25)
        Self.wait(h, 3)
        XCTAssertEqual(Self.runningQuantum(h.state), 25)
    }

    // MARK: - 설정 키 auto_start

    func test_FR16_R410_settingKeyAutoStart() throws {
        let h = try Self.launched(autoStart: false)
        XCTAssertTrue(h.state.setAutoStart(true))
        XCTAssertEqual(try h.settings.value(for: "auto_start"), "true")
        XCTAssertTrue(h.state.autoStartOn)
        XCTAssertTrue(h.relaunched().autoStartOn, "다시 켜도 켜짐이다")

        Self.wait(h, 3)
        XCTAssertEqual(Self.runningQuantum(h.state), 25, "켠 뒤 3초가 지나면 시작한다(켠 것도 입력으로 센다)")

        XCTAssertTrue(h.state.setAutoStart(false))
        XCTAssertFalse(h.state.autoStartOn)
        XCTAssertFalse(h.relaunched().autoStartOn)
    }

    // MARK: - US3-7 "내일"(R-423)

    func test_FR10_R423_US3_7_tomorrowMarksTasksPastRemaining() throws {
        let h = try Self.launched(
            autoStart: false, budget: Self.record(120, used: 0), estimates: [40, 60, 30, nil],
            deadlines: ["2027-01-19", "2027-01-20", nil, nil])
        XCTAssertEqual(h.state.ranks, [1: 1, 2: 2, 3: 3])
        XCTAssertEqual(h.state.tomorrowIDs, [3, 4], "노치 순서로 40 + 60 + 30분이 120분을 넘는 할 일부터")
    }

    func test_FR10_R423_noTomorrowWithoutCap() throws {
        let h = try Self.launched(autoStart: false, estimates: [400, 400])
        XCTAssertEqual(h.state.tomorrowIDs, [], "상한이 없는 하루에는 표시하지 않는다")
    }
}
