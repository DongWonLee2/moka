import MokaCore
import SwiftUI

/// 가용 시간 질문·늘리기·오늘 끝의 고정 글자(확정 시안 005 4~9·10-2·10-3번). 값을 끼우는 글자는 MokaCore `BudgetText`에 있다.
/// 쓰기 실패 네 줄은 시안 밖 문구다(사용자 결정 2026-11-17). 시작 커밋 실패는 data-model §11 글자다.
enum BudgetViewText {
    static let ask = "오늘 몇 시간 할까요?"
    static let askDetail = "고른 시간 안에서만 할 일을 띄워요. 다 쓰면 알려 드릴게요."
    static let pickHint = "고르면 바로 첫 할 일이 떠요"
    static let custom = "직접…"
    static let hoursUnit = "시간"
    static let decide = "정하기"
    static let customHint = "30분 단위로 16시간까지 적을 수 있어요. 예: 1.5"
    static let answerFailed = "답을 저장하지 못했어요. 다시 해 주세요."
    static let extendStart = "늘리고 시작"
    static let extendFailed = "시간을 늘리지 못했어요. 다시 해 주세요."
    static let startFailed = "시작하지 못했어요. 다시 해 주세요."
    static let dayEndDetail = "수고했어요. 더 하고 싶으면 \"더 할래요\"를 눌러 주세요. 오늘은 시간 제한 없이 할 일을 띄워요."
    static let usedLabel = "오늘 쓴 시간"
    static let more = "더 할래요"
    static let moreFailed = "이어서 하지 못했어요. 다시 해 주세요."
    static let collapsedAsk = "몇 시간 할까요?"
    static let collapsedDayEnd = "오늘 끝"
}

/// 늘리기 확인 줄의 Enter 규칙(data-model §11). 확인 줄이 열린 동안 Enter는 "늘리고 시작"이다.
enum BudgetDisplay {
    enum CustomEnter: Equatable { case none, start, extend }

    /// 시작 버튼과 같은 뗌 규칙에 더해, 직접 입력 칸이 열려 있으면 그 칸의 Enter가 늘리고 시작을 맡으므로 뗀다.
    static func detachesExtendShortcut(
        isEnteringTitle: Bool, gatePhase: GatePhase?, isCustomEditing: Bool, isIllustration: Bool = false
    ) -> Bool {
        isCustomEditing
            || GateDisplay.detachesStartShortcut(
                isEnteringTitle: isEnteringTitle, gatePhase: gatePhase, isIllustration: isIllustration)
    }

    /// 시작 전 "직접…" 분 칸의 Enter.
    static func customEnter(canStart: Bool, gatePhase: GatePhase?, extendOpen: Bool) -> CustomEnter {
        guard GateDisplay.customEnterStarts(canStart: canStart, gatePhase: gatePhase) else { return .none }
        return extendOpen ? .extend : .start
    }
}

/// 노치가 할 일 대신 보이는 가용 시간 화면(data-model §12 4·5).
enum BudgetScreenInput {
    case ask(AskBudgetInput)
    case dayEnd(DayEndInput)
}

struct AskBudgetInput {
    /// 직접 적기 칸 글자. nil이면 칸이 닫혀 있다.
    var customText: String?
    var issue: BudgetInputIssue?
    var failed = false
    var onChoose: (Int) -> Void = { _ in }
    var onBeginCustom: () -> Void = {}
    var onEditCustom: (String) -> Void = { _ in }
    var onSubmitCustom: () -> Void = {}
    var onCancelCustom: () -> Void = {}
    var takeFocusRequest: () -> Bool = { false }
}

struct DayEndInput {
    var minutes: Int
    var usedSeconds: Int
    var fraction: Double
    var failed = false
    var onMore: () -> Void = {}
}

/// 시작 전 화면의 가용 시간 줄(시안 5·6번).
struct DraftBudgetInput {
    var capNote: String?
    var extend: ExtendInput?
    var startFailed = false
}

struct ExtendInput {
    var title: String
    var detail: String
    var keep: String
    var failed = false
    /// 직접 입력이 틀리면 꺼진다(R-004).
    var canStart = true
    var onKeep: () -> Void = {}
    var onExtend: () -> Void = {}
}

