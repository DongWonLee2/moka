import MokaCore
import SwiftUI
import XCTest

/// 설정 창 탭 내용을 라이트·다크 PNG로 만든다(ADR-0009, 시안 6번). sanity만 보고 정합은 사람이 비교 페이지에서 본다.
@MainActor
final class SettingsSnapshotTests: XCTestCase {
    /// 설정 창 폭 460pt. 높이는 기본 탭 내용이 들어가는 만큼.
    private static let size = CGSize(width: 460, height: 240)

    func test_R012_basicTabDefaults() throws {
        try snapshot("s06-basic", quantumText: "25", extendText: "10")
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
                rows: rows, selectedID: .constant(2), checkedIDs: .constant([]), canEdit: true, onAdd: {}, onDelete: {})
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
                onDelete: {})
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

    private func snapshot(_ name: String, quantumText: String, extendText: String) throws {
        let calendar = GregorianCalendar.make(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Seoul")))
        let tab = BasicTabView(
            quantum: Self.input(quantumText, range: Defaults.quantumMinRange),
            extend: Self.input(extendText, range: Defaults.extendMinRange),
            dayStart: .constant(Defaults.dayStart.date(calendar: calendar))
        )
        .environment(\.timeZone, calendar.timeZone)
        let content = VStack(spacing: 0) {
            SettingsTabBar(selection: .constant(.basic))
            tab
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MokaColors.settingsWindow)

        try write(name, content: content, size: Self.size)
    }

    private static func input(_ text: String, range: ClosedRange<Int>) -> MinutesFieldInput {
        MinutesFieldInput(
            text: .constant(text), stepperValue: QuantumChip.parseCustom(text) ?? range.lowerBound, range: range,
            onCommit: {}, onStep: { _ in })
    }
}
