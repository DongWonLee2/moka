import AppKit
import MokaCore
import SwiftUI
import XCTest

/// 화면 상태를 라이트·다크 PNG로 만든다(T037, ADR-0009). 기준 이미지와 비교하지 않고 sanity만 본다
/// (크기 0 아님, 픽셀 치수, 단색 아님, 라이트≠다크, 판 안 색). 생성 PASS는 화면이 시안과 맞다는 증거가 아니다. 정합은 사람이 비교 페이지에서 본다.
/// 할 일 제목은 가짜 예시만 쓴다.
@MainActor
final class ScreenStateSnapshotTests: XCTestCase {
    /// 맥북 프로 14" 노치(시안 v3.5: 약 185×32pt).
    private static let notchMetrics = NotchMetrics(holeWidth: 185, height: 32)
    /// 떠 있는 창은 구멍이 없고 귀 줄 높이는 `PanelPlacementMetrics.floatingBarHeight`.
    private static let floatingMetrics = NotchMetrics(
        holeWidth: 0, height: CGFloat(PanelPlacementMetrics.floatingBarHeight))

    private static let title = "보고서 1절 쓰기"
    private static let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private static let running = NotchTimer.running(
        title: title, quantumMin: 25, startedAt: startedAt, endsAt: startedAt.addingTimeInterval(1500))
    /// 접힌 판 오른쪽 "18:42".
    private static let runningRemaining = 1122
    private static let firstAction = "서론 첫 문장 고치기"

    func test_R001_emptyCollapsed() throws {
        try snapshot("01-empty", timer: .empty(draft: nil), remaining: nil, expanded: false)
    }

    func test_R119_storageUnavailableEmpty() throws {
        try snapshot(
            "17-storage-unavailable", timer: .empty(draft: nil), remaining: nil, expanded: true, hovering: true,
            storageUnavailable: true)
    }

    func test_R001_R002_titleEntry() throws {
        try snapshot("02-input", timer: .empty(draft: nil), remaining: nil, expanded: true, hovering: true)
    }

    func test_R003_R004_chipExpanded() throws {
        try snapshot(
            "03-chip", timer: .empty(draft: Draft(title: Self.title, chipMin: 25)), remaining: nil, expanded: true)
    }

    /// 프리셋 밖 기본값(30분)으로 미리 채운 칩. "직접…" 자리에 "30분"이 선택된 채 보인다(#34).
    func test_R003_R004_chipOffPresetDefault() throws {
        try snapshot(
            "03-chip-default-30", timer: .empty(draft: Draft(title: Self.title, chipMin: 30)), remaining: nil,
            expanded: true)
    }

    func test_R104_otherTaskPicker() throws {
        let items = [
            OtherTaskItem(id: 2, title: "보고서 1절 쓰기", note: "마감 지남", tone: .overdue),
            OtherTaskItem(id: 3, title: "스터디 발표 자료 정리", note: "오늘 마감", tone: .soon),
            OtherTaskItem(id: 4, title: "치과 예약 전화", note: "내일 마감", tone: .soon),
            OtherTaskItem(id: 5, title: "기말 과제 개요 잡기", note: "11월 20일", tone: .plain),
            OtherTaskItem(id: 6, title: "영단어 30개 외우기", note: "매일", tone: .plain),
            OtherTaskItem(id: 7, title: "책 반납하기", note: "", tone: .plain),
        ]
        try snapshot(
            "11-other-task-picker", timer: .empty(draft: Draft(title: "장보기 목록 만들기", chipMin: 25)), remaining: nil,
            expanded: true, hovering: true, draftInput: DraftInput(isPickingOther: true, otherItems: items))
    }

    func test_R104_otherTaskPickerEmpty() throws {
        try snapshot(
            "11-other-task-picker-empty", timer: .empty(draft: Draft(title: "장보기 목록 만들기", chipMin: 25)),
            remaining: nil, expanded: true, hovering: true, draftInput: DraftInput(isPickingOther: true))
    }

    func test_R104_draftCollapsed() throws {
        try snapshot(
            "10-draft-collapsed", timer: .empty(draft: Draft(title: Self.title, chipMin: 25)), remaining: nil,
            expanded: false)
    }

