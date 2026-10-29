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

/// 시간 끝 화면(R-008·R-010, 시안 v3.4 6번): 제목과 빨간 0:00, 기본값으로 채운 칩, 다시 시작·완료.
/// 완료가 기본 버튼이다. 직접 입력 중에는 Enter가 할 일을 비우지 않도록 다시 시작을 기본 버튼으로 바꾼다.
/// Enter는 사용자가 판을 클릭해 패널이 key가 된 뒤에만 닿는다(R-009).
struct ExpiredView: View {
    let title: String
    let chipMin: Int
    let chip: QuantumChipInput
    let onStart: () -> Void
    let onComplete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TitleText(title: title)
            RemainingText(seconds: 0, expired: true)
        }
        QuantumChipView(
            chipMin: chipMin, customText: chip.customText,
            onChoose: chip.onChoose, onBeginCustom: chip.onBeginCustom, onEditCustom: chip.onEditCustom)
        HStack(spacing: 6) {
            if let customText = chip.customText {
                CustomMinutesField(
                    text: customText, takeFocusRequest: chip.takeFocusRequest, onEdit: chip.onEditCustom,
                    onSubmit: submitCustom)
            }
            Spacer(minLength: 0)
            if chip.customText != nil {
                Button(action: onStart) { ButtonLabel(text: "다시 시작", shortcut: "↵") }
                    .buttonStyle(NotchButtonStyle(kind: .secondary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!chip.canStart)
                Button(action: onComplete) { ButtonLabel(text: "완료") }
                    .buttonStyle(NotchButtonStyle(kind: .primary))
            } else {
                Button(action: onStart) { ButtonLabel(text: "다시 시작") }
                    .buttonStyle(NotchButtonStyle(kind: .secondary))
                Button(action: onComplete) { ButtonLabel(text: "완료", shortcut: "↵") }
                    .buttonStyle(NotchButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        if let message = CustomIssueText.message(for: chip.customText) {
            CustomIssueText(message: message)
        }
    }

    private func submitCustom() {
        if chip.canStart { onStart() }
    }
}
