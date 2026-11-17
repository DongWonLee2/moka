import Foundation
import MokaCore
import XCTest

/// spec 005 단위 4: 가용 시간 질문과 오늘 끝(US3, T031). 자동 시작(R-410)은 단위 6이라 꺼진 상태다.
/// 메모리 저장소와 주입한 시계만 쓴다. 실제 시간을 기다리지 않는다. 가짜 할 일만 쓴다(ADR-0006).
@MainActor
final class AppBudgetTests: XCTestCase {
    private static let jan13 = LocalDay(text: "2027-01-13")!
    private static let jan14 = LocalDay(text: "2027-01-14")!
    private static let created = AppTestFixture.at(2027, 1, 12, 12, 0)

    private struct Harness {
        let state: AppState
        let repository: InMemoryTaskRepository
        let settings: BudgetWriteFailingSettings
        let clock: TestClock

        var stored: DayBudget? { CoreSettings.readDayBudget(from: settings) }

        /// 같은 저장소로 앱을 다시 켠다.
        func relaunched() -> AppState {
            let state = makeState(repository, settings: settings, clock: clock, budgetAnswered: false)
            state.launch()
            return state
        }
    }

    /// 가짜 할 일 셋을 넣고 `budget`을 미리 써 둔 뒤 켠다. `budget`이 nil이면 오늘 기록이 없다.
    private static func launched(
        budget: DayBudget? = nil, at start: Date = AppTestFixture.noon, tasks: Int = 3
    ) throws -> Harness {
        let repository = InMemoryTaskRepository()
        for index in 0..<tasks {
            _ = try repository.insertTask(
                NewTask(
                    title: "가짜 할 일 \(["A", "B", "C"][index])", deadline: nil, estMin: nil, recurrence: .none,
                    weekday: nil),
                cycleDay: nil, at: created)
        }
        let settings = BudgetWriteFailingSettings()
        if let budget { try CoreSettings.writeDayBudget(budget, to: settings) }
        let clock = TestClock(start)
        let state = makeState(repository, settings: settings, clock: clock, budgetAnswered: false)
        state.launch()
        return Harness(state: state, repository: repository, settings: settings, clock: clock)
    }

    private static func record(_ minutes: Int, used: Int, day: LocalDay = jan13, more: Bool = false) -> DayBudget {
        DayBudget(day: day, minutes: minutes, extendedMinutes: 0, usedSeconds: used, more: more)
    }

    private static func draftChip(_ state: AppState) -> Int? {
        guard case .empty(.some(let draft)) = state.timer else { return nil }
        return draft.chipMin
    }

    private static func expiredChip(_ state: AppState) -> Int? {
        guard case .expired(_, let chipMin, _) = state.timer else { return nil }
        return chipMin
    }

    // MARK: - US3-1: 질문, 답하기 전에는 고르지 않음

    func test_FR10_R419_US3_1_asksBeforePickingAndAnswerPicks() throws {
        let h = try Self.launched()
        XCTAssertEqual(h.state.notchMode, .askBudget)
        XCTAssertEqual(h.state.timer, .empty(draft: nil), "답하기 전에는 할 일을 고르지 않는다")
        XCTAssertNil(h.state.nextMarkID)

        XCTAssertTrue(h.state.answerBudget(120))
        XCTAssertEqual(h.stored, DayBudget.answered(day: Self.jan13, minutes: 120))
        XCTAssertEqual(h.state.notchMode, .session)
        XCTAssertNotNil(Self.draftChip(h.state), "답하면 바로 첫 할 일이 뜬다")
        XCTAssertTrue(try h.repository.decisions().isEmpty, "가용 시간 답은 행동 로그 줄이 없다(R-416)")
    }

    func test_FR10_R419_answerOnlyInAskMode() throws {
        let h = try Self.launched(budget: Self.record(120, used: 0))
        XCTAssertFalse(h.state.answerBudget(60), "오늘 기록이 있으면 다시 답하지 않는다")
        XCTAssertEqual(h.stored?.minutes, 120)
    }

