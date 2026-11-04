import MokaCore
import SwiftUI

/// 새 할 일 시트(시안 8번, R-101). 값과 콜백만 받는다(ADR-0009). 저장 규칙 검증은 `TaskWriteRules`가 다시 한다.
struct TaskFormView: View {
    let today: LocalDay
    let calendar: Calendar
    let onSave: (NewTask) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @State private var hasDeadline = false
    @State private var deadline = Date()
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
                }
                GridRow {
                    FormLabel("마감")
                    HStack(spacing: 8) {
                        MokaCheckbox(title: "마감 있음", isOn: $hasDeadline)
                        if hasDeadline {
                            DatePicker("마감", selection: $deadline, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.field)
                                .environment(\.calendar, calendar)
                                .environment(\.timeZone, calendar.timeZone)
                        }
                    }
                }
                GridRow {
                    FormLabel("반복")
                    ChoiceChips(
                        label: "반복", items: [(Recurrence.none, "없음"), (.daily, "매일"), (.weekly, "매주")],
                        selection: $recurrence)
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
        .onAppear {
            deadline = today.date(calendar: calendar)
            isTitleFocused = true
        }
    }

    private func save() {
        let task = NewTask(
            title: title, deadline: hasDeadline ? LocalDay(date: deadline, calendar: calendar) : nil,
            estMin: TaskFormText.estMin(estText), recurrence: recurrence,
            weekday: recurrence == .weekly ? (weekday ?? todayWeekday) : nil)
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

/// 체크 상자(시안 `.cb`). macOS 체크 상자는 켠 상태를 시스템 강조색으로 그려 직접 그린다.
private struct MokaCheckbox: View {
    let title: String
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn ? MokaColors.mocha : (colorScheme == .dark ? Color(hex: 0x1F1B18) : .white))
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                colorScheme == .dark
                                    ? Color(hex: 0xFFF0E1, opacity: 0.3) : Color(hex: 0x3C2314, opacity: 0.4),
                                lineWidth: 0.5)
                    }
                }
                .frame(width: 14, height: 14)
                Text(title)
                    .font(.system(size: 12.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
