import MokaCore
import SwiftUI

/// 이월 카드의 고정 글자(확정 시안 005 1~3번). 값을 끼우는 글자는 MokaCore `CarryText`에 있다.
enum CarryCardText {
    static let today = "오늘 할래요"
    static let drop = "버릴래요"
    static let move = "날짜 바꿀래요"
    static let tomorrow = "내일"
    static let dayAfter = "모레"
    static let nextMonday = "다음 주 월요일"
    /// 시안 밖 문구, 사용자 결정 2026-11-17.
    static let answerFailed = "답을 저장하지 못했어요. 다시 해 주세요."
}

/// 카드 한 장(R-414). `move`가 있으면 날짜 고르기(R-415)를 보인다.
struct CarryCardInput {
    var title: String
    var firstAction: String?
    /// `CarryText.reason`의 글자.
    var reason: String
    /// 지금 것을 포함한 남은 수.
    var left: Int
    /// 이번 묶음에서 이미 답한 수. 점은 답한 수 + 남은 수만큼 그리고 지금 것에 불을 켠다.
    var answered: Int
    var failed = false
    var move: CarryMoveInput?
    var onToday: () -> Void = {}
    var onDrop: () -> Void = {}
    var onBeginMove: () -> Void = {}
}

struct CarryMoveInput {
    var selected: LocalDay
    var today: LocalDay
    var deadline: LocalDay?
    var calendar: Calendar
    var onPick: (LocalDay) -> Void = { _ in }
    var onCancel: () -> Void = {}
    var onConfirm: () -> Void = {}
}

/// 펼친 판의 카드 내용. 귀와 바깥 여백은 `ExpandedView`가 그린다.
struct CarryCardView: View {
    let input: CarryCardInput

    var body: some View {
        if let move = input.move {
            CarryMoveView(title: input.title, left: input.left, failed: input.failed, input: move)
        } else {
            card
        }
    }

    @ViewBuilder
    private var card: some View {
        CarryHeader(left: input.left) {
            Text(input.reason)
        } trailing: {
            CarryPips(total: input.answered + input.left, current: input.answered)
        }
        TitleText(title: input.title)
        if let firstAction = input.firstAction {
            FirstActionLine(text: firstAction)
        }
        HStack(spacing: 6) {
            Button(CarryCardText.drop, action: input.onDrop)
                .buttonStyle(NotchButtonStyle(kind: .ghostDanger))
            Button(CarryCardText.move, action: input.onBeginMove)
                .buttonStyle(NotchButtonStyle(kind: .secondary))
            Spacer(minLength: 0)
            Button(action: input.onToday) { ButtonLabel(text: CarryCardText.today, shortcut: "↵") }
                .buttonStyle(NotchButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
        }
        if input.failed {
            CustomIssueText(message: CarryCardText.answerFailed)
        }
    }
}

/// 카드 위 줄: 왼쪽 강조 글자, 가운데 빈칸, 오른쪽 점(있으면)과 남은 개수(시안 `.cc-head`).
private struct CarryHeader<Leading: View, Trailing: View>: View {
    let left: Int
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    @Environment(\.panelPalette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            leading
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.firstAction)
                .lineLimit(1)
            Spacer(minLength: 0)
            trailing
            Text(CarryText.left(left))
                .font(.system(size: 11))
                .foregroundStyle(palette.muted)
                .monospacedDigit()
        }
        .padding(.bottom, -4)
    }
}

private struct CarryPips: View {
    let total: Int
    let current: Int

    @Environment(\.panelPalette) private var palette

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index == current ? palette.firstAction : palette.pipOff)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 날짜 고르기(시안 3번). 오늘과 지난 날은 누를 수 없고, 지금 마감은 빨간 테두리다.
private struct CarryMoveView: View {
    let title: String
    let left: Int
    let failed: Bool
    let input: CarryMoveInput

    @State private var shownPage: CarryMonthPage?
    @Environment(\.panelPalette) private var palette

    private static let weekdayNames = ["일", "월", "화", "수", "목", "금", "토"]

    private var page: CarryMonthPage {
        shownPage ?? CarryMonthPage(selected: input.selected, today: input.today, calendar: input.calendar)
    }
    private var month: CalendarMonth { page.month }

