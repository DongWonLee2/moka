/// 온보딩 끝내기(R-116, data-model §6).
public enum Onboarding {
    /// 컨텍스트가 있으면 저장 → 세 설정 쓰기 → 마지막에 `onboarding_done = true`. 중간에 실패하면 그 오류를 던지고
    /// `onboarding_done`을 쓰지 않아 다음 실행에 다시 보인다. 다시 실행해 컨텍스트가 두 번 저장되는 것은 받아들인다.
    public static func finish(
        context: NewContext?, quantumMin: Int, extendMin: Int, dayStart: DayStart, settings: any SettingsStore,
        contexts: any ContextStore
    ) throws {
        if let context {
            _ = try contexts.insertContext(context)
        }
        try QuantumSettings.writeDefault(quantumMin, to: settings)
        try CoreSettings.writeExtendMin(extendMin, to: settings)
        try CoreSettings.writeDayStart(dayStart, to: settings)
        try CoreSettings.markOnboardingDone(in: settings)
    }
}
