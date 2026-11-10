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
    var storageUnavailable = false
    /// 이어서 할 일(R-109). 있으면 제목 아래 한 줄.
    var firstAction: String?
    /// 값이 바뀔 때마다 빈 상태의 제목 칸에 포커스를 준다(펼친 판 클릭, data-model §6).
    let titleFocusRequest: Int
    let chip: QuantumChipInput
    let onEnterTitle: (String) -> Void
    let draftInput: DraftInput
    var notes = NotesInput()
    /// 이유 줄(spec 004 R-301). 시작 전·도는 중 제목 아래.
    var reasonLine: String?
    /// 구체화 게이트(spec 004 R-307). 시작 전 시간 고르기 위.
    var gate: GateInput?
    /// 키 확인 한 줄(spec 004 R-316). 빈 상태·시작 전·도는 중 맨 아래.
    var keyNotice = false
    var onOpenKeySettings: () -> Void = {}
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
            Text(NotchStatus.label(for: timer, pending: notes.pending))
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
            if storageUnavailable {
                StorageUnavailableView()
            }
            keyNoticeLine
        case .empty(.some(let draft)):
            if draftInput.isPickingOther {
                OtherTaskPicker(
                    items: draftInput.otherItems, onChoose: draftInput.onChooseOther,
                    onCancel: draftInput.onCancelOther)
            } else {
                draftStage(draft)
                keyNoticeLine
            }
        case .running(let title, _, _, _):
            if notes.pending != nil {
                CheckpointNotesView(title: title, input: notes)
            } else {
                TitleBlock(title: title, reasonLine: reasonLine)
                if let firstAction {
                    FirstActionLine(text: firstAction)
                }
                HStack(spacing: 6) {
                    RemainingText(seconds: remainingSeconds, expired: false)
                    Spacer(minLength: 0)
                    Button("미루기") { notes.onBegin(.skip) }
                        .buttonStyle(NotchButtonStyle(kind: .secondary))
                    Button("바꾸기") { notes.onBegin(.switch) }
                        .buttonStyle(NotchButtonStyle(kind: .secondary))
                    Button(action: onComplete) { ButtonLabel(text: "완료") }
                        .buttonStyle(NotchButtonStyle(kind: .secondary))
                }
                keyNoticeLine
            }
        case .expired(let title, let chipMin, _):
            ExpiredView(
                title: title, chipMin: chipMin, chip: chip, notes: notes, onStart: onStart, onComplete: onComplete)
        }
    }

    @ViewBuilder
    private func draftStage(_ draft: Draft) -> some View {
        if draftInput.isEnteringTitle {
            TitleEntryRow(
                focusRequest: titleFocusRequest, focusesOnAppear: true, onCancel: draftInput.onCancelNewTitle,
                onSubmit: onEnterTitle)
        } else {
            TitleBlock(title: draft.title, reasonLine: reasonLine)
            if let firstAction, !GateDisplay.hidesFirstAction(gatePhase: gate?.phase) {
                FirstActionLine(text: firstAction)
            }
        }
        if let gate, GateDisplay.isVisible(gatePhase: gate.phase, isEnteringTitle: draftInput.isEnteringTitle) {
            GateView(input: gate)
        }
        // 기본값으로 채운 칩이 선택된 채로 Enter나 시작 한 번이면 그 값으로 시작한다(R-003).
        QuantumChipView(
            chipMin: draft.chipMin, customText: chip.customText,
            onChoose: chip.onChoose, onBeginCustom: chip.onBeginCustom, onEditCustom: chip.onEditCustom)
        HStack(spacing: 6) {
            if let customText = chip.customText {
                CustomMinutesField(
                    text: customText, takeFocusRequest: chip.takeFocusRequest, onEdit: chip.onEditCustom
                ) {
                    if GateDisplay.customEnterStarts(canStart: chip.canStart, gatePhase: gate?.phase) { onStart() }
                }
            } else {
                Button("다른 할 일", action: draftInput.onBeginOther)
                    .buttonStyle(NotchButtonStyle(kind: .ghost))
                Button("+ 새 할 일", action: draftInput.onBeginNewTitle)
                    .buttonStyle(NotchButtonStyle(kind: .ghost))
                    .disabled(draftInput.isEnteringTitle)
                    .accessibilityLabel("새 할 일")
            }
            Spacer(minLength: 0)
            // 게이트가 묻는 중이면 Enter는 적기라 시작 버튼에서 ↵ 표시를 뺀다(확정 시안 4번).
            Button(action: onStart) { ButtonLabel(text: "시작", shortcut: gate?.phase == .asking ? nil : "↵") }
                .buttonStyle(NotchButtonStyle(kind: .primary))
                // 제목 칸이나 게이트 칸이 열려 있으면 Enter는 그 칸의 것이다. 시작까지 함께 부르지 않게 단축키를 뗀다.
                .keyboardShortcut(
                    GateDisplay.detachesStartShortcut(
                        isEnteringTitle: draftInput.isEnteringTitle, gatePhase: gate?.phase)
                        ? nil : .defaultAction
                )
                .disabled(!chip.canStart)
        }
        if let message = QuantumChip.customIssueMessage(customText: chip.customText) {
            CustomIssueText(message: message)
        }
    }

    @ViewBuilder
    private var keyNoticeLine: some View {
        if keyNotice {
            KeyNoticeLine(onOpen: onOpenKeySettings)
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
    var focusesOnAppear = false
    var onCancel: (() -> Void)?
    let onSubmit: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.panelPalette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            TextField(
                "",
                text: $text,
                prompt: Text("무엇을 할까요?").foregroundStyle(
                    contrast == .increased ? palette.placeholderHighContrast : palette.placeholder)
            )
            .notchField(focused: focused)
            .focused($focused)
            .onSubmit(submit)
            Button(action: submit) { ButtonLabel(text: "다음", shortcut: "↵") }
                .buttonStyle(NotchButtonStyle(kind: .primary))
                .disabled(trimmed.isEmpty)
        }
        .onChange(of: focusRequest) { focused = true }
        .onAppear {
            // 나타나는 순간에는 칸이 아직 붙지 않아 포커스 요청이 버려진다. 다음 차례로 미룬다.
            if focusesOnAppear { Task { @MainActor in focused = true } }
        }
        .onExitCommand { onCancel?() }
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        onSubmit(text)
    }
}

