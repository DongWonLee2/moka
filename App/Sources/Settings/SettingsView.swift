import MokaCore
import SwiftUI
import os

/// 설정 화면: 기본 작업 시간(`default_quantum_min`) 하나(R-012).
/// 제출(Enter)이나 포커스를 잃을 때 저장하고, 1~180 정수가 아니거나 저장에 실패하면 칸을 저장된 값으로 되돌린다.
struct SettingsView: View {
    let store: any SettingsStore

    @State private var text = ""
    private static let logger = Logger(subsystem: "dev.dongwon.moka", category: "settings")
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        Form {
            LabeledContent("기본 작업 시간") {
                HStack(spacing: 6) {
                    TextField("기본 작업 시간", text: $text)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                        .focused($isFieldFocused)
                        .onSubmit(commit)
                    Text("분")
                }
            }
            Text("1~180분. 다음에 칩을 채울 때부터 쓴다. 도는 타이머는 그대로다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { text = String(QuantumSettings.readDefault(from: store)) }
        .onChange(of: isFieldFocused) { _, focused in
            if !focused { commit() }
        }
        .onDisappear(perform: commit)
    }

    private func commit() {
        if let minutes = QuantumChip.parseCustom(text) {
            do {
                try QuantumSettings.writeDefault(minutes, to: store)
            } catch {
                Self.logger.error("기본 작업 시간 저장 실패: \(String(reflecting: type(of: error)), privacy: .public)")
            }
        }
        text = String(QuantumSettings.readDefault(from: store))
    }
}