/// 시간 끝 화면의 가용 시간 줄(시안 7·8번).
struct ExpiredBudgetInput {
    /// 남은 분. 이보다 긴 프리셋을 끈다.
    var maxMinutes: Int?
    var note: String?
    /// 있으면 "N분 더"와 칩 줄을 끄고 이 이유를 보인다.
    var offReason: String?
}

/// 시안 4번: 질문, 선택지 다섯과 "직접…", 직접 적기 칸.
struct AskBudgetView<TitleRow: View>: View {
    let input: AskBudgetInput
    let isEnteringTitle: Bool
    let onBeginNewTitle: () -> Void
    @ViewBuilder let titleRow: () -> TitleRow

    @Environment(\.panelPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(BudgetViewText.ask)
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 2)
            Text(BudgetViewText.askDetail)
                .font(.system(size: 11))
                .foregroundStyle(palette.muted)
                .padding(.bottom, 6)
        }
        choices
        if input.customText != nil {
            customRow
        } else if isEnteringTitle {
            titleRow()
        } else {
            HStack(spacing: 6) {
                Button(NotchText.newTask, action: onBeginNewTitle)
                    .buttonStyle(NotchButtonStyle(kind: .ghost))
                    .accessibilityLabel("새 할 일")
                    .illustrationUnfocusable()
                Spacer(minLength: 0)
                Text(BudgetViewText.pickHint)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.muted)
            }
        }
        if input.failed {
            CustomIssueText(message: BudgetViewText.answerFailed)
        }
    }

    private var choices: some View {
        HStack(spacing: 0) {
            ForEach(Array(zip(DayBudget.choiceMinutes, BudgetText.choices)), id: \.0) { minutes, label in
                BudgetChoiceSegment(label: label, selected: false) { input.onChoose(minutes) }
            }
            BudgetChoiceSegment(label: BudgetViewText.custom, selected: input.customText != nil) {
                if input.customText == nil { input.onBeginCustom() }
            }
        }
        .padding(2)
        .background(palette.control, in: .rect(cornerRadius: 7))
    }

    @ViewBuilder
    private var customRow: some View {
        HStack(spacing: 6) {
            BudgetHoursField(
                text: input.customText ?? "", invalid: input.issue.map { $0 != .empty } ?? false,
                takeFocusRequest: input.takeFocusRequest, onEdit: input.onEditCustom, onSubmit: submit,
                onCancel: input.onCancelCustom)
            Text(BudgetViewText.hoursUnit)
                .font(.system(size: 11))
                .foregroundStyle(palette.muted)
            Spacer(minLength: 0)
            Button(action: submit) {
                ButtonLabel(text: BudgetViewText.decide, shortcut: input.issue == nil ? "↵" : nil)
            }
            .buttonStyle(NotchButtonStyle(kind: .primary))
            .disabled(input.issue != nil)
            .illustrationUnfocusable()
        }
        if let message = input.issue?.message {
            CustomIssueText(message: message)
        } else {
            Text(BudgetViewText.customHint)
                .font(.system(size: 11))
                .foregroundStyle(palette.muted)
        }
    }

    private func submit() {
        if input.issue == nil { input.onSubmitCustom() }
    }
}