    func test_FR10_R419_quickInputBeforeAnswerOnlySaves() throws {
        let h = try Self.launched()
        h.state.beginNewTitle()
        XCTAssertTrue(h.state.isEnteringNewTitle, "질문 화면에서도 \"+ 새 할 일\"로 적을 수 있다")
        h.state.enterTitle("가짜 할 일 D")
        XCTAssertEqual(try h.repository.tasks().map(\.title).last, "가짜 할 일 D")
        XCTAssertEqual(h.state.timer, .empty(draft: nil), "질문 전에는 저장만 하고 초안으로 띄우지 않는다")
        XCTAssertEqual(h.state.notchMode, .askBudget)
        XCTAssertFalse(h.state.isEnteringNewTitle)
    }

    func test_FR10_R419_failedAnswerWriteKeepsQuestionAndShowsLine() throws {
        let h = try Self.launched()
        h.settings.failsBudgetWrite = true
        XCTAssertFalse(h.state.answerBudget(120))
        XCTAssertEqual(h.state.notchMode, .askBudget, "질문은 그대로")
        XCTAssertTrue(h.state.budgetAnswerFailed)
        XCTAssertEqual(BudgetViewText.answerFailed, "답을 저장하지 못했어요. 다시 해 주세요.")

        h.settings.failsBudgetWrite = false
        XCTAssertTrue(h.state.answerBudget(120))
        XCTAssertFalse(h.state.budgetAnswerFailed)
    }

    // MARK: - 직접 적기(R-419, data-model §11)

    func test_FR10_R419_customOpensWithFocusAndHalfHourAnswers() throws {
        let h = try Self.launched()
        h.state.beginBudgetCustom()
        XCTAssertEqual(h.state.budgetCustomText, "")
        XCTAssertTrue(h.state.takeBudgetFocusRequest(), "칸이 열리면 포커스가 간다")
        XCTAssertFalse(h.state.takeBudgetFocusRequest())
        XCTAssertEqual(h.state.budgetCustomIssue, .empty)
        XCTAssertFalse(h.state.submitBudgetCustom(), "빈 칸이면 정하기와 Enter가 꺼진다")

        h.state.editBudgetCustom("1.5")
        XCTAssertNil(h.state.budgetCustomIssue)
        XCTAssertTrue(h.state.submitBudgetCustom())
        XCTAssertEqual(h.stored?.minutes, 90)
        XCTAssertNil(h.state.budgetCustomText)
    }

    func test_FR10_R419_customErrorsBlockAnswer() throws {
        let h = try Self.launched()
        h.state.beginBudgetCustom()
        let cases: [(String, BudgetInputIssue, String)] = [
            ("abc", .notNumber, "시간은 숫자로 적어 주세요. 예: 1.5"),
            ("2.3", .notHalfHour, "30분 단위로 적어 주세요. 예: 2 또는 2.5"),
            ("0", .belowMin, "30분(0.5)부터 정할 수 있어요"),
            ("17", .aboveMax, "16시간까지 정할 수 있어요"),
        ]
        for (text, issue, message) in cases {
            h.state.editBudgetCustom(text)
            XCTAssertEqual(h.state.budgetCustomIssue, issue, text)
            XCTAssertEqual(h.state.budgetCustomIssue?.message, message, text)
            XCTAssertFalse(h.state.submitBudgetCustom(), text)
        }
        XCTAssertNil(h.stored, "틀린 값은 쓰지 않는다")
        XCTAssertEqual(h.state.notchMode, .askBudget)
    }

    func test_FR10_R419_choosingChoiceClosesCustomAndAnswers() throws {
        let h = try Self.launched()
        h.state.beginBudgetCustom()
        h.state.editBudgetCustom("2.3")
        XCTAssertTrue(h.state.answerBudget(240))
        XCTAssertNil(h.state.budgetCustomText)
        XCTAssertEqual(h.stored?.minutes, 240)
    }

    // MARK: - US3-2, 2a: 시작 전 칩 상한과 늘리기

    func test_FR10_R409_US3_2_draftChipIsCappedToRemaining() throws {
        let h = try Self.launched(budget: Self.record(120, used: 110 * 60))
        XCTAssertEqual(Self.draftChip(h.state), 10, "칩은 남은 10분보다 길게 채워지지 않는다")
        XCTAssertEqual(h.state.draftCapNote, "오늘 남은 시간은 10분이에요. 더 길게 고르면 오늘 시간을 늘릴지 물어요.")
        XCTAssertNil(h.state.extendNeeded)
    }

