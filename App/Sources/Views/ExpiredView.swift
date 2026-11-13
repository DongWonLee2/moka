import MokaCore
import SwiftUI

/// 시간 칩 줄에 필요한 값과 콜백(시간 고르기·시간 끝 공통).
struct QuantumChipInput {
    var customText: String?
    var canStart: Bool
    var onChoose: (Int) -> Void
    var onBeginCustom: () -> Void
    var onEditCustom: (String) -> Void
    /// 직접 입력 칸이 나타날 때 부른다. 사용자가 "직접…"을 누른 직후에만 true(포커스를 줌).
    var takeFocusRequest: () -> Bool
}

/// 시간 끝 화면(R-008·R-010·R-107, 시안 v2 5번): 제목과 빨간 0:00, 두 줄 칸, 기본값으로 채운 칩,
/// 미루기·바꾸기와 N분 더(다시 시작)·완료. 어느 버튼이든 그때 적힌 두 줄이 남는다.
/// Enter: 칸 밖은 완료, 직접 입력 중에는 N분 더(할 일을 비우지 않게), 첫 칸은 둘째 칸으로, 둘째 칸은 아무 동작 없음(§8).
/// Enter는 사용자가 판을 클릭해 패널이 key가 된 뒤에만 닿는다(R-009).
struct ExpiredView: View {
    let title: String
    let chipMin: Int
    let chip: QuantumChipInput
    let notes: NotesInput
    let onStart: () -> Void
    let onComplete: () -> Void

    @FocusState private var notesFocus: NotesFields.Field?
    @Environment(\.isNotchIllustration) private var isIllustration

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TitleText(title: title, lineLimit: 1)
            RemainingText(seconds: 0, expired: true)
        }
        NotesFields(
            draft: notes.draft, onEdit: notes.onEdit, donePlaceholder: "비워 둬도 돼요", focus: $notesFocus,
            onSubmitNext: {})
        QuantumChipView(
            chipMin: chipMin, customText: chip.customText,
            onChoose: chip.onChoose, onBeginCustom: chip.onBeginCustom, onEditCustom: chip.onEditCustom)
        if let customText = chip.customText {
            CustomMinutesField(
                text: customText, takeFocusRequest: chip.takeFocusRequest, onEdit: chip.onEditCustom,
                onSubmit: submitCustom)
        }
        HStack(spacing: 6) {
            Button(NotchText.skip) { notes.onBegin(.skip) }
                .buttonStyle(NotchButtonStyle(kind: .secondary))
            Button(NotchText.switchTask) { notes.onBegin(.switch) }
                .buttonStyle(NotchButtonStyle(kind: .secondary))
            Spacer(minLength: 0)
            Button(action: onStart) {
                ButtonLabel(text: againLabel, shortcut: againIsDefault ? "↵" : nil)
            }
            .buttonStyle(NotchButtonStyle(kind: .secondary))
            .keyboardShortcut(againIsDefault && !isIllustration ? .defaultAction : nil)
            .disabled(!chip.canStart)
            Button(action: onComplete) {
                ButtonLabel(text: NotchText.complete, shortcut: completeIsDefault ? "↵" : nil)
            }
            .buttonStyle(NotchButtonStyle(kind: .primary))
            .keyboardShortcut(completeIsDefault && !isIllustration ? .defaultAction : nil)
        }
        if let message = QuantumChip.customIssueMessage(customText: chip.customText) {
            CustomIssueText(message: message)
        }
    }

    /// 두 줄 칸에 포커스가 있으면 Enter는 칸의 몫이라 기본 버튼을 두지 않는다.
    private var againIsDefault: Bool { chip.customText != nil && notesFocus == nil }
    private var completeIsDefault: Bool { chip.customText == nil && notesFocus == nil }

    private var againLabel: String {
        QuantumChip.againLabel(chipMin: chipMin, customText: chip.customText)
    }

    private func submitCustom() {
        if chip.canStart { onStart() }
    }
}
