import MokaCore
import SwiftUI

/// 설정 창 일정 탭(시안 10번, R-115). 날짜순 목록, 더하기·고치기(두 번 클릭, R-121)·지우기(한 번 묻는다, R-120). 값과 콜백만 받는다(ADR-0009).
struct ContextTabView: View {
    let rows: [MokaContext]
    @Binding var selectedID: ContextID?
    /// 한꺼번에 지울 일정(R-120). 있으면 `−`가 이것들을 지운다.
    @Binding var checkedIDs: Set<ContextID>
    /// 저장할 수 없으면(R-119) 더하기·지우기가 꺼진다.
    let canEdit: Bool
    let onAdd: () -> Void
    let onEdit: (ContextID) -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, context in
                        if index > 0 { Divider() }
                        HStack(spacing: 0) {
                            RowCheckBox(
                                isOn: Binding(
                                    get: { checkedIDs.contains(context.id) },
                                    set: { isOn in
                                        if isOn {
                                            checkedIDs.insert(context.id)
                                        } else {
                                            checkedIDs.remove(context.id)
                                        }
                                    }),
                                label: context.name
                            )
                            .padding(.leading, 10)
                            ContextRow(context: context)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedID = context.id }
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded { if canEdit { onEdit(context.id) } }
                                )
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAddTraits(context.id == selectedID ? .isSelected : [])
                                .accessibilityAction(named: "고치기") { if canEdit { onEdit(context.id) } }
                        }
                        .background(context.id == selectedID ? MokaColors.mocha.opacity(0.22) : Color.clear)
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
                        .disabled(!canEdit || !rows.contains { $0.id == selectedID || checkedIDs.contains($0.id) })
                }
                Text("두 번 클릭하면 고쳐요. 시험·제출처럼 할 일 순서에 영향을 주는 일정이에요.")
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
        .accessibilityElement(children: .combine)
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
            .accessibilityLabel("중요도 \(ContextText.impact(impact))")
    }

    private var background: Color {
        switch impact {
        case .normal: Color(hex: 0x806E5F, opacity: 0.16)
        case .high: MokaColors.mocha.opacity(0.3)
        case .critical: MokaColors.danger.opacity(0.2)
        }
    }
}