    func test_FR10_R409_draftCapNoteHiddenWhenRemainingIsLonger() throws {
        let h = try Self.launched(budget: Self.record(120, used: 0))
        XCTAssertEqual(Self.draftChip(h.state), 25)
        XCTAssertNil(h.state.draftCapNote, "남은 시간이 기본 작업 시간보다 길면 안내 줄이 없다")
    }

    func test_FR10_R421_US3_2a_longerChipAsksToExtendThenStarts() throws {
        let h = try Self.launched(budget: Self.record(120, used: 110 * 60))
        h.state.chooseQuantum(25)
        XCTAssertEqual(h.state.extendNeeded, 15, "남은 분보다 긴 프리셋도 누를 수 있고 확인 줄이 뜬다")
        h.state.start()
        XCTAssertNotNil(Self.draftChip(h.state), "확인 줄이 열린 동안 시작 버튼으로는 시작하지 않는다")

        XCTAssertTrue(h.state.extendAndStart())
        XCTAssertEqual(h.stored?.minutes, 135)
        XCTAssertEqual(h.stored?.extendedMinutes, 15)
        XCTAssertEqual(h.stored?.usedSeconds, 135 * 60, "늘린 뒤 25분으로 시작한다")
        guard case .running(_, 25, _, _) = h.state.timer else { return XCTFail("25분으로 시작해야 한다") }
        XCTAssertTrue(try h.repository.decisions().isEmpty, "늘리기는 행동 로그 줄이 없다")
    }

    func test_FR10_R421_customLongerThanRemainingAsksToExtend() throws {
        let h = try Self.launched(budget: Self.record(120, used: 110 * 60))
        h.state.beginCustom()
        h.state.editCustom("40")
        XCTAssertTrue(h.state.canStart, "시작 전 화면은 막지 않는다")
        XCTAssertEqual(h.state.extendNeeded, 30)
    }

    func test_FR10_R421_keepRemainingRevertsChipWithoutStarting() throws {
        let h = try Self.launched(budget: Self.record(120, used: 110 * 60))
        h.state.chooseQuantum(25)
        h.state.keepRemaining()
        XCTAssertEqual(Self.draftChip(h.state), 10)
        XCTAssertNil(h.state.extendNeeded)
        XCTAssertEqual(h.stored?.minutes, 120)
        XCTAssertEqual(h.stored?.usedSeconds, 110 * 60, "시작하지 않는다")
    }

    func test_FR10_R421_failedExtendWriteDoesNotStart() throws {
        let h = try Self.launched(budget: Self.record(120, used: 110 * 60))
        h.state.chooseQuantum(25)
        h.settings.failsBudgetWrite = true
        XCTAssertFalse(h.state.extendAndStart())
        XCTAssertNotNil(Self.draftChip(h.state), "시작하지 않는다")
        XCTAssertTrue(h.state.extendFailed)
        XCTAssertEqual(BudgetViewText.extendFailed, "시간을 늘리지 못했어요. 다시 해 주세요.")
        XCTAssertEqual(h.stored?.minutes, 120)

        h.state.keepRemaining()
        XCTAssertFalse(h.state.extendFailed, "다시 누르면 한 줄이 사라진다")
    }

    func test_FR10_R421_extendedButStartFailedKeepsExtensionAndStartsWithoutConfirm() throws {
        let repository = FailingAfterStartRepository()
        _ = try repository.insertTask(
            NewTask(title: "가짜 할 일 A", deadline: nil, estMin: nil, recurrence: .none, weekday: nil), cycleDay: nil,
            at: Self.created)
        let settings = BudgetWriteFailingSettings()
        try CoreSettings.writeDayBudget(Self.record(120, used: 110 * 60), to: settings)
        let clock = TestClock(AppTestFixture.noon)
        let state = makeState(repository, settings: settings, clock: clock, budgetAnswered: false)
        state.launch()
        state.chooseQuantum(25)

        repository.failsApply = true
        XCTAssertFalse(state.extendAndStart())
        XCTAssertEqual(CoreSettings.readDayBudget(from: settings)?.minutes, 135, "늘린 가용 시간은 되돌리지 않는다")
        XCTAssertTrue(state.startFailed)
        XCTAssertEqual(BudgetViewText.startFailed, "시작하지 못했어요. 다시 해 주세요.")
        XCTAssertNil(state.extendNeeded, "이제 남은 분이 칩 이상이라 확인 줄이 없다")
        XCTAssertNotNil(Self.draftChip(state))

        repository.failsApply = false
        state.start()
        guard case .running(_, 25, _, _) = state.timer else { return XCTFail("확인 줄 없이 바로 시작해야 한다") }
        XCTAssertFalse(state.startFailed)
        XCTAssertEqual(CoreSettings.readDayBudget(from: settings)?.minutes, 135, "두 번 늘리지 않는다")
    }