    /// 고른 뒤 3초: 왼쪽 칸에 "이어서 · <첫 행동>"(시안 1번 아래 줄, R-109). 노치는 양쪽 104pt.
    func test_R109_firstActionCollapsed() throws {
        try snapshot(
            "12-first-action-collapsed", timer: .empty(draft: Draft(title: Self.title, chipMin: 25)), remaining: nil,
            expanded: false, firstAction: Self.firstAction, showsFirstActionCollapsed: true)
    }

    func test_R109_draftFirstAction() throws {
        try snapshot(
            "13-draft-first-action", timer: .empty(draft: Draft(title: Self.title, chipMin: 25)), remaining: nil,
            expanded: true, hovering: true, firstAction: Self.firstAction)
    }

    func test_R109_draftFirstActionLongTitle() throws {
        try snapshot(
            "13-draft-first-action-long",
            timer: .empty(draft: Draft(title: "기말 보고서 1절 쓰기와 참고 문헌 목록 정리, 그림 번호 맞추기", chipMin: 25)),
            remaining: nil, expanded: true, hovering: true,
            firstAction: "서론 첫 문장을 고치고 둘째 문단의 인용 출처를 다시 확인하기")
    }

    func test_R109_runningFirstAction() throws {
        try snapshot(
            "14-running-first-action", timer: Self.running, remaining: Self.runningRemaining, expanded: true,
            hovering: true, firstAction: Self.firstAction)
    }

    func test_R106_notesSwitch() throws {
        try snapshot(
            "15-notes-switch", timer: Self.running, remaining: Self.runningRemaining, expanded: true,
            notes: NotesInput(pending: .switch, draft: NotesDraft(done: "배경 문단 두 개 씀", next: ""), elapsedMinutes: 18))
    }

    func test_R106_notesLongTitle() throws {
        let start = Self.startedAt
        try snapshot(
            "15-notes-long",
            timer: .running(
                title: "기말 보고서 1절 쓰기와 참고 문헌 목록 정리, 그림 번호 맞추기", quantumMin: 25, startedAt: start,
                endsAt: start + 1500),
            remaining: Self.runningRemaining, expanded: true,
            notes: NotesInput(
                pending: .skip,
                draft: NotesDraft(done: "서론과 배경 문단 두 개를 쓰고 참고 문헌 다섯 개를 정리함", next: "그림 1 캡션과 표 번호 다시 맞추기"),
                elapsedMinutes: 18))
    }

    func test_R106_notesSkipEmpty() throws {
        try snapshot(
            "15-notes-skip", timer: Self.running, remaining: Self.runningRemaining, expanded: true,
            notes: NotesInput(pending: .skip, elapsedMinutes: 18))
    }

    func test_R006_runningCollapsed() throws {
        try snapshot("04-running-collapsed", timer: Self.running, remaining: Self.runningRemaining, expanded: false)
    }

    func test_R006_runningExpanded() throws {
        try snapshot(
            "05-running-expanded", timer: Self.running, remaining: Self.runningRemaining, expanded: true,
            hovering: true)
    }

    func test_R008_R009_R010_expired() throws {
        try snapshot("06-expired", timer: .expired(title: Self.title, chipMin: 25), remaining: 0, expanded: true)
    }

    func test_R107_expiredNotes() throws {
        try snapshot(
            "16-expired-notes", timer: .expired(title: Self.title, chipMin: 25), remaining: 0, expanded: true,
            hovering: true, notes: NotesInput(draft: NotesDraft(done: "1절 초안 끝냄", next: "그림 1 캡션")))
    }

    func test_R107_expiredCustomInvalid() throws {
        try snapshot(
            "16-expired-custom-invalid",
            timer: .expired(title: "기말 보고서 1절 쓰기와 참고 문헌 목록 정리, 그림 번호 맞추기", chipMin: 25), remaining: 0,
            expanded: true, customText: "200")
    }

    func test_R011_floatingCollapsed() throws {
        try snapshot(
            "07-floating-collapsed", timer: Self.running, remaining: Self.runningRemaining, expanded: false,
            style: .floating)
    }

    func test_R011_floatingExpanded() throws {
        try snapshot(
            "08-floating-expanded", timer: Self.running, remaining: Self.runningRemaining, expanded: true,
            style: .floating)
    }

