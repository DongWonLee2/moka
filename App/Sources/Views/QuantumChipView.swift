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

/// 직접 입력 칸 줄의 앞부분: 숫자 칸, "분", 범위 밖이면 안내(시안 v3.4 3번). 칸을 보이면 바로 포커스를 준다.
struct CustomMinutesField: View {
    let text: String
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
            Text("분")
                .font(.system(size: 11))
                .foregroundStyle(MokaColors.notchMuted)
            if isInvalid {
                Text("1~180분 사이 정수")
                    .font(.system(size: 11))
                    .foregroundStyle(MokaColors.danger)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .onAppear {
            editing = text
            focused = true
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