    // MARK: - US3-6, 쓴 시간(R-420)

    func test_FR10_R420_US3_6_sameDayRelaunchDoesNotAskAgainAndKeepsUsed() throws {
        let h = try Self.launched()
        h.state.answerBudget(120)
        h.state.start()
        h.clock.advance(minutes: 5)
        h.state.complete()
        XCTAssertEqual(h.stored?.usedSeconds, 5 * 60, "일찍 끝내면 남은 20분을 돌려받는다")

        let again = h.relaunched()
        XCTAssertEqual(again.notchMode, .session, "같은 하루에는 다시 묻지 않는다")
        again.start()
        XCTAssertEqual(h.stored?.usedSeconds, 30 * 60, "쓴 시간을 이어서 센다")
    }

    func test_FR10_R420_earlySkipAndSwitchRefundRemaining() throws {
        let h = try Self.launched(budget: Self.record(120, used: 0))
        h.state.start()
        h.clock.advance(minutes: 10)
        h.state.beginSetAside(.skip)
        h.state.setAsideWithoutNotes()
        XCTAssertEqual(h.stored?.usedSeconds, 10 * 60)

        h.state.start()
        h.clock.advance(minutes: 4)
        h.state.beginSetAside(.switch)
        h.state.setAsideWithoutNotes()
        XCTAssertEqual(h.stored?.usedSeconds, 14 * 60)
    }

    func test_FR10_R420_quitWhileRunningRefundsRemaining() throws {
        let h = try Self.launched(budget: Self.record(120, used: 0))
        h.state.start()
        h.clock.advance(minutes: 10)
        h.state.lifecycleCheckpoint(.quit)
        XCTAssertEqual(h.stored?.usedSeconds, 10 * 60)
    }

    func test_FR10_R420_sleepDoesNotRefund() throws {
        let h = try Self.launched(budget: Self.record(120, used: 0))
        h.state.start()
        h.clock.advance(minutes: 10)
        h.state.lifecycleCheckpoint(.sleep)
        XCTAssertEqual(h.stored?.usedSeconds, 25 * 60)
    }

    func test_FR10_R422_SC405_refundBeforeModeSoEarlyFinishDoesNotEndDay() throws {
        let h = try Self.launched(budget: Self.record(60, used: 0))
        h.state.chooseQuantum(60)
        h.state.start()
        h.clock.advance(minutes: 10)
        h.state.complete()
        XCTAssertEqual(h.stored?.usedSeconds, 10 * 60)
        XCTAssertEqual(h.state.notchMode, .session, "돌려받은 50분이 있어 오늘 끝이 아니다")
        let chip = try XCTUnwrap(Self.draftChip(h.state), "고르기가 돈다")
        XCTAssertLessThanOrEqual(chip, 50)
    }

    func test_FR10_R420_runningTimeCountsButWaitingOnExpiredDoesNot() throws {
        let h = try Self.launched(budget: Self.record(120, used: 0))
        h.state.start()
        h.clock.advance(minutes: 25)
        h.state.tick()
        XCTAssertNotNil(Self.expiredChip(h.state))
        h.clock.advance(minutes: 30)
        h.state.tick()
        XCTAssertEqual(h.stored?.usedSeconds, 25 * 60, "시간 끝 화면에서 기다린 시간은 들지 않는다")
        h.state.start()
        XCTAssertEqual(h.stored?.usedSeconds, 35 * 60, "\"10분 더\"는 고른 분을 더한다")
    }

    // MARK: - 시간 끝 칩 상한(R-409, R-421)

