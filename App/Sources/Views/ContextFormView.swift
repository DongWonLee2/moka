import MokaCore
import SwiftUI

/// 일정 시트(시안 10번, R-115). 이름·날짜·중요도 셋 다 필수. `editing`이 있으면 고치기다(R-121). 값과 콜백만 받는다(ADR-0009).
struct ContextFormView: View {
    let today: LocalDay
    let calendar: Calendar
    let editing: MokaContext?
    let onSave: (NewContext) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var date: LocalDay
    @State private var impact: ContextImpact
    @State private var isPickingDate = false
    @FocusState private var isNameFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    init(
        today: LocalDay, calendar: Calendar, editing: MokaContext? = nil, onSave: @escaping (NewContext) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.today = today
        self.calendar = calendar
        self.editing = editing
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: editing?.name ?? "")
        _date = State(initialValue: editing?.date ?? today)
        _impact = State(initialValue: editing?.impact ?? .normal)
    }

    private var canSave: Bool { MokaContext.normalizedName(name) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(editing == nil ? "새 일정" : "일정 고치기")
                .font(.system(size: 13, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    FormLabel("이름")
                    TextField("예: 중간고사", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNameFocused)
                        .accessibilityLabel("이름")
                }
                GridRow {
                    FormLabel("날짜")
                    PillButton(title: ContextText.formDate(date), isMuted: false) { isPickingDate = true }
                        .accessibilityLabel("날짜")
                        .accessibilityValue(ContextText.formDate(date))
                        .popover(isPresented: $isPickingDate, arrowEdge: .bottom) {
                            MokaCalendar(
                                selected: date, today: today, calendar: calendar, allowsClear: false,
                                onPick: { day in
                                    if let day { date = day }
                                    isPickingDate = false
                                })
                        }
                }
                GridRow {
                    FormLabel("중요도")
                    ChoiceChips(
                        label: "중요도", items: ContextImpact.allCases.map { ($0, ContextText.impact($0)) },
                        selection: $impact)
                }
            }
            HStack(spacing: 6) {
                Spacer()
                SheetButton(title: SheetText.cancel, kind: .normal, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                SheetButton(title: SheetText.save, kind: .primary, action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 360)
        .background(colorScheme == .dark ? Color(hex: 0x332D29) : Color(hex: 0xFAF7F5))
        .onAppear { isNameFocused = true }
    }

    private func save() {
        guard canSave else { return }
        onSave(NewContext(name: name, date: date, impact: impact))
    }
}
