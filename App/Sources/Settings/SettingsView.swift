import MokaCore
import SwiftUI
import os

/// 설정 화면: 기본 작업 시간(`default_quantum_min`) 하나(R-012). 시안 8번 "메뉴 막대 메뉴와 설정".
/// 숫자 칸은 제출(Enter)이나 포커스를 잃을 때 저장하고, 1~180 정수가 아니거나 저장에 실패하면 저장된 값으로 되돌린다.
/// 스테퍼는 누를 때마다 1분씩 바꿔 바로 저장한다.
struct SettingsView: View {
    let store: any SettingsStore
    /// 저장을 시도한 뒤 부른다. 펼친 판의 고르지 않은 칩이 새 기본값을 따르게 한다(R-013).
    let onSaved: @MainActor () -> Void

    @State private var text = ""
    private static let logger = Logger(subsystem: "dev.dongwon.moka", category: "settings")
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CupIcon()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(MokaColors.foam)
                    .frame(width: 34, height: 34)
                    .background(MokaColors.mocha, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    MokaWordmark(size: 13)
                    Text("지금 할 일 하나")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack(spacing: 4) {
                Text("기본 작업 시간")
                Spacer()
                TextField("기본 작업 시간", text: $text)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                    .focused($isFieldFocused)
                    .onSubmit(commit)
                Stepper("기본 작업 시간", value: stepperValue, in: Defaults.quantumMinRange, step: 1)
                    .labelsHidden()
                Text("분")
            }
            Text("새 할 일에 먼저 골라 둘 시간이에요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .frame(width: 320)
        .navigationTitle("Moka 설정")
        .onAppear { text = String(QuantumSettings.readDefault(from: store)) }
        .onChange(of: isFieldFocused) { _, focused in
            if !focused { commit() }
        }
        .onDisappear(perform: commit)
    }

    /// 칸에 유효한 값이 있으면 그 값에서, 없으면 저장된 값에서 한 칸 움직인다.
    private var stepperValue: Binding<Int> {
        Binding(
            get: { QuantumChip.parseCustom(text) ?? QuantumSettings.readDefault(from: store) },
            set: { save($0) })
    }

    private func commit() {
        if let minutes = QuantumChip.parseCustom(text) {
            save(minutes)
        } else {
            text = String(QuantumSettings.readDefault(from: store))
        }
    }

    /// 저장하고 칸을 저장된 값으로 맞춘다. 저장에 실패하면 이전 값이 보인다.
    private func save(_ minutes: Int) {
        do {
            try QuantumSettings.writeDefault(minutes, to: store)
        } catch {
            Self.logger.error("기본 작업 시간 저장 실패: \(String(reflecting: type(of: error)), privacy: .public)")
        }
        text = String(QuantumSettings.readDefault(from: store))
        onSaved()
    }
}
