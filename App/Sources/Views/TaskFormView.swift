import MokaCore
import SwiftUI

struct TaskFormValues: Equatable {
    var title: String
    var deadline: LocalDay?
    var recurrence: Recurrence
    var weekday: Weekday?
    var estMin: Int?
}

/// 할 일 시트(시안 8·9번, R-101·R-102). `editing`이 있으면 고치기다. 값과 콜백만 받는다(ADR-0009).
/// 저장 규칙 검증은 `TaskWriteRules`가 다시 한다.
struct TaskFormView: View {
    let today: LocalDay
    let calendar: Calendar
    let editing: MokaTask?
    let onSave: (TaskFormValues) -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    @State private var title: String
    @State private var deadline: LocalDay?
    @State private var isPickingDeadline = false
    @State private var recurrence: Recurrence
    @State private var weekday: Weekday?
    @State private var estText: String
    @State private var isConfirmingDelete = false

    init(
        today: LocalDay, calendar: Calendar, editing: MokaTask? = nil, onSave: @escaping (TaskFormValues) -> Void,
        onCancel: @escaping () -> Void, onDelete: @escaping () -> Void = {}
    ) {
        self.today = today
        self.calendar = calendar
        self.editing = editing
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        _title = State(initialValue: editing?.title ?? "")
        _deadline = State(initialValue: editing?.deadline)
        _recurrence = State(initialValue: editing?.recurrence ?? .none)
        _weekday = State(initialValue: editing?.weekday)
        _estText = State(initialValue: editing?.estMin.map(String.init) ?? "")
    }
    @FocusState private var isTitleFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private static let weekdayItems: [(Weekday, String)] = zip(1...7, ["일", "월", "화", "수", "목", "금", "토"])
        .compactMap { raw, name in Weekday(rawValue: raw).map { ($0, name) } }

    private var todayWeekday: Weekday { today.weekday(calendar: calendar) }
    private var titleIssue: String? { TaskFormText.titleIssue(title) }
    private var estIssue: String? { TaskFormText.estMinIssue(estText) }
    private var canSave: Bool { titleIssue == nil && estIssue == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(editing == nil ? "새 할 일" : "할 일 고치기")
                .font(.system(size: 13, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    FormLabel("제목")
                    TextField("무엇을 할까요?", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTitleFocused)
                        .accessibilityLabel("제목")
                }
                GridRow {
                    FormLabel("반복")
                    ChoiceChips(
                        label: "반복", items: [(Recurrence.none, "없음"), (.daily, "매일"), (.weekly, "매주")],
                        selection: $recurrence)
                }
                if recurrence == .none {
                    GridRow {
                        FormLabel("마감")
                        PillButton(title: TaskFormText.deadlineLabel(deadline), isMuted: deadline == nil) {
                            isPickingDeadline = true
                        }
                        .accessibilityLabel("마감")
                        .accessibilityValue(TaskFormText.deadlineLabel(deadline))
                        .popover(isPresented: $isPickingDeadline, arrowEdge: .bottom) {
                            MokaCalendar(
                                selected: deadline, today: today, calendar: calendar,
                                onPick: { day in
                                    deadline = day
                                    isPickingDeadline = false
                                })
                        }
                    }
                }
                if recurrence == .weekly {
                    GridRow {
                        FormLabel("요일")
                        ChoiceChips(
                            label: "요일", items: Self.weekdayItems,
                            selection: Binding(get: { weekday ?? todayWeekday }, set: { weekday = $0 }),
                            horizontalPadding: 6)
                    }
                }
                GridRow {
                    FormLabel("다 하는 데")
                    HStack(spacing: 4) {
                        TextField("—", text: $estText)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 52)
                            .accessibilityLabel("다 하는 데 걸릴 시간, 분")
                        Text("분쯤 걸려요")
                    }
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Hint("끝까지 하는 데 걸릴 시간이에요. 비워 둬도 되고, 나눠서 해도 돼요.")
                }
                if let firstAction = editing?.firstAction {
                    GridRow {
                        FormLabel("이어서 할 일")
                        Text(TaskFormText.firstActionNote(firstAction))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                if let estIssue {
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        Text(estIssue)
                            .font(.system(size: 11))
                            .foregroundStyle(MokaColors.danger)
                    }
                }
            }
            HStack(spacing: 6) {
                if editing != nil {
                    SheetButton(title: "지우기…", kind: .dangerText) { isConfirmingDelete = true }
                }
                if let titleIssue {
                    Text(titleIssue)
                        .font(.system(size: 11))
                        .foregroundStyle(MokaColors.danger)
                }
                Spacer()
                SheetButton(title: "취소", kind: .normal, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                SheetButton(title: "저장", kind: .primary, action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 360)
        .background(colorScheme == .dark ? Color(hex: 0x332D29) : Color(hex: 0xFAF7F5))
        .onAppear { isTitleFocused = true }
        .sheet(isPresented: $isConfirmingDelete) {
            if let editing {
                DeleteConfirmView(
                    title: editing.title, stopsTimer: editing.status == .active,
                    onDelete: {
                        isConfirmingDelete = false
                        onDelete()
                    },
                    onCancel: { isConfirmingDelete = false })
            }
        }
    }

    /// 요일을 건드리지 않았으면 nil로 넘겨 `prepareNew`가 저장 순간의 하루로 채운다(§5.8).
    private func save() {
        guard canSave else { return }
        onSave(
            TaskFormValues(
                title: title, deadline: recurrence == .none ? deadline : nil, recurrence: recurrence,
                weekday: recurrence == .weekly ? weekday : nil, estMin: TaskFormText.estMin(estText)))
    }
}

struct FormLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: 76, alignment: .trailing)
    }
}

