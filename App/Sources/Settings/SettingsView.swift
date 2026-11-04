import MokaCore
import SwiftUI
import os

/// 설정 창: 위에 탭, 창 제목은 탭 이름(시안 6·7번, R-012·R-102). 일정 탭은 T060에서 더한다.
/// 숫자 칸은 받는 값이면 저장하고, 아니거나 저장에 실패하면 저장된 값으로 되돌린다(`FieldCommit`).
/// 스테퍼는 누를 때마다 1분씩 바꿔 바로 저장한다. 하루 시작 시각은 고를 때마다 저장한다.
struct SettingsView: View {
    let store: any SettingsStore
    @Bindable var appState: AppState
    /// 기본 작업 시간 저장을 시도한 뒤 부른다. 펼친 판의 고르지 않은 칩이 새 기본값을 따르게 한다(R-013).
    let onSaved: @MainActor () -> Void

    @State private var quantumText = ""
    @State private var extendText = ""
    @State private var dayStart = Date()
    private let calendar = GregorianCalendar.make(timeZone: .autoupdatingCurrent)
    private static let logger = Logger(subsystem: "dev.dongwon.moka", category: "settings")

    var body: some View {
        TabView {
            BasicTabView(
                quantum: MinutesFieldInput(
                    text: $quantumText,
                    stepperValue: QuantumChip.parseCustom(quantumText) ?? QuantumSettings.readDefault(from: store),
                    range: Defaults.quantumMinRange,
                    onCommit: { applyQuantum(QuantumSettings.commitField(quantumText, to: store)) },
                    onStep: { applyQuantum(QuantumSettings.saveField($0, to: store)) }),
                extend: MinutesFieldInput(
                    text: $extendText,
                    stepperValue: QuantumChip.parseCustom(extendText) ?? CoreSettings.readExtendMin(from: store),
                    range: Defaults.extendMinRange,
                    onCommit: { applyExtend(CoreSettings.commitExtendField(extendText, to: store)) },
                    onStep: { applyExtend(CoreSettings.saveExtendField($0, to: store)) }),
                dayStart: Binding(get: { dayStart }, set: { saveDayStart($0) })
            )
            .tabItem { Label("기본", systemImage: "gearshape") }
            TaskListTabView(
                rows: appState.taskListRows, nextMarkID: appState.nextMarkID, scope: $appState.taskListScope,
                order: $appState.taskListOrder
            )
            .tabItem { Label("할 일", systemImage: "list.bullet") }
        }
        .frame(width: 460)
        .background(SettingsWindowRaiser.Anchor())
        .onAppear(perform: load)
        .onDisappear {
            applyQuantum(QuantumSettings.commitField(quantumText, to: store))
            applyExtend(CoreSettings.commitExtendField(extendText, to: store))
        }
    }

    private func load() {
        quantumText = String(QuantumSettings.readDefault(from: store))
        extendText = String(CoreSettings.readExtendMin(from: store))
        dayStart = CoreSettings.readDayStart(from: store).date(calendar: calendar)
    }

    private func applyQuantum(_ result: FieldCommit) {
        log(result.error, "기본 작업 시간")
        quantumText = result.shown
        if result.attempted { onSaved() }
    }

    private func applyExtend(_ result: FieldCommit) {
        log(result.error, "추가 시간")
        extendText = result.shown
    }

    private func saveDayStart(_ date: Date) {
        do {
            try CoreSettings.writeDayStart(DayStart(date: date, calendar: calendar), to: store)
        } catch {
            log(error, "하루 시작 시각")
        }
        dayStart = CoreSettings.readDayStart(from: store).date(calendar: calendar)
    }

    private func log(_ error: (any Error)?, _ field: String) {
        guard let error else { return }
        Self.logger.error("\(field, privacy: .public) 저장 실패: \(String(reflecting: type(of: error)), privacy: .public)")
    }
}