/// 선택지 칸. 마우스를 올리면 고를 칸을 강조한다(시안 4-1번 2시간 칸).
private struct BudgetChoiceSegment: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.panelPalette) private var palette

    var body: some View {
        let lit = selected || isHovering
        Button(action: action) {
            Text(label)
                .font(.system(size: 12.5, weight: lit ? .semibold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(lit ? MokaColors.textOnPrimary : palette.segmentText)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background {
                    if lit { RoundedRectangle(cornerRadius: 5).fill(MokaColors.primaryGradient) }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .illustrationUnfocusable()
    }
}

/// 직접 적기 숫자 칸. 틀리면 빨간 테두리, 이유는 칸 아래 줄이 보인다.
private struct BudgetHoursField: View {
    let text: String
    let invalid: Bool
    let takeFocusRequest: () -> Bool
    let onEdit: (String) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @State private var editing = ""
    @FocusState private var focused: Bool
    @Environment(\.panelPalette) private var palette
    @Environment(\.panelIsKey) private var panelIsKey

    var body: some View {
        TextField("", text: $editing)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .focused($focused)
            .onSubmit(onSubmit)
            .padding(.horizontal, 8)
            .frame(width: 46, height: 24)
            .background(palette.field, in: .rect(cornerRadius: ExpandedView.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ExpandedView.controlRadius).strokeBorder(borderColor, lineWidth: 1)
            }
            .accessibilityLabel("직접 적는 시간")
            .onAppear {
                editing = text
                if takeFocusRequest() { focused = true }
            }
            .onChange(of: editing) { _, newValue in
                if newValue != text { onEdit(newValue) }
            }
            .onExitCommand(perform: onCancel)
    }

    private var borderColor: Color {
        switch FieldBorder.kind(invalid: invalid, focused: focused, panelIsKey: panelIsKey) {
        case .error: palette.danger
        case .focus: MokaColors.mochaHighlight
        case .normal: palette.fieldLine
        }
    }
}

/// 시안 9번: 오늘 끝과 "더 할래요". 실수로 다시 시작하지 않게 기본 버튼(↵)을 두지 않는다.
struct DayEndView: View {
    let input: DayEndInput

    @Environment(\.panelPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(BudgetText.dayEndTitle(minutes: input.minutes))
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 2)
            Text(BudgetViewText.dayEndDetail)
                .font(.system(size: 11))
                .foregroundStyle(palette.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: 8) {
            Text(BudgetViewText.usedLabel)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.control)
                    Capsule().fill(MokaColors.mocha).frame(width: proxy.size.width * input.fraction)
                }
            }
            .frame(height: 5)
            Text(BudgetText.used(seconds: input.usedSeconds))
                .monospacedDigit()
        }
        .font(.system(size: 11))
        .foregroundStyle(palette.muted)
        .accessibilityElement(children: .combine)
        HStack {
            Spacer(minLength: 0)
            Button(BudgetViewText.more, action: input.onMore)
                .buttonStyle(NotchButtonStyle(kind: .secondary))
                .illustrationUnfocusable()
        }
        if input.failed {
            CustomIssueText(message: BudgetViewText.moreFailed)
        }
    }
}

/// 시안 6번: 시작 버튼 자리의 늘리기 확인(구체화 게이트와 같은 모양). Enter는 "늘리고 시작"이다.
struct ExtendConfirmView: View {
    let input: ExtendInput
    /// 제목 칸·게이트 칸·직접 입력 칸이 Enter를 맡으면 뗀다(`BudgetDisplay.detachesExtendShortcut`).
    var detachesShortcut = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.panelPalette) private var palette
    @Environment(\.isNotchIllustration) private var isIllustration

    var body: some View {
        let tint = GateDisplay.tint(colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            Text(input.title)
                .font(.system(size: 12, weight: .semibold))
            Text(input.detail)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            if input.failed {
                Text(BudgetViewText.extendFailed)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.danger)
                    .padding(.top, 5)
            }
            HStack(spacing: 6) {
                Button(input.keep, action: input.onKeep)
                    .buttonStyle(NotchButtonStyle(kind: .secondary))
                    .illustrationUnfocusable()
                Spacer(minLength: 0)
                Button(action: input.onExtend) {
                    ButtonLabel(text: BudgetViewText.extendStart, shortcut: detachesShortcut ? nil : "↵")
                }
                .buttonStyle(NotchButtonStyle(kind: .primary))
                .keyboardShortcut(detachesShortcut ? nil : .defaultAction)
                .disabled(!input.canStart)
                .illustrationUnfocusable()
            }
            .padding(.top, 6)
        }
        .padding(.top, 8)
        .padding(.horizontal, 9)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(tint.opacity(0.35), lineWidth: 0.5) }
    }
}

/// 칩 아래 크레마 안내 한 줄(시안 5·7·8번 `.why-in`·`.offwhy`).
struct BudgetNoteText: View {
    let text: String

    @Environment(\.panelPalette) private var palette

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(palette.firstAction)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 시안 10-2·10-3번: 접힌 노치. 질문은 회색 점과 크레마 글자, 오늘 끝은 회색 점과 회색 글자.
struct CollapsedBudgetView: View {
    let screen: BudgetScreenInput

    @Environment(\.panelPalette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(active: false)
            switch screen {
            case .ask:
                Text(BudgetViewText.collapsedAsk)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(palette.firstAction)
            case .dayEnd:
                Text(BudgetViewText.collapsedDayEnd)
                    .lineLimit(1)
                    .foregroundStyle(palette.muted)
            }
        }
    }
}