private struct Hint: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SheetButton: View {
    enum Kind { case normal, primary, danger, dangerText }

    let title: String
    let kind: Kind
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: kind == .primary || kind == .danger ? .semibold : .regular))
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .frame(height: 22)
                .background(background, in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(hasBorder ? Color(hex: 0x3C2314, opacity: 0.3) : Color.clear, lineWidth: 0.5)
                )
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var hasBorder: Bool { colorScheme == .light && (kind == .normal || kind == .dangerText) }

    private var foreground: Color {
        switch kind {
        case .primary, .danger: MokaColors.textOnPrimary
        case .normal: .primary
        case .dangerText: MokaColors.danger
        }
    }

    private var background: Color {
        switch kind {
        case .primary: MokaColors.mocha
        case .danger: MokaColors.danger
        case .normal, .dangerText: colorScheme == .dark ? Color(hex: 0x4A423C) : .white
        }
    }
}

struct DeleteConfirmView: View {
    private let heading: String
    private let message: String
    let onDelete: () -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    init(heading: String, message: String, onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.heading = heading
        self.message = message
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    init(title: String, stopsTimer: Bool, onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.init(
            heading: TaskFormText.deleteTitle(title), message: TaskFormText.deleteMessage(stopsTimer: stopsTimer),
            onDelete: onDelete, onCancel: onCancel)
    }

    /// 여러 개 지우기(R-120).
    init(count: Int, stopsTimer: Bool, onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.init(
            heading: TaskFormText.deleteManyTitle(count: count),
            message: TaskFormText.deleteManyMessage(stopsTimer: stopsTimer), onDelete: onDelete, onCancel: onCancel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Spacer()
                SheetButton(title: "취소", kind: .normal, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                SheetButton(title: "지우기", kind: .danger, action: onDelete)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 300)
        .background(colorScheme == .dark ? Color(hex: 0x332D29) : Color(hex: 0xFAF7F5))
    }
}

struct PillButton: View {
    let title: String
    let isMuted: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .foregroundStyle(isMuted ? Color.secondary : Color.primary)
                Text("▾")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(colorScheme == .dark ? Color(hex: 0x1F1B18) : .white, in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(
                        colorScheme == .dark ? Color(hex: 0xFFF0E1, opacity: 0.2) : Color(hex: 0x3C2314, opacity: 0.3),
                        lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MokaCalendar: View {
    let selected: LocalDay?
    let today: LocalDay
    let calendar: Calendar
    /// 날짜를 비울 수 있는지. 일정 날짜는 필수라 끈다(R-115).
    var allowsClear = true
    let onPick: (LocalDay?) -> Void

    @State private var monthOffset = 0

    private static let weekdayNames = ["일", "월", "화", "수", "목", "금", "토"]

    private var month: CalendarMonth { CalendarMonth(containing: selected ?? today).adding(months: monthOffset) }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button("‹") { monthOffset -= 1 }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("이전 달")
                Spacer()
                Text("\(String(month.year))년 \(month.month)월")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("›") { monthOffset += 1 }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("다음 달")
            }
            .buttonStyle(.plain)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 2), count: 7), spacing: 2) {
                ForEach(Self.weekdayNames, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(month.cells(calendar: calendar).enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayCell(day: day, isSelected: day == selected, isToday: day == today) { onPick(day) }
                    } else {
                        Color.clear.frame(height: 22)
                    }
                }
            }
            if allowsClear, selected != nil {
                Button("마감 지우기") { onPick(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(MokaColors.danger)
            }
        }
        .padding(10)
        .frame(width: 214)
    }
}

private struct DayCell: View {
    let day: LocalDay
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(day.day)")
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? MokaColors.textOnPrimary : Color.primary)
                .frame(width: 26, height: 22)
                .background(isSelected ? MokaColors.mocha : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isToday && !isSelected ? MokaColors.mochaHighlight : Color.clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.month)월 \(day.day)일")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
