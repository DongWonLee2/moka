import AppKit
import MokaCore
import SwiftUI

/// 펼친 판(폭 340pt). 위쪽 노치 높이만큼은 구멍 양옆 귀에 브랜드와 상태를 두고, 그 아래에 단계별 내용을 둔다.
struct ExpandedView: View {
    static let width: CGFloat = 340
    /// 판 안 버튼·입력칸 모서리 반경.
    static let controlRadius: CGFloat = 6
    nonisolated static let wordmarkSize: CGFloat = 10
    static let wordmarkTracking: CGFloat = 1.25

    let timer: NotchTimer
    let remainingSeconds: Int?
    let metrics: NotchMetrics
    /// 값이 바뀔 때마다 빈 상태의 제목 칸에 포커스를 준다(펼친 판 클릭, data-model §6).
    let titleFocusRequest: Int
    /// 접힘과 잇는 제목·남은 시간의 이름공간. nil이면 잇지 않는다(동작 줄이기).
    var namespace: Namespace.ID?
    let onEnterTitle: (String) -> Void
    let onStart: () -> Void
    let onComplete: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

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
        .foregroundStyle(MokaColors.notchForeground)
    }

    private var ears: some View {
        HStack(spacing: 0) {
            // 잔 몸통(그릇+받침) 세로 가운데를 워드마크 대문자 높이의 가운데에 맞춘다.
            HStack(alignment: .capCenter, spacing: 5) {
                CupIcon()
                    .frame(width: 13, height: 13)
                    .foregroundStyle(MokaColors.mocha)
                    .alignmentGuide(.capCenter) { $0.height * CupIcon.bodyCenterFraction }
                Text("MOKA")
                    .font(.system(size: Self.wordmarkSize, weight: .bold))
                    .tracking(Self.wordmarkTracking)
                    .foregroundStyle(MokaColors.foam.opacity(0.92))
                    .alignmentGuide(.capCenter) { $0[.firstTextBaseline] - Self.wordmarkCapHeight / 2 }
            }
            .frame(width: 64, alignment: .leading)
            Spacer(minLength: 0)
            Text(NotchStatus.label(for: timer))
                .font(.system(size: 10.5, weight: isExpired ? .semibold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(isExpired ? MokaColors.danger : mutedColor)
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
            HStack(spacing: 6) {
                // 칩 고르기 UI는 #27. 지금은 기본값으로 채운 칩 하나만 보인다(R-003).
                Text("\(draft.chipMin)분")
                    .font(.system(size: 11.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(MokaColors.textOnPrimary)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(MokaColors.primaryGradient, in: .rect(cornerRadius: 5))
                Spacer(minLength: 0)
                Button(action: onStart) { ButtonLabel(text: "시작", shortcut: "↵") }
                    .buttonStyle(NotchButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        case .running(let title, _, _, _):
            TitleText(title: title).matchedElement("title", in: namespace)
            HStack(spacing: 6) {
                RemainingText(seconds: remainingSeconds, expired: false).matchedElement("remaining", in: namespace)
                Spacer(minLength: 0)
                Button(action: onComplete) { ButtonLabel(text: "완료") }
                    .buttonStyle(NotchButtonStyle(kind: .secondary))
            }
        case .expired(let title, _):
            // 시간 끝 화면(칩·다시 시작)은 4b. 지금은 완료만 둔다.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TitleText(title: title).matchedElement("title", in: namespace)
                RemainingText(seconds: remainingSeconds, expired: true).matchedElement("remaining", in: namespace)
            }
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Button(action: onComplete) { ButtonLabel(text: "완료", shortcut: "↵") }
                    .buttonStyle(NotchButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var isExpired: Bool {
        if case .expired = timer { return true }
        return false
    }

    private var mutedColor: Color {
        contrast == .increased ? MokaColors.notchMutedHighContrast : MokaColors.notchMuted
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

    var body: some View {
        HStack(spacing: 6) {
            TextField(
                "",
                text: $text,
                prompt: Text("할 일 없음 — 무엇을 할까요?").foregroundStyle(
                    contrast == .increased ? MokaColors.placeholderHighContrast : MokaColors.placeholder)
            )
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit(submit)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(MokaColors.field, in: .rect(cornerRadius: ExpandedView.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ExpandedView.controlRadius)
                    .strokeBorder(focused ? MokaColors.mochaHighlight : MokaColors.fieldLine, lineWidth: 1)
            }
            .shadow(color: focused ? MokaColors.mocha.opacity(0.38) : .clear, radius: 3)
            Button(action: submit) { ButtonLabel(text: "다음", shortcut: "↵") }
                .buttonStyle(NotchButtonStyle(kind: .primary))
                .disabled(trimmed.isEmpty)
        }
        .onChange(of: focusRequest) { focused = true }
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        onSubmit(text)
    }
}

private struct TitleText: View {
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

private struct RemainingText: View {
    let seconds: Int?
    let expired: Bool

    var body: some View {
        Text(RemainingFormat.string(seconds ?? 0))
            .font(.system(size: 22, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(expired ? MokaColors.danger : MokaColors.notchForeground)
    }
}

private struct ButtonLabel: View {
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
        guard isEnabled else { return MokaColors.textDisabled }
        return kind == .primary ? MokaColors.textOnPrimary : MokaColors.notchForeground
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: ExpandedView.controlRadius)
        if !isEnabled {
            shape.fill(MokaColors.controlDisabled)
        } else if kind == .primary {
            shape.fill(MokaColors.primaryGradient)
        } else {
            shape.fill(MokaColors.control)
        }
    }
}
