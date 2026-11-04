import SwiftUI

/// 하나만 고르는 칩 줄(시안 `.ms`). macOS 세그먼트는 고른 칸을 시스템 강조색으로 그려 직접 그린다.
struct ChoiceChips<Value: Hashable>: View {
    let label: String
    let items: [(Value, String)]
    @Binding var selection: Value
    var horizontalPadding: CGFloat = 9
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { value, title in
                let isOn = value == selection
                Button {
                    selection = value
                } label: {
                    Text(title)
                        .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? MokaColors.textOnPrimary : Color.primary)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, 1)
                        .background(isOn ? MokaColors.mocha : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            colorScheme == .dark ? Color(hex: 0xFFF0E1, opacity: 0.09) : Color(hex: 0x3C2314, opacity: 0.08),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
