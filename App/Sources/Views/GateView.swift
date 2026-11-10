import MokaCore
import SwiftUI

/// 노치 시작 전 화면의 구체화 게이트 값과 콜백(spec 004 data-model §5, ADR-0009).
struct GateInput {
    var phase: GatePhase
    var text: Binding<String>
    /// 이 할 일에 지금까지 적은 횟수. 1 이상이고 묻는 중이면 다시 묻기 문구를 보인다(시안 6번).
    var submissions = 0
    var saveFailed = false
    var onSubmit: () -> Void = {}
    var onSkip: () -> Void = {}
}

/// 게이트 표시 규칙과 글자(확정 시안 004-mockup 4~8번, 사용자 확정 2026-11-10).
enum GateDisplay {
    struct Message: Equatable {
        let text: String
        let isError: Bool
    }

    static let title = "어디서 시작할지 막연해 보여요"
    /// 키 확인 한 줄(확정 시안 12~14번).
    static let keyNoticeText = "키가 맞지 않아 판단 모델에 묻지 못하고 있어요."
    static let keyNoticeButton = "키 확인"
    private static let firstSubtitle = "2분 안에 바로 할 수 있는 첫 행동을 한 줄 적어 주세요. 판단 모델이 다시 확인하고, 노치를 펼치면 제목 아래 보여요."
    private static let retrySubtitle = "방금 적은 줄이에요. 고쳐 써도 돼요."

    /// 새 할 일 제목 칸이 열린 동안은 숨기고 닫히면 다시 보인다(시안 확정할 것 9번).
    static func isVisible(gatePhase: GatePhase?, isEnteringTitle: Bool) -> Bool {
        guard let gatePhase, gatePhase != .closed else { return false }
        return !isEnteringTitle
    }

    /// 제목 칸이 열렸거나 게이트가 묻는 중이면 Enter는 그 칸의 것이라 시작 버튼 단축키를 뗀다.
    static func detachesStartShortcut(isEnteringTitle: Bool, gatePhase: GatePhase?) -> Bool {
        isEnteringTitle || gatePhase == .asking
    }

    /// 묻는 중이면 Enter는 적기라 시작 버튼에서 ↵ 표시를 뺀다(확정 시안 4번).
    static func startShortcutMark(gatePhase: GatePhase?) -> String? {
        gatePhase == .asking ? nil : "↵"
    }

    /// "직접…" 분 칸의 Enter. 게이트가 묻는 중이면 시작하지 않는다.
    static func customEnterStarts(canStart: Bool, gatePhase: GatePhase?) -> Bool {
        canStart && gatePhase != .asking
    }

    /// 게이트 칸이 같은 줄을 보이는 동안 제목 아래 이어서 할 일 줄을 숨긴다(R-311).
    static func hidesFirstAction(gatePhase: GatePhase?) -> Bool {
        gatePhase == .asking || gatePhase == .checking
    }

    static func subtitle(phase: GatePhase, submissions: Int) -> String {
        phase == .asking && submissions > 0 ? retrySubtitle : firstSubtitle
    }

    static func message(phase: GatePhase, submissions: Int, saveFailed: Bool) -> Message? {
        if saveFailed {
            return Message(text: "첫 행동을 저장하지 못했어요. 다시 해 주세요.", isError: true)
        }
        switch phase {
        case .checking:
            return Message(text: "판단 모델에 다시 물어보고 있어요.", isError: false)
        case .asking where submissions > 0:
            let left = max(1, Defaults.concreteGateMaxSubmissions - submissions)
            return Message(text: "조금 더 작게 적어 볼까요? \(countWord(left)) 더 물어볼게요.", isError: false)
        case .asking, .closed:
            return nil
        }
    }

    private static func countWord(_ count: Int) -> String {
        switch count {
        case 1: "한 번"
        case 2: "두 번"
        case 3: "세 번"
        default: "\(count)번"
        }
    }
}

/// 시간 고르기 위에 뜨는 게이트 칸. 묻는 중이면 입력 칸과 "지금은 넘기기"·"적기", 확인하는 중이면 읽기만 하는 칸과 문구.
struct GateView: View {
    let input: GateInput

    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.panelPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(GateDisplay.title)
                .font(.system(size: 12, weight: .semibold))
            Text(GateDisplay.subtitle(phase: input.phase, submissions: input.submissions))
                .font(.system(size: 10.5))
                .foregroundStyle(mutedColor)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            field
                .padding(.top, 6)
            if let message = GateDisplay.message(
                phase: input.phase, submissions: input.submissions, saveFailed: input.saveFailed)
            {
                Text(message.text)
                    .font(.system(size: 11))
                    .foregroundStyle(message.isError ? palette.danger : mutedColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
            }
            if input.phase == .asking {
                HStack(spacing: 6) {
                    Button("지금은 넘기기", action: input.onSkip)
                        .buttonStyle(NotchButtonStyle(kind: .ghost))
                    Spacer(minLength: 0)
                    Button(action: submit) { ButtonLabel(text: "적기", shortcut: "↵") }
                        .buttonStyle(NotchButtonStyle(kind: .primary))
                        .disabled(trimmed.isEmpty)
                }
                .padding(.top, 6)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 9)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7).strokeBorder(tint.opacity(0.35), lineWidth: 0.5)
        }
        .onAppear {
            // 나타나는 순간에는 칸이 아직 붙지 않아 포커스 요청이 버려진다. 다음 차례로 미룬다.
            if input.phase == .asking { Task { @MainActor in focused = true } }
        }
        .onChange(of: input.phase) { _, phase in
            // 확인하는 중에서 다시 묻기로 돌아오면 칸이 새로 생기므로 다시 포커스를 준다(확정 시안 6번).
            if phase == .asking { Task { @MainActor in focused = true } }
        }
    }

    @ViewBuilder
    private var field: some View {
        if input.phase == .asking {
            TextField("", text: input.text)
                .notchField(focused: focused)
                .focused($focused)
                .onSubmit(submit)
                .accessibilityLabel("첫 행동")
        } else {
            Text(input.text.wrappedValue)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .notchField(focused: false)
                .accessibilityLabel("첫 행동")
        }
    }

    private var trimmed: String {
        input.text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard input.phase == .asking, !trimmed.isEmpty else { return }
        input.onSubmit()
    }

    /// 시안 `.light .gate`(#8C5A3A)와 `.dark .gate`(#D9A774).
    private var tint: Color {
        colorScheme == .light ? Color(hex: 0x8C5A3A) : Color(hex: 0xD9A774)
    }

    private var mutedColor: Color {
        contrast == .increased ? palette.mutedHighContrast : palette.muted
    }
}

/// 노치 펼친 화면 제목 아래 이유 줄(R-301). 글자는 MokaCore `ReasonText`가 만든다.
struct ReasonLineText: View {
    let text: String

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.panelPalette) private var palette

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .lineLimit(1)
            .foregroundStyle(contrast == .increased ? palette.mutedHighContrast : palette.muted)
    }
}

/// 키 확인 필요인 동안 노치 펼친 화면 아래 한 줄(R-316, 확정 시안 12~14번).
struct KeyNoticeLine: View {
    let onOpen: () -> Void

    @Environment(\.panelPalette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Text(GateDisplay.keyNoticeText)
                .font(.system(size: 11))
                .foregroundStyle(palette.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(GateDisplay.keyNoticeButton, action: onOpen)
                .buttonStyle(NotchButtonStyle(kind: .ghost))
        }
    }
}
