import AppKit
import MokaCore
import SwiftUI

/// 펼친 판(폭 340pt). 위쪽 노치 높이만큼은 구멍 양옆 귀에 브랜드와 상태를 두고, 그 아래에 단계별 내용을 둔다.
struct ExpandedView: View {
    nonisolated static let width: CGFloat = 340
    /// 판 안 버튼·입력칸 모서리 반경.
    static let controlRadius: CGFloat = 6
    nonisolated static let wordmarkSize: CGFloat = 10

    let timer: NotchTimer
    let remainingSeconds: Int?
    let metrics: NotchMetrics
    /// 값이 바뀔 때마다 빈 상태의 제목 칸에 포커스를 준다(펼친 판 클릭, data-model §6).
    let titleFocusRequest: Int
    let chip: QuantumChipInput
    let onEnterTitle: (String) -> Void
    let onStart: () -> Void
    let onComplete: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.panelPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            stage
        }
        .padding(.top, metrics.height + 12)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .frame(width: Self.width, alignment: .leading)
        .overlay(alignment: .top) { ears }
        .font(.system(size: 12))
        .foregroundStyle(palette.foreground)
    }

    private var ears: some View {
        HStack(spacing: 0) {
            // 잔 몸통(그릇+받침) 세로 가운데를 워드마크 대문자 높이의 가운데에 맞춘다.
            HStack(alignment: .capCenter, spacing: 5) {
                CupIcon()
                    .frame(width: 13, height: 13)
                    .foregroundStyle(MokaColors.mocha)
                    .alignmentGuide(.capCenter) { $0.height * CupIcon.bodyCenterFraction }
                MokaWordmark()
                    .foregroundStyle(palette.wordmark)
                    .alignmentGuide(.capCenter) { $0[.firstTextBaseline] - Self.wordmarkCapHeight / 2 }
            }
            .frame(width: 64, alignment: .leading)
            Spacer(minLength: 0)
            Text(NotchStatus.label(for: timer))
                .font(.system(size: 10.5, weight: isExpired ? .semibold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(isExpired ? palette.danger : mutedColor)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: metrics.height)
    }

    @ViewBuilder
    private var stage: some View {
        switch timer {
        case .empty(nil):
            TitleEntryRow(focusRequest: titleFocusRequest, onSubmit: onEnterTitle)
        case .empty(.some(let draft)):
            TitleText(title: draft.title)
            // 기본값으로 채운 칩이 선택된 채로 Enter나 시작 한 번이면 그 값으로 시작한다(R-003).
            QuantumChipView(
                chipMin: draft.chipMin, customText: chip.customText,
                onChoose: chip.onChoose, onBeginCustom: chip.onBeginCustom, onEditCustom: chip.onEditCustom)
            HStack(spacing: 6) {
                if let customText = chip.customText {
                    CustomMinutesField(
                        text: customText, takeFocusRequest: chip.takeFocusRequest, onEdit: chip.onEditCustom
                    ) {
                        if chip.canStart { onStart() }
                    }
                }
                Spacer(minLength: 0)
                Button(action: onStart) { ButtonLabel(text: "시작", shortcut: "↵") }
                    .buttonStyle(NotchButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!chip.canStart)
            }
            if let message = CustomIssueText.message(for: chip.customText) {
                CustomIssueText(message: message)
            }
        case .running(let title, _, _, _):
            TitleText(title: title)
            HStack(spacing: 6) {
                RemainingText(seconds: remainingSeconds, expired: false)
                Spacer(minLength: 0)
                Button(action: onComplete) { ButtonLabel(text: "완료") }
                    .buttonStyle(NotchButtonStyle(kind: .secondary))
            }
        case .expired(let title, let chipMin):
            ExpiredView(title: title, chipMin: chipMin, chip: chip, onStart: onStart, onComplete: onComplete)
        }
    }

    private var isExpired: Bool {
        if case .expired = timer { return true }
        return false
    }

    private var mutedColor: Color {
        contrast == .increased ? palette.mutedHighContrast : palette.muted
    }

    private nonisolated static let wordmarkCapHeight = NSFont.systemFont(ofSize: wordmarkSize, weight: .bold).capHeight
}

extension VerticalAlignment {
    private enum CapCenter: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[VerticalAlignment.center]
        }
    }

    /// 대문자 높이의 가운데(아이콘과 워드마크 정렬용).
    static let capCenter = VerticalAlignment(CapCenter.self)
}

/// 빈 상태 입력 줄. 앞뒤 공백을 뺀 제목이 비면 Enter·다음으로 넘어가지 않는다(R-002).
private struct TitleEntryRow: View {
    let focusRequest: Int
    let onSubmit: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.panelPalette) private var palette
    @Environment(\.panelIsKey) private var panelIsKey

    var body: some View {
        HStack(spacing: 6) {
            TextField(
                "",
                text: $text,
                prompt: Text("무엇을 할까요?").foregroundStyle(
                    contrast == .increased ? palette.placeholderHighContrast : palette.placeholder)
            )
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit(submit)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(palette.field, in: .rect(cornerRadius: ExpandedView.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ExpandedView.controlRadius)
                    .strokeBorder(showsFocus ? MokaColors.mochaHighlight : palette.fieldLine, lineWidth: 1)
            }
            .shadow(color: showsFocus ? MokaColors.mocha.opacity(0.38) : .clear, radius: 3)
            Button(action: submit) { ButtonLabel(text: "다음", shortcut: "↵") }
                .buttonStyle(NotchButtonStyle(kind: .primary))
                .disabled(trimmed.isEmpty)
        }
        .onChange(of: focusRequest) { focused = true }
    }

    private var showsFocus: Bool {
        FieldBorder.kind(invalid: false, focused: focused, panelIsKey: panelIsKey) == .focus
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        onSubmit(text)
    }
}

struct TitleText: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .lineSpacing(2)
            .lineLimit(2)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RemainingText: View {
    let seconds: Int?
    let expired: Bool

    @Environment(\.panelPalette) private var palette

    var body: some View {
        Text(RemainingFormat.string(seconds ?? 0))
            .font(.system(size: 22, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(expired ? palette.danger : palette.foreground)
    }
}

struct ButtonLabel: View {
    let text: String
    var shortcut: String?

    var body: some View {
        HStack(spacing: 5) {
            Text(text)
            if let shortcut {
                Text(shortcut).font(.system(size: 10)).opacity(0.7)
            }
        }
    }
}

struct NotchButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.panelPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: kind == .primary && isEnabled ? .semibold : .medium))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background { background }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(.rect)
    }

    private var foreground: Color {
        guard isEnabled else { return palette.textDisabled }
        return kind == .primary ? MokaColors.textOnPrimary : palette.foreground
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: ExpandedView.controlRadius)
        if !isEnabled {
            shape.fill(palette.controlDisabled)
        } else if kind == .primary {
            shape.fill(MokaColors.primaryGradient)
        } else {
            shape.fill(palette.control)
        }
    }
}
