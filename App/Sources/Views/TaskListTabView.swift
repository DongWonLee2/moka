import MokaCore
import SwiftUI

/// 설정 창 할 일 탭(시안 7번, R-102·R-118). 값과 콜백만 받는다(ADR-0009).
/// 더하기·지우기와 고치기는 할 일 시트(T031)에서 더한다.
struct TaskListTabView: View {
    let rows: [MokaTask]
    /// 노치에 뜨거나 다음에 뜰 할 일(`NotchSession.nextMark`).
    let nextMarkID: TaskID?
    @Binding var scope: TaskListScope
    @Binding var order: TaskListOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("보기", selection: $scope) {
                    Text("전체").tag(TaskListScope.all)
                    Text("오늘").tag(TaskListScope.today)
                    Text("이번 주").tag(TaskListScope.thisWeek)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Picker("정렬", selection: $order) {
                    Text("만든 순").tag(TaskListOrder.created)
                    Text("마감 순").tag(TaskListOrder.deadline)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
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
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: .separatorColor)))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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
