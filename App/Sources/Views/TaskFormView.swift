import MokaCore
import SwiftUI

/// 새 할 일 시트(시안 8번, R-101). 값과 콜백만 받는다(ADR-0009). 저장 규칙 검증은 `TaskWriteRules`가 다시 한다.
struct TaskFormView: View {
    let today: LocalDay
    let calendar: Calendar
    let onSave: (NewTask) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var deadline: LocalDay?
    @State private var isPickingDeadline = false
    @State private var recurrence: Recurrence = .none
    @State private var weekday: Weekday?
    @State private var estText = ""
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
            Text("새 할 일")
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
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        Hint(TaskFormText.weekdayHint(today: todayWeekday))
                    }
                }
                GridRow {
                    FormLabel("예상 소요")
                    HStack(spacing: 4) {
                        TextField("—", text: $estText)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 52)
                            .accessibilityLabel("예상 소요 분")
                        Text("분")
                        if estText.isEmpty {
                            Hint("비워 둬도 돼요")
                        }
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
                if let titleIssue {
                    Text(titleIssue)
                        .font(.system(size: 11))
                        .foregroundStyle(MokaColors.danger)
                }
                Spacer()
                SheetButton(title: "취소", isPrimary: false, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                SheetButton(title: "저장", isPrimary: true, action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 360)
        .background(colorScheme == .dark ? Color(hex: 0x332D29) : Color(hex: 0xFAF7F5))
        .onAppear { isTitleFocused = true }
    }

    /// 요일을 건드리지 않았으면 nil로 넘겨 `prepareNew`가 저장 순간의 하루로 채운다(§5.8).
    private func save() {
        guard canSave else { return }
        let task = NewTask(
            title: title, deadline: recurrence == .none ? deadline : nil, estMin: TaskFormText.estMin(estText),
            recurrence: recurrence, weekday: recurrence == .weekly ? weekday : nil)
        onSave(task)
    }
}

private struct FormLabel: View {
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

private struct SheetButton: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: isPrimary ? .semibold : .regular))
                .foregroundStyle(isPrimary ? MokaColors.textOnPrimary : Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 22)
                .background(background, in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            isPrimary || colorScheme == .dark ? Color.clear : Color(hex: 0x3C2314, opacity: 0.3),
                            lineWidth: 0.5)
                )
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        if isPrimary { return MokaColors.mocha }
        return colorScheme == .dark ? Color(hex: 0x4A423C) : .white
    }
}

private struct PillButton: View {
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
            if selected != nil {
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