    func test_R011_floatingExpired() throws {
        try snapshot(
            "09-floating-expired", timer: .expired(title: Self.title, chipMin: 25), remaining: 0, expanded: true,
            style: .floating)
    }

    // MARK: spec 004 노치 펼친 화면(확정 시안 004-mockup 1~8번, 12~14번, 사용자 확정 2026-11-10)

    private static let fakeTitle = "가짜 할 일 A"
    private static let fakeDraft = NotchTimer.empty(draft: Draft(title: fakeTitle, chipMin: 25))
    private static let fakeRunning = NotchTimer.running(
        title: fakeTitle, quantumMin: 25, startedAt: startedAt, endsAt: startedAt.addingTimeInterval(1500))
    private static let fakeFirstAction = "가짜 첫 행동"
    private static let fakeGateLine = "가짜 자료 정리하기"

    /// 시안 1번: 제목 아래 이유 줄, 그 아래 이어서 할 일 줄.
    func test_R301_draftReason() throws {
        try snapshot(
            "18-reason-draft", timer: Self.fakeDraft, remaining: nil, expanded: true, hovering: true,
            firstAction: Self.fakeFirstAction, reasonLine: "D-3 · 중요도 보통 · 미룬 2번")
    }

    /// 시안 2번: 판단 결과가 없으면 중요도 칸 없이 두 칸.
    func test_R301_draftReasonNoImpact() throws {
        try snapshot(
            "18-reason-draft-no-impact", timer: Self.fakeDraft, remaining: nil, expanded: true, hovering: true,
            reasonLine: "D-day · 미룬 0번")
    }

    /// 시안 3번: 도는 중에도 같은 줄.
    func test_R301_runningReason() throws {
        try snapshot(
            "18-reason-running", timer: Self.fakeRunning, remaining: Self.runningRemaining, expanded: true,
            hovering: true, firstAction: Self.fakeFirstAction, reasonLine: "D-3 · 중요도 보통 · 미룬 2번")
    }

    /// 시안 4번. 할 일에 첫 행동이 있어도 게이트가 묻는 중이면 제목 아래 이어서 할 일 줄을 숨긴다(R-311).
    func test_R307_gateAsking() throws {
        try snapshot(
            "19-gate-asking", timer: Self.fakeDraft, remaining: nil, expanded: true, hovering: true,
            firstAction: Self.fakeFirstAction, reasonLine: "D-3 · 중요도 보통 · 미룬 0번",
            gate: Self.gate(.asking, text: Self.fakeGateLine))
    }

    /// 시안 5번: 칸은 읽기만, 확인하는 중 문구, 시작 버튼 ↵.
    func test_R307_gateChecking() throws {
        try snapshot(
            "19-gate-checking", timer: Self.fakeDraft, remaining: nil, expanded: true, hovering: true,
            firstAction: Self.fakeFirstAction, reasonLine: "D-3 · 중요도 보통 · 미룬 0번",
            gate: Self.gate(.checking, text: Self.fakeGateLine, submissions: 1))
    }

    /// 시안 6번: 다시 묻기. 방금 적은 줄이 칸에 남고 남은 횟수를 말로 보인다.
    func test_R309_gateRetry() throws {
        try snapshot(
            "19-gate-retry", timer: Self.fakeDraft, remaining: nil, expanded: true, hovering: true,
            firstAction: Self.fakeGateLine, reasonLine: "D-3 · 중요도 보통 · 미룬 0번",
            gate: Self.gate(.asking, text: Self.fakeGateLine, submissions: 1))
    }

    /// 시안 7번: 통과하면 게이트가 닫히고 적은 줄이 이어서 할 일로 보인다.
    func test_R311_gatePassed() throws {
        try snapshot(
            "19-gate-passed", timer: Self.fakeDraft, remaining: nil, expanded: true, hovering: true,
            firstAction: "가짜 자료 폴더 열기", reasonLine: "D-3 · 중요도 보통 · 미룬 0번",
            gate: Self.gate(.closed, text: "가짜 자료 폴더 열기", submissions: 2))
    }

