import MokaCore
import SwiftUI

/// 설정 창 할 일 탭(시안 7번, R-102·R-118). 값과 콜백만 받는다(ADR-0009).
struct TaskListTabView: View {
    let rows: [MokaTask]
    let nextMarkID: TaskID?
    @Binding var scope: TaskListScope
    @Binding var order: TaskListOrder
    @Binding var selectedID: TaskID?
    /// 한꺼번에 지울 할 일(R-120). 있으면 `−`가 이것들을 지운다.
    @Binding var checkedIDs: Set<TaskID>
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
            VStack(spacing: 0) {
                SelectAllHeader(
                    state: RowSelection.state(checked: checkedIDs, visible: rows.map(\.id)),
                    onToggle: { checkedIDs = RowSelection.toggledAll(checked: checkedIDs, visible: rows.map(\.id)) }
                ) {
                    HeaderTextButton(title: "완료만 고르기") {
                        checkedIDs = RowSelection.doneOnly(rows.map { ($0.id, $0.status == .done) })
                    }
                    .disabled(!rows.contains { $0.status == .done })
                }
                .disabled(rows.isEmpty)
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, task in
                            if index > 0 { Divider() }
                            // 체크 칸은 줄 고르기·두 번 클릭 고치기 영역 밖에 둔다. 안에 두면 체크 칸을 빠르게 두 번 누를 때
                            // 고치기 시트가 같이 열렸다(PR #88 리뷰).
                            HStack(spacing: 0) {
                                RowCheckBox(
                                    isOn: Binding(
                                        get: { checkedIDs.contains(task.id) },
                                        set: { isOn in
                                            if isOn { checkedIDs.insert(task.id) } else { checkedIDs.remove(task.id) }
                                        }),
                                    label: task.title
                                )
                                .padding(.leading, 10)
                                TaskRow(task: task, isNext: task.id == nextMarkID)
                                    .contentShape(Rectangle())
                                    // 두 번 클릭을 동시에 들어야 한 번 클릭이 더블 클릭 간격을 기다리지 않는다.
                                    .onTapGesture { selectedID = task.id }
                                    .simultaneousGesture(
                                        TapGesture(count: 2).onEnded { if canEdit { onEdit(task.id) } }
                                    )
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAddTraits(task.id == selectedID ? .isSelected : [])
                            }
                            .background(task.id == selectedID ? MokaColors.mocha.opacity(0.22) : Color.clear)
                            .accessibilityAction(named: "고치기") { if canEdit { onEdit(task.id) } }
                        }
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
                        .disabled(!canEdit || !rows.contains { $0.id == selectedID || checkedIDs.contains($0.id) })
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

struct ListEditButton: View {
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

/// 줄 왼쪽 체크 칸(R-120). macOS 체크 상자는 시스템 강조색이라 모카색으로 직접 그린다.
struct RowCheckBox: View {
    @Binding var isOn: Bool
    let label: String
    /// 일부만 골랐을 때(R-122 머리 줄). 칸을 채우고 `−`를 그린다.
    var isMixed = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let filled = isOn || isMixed
        Button {
            isOn.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 3.5)
                .fill(filled ? MokaColors.mocha : (colorScheme == .dark ? Color(hex: 0x1F1B18) : .white))
                .overlay(
                    RoundedRectangle(cornerRadius: 3.5)
                        .strokeBorder(filled ? Color.clear : Color(hex: 0x806E5F, opacity: 0.55), lineWidth: 1)
                )
                .overlay {
                    if filled {
                        Image(systemName: isMixed ? "minus" : "checkmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(MokaColors.textOnPrimary)
                    }
                }
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) 고르기")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// 목록 맨 위 "전체" 줄(R-122). 체크 칸은 줄 체크 칸과 같은 자리이고, 일부만 골랐으면 `−`다.
struct SelectAllHeader<Trailing: View>: View {
    let state: RowSelection.State
    let onToggle: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    init(state: RowSelection.State, onToggle: @escaping () -> Void, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.state = state
        self.onToggle = onToggle
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            RowCheckBox(
                isOn: Binding(get: { state == .all }, set: { _ in onToggle() }), label: "전체",
                isMixed: state == .some
            )
            .accessibilityValue(state == .some ? "일부 고름" : "")
            Text("전체")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
    }
}

extension SelectAllHeader where Trailing == EmptyView {
    init(state: RowSelection.State, onToggle: @escaping () -> Void) {
        self.init(state: state, onToggle: onToggle) { EmptyView() }
    }
}

struct HeaderTextButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(colorScheme == .dark ? MokaColors.crema : MokaColors.mocha)
            .opacity(isEnabled ? 1 : 0.4)
    }
}