private struct NotchFieldModifier: ViewModifier {
    let focused: Bool

    @Environment(\.panelPalette) private var palette
    @Environment(\.panelIsKey) private var panelIsKey

    func body(content: Content) -> some View {
        let showsFocus = FieldBorder.kind(invalid: false, focused: focused, panelIsKey: panelIsKey) == .focus
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(palette.field, in: .rect(cornerRadius: ExpandedView.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ExpandedView.controlRadius)
                    .strokeBorder(showsFocus ? MokaColors.mochaHighlight : palette.fieldLine, lineWidth: 1)
            }
            .shadow(color: showsFocus ? MokaColors.mocha.opacity(0.38) : .clear, radius: 3)
    }
}

extension View {
    func notchField(focused: Bool) -> some View {
        modifier(NotchFieldModifier(focused: focused))
    }
}

struct TitleText: View {
    let title: String
    var lineLimit = 2

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .lineSpacing(2)
            .lineLimit(lineLimit)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 제목과 그 바로 아래 이유 줄(시안 `margin-top: 4px`). 이유 줄이 없으면 제목만.
private struct TitleBlock: View {
    let title: String
    let reasonLine: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TitleText(title: title)
            if let reasonLine {
                ReasonLineText(text: reasonLine)
            }
        }
    }
}

private struct FirstActionLine: View {
    let text: String

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.panelPalette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Text("이어서 할 일")
                .font(.system(size: 10.5))
                .foregroundStyle(contrast == .increased ? palette.mutedHighContrast : palette.muted)
            Text(text)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(palette.firstAction)
        }
        .accessibilityElement(children: .combine)
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
        case ghost
    }

    let kind: Kind

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.panelPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: kind == .primary && isEnabled ? .semibold : .medium))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .ghost ? 6 : 12)
            .frame(height: 24)
            .background { background }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(.rect)
    }

    private var foreground: Color {
        guard isEnabled else { return palette.textDisabled }
        switch kind {
        case .primary: return MokaColors.textOnPrimary
        case .secondary: return palette.foreground
        case .ghost: return palette.muted
        }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: ExpandedView.controlRadius)
        if kind == .ghost {
            Color.clear
        } else if !isEnabled {
            shape.fill(palette.controlDisabled)
        } else if kind == .primary {
            shape.fill(MokaColors.primaryGradient)
        } else {
            shape.fill(palette.control)
        }
    }
}

/// 시작 전 화면의 "+ 새 할 일" 칸(R-103)과 "다른 할 일" 목록(R-104).
struct DraftInput {
    var isEnteringTitle = false
    var onBeginNewTitle: () -> Void = {}
    var onCancelNewTitle: () -> Void = {}
    var isPickingOther = false
    var otherItems: [OtherTaskItem] = []
    var onBeginOther: () -> Void = {}
    var onCancelOther: () -> Void = {}
    var onChooseOther: (TaskID) -> Void = { _ in }
}

struct OtherTaskItem: Identifiable, Equatable {
    let id: TaskID
    let title: String
    let note: String
    let tone: OtherTaskText.Tone
}

private struct OtherTaskPicker: View {
    let items: [OtherTaskItem]
    let onChoose: (TaskID) -> Void
    let onCancel: () -> Void

    @Environment(\.panelPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("다른 할 일 고르기")
                    .foregroundStyle(palette.muted)
                Spacer(minLength: 0)
                Button(action: onCancel) { ButtonLabel(text: "돌아가기", shortcut: "esc") }
                    .buttonStyle(NotchButtonStyle(kind: .ghost))
                    .keyboardShortcut(.cancelAction)
            }
            if items.isEmpty {
                Text("다른 대기 할 일이 없어요.")
                    .foregroundStyle(palette.muted)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider().overlay(palette.control) }
                            OtherTaskRow(item: item) { onChoose(item.id) }
                        }
                    }
                }
                .frame(maxHeight: 118)
                .fixedSize(horizontal: false, vertical: true)
                .background(palette.control.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }
}

private struct OtherTaskRow: View {
    let item: OtherTaskItem
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.panelPalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(item.title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(item.note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(noteColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isHovering ? MokaColors.mocha.opacity(0.28) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(item.note.isEmpty ? item.title : "\(item.title), \(item.note)")
    }

    private var noteColor: Color {
        switch item.tone {
        case .overdue: palette.danger
        case .soon: MokaColors.crema
        case .plain: palette.muted
        }
    }
}
