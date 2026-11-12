import MokaCore
import SwiftUI
import XCTest

/// 설정 창 탭 내용을 라이트·다크 PNG로 만든다(ADR-0009, 시안 6번). sanity만 보고 정합은 사람이 비교 페이지에서 본다.
@MainActor
final class SettingsSnapshotTests: XCTestCase {
    func test_R012_basicTabDefaults() throws {
        try snapshot("s06-basic")
    }

    /// 받지 않는 값을 적는 동안은 안내 대신 이유가 보인다(#59, #35에서 옮겨 온 항목).
    func test_R012_basicTabIssue() throws {
        try snapshot("s06-basic-issue", quantumText: "181", extendText: "4.5")
    }

    /// 시안 7번의 다섯 줄(가짜 예시): 진행 중, 매일 연속 + 다음, 매주 미룸 + 연속, 보조 줄 없음, 완료.
    func test_R102_R118_taskListTab() throws {
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        func task(
            _ id: TaskID, _ title: String, deadline: String? = nil, estMin: Int? = nil, recurrence: Recurrence = .none,
            weekday: Int? = nil, status: TaskStatus = .todo, skipCount: Int = 0, streak: Int = 0
        ) -> MokaTask {
            MokaTask(
                id: id, title: title, deadline: deadline.flatMap(LocalDay.init(text:)), estMin: estMin,
                recurrence: recurrence, weekday: weekday.flatMap(Weekday.init(rawValue:)),
                cycleDay: recurrence == .none ? nil : LocalDay(text: "2026-11-04"), firstAction: nil, status: status,
                skipCount: skipCount, streak: streak, createdAt: created)
        }
        let rows = [
            task(1, "보고서 1절 쓰기", deadline: "2026-11-05", estMin: 50, status: .active),
            task(2, "영단어 30개 외우기", recurrence: .daily, streak: 3),
            task(3, "스터디 발표 자료 정리", recurrence: .weekly, weekday: 4, skipCount: 2, streak: 2),
            task(4, "장보기 목록 만들기"),
            task(5, "세탁기 돌리기", status: .done),
        ]
        let size = CGSize(width: 460, height: 450)
        let content = VStack(spacing: 0) {
            SettingsTabBar(selection: .constant(.tasks))
            TaskListTabView(
                rows: rows, nextMarkID: 2, scope: .constant(.all), order: .constant(.created),
                selectedID: .constant(2), checkedIDs: .constant([]), canEdit: true, onAdd: {}, onEdit: { _ in },
                onDelete: {})
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MokaColors.settingsWindow)
        try write("s07-task-list", content: content, size: size)
    }

