import SwiftUI

enum SettingsTab: CaseIterable {
    case basic, tasks

    var title: String {
        switch self {
        case .basic: "기본"
        case .tasks: "할 일"
        }
    }

    var symbol: String {
        switch self {
        case .basic: "gearshape"
        case .tasks: "checklist"
        }
    }
}

/// 설정 창 위 탭 줄(시안 6·7번 `.tabs`). macOS 설정 툴바는 고른 탭을 시스템 강조색으로 그려 모카색을 줄 수 없어 직접 그린다.
struct SettingsTabBar: View {
    @Binding var selection: SettingsTab
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                let isOn = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 15))
                            .frame(height: 18)
                        Text(tab.title)
                            .font(.system(size: 11))
                    }
                    .frame(width: 64)
                    .padding(.vertical, 4)
                    .foregroundStyle(isOn ? onColor : Color.primary)
                    .opacity(isOn ? 1 : 0.75)
                    .background(
                        isOn ? MokaColors.mocha.opacity(colorScheme == .dark ? 0.22 : 0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(colorScheme == .dark ? Color(hex: 0xFFF0E1, opacity: 0.1) : Color(hex: 0x3C2314, opacity: 0.12))
                .frame(height: 1)
        }
    }

    private var onColor: Color { colorScheme == .dark ? MokaColors.crema : MokaColors.mocha }
}