    /// 시안 8번: 저장 실패 문구, 횟수는 그대로.
    func test_R307_gateSaveFailed() throws {
        try snapshot(
            "19-gate-save-failed", timer: Self.fakeDraft, remaining: nil, expanded: true, hovering: true,
            firstAction: Self.fakeFirstAction, reasonLine: "D-3 · 중요도 보통 · 미룬 0번",
            gate: Self.gate(.asking, text: Self.fakeGateLine, saveFailed: true))
    }

    /// 게이트가 열린 동안 앱은 펼친 화면 줄(`firstAction`)을 nil로 넘기고 접힌 3초 표시 글자는 따로 넘긴다(R-311, 단위 2 리뷰).
    func test_R311_gateFirstActionCollapsed() throws {
        try snapshot(
            "19-gate-first-action-collapsed", timer: Self.fakeDraft, remaining: nil, expanded: false,
            showsFirstActionCollapsed: true, collapsedFirstAction: Self.fakeFirstAction,
            gate: Self.gate(.asking, text: ""))
    }

    /// 시안 12번: 빈 상태 아래 키 확인 한 줄.
    func test_R316_keyNoticeEmpty() throws {
        try snapshot(
            "20-key-notice-empty", timer: .empty(draft: nil), remaining: nil, expanded: true, hovering: true,
            keyNotice: true)
    }

    /// 시안 13번: 시작 전 버튼 줄 아래.
    func test_R316_keyNoticeDraft() throws {
        try snapshot(
            "20-key-notice-draft", timer: Self.fakeDraft, remaining: nil, expanded: true, hovering: true,
            reasonLine: "D-3 · 중요도 보통 · 미룬 2번", keyNotice: true)
    }

    /// 시안 14번: 도는 중 버튼 줄 아래.
    func test_R316_keyNoticeRunning() throws {
        try snapshot(
            "20-key-notice-running", timer: Self.fakeRunning, remaining: Self.runningRemaining, expanded: true,
            hovering: true, reasonLine: "D-3 · 중요도 보통 · 미룬 2번", keyNotice: true)
    }

