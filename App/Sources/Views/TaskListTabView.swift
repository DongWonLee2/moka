import MokaCore
import SwiftUI

/// 설정 창 할 일 탭(시안 7번, R-102·R-118). 값과 콜백만 받는다(ADR-0009).
struct TaskListTabView: View {
    let rows: [MokaTask]
    let nextMarkID: TaskID?
    @Binding var scope: TaskListScope
    @Binding var order: TaskListOrder
    @Binding var selectedID: TaskID?
    /// 저장할 수 없으면(R-119) 더하기·고치기·지우기가 꺼진다.
    let canEdit: Bool
    let onAdd: () -> Void
    let onEdit: (TaskID) -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ChoiceChips(
                    label: "보기", items: [(TaskListScope.all, "전체"), (.today, "오늘"), (.thisWeek, "이번 주")],
                    selection: $scope)
                Spacer()
                SortPill(selection: $order)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, task in
                        if index > 0 { Divider() }
                        TaskRow(task: task, isNext: task.id == nextMarkID, isSelected: task.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                selectedID = task.id
                                if canEdit { onEdit(task.id) }
                            }
                            .onTapGesture { selectedID = task.id }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction(named: "고치기") { if canEdit { onEdit(task.id) } }
                    }
                }
            }
            .frame(height: 300)
            .background(
                colorScheme == .dark ? Color(hex: 0x221E1B) : Color.white, in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color(hex: 0xFFF0E1, opacity: 0.12) : Color(hex: 0x3C2314, opacity: 0.18),
                        lineWidth: 0.5))
            HStack(spacing: 6) {
                HStack(spacing: 1) {
                    ListEditButton(symbol: "plus", label: "새 할 일", action: onAdd)
                        .disabled(!canEdit)
                    ListEditButton(symbol: "minus", label: "고른 할 일 지우기", action: onDelete)
                        .disabled(!canEdit || selectedID == nil)
                }
                Text("두 번 클릭하면 고쳐요. **다음** 표시가 붙은 할 일이 노치에 떠요.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }
}

private struct SortPill: View {
    @Binding var selection: TaskListOrder
    @Environment(\.colorScheme) private var colorScheme

    private static let items: [(TaskListOrder, String)] = [(.created, "만든 순"), (.deadline, "마감 순")]

    private var title: String { Self.items.first { $0.0 == selection }?.1 ?? "" }

    var body: some View {
        Menu {
            Picker("정렬", selection: $selection) {
                ForEach(Self.items, id: \.0) { order, title in
                    Text(title).tag(order)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text("\(title) ▾")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
                .background(
                    colorScheme == .dark ? Color(hex: 0x3B342F) : Color.white, in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            colorScheme == .dark ? Color.clear : Color(hex: 0x3C2314, opacity: 0.3), lineWidth: 0.5)
                )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("정렬")
        .accessibilityValue(title)
    }
}

private struct TaskRow: View {
    let task: MokaTask
    let isNext: Bool
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var isDone: Bool { task.status == .done }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .fontWeight(.medium)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    Text(TaskRowText.meta(task))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let streak = TaskRowText.streakBadge(task) {
                        StreakBadge(text: streak)
                    }
                }
            }
            Spacer(minLength: 0)
            if isNext {
                Text("다음")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .foregroundStyle(nextColor)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(nextColor, lineWidth: 1))
            }
            StatusBadge(status: task.status)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 40)
        .background(isSelected ? MokaColors.mocha.opacity(0.22) : Color.clear)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var nextColor: Color { colorScheme == .dark ? MokaColors.crema : MokaColors.mocha }
}

private struct StreakBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            CupIcon()
                .frame(width: 10, height: 10)
            Text(text)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .padding(.horizontal, 7)
        .foregroundStyle(MokaColors.textOnPrimary)
        .background(
            LinearGradient(colors: [MokaColors.mocha, MokaColors.mochaLow], startPoint: .top, endPoint: .bottom),
            in: Capsule())
    }
}

private struct StatusBadge: View {
    let status: TaskStatus

    var body: some View {
        Text(TaskRowText.status(status))
            .font(.system(size: 10.5))
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
    }

    private var foreground: AnyShapeStyle {
        switch status {
        case .active: AnyShapeStyle(MokaColors.textOnPrimary)
        case .done: AnyShapeStyle(.secondary)
        case .todo, .dropped: AnyShapeStyle(.primary)
        }
    }

    private var background: AnyShapeStyle {
        switch status {
        case .active: AnyShapeStyle(MokaColors.mocha)
        case .todo, .dropped: AnyShapeStyle(Color(hex: 0x806E5F, opacity: 0.16))
        case .done: AnyShapeStyle(Color.clear)
        }
    }
}

private struct ListEditButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 20)
                .background(
                    colorScheme == .dark ? Color(hex: 0x3B342F) : Color.white, in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            colorScheme == .dark ? Color.clear : Color(hex: 0x3C2314, opacity: 0.2), lineWidth: 0.5)
                )
                .opacity(isEnabled ? 1 : 0.35)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
