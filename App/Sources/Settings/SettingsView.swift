import MokaCore
import SwiftUI
import os

/// 설정 창: 위에 탭 줄(`SettingsTabBar`), 창 제목은 "설정"(시안 6·7번, R-012·R-102, 2026-11-04 사용자 결정).
/// 숫자 칸은 받는 값이면 저장하고, 아니거나 저장에 실패하면 저장된 값으로 되돌린다(`FieldCommit`).
/// 스테퍼는 누를 때마다 1분씩 바꿔 바로 저장한다. 하루 시작 시각은 고를 때마다 저장한다.
struct SettingsView: View {
    let store: any SettingsStore
    @Bindable var appState: AppState
    /// 기본 작업 시간 저장을 시도한 뒤 부른다. 펼친 판의 고르지 않은 칩이 새 기본값을 따르게 한다(R-013).
    let onSaved: @MainActor () -> Void

    @State private var quantumText = ""
    @State private var extendText = ""
    @State private var dayStart = Date()
    @State private var tab: SettingsTab = .basic
    @State private var isAddingTask = false
    @State private var selectedTaskID: TaskID?
    @State private var editing: TaskRequest?
    @State private var deleting: TaskRequest?
    @State private var checkedTaskIDs: Set<TaskID> = []
    @State private var deletingTasks: TaskDeletion?
    @State private var checkedContextIDs: Set<ContextID> = []
    @State private var deletingContexts: ContextDeletion?
    @State private var isAddingContext = false
    @State private var selectedContextID: ContextID?
    private let calendar = GregorianCalendar.make(timeZone: .autoupdatingCurrent)
    private static let logger = Logger(subsystem: "dev.dongwon.moka", category: "settings")

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selection: $tab)
            switch tab {
            case .basic:
                BasicTabView(
                    quantum: MinutesFieldInput(
                        text: $quantumText,
                        stepperValue: QuantumChip.parseCustom(quantumText) ?? QuantumSettings.readDefault(from: store),
                        range: Defaults.quantumMinRange,
                        onCommit: { applyQuantum(QuantumSettings.commitField(quantumText, to: store)) },
                        onStep: { applyQuantum(QuantumSettings.saveField($0, to: store)) }),
                    extend: MinutesFieldInput(
                        text: $extendText,
                        stepperValue: QuantumChip.parseCustom(extendText) ?? CoreSettings.readExtendMin(from: store),
                        range: Defaults.extendMinRange,
                        onCommit: { applyExtend(CoreSettings.commitExtendField(extendText, to: store)) },
                        onStep: { applyExtend(CoreSettings.saveExtendField($0, to: store)) }),
                    dayStart: Binding(get: { dayStart }, set: { saveDayStart($0) })
                )
            case .tasks:
                TaskListTabView(
                    rows: appState.taskListRows, nextMarkID: appState.nextMarkID, scope: $appState.taskListScope,
                    order: $appState.taskListOrder, selectedID: $selectedTaskID, checkedIDs: $checkedTaskIDs,
                    canEdit: !appState.storageUnavailable,
                    onAdd: { isAddingTask = true }, onEdit: { editing = request(for: $0) },
                    onDelete: {
                        let ids = visibleCheckedTaskIDs
                        if ids.isEmpty {
                            deleting = selectedTaskID.flatMap(request(for:))
                        } else {
                            deletingTasks = TaskDeletion(
                                ids: ids,
                                stopsTimer: appState.tasks.contains { ids.contains($0.id) && $0.status == .active })
                        }
                    }
                )
            case .contexts:
                ContextTabView(
                    rows: appState.contexts, selectedID: $selectedContextID, checkedIDs: $checkedContextIDs,
                    canEdit: appState.canEditContexts,
                    onAdd: { isAddingContext = true },
                    onDelete: { deletingContexts = contextDeletion() })
            }
        }
        .navigationTitle("설정")
        .sheet(isPresented: $isAddingContext) {
            ContextFormView(
                today: appState.logicalToday, calendar: calendar,
                onSave: { if appState.addContext($0) { isAddingContext = false } },
                onCancel: { isAddingContext = false })
        }
        .sheet(isPresented: $isAddingTask) {
            TaskFormView(
                today: appState.logicalToday, calendar: calendar,
                onSave: { values in
                    let task = NewTask(
                        title: values.title, deadline: values.deadline, estMin: values.estMin,
                        recurrence: values.recurrence, weekday: values.weekday)
                    if appState.addTask(task) { isAddingTask = false }
                },
                onCancel: { isAddingTask = false })
        }
        // 시트 내용은 누른 순간의 할 일을 직접 받는다. 상태 id로 다시 찾으면 시트가 고르기 전 값으로 그려져 빈다.
        .sheet(item: $editing) { request in
            TaskFormView(
                today: appState.logicalToday, calendar: calendar, editing: request.task,
                onSave: { values in
                    if appState.editTask(request.id, Self.edit(from: values)) { editing = nil }
                },
                onCancel: { editing = nil },
                onDelete: {
                    appState.dropTask(request.id)
                    selectedTaskID = nil
                    editing = nil
                })
        }
        // 시트 내용은 누른 순간 모은 값을 받는다. 시트 안에서 체크 상태를 다시 읽으면 처음 뜰 때 0개로 그려졌다(2026-11-06 사람 확인).
        .sheet(item: $deletingTasks) { deletion in
            DeleteConfirmView(
                count: deletion.ids.count, stopsTimer: deletion.stopsTimer,
                onDelete: {
                    appState.dropTasks(deletion.ids)
                    checkedTaskIDs = []
                    selectedTaskID = nil
                    deletingTasks = nil
                },
                onCancel: { deletingTasks = nil })
        }
        .sheet(item: $deletingContexts) { deletion in
            DeleteConfirmView(
                heading: deletion.heading, message: ContextText.deleteMessage,
                onDelete: {
                    appState.deleteContexts(deletion.ids)
                    checkedContextIDs.subtract(deletion.ids)
                    selectedContextID = nil
                    deletingContexts = nil
                },
                onCancel: { deletingContexts = nil })
        }
        .sheet(item: $deleting) { request in
            DeleteConfirmView(
                title: request.task.title, stopsTimer: request.task.status == .active,
                onDelete: {
                    appState.dropTask(request.id)
                    selectedTaskID = nil
                    deleting = nil
                },
                onCancel: { deleting = nil })
        }
        .background(MokaColors.settingsWindow)
        .frame(width: 460)
        .background(SettingsWindowRaiser.Anchor())
        .onAppear(perform: load)
        .onChange(of: tab) { previous, _ in
            if previous == .basic { commitFields() }
        }
        .onDisappear(perform: commitFields)
    }

    /// 체크한 할 일 가운데 지금 보기에 보이는 것만 지운다. 보기를 바꿔 숨은 할 일이 같이 지워지지 않게 한다.
    private var visibleCheckedTaskIDs: Set<TaskID> {
        checkedTaskIDs.intersection(appState.taskListRows.map(\.id))
    }

    /// 체크한 일정이 있으면 그것들, 없으면 고른 한 줄(R-120). 지울 것이 없으면 nil.
    private func contextDeletion() -> ContextDeletion? {
        let checked = checkedContextIDs.intersection(appState.contexts.map(\.id))
        if !checked.isEmpty {
            return ContextDeletion(ids: checked, heading: ContextText.deleteManyTitle(count: checked.count))
        }
        guard let id = selectedContextID, let context = appState.contexts.first(where: { $0.id == id }) else {
            return nil
        }
        return ContextDeletion(ids: [id], heading: ContextText.deleteTitle(context.name))
    }

    private func request(for id: TaskID) -> TaskRequest? {
        appState.tasks.first { $0.id == id }.map(TaskRequest.init)
    }

    private static func edit(from values: TaskFormValues) -> TaskEdit {
        TaskEdit(
            title: values.title, deadline: values.deadline.map { .set($0) } ?? .clear,
            estMin: values.estMin.map { .set($0) } ?? .clear, recurrence: values.recurrence, weekday: values.weekday)
    }

    private func commitFields() {
        applyQuantum(QuantumSettings.commitField(quantumText, to: store))
        applyExtend(CoreSettings.commitExtendField(extendText, to: store))
    }

    private func load() {
        quantumText = String(QuantumSettings.readDefault(from: store))
        extendText = String(CoreSettings.readExtendMin(from: store))
        dayStart = CoreSettings.readDayStart(from: store).date(calendar: calendar)
    }

    private func applyQuantum(_ result: FieldCommit) {
        log(result.error, "기본 작업 시간")
        quantumText = result.shown
        if result.attempted { onSaved() }
    }

    private func applyExtend(_ result: FieldCommit) {
        log(result.error, "추가 시간")
        extendText = result.shown
    }

    private func saveDayStart(_ date: Date) {
        do {
            try CoreSettings.writeDayStart(DayStart(date: date, calendar: calendar), to: store)
        } catch {
            log(error, "하루 시작 시각")
        }
        dayStart = CoreSettings.readDayStart(from: store).date(calendar: calendar)
    }

    private func log(_ error: (any Error)?, _ field: String) {
        guard let error else { return }
        Self.logger.error("\(field, privacy: .public) 저장 실패: \(String(reflecting: type(of: error)), privacy: .public)")
    }
}

/// 고치기·지우기 시트를 띄울 때의 할 일.
private struct TaskRequest: Identifiable {
    let task: MokaTask
    var id: TaskID { task.id }
}

/// 한꺼번에 지울 할 일(R-120). `−`를 누른 순간 모은 값이다.
private struct TaskDeletion: Identifiable {
    let id = UUID()
    let ids: Set<TaskID>
    let stopsTimer: Bool
}

/// 지울 일정(R-120). 하나든 여럿이든 한 번 묻는다.
private struct ContextDeletion: Identifiable {
    let id = UUID()
    let ids: Set<ContextID>
    let heading: String
}