    /// 접힌 노치에는 키 확인 표시가 없다(R-316, debate Q3). 키 확인 필요여도 그림이 같다.
    func test_R316_keyNoticeNotInCollapsed() throws {
        let metrics = Self.notchMetrics
        let size = NotchLayout.panelSize(metrics: metrics)
        for (timer, remaining) in [
            (NotchTimer.empty(draft: nil), nil), (Self.fakeDraft, nil), (Self.fakeRunning, Self.runningRemaining),
        ] {
            let plain = Self.content(timer: timer, remaining: remaining, expanded: false, metrics: metrics)
            let notice = Self.content(
                timer: timer, remaining: remaining, expanded: false, metrics: metrics, keyNotice: true)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                XCTAssertEqual(
                    try renderPNG(view: plain, size: size, appearance: appearance),
                    try renderPNG(view: notice, size: size, appearance: appearance), "\(timer) \(appearance.rawValue)")
            }
        }
    }

    // MARK: - 이월 카드(spec 005 R-414·R-415, 확정 시안 005 1~3·10-1번). 오늘은 2026-11-16(월).

    private static let seoul = GregorianCalendar.make(timeZone: TimeZone(identifier: "Asia/Seoul")!)
    private static let carryToday = LocalDay(text: "2026-11-16")!

    private static func carry(
        title: String, firstAction: String? = nil, reason: CarryCardReason, left: Int, answered: Int,
        failed: Bool = false, move: CarryMoveInput? = nil
    ) -> CarryCardInput {
        CarryCardInput(
            title: title, firstAction: firstAction, reason: CarryText.reason(reason), left: left, answered: answered,
            failed: failed, move: move)
    }

    private static func move(deadline: String?) -> CarryMoveInput {
        CarryMoveInput(
            selected: LocalDay(text: "2026-11-19")!, today: carryToday,
            deadline: deadline.flatMap(LocalDay.init(text:)),
            calendar: seoul)
    }

    /// 시안 1번: 하다 만 할 일, 이어서 할 일, 남은 3개 가운데 첫째.
    func test_R414_carryCardTouched() throws {
        try snapshot(
            "21-carry-card-touched", timer: .empty(draft: nil), remaining: nil, expanded: true, hovering: true,
            carry: Self.carry(
                title: "가짜 할 일 A", firstAction: "가짜 첫 행동", reason: .touched, left: 3, answered: 0))
    }

    /// 시안 2번: 마감이 지난 할 일(D+2), 이어서 할 일 없음, 긴 제목은 두 줄, 셋 가운데 마지막.
    func test_R414_carryCardOverdueLast() throws {
        try snapshot(
            "21-carry-card-overdue-last", timer: .empty(draft: nil), remaining: nil, expanded: true, hovering: true,
            carry: Self.carry(
                title: "가짜 할 일 B, 제목이 길면 두 줄까지 보이고 나머지는 줄여요", reason: .overdue(days: 2), left: 1, answered: 2))
    }

    /// 답 쓰기 실패 한 줄(시안 밖 문구, 사용자 결정 2026-11-17).
    func test_R414_carryCardAnswerFailed() throws {
        try snapshot(
            "21-carry-card-failed", timer: .empty(draft: nil), remaining: nil, expanded: true, hovering: true,
            carry: Self.carry(title: "가짜 할 일 A", reason: .touched, left: 3, answered: 0, failed: true))
    }

    /// 시안 3번: 날짜 고르기, 지금 마감 11월 14일(토), 19일을 고름.
    func test_R415_datePicker() throws {
        try snapshot(
            "22-date-picker", timer: .empty(draft: nil), remaining: nil, expanded: true, hovering: true,
            carry: Self.carry(
                title: "가짜 할 일 B", reason: .overdue(days: 2), left: 1, answered: 2,
                move: Self.move(deadline: "2026-11-14")))
    }

    /// 마감이 없는 할 일의 날짜 고르기(안내 뒷문장만, 시안 밖 문구, 사용자 결정 2026-11-17).
    func test_R415_datePickerNoDeadline() throws {
        try snapshot(
            "22-date-picker-no-deadline", timer: .empty(draft: nil), remaining: nil, expanded: true, hovering: true,
            carry: Self.carry(
                title: "가짜 할 일 A", reason: .touched, left: 3, answered: 0, move: Self.move(deadline: nil)))
    }

    /// 여섯 주인 달(2026년 8월)의 날짜 고르기.
    func test_R415_datePickerSixWeeks() throws {
        let move = CarryMoveInput(
            selected: LocalDay(text: "2026-08-01")!, today: LocalDay(text: "2026-07-30")!,
            deadline: LocalDay(text: "2026-07-28"), calendar: Self.seoul)
        try snapshot(
            "22-date-picker-six-weeks", timer: .empty(draft: nil), remaining: nil, expanded: true, hovering: true,
            carry: Self.carry(
                title: "가짜 할 일 B, 제목이 길면 두 줄까지 보이고 나머지는 줄여요", reason: .overdue(days: 2), left: 5, answered: 0,
                move: move))
    }

    /// 시안 10-1번: 접힌 노치, 빨간 점과 "정할 일 3개".
    func test_R414_collapsedCarry() throws {
        try snapshot(
            "23-carry-collapsed", timer: .empty(draft: nil), remaining: nil, expanded: false,
            carry: Self.carry(title: "가짜 할 일 A", reason: .touched, left: 3, answered: 0))
    }

    // MARK: - 가용 시간 질문과 오늘 끝(spec 005 R-409·R-419·R-421·R-422, 확정 시안 005 4~9·10-2·10-3번)

    private static func ask(customText: String? = nil, failed: Bool = false) -> BudgetScreenInput {
        .ask(
            AskBudgetInput(
                customText: customText, issue: customText.flatMap(BudgetInput.issue), failed: failed))
    }

    private static let budgetDraft = NotchTimer.empty(draft: Draft(title: "가짜 할 일 C", chipMin: 10))
    private static let budgetReason = "D-3 · 중요도 보통 · 미룬 0번"

    /// 시안 4-1번: 질문 처음 모습.
    func test_R419_askBudget() throws {
        try snapshot(
            "24-ask-budget", timer: .empty(draft: nil), remaining: nil, expanded: true, hovering: true,
            budget: Self.ask())
    }

    /// 시안 4-2번: "직접…"을 누르고 적는 중.
    func test_R419_askBudgetCustom() throws {
        try snapshot(
            "24-ask-budget-custom", timer: .empty(draft: nil), remaining: nil, expanded: true, hovering: true,
            budget: Self.ask(customText: "2.5"))
    }

    /// 시안 4-3번: 30분 단위가 아님.
    func test_R419_askBudgetCustomInvalid() throws {
        try snapshot(
            "24-ask-budget-custom-invalid", timer: .empty(draft: nil), remaining: nil, expanded: true, hovering: true,
            budget: Self.ask(customText: "2.3"))
    }

    /// 답 쓰기 실패 한 줄(시안 밖 문구, 사용자 결정 2026-11-17).
    func test_R419_askBudgetFailed() throws {
        try snapshot(
            "24-ask-budget-failed", timer: .empty(draft: nil), remaining: nil, expanded: true, hovering: true,
            budget: Self.ask(failed: true))
    }

    /// 시안 5번: 시작 전, 칩을 남은 10분으로 줄여 채움.
    func test_R421_draftCapped() throws {
        try snapshot(
            "25-draft-capped", timer: Self.budgetDraft, remaining: nil, expanded: true, hovering: true,
            reasonLine: Self.budgetReason,
            draftBudget: DraftBudgetInput(capNote: BudgetText.capNote(minutes: 10, expired: false)))
    }

    private static func extend(failed: Bool = false) -> ExtendInput {
        ExtendInput(
            title: BudgetText.extendTitle(extra: 15, chip: 25),
            detail: BudgetText.extendDetail(remaining: 10, newTotal: 135),
            keep: BudgetText.keepRemaining(minutes: 10), failed: failed)
    }

    /// 시안 6번: 남은 시간보다 길게 고름, 늘리기 확인.
    func test_R421_extendConfirm() throws {
        try snapshot(
            "25-extend-confirm", timer: .empty(draft: Draft(title: "가짜 할 일 C", chipMin: 25, chipPicked: true)),
            remaining: nil, expanded: true, hovering: true, reasonLine: Self.budgetReason,
            draftBudget: DraftBudgetInput(extend: Self.extend()))
    }

    /// 늘리기 쓰기 실패 한 줄(시안 밖 문구, 사용자 결정 2026-11-17).
    func test_R421_extendFailed() throws {
        try snapshot(
            "25-extend-failed", timer: .empty(draft: Draft(title: "가짜 할 일 C", chipMin: 25, chipPicked: true)),
            remaining: nil, expanded: true, hovering: true, reasonLine: Self.budgetReason,
            draftBudget: DraftBudgetInput(extend: Self.extend(failed: true)))
    }

    /// 늘린 뒤 시작 커밋 실패 한 줄(data-model §11 글자).
    func test_R421_startFailed() throws {
        try snapshot(
            "25-start-failed", timer: .empty(draft: Draft(title: "가짜 할 일 C", chipMin: 25, chipPicked: true)),
            remaining: nil, expanded: true, hovering: true, reasonLine: Self.budgetReason,
            draftBudget: DraftBudgetInput(startFailed: true))
    }

    /// 시안 7번: 시간 끝, 오늘 남은 시간 5분.
    func test_R409_expiredCapped() throws {
        try snapshot(
            "26-expired-capped", timer: .expired(title: "가짜 할 일 C", chipMin: 5), remaining: 0, expanded: true,
            expiredBudget: ExpiredBudgetInput(maxMinutes: 5, note: BudgetText.capNote(minutes: 5, expired: true)))
    }

    /// 시안 8번: 시간 끝과 오늘 끝이 겹침.
    func test_R422_expiredDayEnd() throws {
        try snapshot(
            "26-expired-day-end", timer: .expired(title: "가짜 할 일 C", chipMin: 10), remaining: 0, expanded: true,
            expiredBudget: ExpiredBudgetInput(offReason: BudgetText.dayEndOff(minutes: 120)))
    }

    /// 하루 경계를 넘긴 시간 끝, 시작한 날 남은 시간 0(시안 밖 문구, 사용자 결정 2026-11-17).
    func test_R422_expiredCrossDayEnd() throws {
        try snapshot(
            "26-expired-cross-day-end", timer: .expired(title: "가짜 할 일 C", chipMin: 10), remaining: 0,
            expanded: true, expiredBudget: ExpiredBudgetInput(offReason: BudgetText.crossDayOff(minutes: 120)))
    }

    /// 시안 9번: 오늘 끝과 "더 할래요".
    func test_R422_dayEnd() throws {
        try snapshot(
            "27-day-end", timer: .empty(draft: nil), remaining: nil, expanded: true, hovering: true,
            budget: .dayEnd(DayEndInput(minutes: 120, usedSeconds: 7200, fraction: 1)))
    }

    /// "더 할래요" 쓰기 실패 한 줄(시안 밖 문구, 사용자 결정 2026-11-17).
    func test_R422_dayEndMoreFailed() throws {
        try snapshot(
            "27-day-end-more-failed", timer: .empty(draft: nil), remaining: nil, expanded: true, hovering: true,
            budget: .dayEnd(DayEndInput(minutes: 120, usedSeconds: 7200, fraction: 1, failed: true)))
    }

    /// 판 높이(노치 아래 340pt) 안에 새 화면이 들어가는지. 펼친 판의 맞춤 높이를 잰다.
    func test_R433_budgetScreensFitPanelHeight() {
        let size = NotchLayout.panelSize(metrics: Self.notchMetrics)
        let screens: [(String, NotchContentView)] = [
            ("ask-custom-invalid", Self.content(
                timer: .empty(draft: nil), remaining: nil, expanded: true, metrics: Self.notchMetrics,
                budget: Self.ask(customText: "2.3", failed: true))),
            ("extend-failed", Self.content(
                timer: .empty(draft: Draft(title: "가짜 할 일 C, 제목이 길면 두 줄까지 보이고 나머지는 줄여요", chipMin: 25)),
                remaining: nil, expanded: true, metrics: Self.notchMetrics, reasonLine: Self.budgetReason,
                draftBudget: DraftBudgetInput(extend: Self.extend(failed: true), startFailed: true))),
            ("expired-day-end", Self.content(
                timer: .expired(title: "가짜 할 일 C", chipMin: 10), remaining: 0, expanded: true,
                metrics: Self.notchMetrics,
                expiredBudget: ExpiredBudgetInput(offReason: BudgetText.dayEndOff(minutes: 135)))),
            ("day-end-more-failed", Self.content(
                timer: .empty(draft: nil), remaining: nil, expanded: true, metrics: Self.notchMetrics,
                budget: .dayEnd(DayEndInput(minutes: 135, usedSeconds: 8100, fraction: 1, failed: true)))),
        ]
        for (name, view) in screens {
            let height = NSHostingView(rootView: view.fixedSize()).fittingSize.height
            print("판 높이 \(name): \(height)pt / 패널 \(size.height)pt")
            XCTAssertLessThanOrEqual(height, size.height, name)
        }
    }

    /// 시안 10-2번: 접힌 노치, 가용 시간 질문을 기다림.
    func test_R419_collapsedAskBudget() throws {
        try snapshot(
            "28-ask-budget-collapsed", timer: .empty(draft: nil), remaining: nil, expanded: false, budget: Self.ask())
    }

    /// 시안 10-3번: 접힌 노치, 오늘 끝.
    func test_R422_collapsedDayEnd() throws {
        try snapshot(
            "28-day-end-collapsed", timer: .empty(draft: nil), remaining: nil, expanded: false,
            budget: .dayEnd(DayEndInput(minutes: 120, usedSeconds: 7200, fraction: 1)))
    }

    private static func gate(
        _ phase: GatePhase, text: String, submissions: Int = 0, saveFailed: Bool = false
    ) -> GateInput {
        GateInput(phase: phase, text: .constant(text), submissions: submissions, saveFailed: saveFailed)
    }

    private static func content(
        timer: NotchTimer, remaining: Int?, expanded: Bool, hovering: Bool = false, metrics: NotchMetrics,
        style: PanelStyle = .notch, draftInput: DraftInput = DraftInput(), firstAction: String? = nil,
        showsFirstActionCollapsed: Bool = false, collapsedFirstAction: String? = nil, notes: NotesInput = NotesInput(),
        customText: String? = nil, storageUnavailable: Bool = false, reasonLine: String? = nil,
        gate: GateInput? = nil, keyNotice: Bool = false, carry: CarryCardInput? = nil,
        budget: BudgetScreenInput? = nil, draftBudget: DraftBudgetInput = DraftBudgetInput(),
        expiredBudget: ExpiredBudgetInput = ExpiredBudgetInput()
    ) -> NotchContentView {
        NotchContentView(
            timer: timer, remainingSeconds: remaining, isExpanded: expanded, isHovering: hovering, metrics: metrics,
            style: style, storageUnavailable: storageUnavailable, firstAction: firstAction,
            showsFirstActionCollapsed: showsFirstActionCollapsed, collapsedFirstAction: collapsedFirstAction,
            reasonLine: reasonLine, gate: gate, keyNotice: keyNotice, carry: carry, budget: budget,
            draftBudget: draftBudget, expiredBudget: expiredBudget,
            titleFocusRequest: 0,
            chip: QuantumChipInput(
                customText: customText, canStart: QuantumChip.startAllowed(customText: customText), onChoose: { _ in },
                onBeginCustom: {}, onEditCustom: { _ in },
                takeFocusRequest: { false }),
            onEnterTitle: { _ in }, draftInput: draftInput, notes: notes, onStart: {}, onComplete: {})
    }

    /// 같은 상태를 라이트·다크로 그려 저장하고 sanity를 단언한다.
    /// 시안 2번(입력)·5번(도는 중 펼침)은 마우스를 올린 상태라 `hovering: true`로 모카 테두리를 그린다.
    private func snapshot(
        _ name: String, timer: NotchTimer, remaining: Int?, expanded: Bool, hovering: Bool = false,
        style: PanelStyle = .notch, draftInput: DraftInput = DraftInput(), firstAction: String? = nil,
        showsFirstActionCollapsed: Bool = false, collapsedFirstAction: String? = nil, notes: NotesInput = NotesInput(),
        customText: String? = nil, storageUnavailable: Bool = false, reasonLine: String? = nil,
        gate: GateInput? = nil, keyNotice: Bool = false, carry: CarryCardInput? = nil,
        budget: BudgetScreenInput? = nil, draftBudget: DraftBudgetInput = DraftBudgetInput(),
        expiredBudget: ExpiredBudgetInput = ExpiredBudgetInput()
    ) throws {
        let metrics = style == .notch ? Self.notchMetrics : Self.floatingMetrics
        let size = NotchLayout.panelSize(metrics: metrics)
        let content = Self.content(
            timer: timer, remaining: remaining, expanded: expanded, hovering: hovering, metrics: metrics, style: style,
            draftInput: draftInput, firstAction: firstAction, showsFirstActionCollapsed: showsFirstActionCollapsed,
            collapsedFirstAction: collapsedFirstAction, notes: notes, customText: customText,
            storageUnavailable: storageUnavailable, reasonLine: reasonLine, gate: gate, keyNotice: keyNotice,
            carry: carry, budget: budget, draftBudget: draftBudget, expiredBudget: expiredBudget)

        let light = try renderPNG(view: content, size: size, appearance: .aqua)
        let dark = try renderPNG(view: content, size: size, appearance: .darkAqua)
        for (png, suffix) in [(light, "light"), (dark, "dark")] {
            let url = try SnapshotOutput.write(png, name: "\(name)-\(suffix)")
            let issue = SnapshotSanity.issue(in: png)
            XCTAssertNil(issue, "\(url.lastPathComponent): \(issue ?? "")")
            let sizeIssue = SnapshotSanity.sizeIssue(in: png, size: size)
            XCTAssertNil(sizeIssue, "\(url.lastPathComponent): \(sizeIssue ?? "")")
        }
        XCTAssertNotEqual(light, dark, "\(name): 라이트와 다크 PNG가 같다")
        // 판은 가로 가운데에 있고(노치 판은 구멍 가운데가 가운데), 위 끝에서 귀 줄 높이 절반 아래는 판 안이다.
        let board = CGPoint(x: size.width / 2, y: metrics.height / 2)
        let boardIssue =
            switch style {
            case .notch: SnapshotSanity.notchBoardIssue(light: light, dark: dark, board: board)
            case .floating: SnapshotSanity.floatingBoardIssue(light: light, dark: dark, board: board)
            }
        XCTAssertNil(boardIssue, "\(name): \(boardIssue ?? "")")
    }
}
