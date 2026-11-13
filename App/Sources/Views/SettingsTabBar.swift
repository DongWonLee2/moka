import SwiftUI

enum SettingsTab: CaseIterable {
    case basic, tasks, contexts, help

    var title: String {
        switch self {
        case .basic: "기본"
        case .tasks: "할 일"
        case .contexts: "일정"
        case .help: "도움말"
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
                        TabIcon(tab: tab)
                            .frame(width: 18, height: 18)
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
                .accessibilityLabel(tab.title)
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

private struct TabIcon: View {
    let tab: SettingsTab

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            context.scaleBy(x: scale, y: scale)
            let line = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            switch tab {
            case .basic:
                context.stroke(
                    Path(ellipseIn: CGRect(x: 8.8, y: 8.8, width: 6.4, height: 6.4)), with: .foreground,
                    style: line)
                context.stroke(Self.gearRays, with: .foreground, style: line)
            case .tasks:
                context.stroke(
                    Self.checks, with: .foreground,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                context.stroke(Self.listLines, with: .foreground, style: line)
            case .contexts:
                context.stroke(
                    Path(roundedRect: CGRect(x: 3.5, y: 5, width: 17, height: 15), cornerRadius: 2.5),
                    with: .foreground, style: line)
                context.stroke(Self.calendarLines, with: .foreground, style: line)
            case .help:
                context.stroke(
                    Path(ellipseIn: CGRect(x: 3.4, y: 3.4, width: 17.2, height: 17.2)), with: .foreground, style: line)
                context.stroke(Self.questionHook, with: .foreground, style: line)
                context.fill(Path(ellipseIn: CGRect(x: 11, y: 15.6, width: 2, height: 2)), with: .foreground)
            }
        }
    }

    private static let gearRays = Path { path in
        for (from, to) in [
            ((12.0, 2.8), (12.0, 5.4)), ((12.0, 18.6), (12.0, 21.2)), ((2.8, 12.0), (5.4, 12.0)),
            ((18.6, 12.0), (21.2, 12.0)), ((5.5, 5.5), (7.3, 7.3)), ((16.7, 16.7), (18.5, 18.5)),
            ((5.5, 18.5), (7.3, 16.7)), ((16.7, 7.3), (18.5, 5.5)),
        ] {
            path.move(to: CGPoint(x: from.0, y: from.1))
            path.addLine(to: CGPoint(x: to.0, y: to.1))
        }
    }

    private static let checks = Path { path in
        for y in [6.5, 12.5, 18.5] {
            path.move(to: CGPoint(x: 4, y: y))
            path.addLine(to: CGPoint(x: 5.5, y: y + 1.5))
            path.addLine(to: CGPoint(x: 8, y: y - 1))
        }
    }

    private static let calendarLines = Path { path in
        for (from, to) in [((3.5, 10.0), (20.5, 10.0)), ((8.0, 3.0), (8.0, 7.0)), ((16.0, 3.0), (16.0, 7.0))] {
            path.move(to: CGPoint(x: from.0, y: from.1))
            path.addLine(to: CGPoint(x: to.0, y: to.1))
        }
    }

    private static let questionHook = Path { path in
        path.addArc(
            center: CGPoint(x: 12.1, y: 9.37), radius: 2.5, startAngle: .degrees(180), endAngle: .degrees(68.9),
            clockwise: false)
        path.addCurve(
            to: CGPoint(x: 12, y: 13.2), control1: CGPoint(x: 12.3, y: 12), control2: CGPoint(x: 12, y: 12.5))
        path.addLine(to: CGPoint(x: 12, y: 13.8))
    }

    private static let listLines = Path { path in
        for y in [7.0, 13.0, 19.0] {
            path.move(to: CGPoint(x: 11, y: y))
            path.addLine(to: CGPoint(x: 20, y: y))
        }
    }
}