    /// 시안 v2 8번(가짜 예시): 노치 순서 앞 셋에 순위, 노치에 뜰 할 일은 "1순위 · 다음" 한 배지. 끝낸 뒤 나머지가 올라간다.
    func test_R215_rankColumn() throws {
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        func rows(firstDone: Bool) -> [MokaTask] {
            func task(
                _ id: TaskID, _ title: String, deadline: String? = nil, estMin: Int? = nil,
                recurrence: Recurrence = .none, weekday: Int? = nil, status: TaskStatus = .todo, skipCount: Int = 0
            ) -> MokaTask {
                MokaTask(
                    id: id, title: title, deadline: deadline.flatMap(LocalDay.init(text:)), estMin: estMin,
                    recurrence: recurrence, weekday: weekday.flatMap(Weekday.init(rawValue:)),
                    cycleDay: recurrence == .none ? nil : LocalDay(text: "2026-11-04"), firstAction: nil,
                    status: status, skipCount: skipCount, streak: 0, createdAt: created)
            }
            return [
                task(1, "가짜 영단어 30개 외우기", recurrence: .daily, status: firstDone ? .done : .todo),
                task(2, "가짜 보고서 1절 쓰기", deadline: "2026-11-09", estMin: 50),
                task(3, "가짜 발표 자료 정리", recurrence: .weekly, weekday: 4, skipCount: 2),
                task(4, "가짜 장보기 목록 만들기"),
                task(5, "가짜 세탁기 돌리기", status: .done),
            ]
        }
        for (name, firstDone, nextMarkID, ranks) in [
            ("s23-rank-column", false, TaskID(1), [TaskID(1): 1, 2: 2, 3: 3]),
            ("s23-rank-column-after", true, TaskID(2), [TaskID(2): 1, 3: 2, 4: 3]),
        ] {
            let content = VStack(spacing: 0) {
                SettingsTabBar(selection: .constant(.tasks))
                TaskListTabView(
                    rows: rows(firstDone: firstDone), nextMarkID: nextMarkID, ranks: ranks, scope: .constant(.all),
                    order: .constant(.created), selectedID: .constant(nil), checkedIDs: .constant([]), canEdit: true,
                    onAdd: {}, onEdit: { _ in }, onDelete: {})
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(MokaColors.settingsWindow)
            try write(name, content: content, size: CGSize(width: 460, height: 450))
        }
    }

    // MARK: - 기본 탭 키 칸 상태 여섯(spec 003 R-213, SC-210, 시안 v2 1·3~7번). spec 006에서 판단 모델 칸 안으로 옮겼다.

    func test_R213_keyFieldNoKey() throws {
        try snapshot("s24-key-none", decision: Self.typeSafe(.noKey))
    }

    func test_R213_keyFieldSaved() throws {
        try snapshot("s24-key-saved", decision: Self.typeSafe(.saved, canRetry: true))
    }

    func test_R213_keyFieldSavedNoTasks() throws {
        try snapshot("s24-key-saved-no-tasks", decision: Self.typeSafe(.savedNoTasks))
    }

    func test_R213_keyFieldNeedsCheck() throws {
        try snapshot("s24-key-needs-check", decision: Self.typeSafe(.needsCheck))
    }

    /// 시안 6번: 저장됨 줄 아래 저장 실패 문구.
    func test_R213_keyFieldActionFailed() throws {
        try snapshot(
            "s24-key-action-failed", decision: Self.typeSafe(.actionFailed(.save, hasKey: true), canRetry: true))
    }

    func test_R213_keyFieldStorageUnavailable() throws {
        try snapshot("s24-key-unavailable", decision: Self.typeSafe(.storageUnavailable))
    }

    // MARK: - 판단 모델 칸(spec 006 data-model §9, 006 시안 1~10번, 시안 확정 2026-11-12)

    /// 시안 3번: 다섯 공급자가 보이고 열리지 않은 넷은 흐리게 이유 한 줄과 함께 보인다.
    func test_ADR0011_R620_providerListOpen() throws {
        try snapshot(
            "s25-provider-list", decision: Self.typeSafe(.saved, canRetry: true),
            start: DecisionFieldStart(listOpen: true), height: 640)
    }

    /// 시안 4번: 가짜로 연 Perplexity 줄. 지금 빌드에서는 고를 수 없어 뷰만 그린다.
    func test_ADR0011_R621_provisionalProvider() throws {
        let decision = DecisionFieldInput(
            providers: Self.rows(opening: [.typesafe, .perplexity]), selected: .perplexity,
            issueURL: URL(string: "https://console.perplexity.ai"), host: "api.perplexity.ai", provisional: true,
            keyState: .noKey)
        try snapshot("s25-provider-provisional", decision: decision)
    }

    /// 시안 6번: 설정을 저장하지 못하면 원래 공급자로 남고 다시 해 달라는 문구가 보인다.
    func test_ADR0011_R622_selectFailed() throws {
        var decision = Self.typeSafe(.saved, canRetry: true)
        decision.failure = .select
        try snapshot("s25-provider-select-failed", decision: decision)
    }

    /// 시안 7번: 주소가 없으면 가는 곳 줄 대신 묻지 않는다는 안내가 보인다.
    func test_ADR0011_R623_microsoftEmpty() throws {
        try snapshot(
            "s26-microsoft-empty",
            decision: Self.microsoft(
                MicrosoftFieldInput(
                    savedEndpoint: nil, savedDeployment: nil, showsKeyResetNotice: false, keyCleared: false),
                host: nil, offNote: DecisionFieldText.offNote(.needsEndpoint), keyState: .noKey),
            height: Self.microsoftHeight)
    }

    /// 시안 8번: https가 아닌 주소를 저장하려 하면 이유를 보이고 저장하지 않는다.
    func test_ADR0011_R623_microsoftRejectedScheme() throws {
        try snapshot(
            "s26-microsoft-rejected-scheme", decision: Self.microsoftUnsaved,
            start: DecisionFieldStart(
                endpoint: "http://example-resource.invalid", deployment: "가짜-배포-1", rejection: .scheme),
            height: Self.microsoftHeight)
    }

    /// 경로가 붙은 주소(R-605 7번 규칙).
    func test_ADR0011_R623_microsoftRejectedPath() throws {
        try snapshot(
            "s26-microsoft-rejected-path", decision: Self.microsoftUnsaved,
            start: DecisionFieldStart(
                endpoint: "https://example-resource.invalid/openai", deployment: "가짜-배포-1", rejection: .path),
            height: Self.microsoftHeight)
    }

    /// 시안 9번: 저장됨. 주소를 바꾸면 키를 지운다는 안내가 늘 보인다.
    func test_ADR0011_R623_microsoftSaved() throws {
        try snapshot(
            "s26-microsoft-saved",
            decision: Self.microsoft(
                MicrosoftFieldInput(
                    savedEndpoint: "https://example-resource.invalid", savedDeployment: "가짜-배포-1",
                    showsKeyResetNotice: true, keyCleared: false),
                host: "example-resource.invalid", keyState: .saved, canRetry: true),
            height: Self.microsoftHeight)
    }

    /// 시안 10번: 주소를 바꿔 키를 지운 뒤.
    func test_ADR0011_R616_R623_microsoftKeyCleared() throws {
        try snapshot(
            "s26-microsoft-key-cleared",
            decision: Self.microsoft(
                MicrosoftFieldInput(
                    savedEndpoint: "https://example-other.invalid", savedDeployment: "가짜-배포-1",
                    showsKeyResetNotice: false, keyCleared: true),
                host: "example-other.invalid", keyState: .noKey),
            height: Self.microsoftHeight)
    }

    // MARK: - 할 일 탭 키 확인 한 줄(spec 006 R-627, spec 004 시안 15번)

    func test_FR14_R627_taskTabKeyNotice() throws {
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        let rows = [
            ("가짜 할 일 A", "2026-11-13", 0), ("가짜 할 일 B", "2026-11-15", 2), ("가짜 할 일 C", nil, 0),
        ].enumerated().map { index, row in
            MokaTask(
                id: TaskID(index + 1), title: row.0, deadline: row.1.flatMap(LocalDay.init(text:)), estMin: nil,
                recurrence: .none, weekday: nil, cycleDay: nil, firstAction: nil, status: .todo, skipCount: row.2,
                streak: 0, createdAt: created)
        }
        let content = VStack(spacing: 0) {
            SettingsTabBar(selection: .constant(.tasks))
            TaskListTabView(
                rows: rows, nextMarkID: 1, ranks: [1: 1, 2: 2, 3: 3], scope: .constant(.all),
                order: .constant(.created), selectedID: .constant(nil), checkedIDs: .constant([]), canEdit: true,
                onAdd: {}, onEdit: { _ in }, onDelete: {}, keyNotice: true)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MokaColors.settingsWindow)
        try write("s27-task-list-key-notice", content: content, size: CGSize(width: 460, height: 480))
    }

    func test_R115_contextTab() throws {
        let rows = [
            MokaContext(id: 3, name: "동아리 회의", date: try XCTUnwrap(LocalDay(text: "2026-11-04")), impact: .normal),
            MokaContext(id: 2, name: "가짜 과제 제출", date: try XCTUnwrap(LocalDay(text: "2026-11-07")), impact: .high),
            MokaContext(
                id: 1, name: "가짜 중간고사", date: try XCTUnwrap(LocalDay(text: "2026-11-12")), impact: .critical),
        ]
        let content = VStack(spacing: 0) {
            SettingsTabBar(selection: .constant(.contexts))
            ContextTabView(
                rows: rows, selectedID: .constant(2), checkedIDs: .constant([]), canEdit: true, onAdd: {},
                onEdit: { _ in }, onDelete: {})
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MokaColors.settingsWindow)
        try write("s10-context-tab", content: content, size: CGSize(width: 460, height: 450))
    }

    func test_R115_newContextSheet() throws {
        let calendar = GregorianCalendar.make(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Seoul")))
        let content = ContextFormView(
            today: try XCTUnwrap(LocalDay(text: "2026-11-06")), calendar: calendar, onSave: { _ in }, onCancel: {})
        try write("s10-new-context", content: content, size: CGSize(width: 360, height: 170))
    }

    func test_R116_onboardingStep1() throws {
        try writeOnboarding("o11-onboarding-1", step: 1)
    }

    func test_R116_onboardingStep2() throws {
        try writeOnboarding("o12-onboarding-2", step: 2)
    }

    private func writeOnboarding(_ name: String, step: Int) throws {
        let calendar = GregorianCalendar.make(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Seoul")))
        let content = OnboardingView(
            today: try XCTUnwrap(LocalDay(text: "2026-11-06")), calendar: calendar, initialQuantum: 25,
            initialExtend: 10, initialDayStart: Defaults.dayStart, initialStep: step, onFinish: { _ in }
        )
        .environment(\.timeZone, calendar.timeZone)
        .background(MokaColors.settingsWindow)
        try write(name, content: content, size: CGSize(width: 400, height: 250))
    }

    func test_R121_editContextSheet() throws {
        let calendar = GregorianCalendar.make(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Seoul")))
        let content = ContextFormView(
            today: try XCTUnwrap(LocalDay(text: "2026-11-06")), calendar: calendar,
            editing: MokaContext(
                id: 1, name: "가짜 중간고사", date: try XCTUnwrap(LocalDay(text: "2026-11-12")), impact: .critical),
            onSave: { _ in }, onCancel: {})
        try write("s21-edit-context", content: content, size: CGSize(width: 360, height: 170))
    }

    func test_R101_newTaskSheet() throws {
        let calendar = GregorianCalendar.make(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Seoul")))
        let today = try XCTUnwrap(LocalDay(text: "2026-11-06"))
        let content = TaskFormView(today: today, calendar: calendar, onSave: { _ in }, onCancel: {})
            .environment(\.timeZone, calendar.timeZone)
        try write("s08-new-task", content: content, size: CGSize(width: 360, height: 220))
    }

    func test_R102_editTaskSheet() throws {
        let calendar = GregorianCalendar.make(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Seoul")))
        let task = MokaTask(
            id: 2, title: "영단어 30개 외우기", deadline: nil, estMin: 20, recurrence: .weekly,
            weekday: Weekday(rawValue: 4), cycleDay: LocalDay(text: "2026-11-04"), firstAction: "31번부터",
            status: .todo, skipCount: 0, streak: 3, createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        let content = TaskFormView(
            today: try XCTUnwrap(LocalDay(text: "2026-11-06")), calendar: calendar, editing: task, onSave: { _ in },
            onCancel: {})
        try write("s09-edit-task", content: content, size: CGSize(width: 360, height: 270))
    }

    func test_R120_taskListChecked() throws {
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        let rows = (1...4).map { id in
            MokaTask(
                id: TaskID(id), title: ["보고서 1절 쓰기", "장보기 목록 만들기", "치과 예약 전화", "책 반납하기"][id - 1],
                deadline: nil, estMin: nil, recurrence: .none, weekday: nil, cycleDay: nil, firstAction: nil,
                status: id == 1 ? .active : .todo, skipCount: 0, streak: 0, createdAt: created)
        }
        let content = VStack(spacing: 0) {
            SettingsTabBar(selection: .constant(.tasks))
            TaskListTabView(
                rows: rows, nextMarkID: 2, scope: .constant(.all), order: .constant(.created),
                selectedID: .constant(nil), checkedIDs: .constant([1, 3, 4]), canEdit: true, onAdd: {},
                onEdit: { _ in }, onDelete: {})
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MokaColors.settingsWindow)
        try write("s20-task-list-checked", content: content, size: CGSize(width: 460, height: 450))
    }

    func test_R120_contextTabChecked() throws {
        let rows = [
            MokaContext(id: 1, name: "동아리 회의", date: try XCTUnwrap(LocalDay(text: "2026-11-04")), impact: .normal),
            MokaContext(id: 2, name: "가짜 과제 제출", date: try XCTUnwrap(LocalDay(text: "2026-11-07")), impact: .high),
        ]
        let content = VStack(spacing: 0) {
            SettingsTabBar(selection: .constant(.contexts))
            ContextTabView(
                rows: rows, selectedID: .constant(nil), checkedIDs: .constant([1, 2]), canEdit: true, onAdd: {},
                onEdit: { _ in }, onDelete: {})
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MokaColors.settingsWindow)
        try write("s20-context-tab-checked", content: content, size: CGSize(width: 460, height: 450))
    }

    func test_R120_deleteManyConfirm() throws {
        let content = DeleteConfirmView(count: 3, stopsTimer: true, onDelete: {}, onCancel: {})
        try write("s20-delete-many-confirm", content: content, size: CGSize(width: 300, height: 130))
    }

    func test_R120_contextDeleteConfirm() throws {
        let content = DeleteConfirmView(
            heading: ContextText.deleteManyTitle(count: 2), message: ContextText.deleteMessage, onDelete: {},
            onCancel: {})
        try write("s20-context-delete-confirm", content: content, size: CGSize(width: 300, height: 110))
    }

    func test_R122_taskListSomeChecked() throws {
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        let rows = (1...4).map { id in
            MokaTask(
                id: TaskID(id), title: ["보고서 1절 쓰기", "장보기 목록 만들기", "치과 예약 전화", "책 반납하기"][id - 1],
                deadline: nil, estMin: nil, recurrence: .none, weekday: nil, cycleDay: nil, firstAction: nil,
                status: id >= 3 ? .done : .todo, skipCount: 0, streak: 0, createdAt: created)
        }
        let content = VStack(spacing: 0) {
            SettingsTabBar(selection: .constant(.tasks))
            TaskListTabView(
                rows: rows, nextMarkID: 1, scope: .constant(.all), order: .constant(.created),
                selectedID: .constant(nil), checkedIDs: .constant([3]), canEdit: true, onAdd: {},
                onEdit: { _ in }, onDelete: {})
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MokaColors.settingsWindow)
        try write("s22-task-list-some", content: content, size: CGSize(width: 460, height: 450))
    }

    func test_R122_selectAllHeaderStates() throws {
        let content = VStack(spacing: 0) {
            SelectAllHeader(state: .none, onToggle: {})
            SelectAllHeader(state: .some, onToggle: {}) {
                Button("완료만 고르기") {}
            }
            SelectAllHeader(state: .all, onToggle: {})
        }
        .frame(width: 432)
        .background(Color.white)
        try write("s22-select-all-header", content: content, size: CGSize(width: 432, height: 100))
    }

    func test_R102_deleteConfirmActive() throws {
        let content = DeleteConfirmView(title: "보고서 1절 쓰기", stopsTimer: true, onDelete: {}, onCancel: {})
        try write("s09-delete-confirm", content: content, size: CGSize(width: 300, height: 130))
    }

    func test_R101_deadlineCalendar() throws {
        let calendar = GregorianCalendar.make(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Seoul")))
        let content = MokaCalendar(
            selected: LocalDay(text: "2026-11-11"), today: try XCTUnwrap(LocalDay(text: "2026-11-06")),
            calendar: calendar, onPick: { _ in })
        try write("s08-deadline-calendar", content: content, size: CGSize(width: 214, height: 230))
    }

    private func write(_ name: String, content: some View, size: CGSize) throws {
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
    }

    private func snapshot(
        _ name: String, quantumText: String = "25", extendText: String = "10",
        decision: DecisionFieldInput = SettingsSnapshotTests.typeSafe(.noKey),
        start: DecisionFieldStart = DecisionFieldStart(), height: CGFloat = SettingsSnapshotTests.basicHeight
    ) throws {
        let calendar = GregorianCalendar.make(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Seoul")))
        let tab = BasicTabView(
            quantum: Self.input(quantumText, range: Defaults.quantumMinRange),
            extend: Self.input(extendText, range: Defaults.extendMinRange),
            dayStart: .constant(Defaults.dayStart.date(calendar: calendar)), decision: decision, decisionStart: start
        )
        .environment(\.timeZone, calendar.timeZone)
        let content = VStack(spacing: 0) {
            SettingsTabBar(selection: .constant(.basic))
            tab
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MokaColors.settingsWindow)

        try write(name, content: content, size: CGSize(width: 460, height: height))
    }

    /// 다섯 공급자 줄. `opening`에 든 공급자만 고를 수 있다.
    private static func rows(opening: Set<ProviderID> = [.typesafe]) -> [ProviderRow] {
        ProviderCatalog.all.map { row in
            let isOpen = opening.contains(row.id)
            return ProviderRow(
                id: row.id, displayName: row.displayName, isOpen: isOpen,
                closedNote: isOpen ? nil : DecisionFieldText.closedNote)
        }
    }

    /// 지금 빌드처럼 TypeSafe Jev만 열렸고 골라져 있다. 발급 링크는 확인 전이라 없다.
    private static func typeSafe(_ keyState: KeyFieldState, canRetry: Bool = false) -> DecisionFieldInput {
        DecisionFieldInput(
            providers: rows(), selected: .typesafe, host: "api.typesafe.ai", keyState: keyState, canRetry: canRetry)
    }

    /// 가짜로 연 Microsoft 줄을 고른 칸.
    private static func microsoft(
        _ input: MicrosoftFieldInput, host: String?, offNote: String? = nil, keyState: KeyFieldState,
        canRetry: Bool = false
    ) -> DecisionFieldInput {
        DecisionFieldInput(
            providers: rows(opening: [.typesafe, .microsoft]), selected: .microsoft, host: host, offNote: offNote,
            microsoft: input, keyState: keyState, canRetry: canRetry)
    }

    private static let microsoftUnsaved = microsoft(
        MicrosoftFieldInput(savedEndpoint: nil, savedDeployment: nil, showsKeyResetNotice: false, keyCleared: false),
        host: nil, offNote: DecisionFieldText.offNote(.needsEndpoint), keyState: .noKey)

    /// 기본 탭(숫자 칸, 판단 모델 칸) 높이.
    private static let basicHeight: CGFloat = 470
    private static let microsoftHeight: CGFloat = 600

    private static func input(_ text: String, range: ClosedRange<Int>) -> MinutesFieldInput {
        MinutesFieldInput(
            text: .constant(text), stepperValue: QuantumChip.parseCustom(text) ?? range.lowerBound, range: range,
            onCommit: {}, onStep: { _ in })
    }
}