    func test_FR10_R409_US3_3_expiredChipIsCappedAndLongerPresetsOff() throws {
        let h = try Self.launched(budget: Self.record(120, used: 90 * 60))
        h.state.start()
        h.clock.advance(minutes: 25)
        h.state.tick()
        XCTAssertEqual(Self.expiredChip(h.state), 5, "추가 시간 10분과 남은 5분 가운데 짧은 값")
        XCTAssertEqual(h.state.expiredCap, 5)
        XCTAssertEqual(h.state.expiredCapNote, "오늘 남은 시간이 5분이라 5분까지 이어 갈 수 있어요.")
        XCTAssertFalse(h.state.expiredDayEnd)
        XCTAssertNil(h.state.extendNeeded, "시간 끝 화면에는 늘리기가 없다")

        h.state.beginCustom()
        h.state.editCustom("10")
        XCTAssertFalse(h.state.canStart, "직접 입력이 남은 분보다 크면 \"N분 더\"가 꺼진다")
        h.state.editCustom("5")
        XCTAssertTrue(h.state.canStart)
    }

    // MARK: - US3-4, 4a, 4b, 5: 오늘 끝

    func test_FR10_R422_US3_4a_4b_expiredOnLastMinuteTurnsOffAgainThenDayEnd() throws {
        let h = try Self.launched(budget: Self.record(120, used: 95 * 60))
        h.state.start()
        XCTAssertEqual(h.stored?.usedSeconds, 120 * 60)
        h.clock.advance(minutes: 25)
        h.state.tick()
        XCTAssertTrue(h.state.expiredDayEnd)
        XCTAssertFalse(h.state.canStart)
        XCTAssertEqual(
            h.state.expiredOffReason, "오늘 정한 2시간을 다 써서 더 이어 갈 수 없어요. 두 줄을 적고 버튼을 눌러 주세요.")
        h.state.start()
        XCTAssertNotNil(Self.expiredChip(h.state), "\"N분 더\"는 눌리지 않는다")
        h.state.beginCustom()
        XCTAssertNil(h.state.customText, "직접 입력 칸을 열 수 없어 Enter로 다시 시작하는 길도 없다")

        let id = try XCTUnwrap(h.state.session.taskID)
        h.state.editNotes(NotesDraft(done: "가짜 한 일", next: "가짜 다음 일"))
        h.state.beginSetAside(.skip)
        let task = try XCTUnwrap(try h.repository.tasks().first { $0.id == id })
        XCTAssertEqual(task.status, .todo)
        XCTAssertEqual(task.skipCount, 1)
        XCTAssertEqual(try h.repository.checkpoints().last?.trigger, .dayEnd)
        XCTAssertEqual(try h.repository.decisions().last?.userAction, .skip)
        XCTAssertEqual(h.state.notchMode, .dayEnd)
        XCTAssertEqual(h.state.timer, .empty(draft: nil), "스케줄러가 고르지 않는다(SC-405)")
    }

    func test_FR10_R422_expiredDayEndCompleteAndSwitchAreDayEnd() throws {
        for action in ["complete", "switch"] {
            let h = try Self.launched(budget: Self.record(120, used: 95 * 60))
            h.state.start()
            h.clock.advance(minutes: 25)
            h.state.tick()
            if action == "complete" { h.state.complete() } else { h.state.beginSetAside(.switch) }
            XCTAssertEqual(try h.repository.checkpoints().last?.trigger, .dayEnd, action)
            XCTAssertEqual(h.state.notchMode, .dayEnd, action)
        }
    }

    func test_FR10_R422_US3_5_moreLiftsCapForTheDay() throws {
        let h = try Self.launched(budget: Self.record(60, used: 60 * 60))
        XCTAssertEqual(h.state.notchMode, .dayEnd, "노치 할 일이 없을 때 이미 닿아 있으면 바로 오늘 끝")
        XCTAssertEqual(BudgetText.dayEndTitle(minutes: h.stored?.minutes ?? 0), "오늘 정한 1시간을 다 썼어요")

        XCTAssertTrue(h.state.more())
        XCTAssertEqual(h.stored?.more, true)
        XCTAssertEqual(Self.draftChip(h.state), 25, "상한 없이 고른다")
        XCTAssertTrue(try h.repository.decisions().isEmpty, "\"더 할래요\"는 행동 로그 줄이 없다")
        h.state.start()
        h.clock.advance(minutes: 25)
        h.state.complete()
        XCTAssertEqual(h.state.notchMode, .session, "그날은 다시 오늘 끝으로 막지 않는다")
    }

