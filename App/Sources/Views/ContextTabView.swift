import MokaCore
import SwiftUI

/// 설정 창 일정 탭(시안 10번, R-115). 날짜순 목록, 더하기·지우기만 있다(−는 확인 없이 바로 지움). 값과 콜백만 받는다(ADR-0009).
struct ContextTabView: View {
    let rows: [MokaContext]
    @Binding var selectedID: ContextID?
    /// 저장할 수 없으면(R-119) 더하기·지우기가 꺼진다.
    let canEdit: Bool
    let onAdd: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, context in
                        if index > 0 { Divider() }
                        ContextRow(context: context, isSelected: context.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedID = context.id }
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
            .frame(height: 300)
            .background(
                colorScheme == .dark ? Color(hex: 0x221E1B) : Color.white, in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color(hex: 0xFFF0E1, opacity: 0.12) : Color(hex: 0x3C2314, opacity: 0.18),
                        lineWidth: 0.5))
            HStack(spacing: 6) {
                HStack(spacing: 1) {
                    ListEditButton(symbol: "plus", label: "새 일정", action: onAdd)
                        .disabled(!canEdit)
                    ListEditButton(symbol: "minus", label: "고른 일정 지우기", action: onDelete)
                        .disabled(!canEdit || !rows.contains { $0.id == selectedID })
                }
                Text("시험·제출처럼 할 일 순서에 영향을 주는 일정이에요.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }
}

private struct ContextRow: View {
    let context: MokaContext
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(context.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(ContextText.rowDate(context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ImpactBadge(impact: context.impact)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 40)
        .background(isSelected ? MokaColors.mocha.opacity(0.22) : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ImpactBadge: View {
    let impact: ContextImpact

    var body: some View {
        Text(ContextText.impact(impact))
            .font(.system(size: 10.5, weight: impact == .critical ? .semibold : .regular))
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .foregroundStyle(impact == .critical ? MokaColors.danger : Color.primary)
            .background(background, in: Capsule())
    }

    private var background: Color {
        switch impact {
        case .normal: Color(hex: 0x806E5F, opacity: 0.16)
        case .high: MokaColors.mocha.opacity(0.3)
        case .critical: MokaColors.danger.opacity(0.2)
        }
    }
}
