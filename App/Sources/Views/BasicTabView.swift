import MokaCore
import SwiftUI

/// 설정 창 기본 탭(시안 6번, R-012, data-model §6). 값과 콜백만 받는다(ADR-0009).
/// 숫자 칸은 제출(Enter)이나 포커스를 잃을 때 `onCommit`을 부른다. 받지 않는 값을 적는 동안은 안내 대신 이유를 보인다.
struct BasicTabView: View {
    let quantum: MinutesFieldInput
    let extend: MinutesFieldInput
    @Binding var dayStart: Date

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            MinutesFieldRow(
                label: "기본 작업 시간", hint: "새 할 일에 먼저 골라 둘 시간이에요.", input: quantum)
            MinutesFieldRow(
                label: "추가 시간", hint: "시간이 끝났을 때 더 이어 갈 시간이에요.", input: extend)
            GridRow {
                Text("하루 시작 시각")
                DatePicker("하루 시작 시각", selection: $dayStart, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .environment(\.locale, Self.twentyFourHour)
                    .fixedSize()
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                HintText(text: "이 시각이 지나면 반복 할 일이 다시 대기로 돌아와요.", isIssue: false)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 시안 6번처럼 `06:00`(24시간)으로 보인다. 언어·지역은 시스템 설정을 따른다.
    private static let twentyFourHour: Locale = {
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