    func test_FR10_R422_failedMoreWriteStaysOnDayEnd() throws {
        let h = try Self.launched(budget: Self.record(60, used: 60 * 60))
        h.settings.failsBudgetWrite = true
        XCTAssertFalse(h.state.more())
        XCTAssertEqual(h.state.notchMode, .dayEnd)
        XCTAssertTrue(h.state.moreFailed)
        XCTAssertEqual(BudgetViewText.moreFailed, "이어서 하지 못했어요. 다시 해 주세요.")
        h.settings.failsBudgetWrite = false
        XCTAssertTrue(h.state.more())
        XCTAssertFalse(h.state.moreFailed)
    }

    func test_FR10_R422_dayEndStaysAfterRelaunch() throws {
        let h = try Self.launched(budget: Self.record(60, used: 60 * 60))
        XCTAssertEqual(h.relaunched().notchMode, .dayEnd)
    }

    // MARK: - 하루 경계 뒤 "N분 더"(research R10, data-model §11·§12)

    func test_FR10_R421_R10_restartAfterBoundaryIsCappedByStartDay() throws {
        let h = try Self.launched(budget: Self.record(120, used: 90 * 60), at: AppTestFixture.at(2027, 1, 14, 5, 50))
        h.state.start()
        h.clock.advance(minutes: 25)
        h.state.tick()
        XCTAssertEqual(h.state.logicalToday, Self.jan14)
        XCTAssertEqual(Self.expiredChip(h.state), 5, "칩은 시작한 하루의 남은 5분 이하")
        h.state.start()
        XCTAssertEqual(h.stored?.day, Self.jan13)
        XCTAssertEqual(h.stored?.usedSeconds, 120 * 60, "\"N분 더\"는 시작한 하루 기록에 더한다")
    }

    func test_FR10_R422_R10_restartAfterBoundaryOffWhenStartDaySpent() throws {
        let h = try Self.launched(budget: Self.record(120, used: 95 * 60), at: AppTestFixture.at(2027, 1, 14, 5, 50))
        h.state.start()
        h.clock.advance(minutes: 25)
        h.state.tick()
        XCTAssertTrue(h.state.expiredDayEnd)
        XCTAssertFalse(h.state.canStart)
        XCTAssertEqual(h.state.expiredOffReason, "어제 정한 2시간을 다 썼어요.")

        h.state.beginSetAside(.skip)
        XCTAssertEqual(try h.repository.checkpoints().last?.trigger, .dayEnd)
        XCTAssertEqual(h.state.notchMode, .askBudget, "버튼 뒤 새 하루의 질문")
    }

    func test_FR10_R421_R10_noCapAfterBoundaryWhenStartDayHadMore() throws {
        let h = try Self.launched(
            budget: Self.record(60, used: 60 * 60, more: true), at: AppTestFixture.at(2027, 1, 14, 5, 50))
        h.state.start()
        h.clock.advance(minutes: 25)
        h.state.tick()
        XCTAssertEqual(Self.expiredChip(h.state), 10, "\"더 할래요\" 뒤라 상한이 없다")
        XCTAssertFalse(h.state.expiredDayEnd)
        XCTAssertNil(h.state.expiredCap)
    }

    // MARK: - 이월 카드 다음(R-419)

    func test_FR10_R419_answeringAllCardsLeadsToBudgetQuestion() throws {
        let h = try Self.launched()
        h.state.answerBudget(120)
        h.state.start()
        h.clock.advance(minutes: 5)
        h.state.beginSetAside(.skip)
        h.state.setAsideWithoutNotes()
        h.clock.advanceToNextDay(hour: 7)
        h.state.activate()
        guard case .carryCard(let id, _, _) = h.state.notchMode else { return XCTFail("먼저 이월 카드") }
        XCTAssertTrue(h.state.answerCarry(.today, for: id))
        XCTAssertEqual(h.state.notchMode, .askBudget, "카드를 다 답하면 가용 시간 질문")
        XCTAssertEqual(h.state.timer, .empty(draft: nil))
    }
}
