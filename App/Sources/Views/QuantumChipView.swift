import MokaCore
import SwiftUI

/// 시간 칩: 분할 컨트롤(15분|25분|45분|60분|직접…)과 직접 입력 칸(R-003·R-004, 시안 v3.4 3·6번).
/// 값과 콜백만 받는다. 칩 값이 프리셋이 아니면(직접 입력이나 프리셋 밖 기본값) "직접…"이 선택된다.
struct QuantumChipView: View {
    let chipMin: Int
    /// 직접 입력 칸 글자. nil이면 직접 입력을 쓰지 않는 중.
    let customText: String?
    let onChoose: (Int) -> Void
    let onBeginCustom: () -> Void
    let onEditCustom: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(QuantumChip.presets, id: \.self) { minutes in
                segment("\(minutes)분", selected: !isCustom && chipMin == minutes) { onChoose(minutes) }
            }
            segment("직접…", selected: isCustom) {
                if customText == nil { onBeginCustom() }
            }
        }
        .padding(2)
        .background(MokaColors.control, in: .rect(cornerRadius: 7))
    }

    private var isCustom: Bool {
        customText != nil || !QuantumChip.presets.contains(chipMin)
    }

    private func segment(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(selected ? MokaColors.textOnPrimary : MokaColors.segmentText)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 5).fill(MokaColors.primaryGradient)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 직접 입력 칸 줄의 앞부분: 숫자 칸과 "분". 틀린 값은 빨간 테두리와 꺼진 시작 버튼으로만 알린다(화면 문구 없음).
/// 포커스는 "직접…"을 누른 직후 나타날 때만 준다. 마우스로 다시 펼쳐 칸이 다시 만들어질 때는 주지 않는다(SC-003).
struct CustomMinutesField: View {
    let text: String
    let takeFocusRequest: () -> Bool
    let onEdit: (String) -> Void
    let onSubmit: () -> Void

    @State private var editing = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $editing)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($focused)
                .onSubmit(onSubmit)
                .padding(.horizontal, 8)
                .frame(width: 46, height: 24)
                .background(MokaColors.field, in: .rect(cornerRadius: ExpandedView.controlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: ExpandedView.controlRadius)
                        .strokeBorder(borderColor, lineWidth: 1)
                }
                .accessibilityLabel("직접 입력 분")
                .accessibilityHint(isInvalid ? "1에서 180 사이 정수를 입력하세요" : "")
            Text("분")
                .font(.system(size: 11))
                .foregroundStyle(MokaColors.notchMuted)
        }
        .onAppear {
            editing = text
            if takeFocusRequest() { focused = true }
        }
        .onChange(of: editing) { _, newValue in
            if newValue != text { onEdit(newValue) }
        }
    }

    private var isInvalid: Bool {
        QuantumChip.parseCustom(text) == nil
    }

    private var borderColor: Color {
        if isInvalid { return MokaColors.danger }
        return focused ? MokaColors.mochaHighlight : MokaColors.fieldLine
    }
}
