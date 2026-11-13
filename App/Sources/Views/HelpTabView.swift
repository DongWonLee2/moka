import SwiftUI

/// 설정 창 도움말 탭(spec 007 R-701~R-707, 확정 시안 1~9번). 읽기만 한다. 펼친 항목은 탭 밖(`AppState.helpExpanded`)에 둔다.
struct HelpTabView: View {
    @Binding var expanded: Set<HelpTopic>
    let onShowGuide: () -> Void

    /// 접힌 목차가 스크롤 없이 다 보이는 높이. 펼친 글이 넘치면 탭 안에서 스크롤한다(R-707).
    static let scrollHeight: CGFloat = 430

    var body: some View {
        ScrollView {
            HelpTabContent(expanded: $expanded, onShowGuide: onShowGuide)
        }
        .frame(height: Self.scrollHeight)
    }
}

/// 맨 위 줄(설명과 "안내 다시 보기")과 항목 여덟.
struct HelpTabContent: View {
    @Binding var expanded: Set<HelpTopic>
    let onShowGuide: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(HelpText.guideMessage)
                    .font(.system(size: 11.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                SheetButton(title: HelpText.guideButton, kind: .normal, action: onShowGuide)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                MokaColors.mocha.opacity(colorScheme == .dark ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 7))
            VStack(spacing: 0) {
                ForEach(Array(HelpTopic.allCases.enumerated()), id: \.element) { index, topic in
                    if index > 0 { Divider() }
                    HelpTopicRow(topic: topic, isExpanded: expanded.contains(topic)) {
                        if expanded.contains(topic) { expanded.remove(topic) } else { expanded.insert(topic) }
                    }
                }
            }
            .background(
                colorScheme == .dark ? Color(hex: 0x221E1B) : Color.white, in: RoundedRectangle(cornerRadius: 7)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color(hex: 0xFFF0E1, opacity: 0.12) : Color(hex: 0x3C2314, opacity: 0.18),
                        lineWidth: 0.5))
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }
}

private struct HelpTopicRow: View {
    let topic: HelpTopic
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 8) {
                    Text(isExpanded ? "▾" : "▸")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, alignment: .leading)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(HelpContent.title(topic))
                            .fontWeight(.medium)
                        Text(HelpContent.summary(topic))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(HelpText.value(expanded: isExpanded))
            if isExpanded {
                HelpBodyView(content: HelpContent.body(topic))
                    .padding(.leading, 20)
                    .padding(.top, 5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 36)
        .background(isExpanded ? MokaColors.mocha.opacity(0.08) : Color.clear)
    }
}

private struct HelpBodyView: View {
    let content: HelpBody

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch content {
        case .text(let text):
            Text(text)
                .font(.system(size: 11.5))
                .lineSpacing(3.5)
                .foregroundStyle(colorScheme == .dark ? Color(hex: 0xD9CFC6) : Color(hex: 0x3B322C))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .shortcuts(let rows):
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Divider()
                    HStack(alignment: .top, spacing: 0) {
                        Text(row.action)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .frame(width: 72, alignment: .leading)
                            .padding(.horizontal, 4)
                        Text(row.place)
                            .foregroundStyle(.secondary)
                            .frame(width: 112, alignment: .leading)
                            .padding(.horizontal, 4)
                        Text(row.effect)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .combine)
                }
            }
            .font(.system(size: 11))
            .padding(.top, 1)
        }
    }
}
