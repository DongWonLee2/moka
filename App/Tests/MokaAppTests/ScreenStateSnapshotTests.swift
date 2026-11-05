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

    /// 같은 상태를 라이트·다크로 그려 저장하고 sanity를 단언한다.
    /// 시안 2번(입력)·5번(도는 중 펼침)은 마우스를 올린 상태라 `hovering: true`로 모카 테두리를 그린다.
    private func snapshot(
        _ name: String, timer: NotchTimer, remaining: Int?, expanded: Bool, hovering: Bool = false,
        style: PanelStyle = .notch, draftInput: DraftInput = DraftInput(), firstAction: String? = nil,
        showsFirstActionCollapsed: Bool = false, notes: NotesInput = NotesInput()
    ) throws {
        let metrics = style == .notch ? Self.notchMetrics : Self.floatingMetrics
        let size = NotchLayout.panelSize(metrics: metrics)
        let content = NotchContentView(
            timer: timer, remainingSeconds: remaining, isExpanded: expanded, isHovering: hovering, metrics: metrics,
            style: style, firstAction: firstAction, showsFirstActionCollapsed: showsFirstActionCollapsed,
            titleFocusRequest: 0,
            chip: QuantumChipInput(
                customText: nil, canStart: true, onChoose: { _ in }, onBeginCustom: {}, onEditCustom: { _ in },
                takeFocusRequest: { false }),
            onEnterTitle: { _ in }, draftInput: draftInput, notes: notes, onStart: {}, onComplete: {})

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
