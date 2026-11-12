import AppKit
import MokaCore
import SwiftUI

/// 설정 창 기본 탭(시안 6번, R-012, data-model §6). 값과 콜백만 받는다(ADR-0009).
/// 숫자 칸은 제출(Enter)이나 포커스를 잃을 때 `onCommit`을 부른다. 받지 않는 값을 적는 동안은 안내 대신 이유를 보인다.
/// 아래에 판단 모델 칸(spec 006 data-model §9, 006 시안 1~10번)을 둔다.
struct BasicTabView: View {
    let quantum: MinutesFieldInput
    let extend: MinutesFieldInput
    @Binding var dayStart: Date
    var decision = DecisionFieldInput()
    var decisionStart = DecisionFieldStart()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsGrid
            DecisionFieldBox(input: decision, start: decisionStart)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            MinutesFieldRow(
                label: "기본 작업 시간", hint: "한 번에 집중할 시간이에요. 새 할 일에 먼저 골라 둬요.", input: quantum)
            MinutesFieldRow(
                label: "추가 시간", hint: "시간이 끝났을 때 더 이어 갈 시간이에요.", input: extend)
            GridRow {
                Text("하루 시작 시각")
                TimeField(date: $dayStart, locale: Self.twentyFourHour)
                    .accessibilityLabel("하루 시작 시각")
                    .frame(width: 52)
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                HintText(text: "이 시각이 지나면 반복 할 일이 다시 대기로 돌아와요.", isIssue: false)
            }
        }
    }

    /// 시안 6번처럼 `06:00`(24시간)으로 보인다. 언어·지역은 시스템 설정을 따른다.
    static let twentyFourHour: Locale = {
        var components = Locale.Components(locale: .autoupdatingCurrent)
        components.hourCycle = .zeroToTwentyThree
        return Locale(components: components)
    }()
}

/// 분 칸 하나의 값과 콜백.
struct MinutesFieldInput {
    @Binding var text: String
    /// 스테퍼가 움직일 기준 값(칸에 받는 값이 있으면 그 값, 없으면 저장된 값).
    let stepperValue: Int
    let range: ClosedRange<Int>
    let onCommit: () -> Void
    let onStep: (Int) -> Void
}

private struct MinutesFieldRow: View {
    let label: String
    let hint: String
    let input: MinutesFieldInput
    @FocusState private var isFocused: Bool

    var body: some View {
        GridRow {
            Text(label)
            HStack(spacing: 4) {
                // macOS는 TextField 제목을 칸 안 자리표시로 그리므로 제목은 비우고 접근성 라벨로만 둔다(#45).
                TextField("", text: input.$text)
                    .labelsHidden()
                    .accessibilityLabel(label)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .focused($isFocused)
                    .onSubmit(input.onCommit)
                    .onChange(of: isFocused) { _, focused in
                        if !focused { input.onCommit() }
                    }
                Stepper(
                    label, value: Binding(get: { input.stepperValue }, set: input.onStep),
                    in: input.range, step: 1
                )
                .labelsHidden()
                Text("분")
            }
        }
        GridRow {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            if let issue = QuantumChip.customIssueMessage(customText: input.text) {
                HintText(text: issue, isIssue: true)
            } else {
                HintText(text: hint, isIssue: false)
            }
        }
    }
}

/// 판단 모델 칸 아래 키 칸(spec 003 R-213 여섯 상태). 키 값은 붙여 넣는 동안 가림 입력에만 있고,
/// 저장을 누르면 넘긴 뒤 바로 비운다(R-214).
struct KeyFieldBox: View {
    let state: KeyFieldState
    /// 다시 물을 할 일이 없거나 물을 수 없으면 "다시 물어보기"가 꺼진다.
    let canRetry: Bool
    let onSave: (String) -> Void
    let onDelete: () -> Void
    let onRetry: () -> Void
    /// 키가 없을 때 칸 위 안내. Microsoft 주소를 바꿔 키를 지운 뒤에는 지웠다는 문구가 대신한다(006 시안 10번).
    var showsIntro = true
    @State private var keyText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state.showsSavedRow {
                HStack(spacing: 6) {
                    Text("저장되어 있어요")
                        .font(.system(size: 12.5))
                    Spacer(minLength: 0)
                    SheetButton(title: "지우기", kind: .dangerText, action: onDelete)
                    SheetButton(title: "다시 물어보기", kind: .normal, action: onRetry)
                        .disabled(!canRetry)
                }
            } else {
                if showsIntro, let intro = KeyFieldState.noKey.notice {
                    Text(intro.text)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 6)
                }
                HStack(spacing: 6) {
                    SecureField("키를 붙여 넣어 주세요", text: $keyText)
                        .accessibilityLabel("판단 모델 키")
                        .onSubmit(save)
                    SheetButton(title: "저장", kind: .primary, action: save)
                        .disabled(!KeyFieldState.canSave(keyText))
                }
            }
            if state != .noKey, let notice = state.notice {
                Text(notice.text)
                    .font(.system(size: 11))
                    .foregroundStyle(notice.isWarning ? AnyShapeStyle(MokaColors.danger) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        guard KeyFieldState.canSave(keyText) else { return }
        onSave(keyText)
        keyText = ""
    }
}

private struct HintText: View {
    let text: String
    let isIssue: Bool

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(isIssue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .fixedSize()
            .padding(.bottom, 6)
    }
}

/// 시·분 칸. SwiftUI `DatePicker`는 macOS에서 내용 폭보다 넓어지지 않아 `NSDatePicker`를 감싼다.
struct TimeField: NSViewRepresentable {
    @Binding var date: Date
    let locale: Locale

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = .hourMinute
        picker.isBezeled = true
        picker.drawsBackground = true
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.date = $date
        picker.locale = locale
        picker.calendar = context.environment.calendar
        picker.timeZone = context.environment.timeZone
        if picker.dateValue != date {
            picker.dateValue = date
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView picker: NSDatePicker, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? picker.intrinsicContentSize.width, height: picker.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(date: $date) }

    @MainActor
    final class Coordinator: NSObject {
        var date: Binding<Date>

        init(date: Binding<Date>) { self.date = date }

        @objc func changed(_ sender: NSDatePicker) {
            date.wrappedValue = sender.dateValue
        }
    }
}