    private func turn(_ change: (inout CarryMonthPage) -> Void) {
        var next = page
        change(&next)
        shownPage = next
    }

    private func pick(_ day: LocalDay) {
        turn { $0.pick(day) }
        input.onPick(day)
    }

    var body: some View {
        CarryHeader(left: left) {
            Text(title)
        } trailing: {
            EmptyView()
        }
        Text(CarryText.moveNote(deadline: input.deadline, calendar: input.calendar))
            .font(.system(size: 11))
            .foregroundStyle(palette.muted)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 4) {
            let quick = CarryText.quickDays(after: input.today, calendar: input.calendar)
            ForEach(
                Array(zip([CarryCardText.tomorrow, CarryCardText.dayAfter, CarryCardText.nextMonday], quick)),
                id: \.0
            ) { label, day in
                Button(label) { pick(day) }
                    .buttonStyle(NotchButtonStyle(kind: .secondary, compact: true))
            }
        }
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("\(String(month.year))년 \(month.month)월")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Button("‹") { turn { $0.previous() } }
                    .disabled(!page.canGoBack)
                    .accessibilityLabel("이전 달")
                Button("›") { turn { $0.next() } }
                    .accessibilityLabel("다음 달")
            }
            .buttonStyle(CalendarArrowStyle())
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    ForEach(Self.weekdayNames, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 10))
                            .foregroundStyle(palette.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                    }
                }
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    GridRow {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            if let day {
                                CarryDayCell(
                                    day: day, isPickable: input.today < day, isToday: day == input.today,
                                    isDeadline: day == input.deadline, isSelected: day == input.selected
                                ) { pick(day) }
                            } else {
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                            }
                        }
                    }
                }
            }
        }
        HStack(spacing: 6) {
            Button(action: input.onCancel) { ButtonLabel(text: NotchText.back, shortcut: "esc") }
                .buttonStyle(NotchButtonStyle(kind: .ghost))
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: 0)
            Button(action: input.onConfirm) {
                ButtonLabel(text: CarryText.moveConfirm(input.selected), shortcut: "↵")
            }
            .buttonStyle(NotchButtonStyle(kind: .primary))
            .keyboardShortcut(.defaultAction)
        }
        if failed {
            CustomIssueText(message: CarryCardText.answerFailed)
        }
    }

    /// 일요일 시작 주로 나눈 칸. 마지막 주는 빈칸으로 채운다.
    private var weeks: [[LocalDay?]] {
        let cells = month.cells(calendar: input.calendar)
        let padded = cells + Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: padded.count, by: 7).map { Array(padded[$0..<$0 + 7]) }
    }
}

private struct CarryDayCell: View {
    let day: LocalDay
    let isPickable: Bool
    let isToday: Bool
    let isDeadline: Bool
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.panelPalette) private var palette

    var body: some View {
        Button(action: action) {
            Text("\(day.day)")
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 5).fill(MokaColors.primaryGradient)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(border, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isPickable)
        .accessibilityLabel("\(day.month)월 \(day.day)일")
        .accessibilityValue(accessibilityNote)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityNote: String {
        [isDeadline ? "지금 마감" : nil, isToday ? "오늘" : nil].compactMap { $0 }.joined(separator: ", ")
    }

    private var foreground: Color {
        if isSelected { return MokaColors.textOnPrimary }
        if isDeadline { return palette.deadlineDay }
        return isPickable ? palette.foreground : palette.textDisabled
    }

    private var border: Color {
        if isSelected { return .clear }
        if isDeadline { return palette.danger }
        return isToday ? palette.pipOff : .clear
    }
}

private struct CalendarArrowStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.panelPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(isEnabled ? palette.muted : palette.textDisabled)
            .padding(.horizontal, 4)
            .contentShape(.rect)
    }
}

/// 접힌 판 왼쪽 칸의 카드 대기(시안 10-1번): 빨간 점과 "정할 일 N개".
struct CollapsedCarryView: View {
    let left: Int

    @Environment(\.panelPalette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(palette.danger)
                .frame(width: 6, height: 6)
                .shadow(color: palette.activeDotGlows ? palette.danger.opacity(0.6) : .clear, radius: 3)
            Text(CarryText.collapsed(left))
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(palette.firstAction)
        }
    }
}
