import MokaCore
import SwiftUI

/// 설정 창 할 일 탭(시안 7번, R-102·R-118). 값과 콜백만 받는다(ADR-0009).
struct TaskListTabView: View {
    let rows: [MokaTask]
    let nextMarkID: TaskID?
    @Binding var scope: TaskListScope
    @Binding var order: TaskListOrder

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ScopeChips(selection: $scope)
                Spacer()
                SortPill(selection: $order)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, task in
                        if index > 0 { Divider() }
                        TaskRow(task: task, isNext: task.id == nextMarkID)
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
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }
}

/// 보기 고르기(시안 7번 `.ms`). macOS 세그먼트는 고른 칸을 시스템 강조색으로 그려 직접 그린다.
private struct ScopeChips: View {
    @Binding var selection: TaskListScope
    @Environment(\.colorScheme) private var colorScheme

    private static let items: [(TaskListScope, String)] = [(.all, "전체"), (.today, "오늘"), (.thisWeek, "이번 주")]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.items, id: \.0) { scope, title in
                let isOn = scope == selection
                Button {
                    selection = scope
                } label: {
                    Text(title)
                        .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? MokaColors.textOnPrimary : Color.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 1)
                        .background(isOn ? MokaColors.mocha : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            colorScheme == .dark ? Color(hex: 0xFFF0E1, opacity: 0.09) : Color(hex: 0x3C2314, opacity: 0.08),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("보기")
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
