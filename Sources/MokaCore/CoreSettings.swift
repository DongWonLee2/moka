public enum CoreSettingsError: Error, Equatable {
    case outOfRange
}

/// `default_extend_min`·`day_start`·`onboarding_done` 읽기·쓰기 규칙(data-model §6). `default_quantum_min`은 `QuantumSettings`.
public enum CoreSettings {
    public static let extendMinKey = "default_extend_min"
    public static let dayStartKey = "day_start"
    public static let onboardingDoneKey = "onboarding_done"

    /// 없거나 읽기 실패·정수 아님·1~180 밖이면 10.
    public static func readExtendMin(from store: some SettingsStore) -> Int {
        guard let text = try? store.value(for: extendMinKey),
            let minutes = Int(text),
            Defaults.extendMinRange.contains(minutes)
        else { return Defaults.extendMin }
        return minutes
    }

    /// 1~180 밖이면 쓰지 않고 던진다(이전 값 유지).
    public static func writeExtendMin(_ minutes: Int, to store: some SettingsStore) throws {
        guard Defaults.extendMinRange.contains(minutes) else { throw CoreSettingsError.outOfRange }
        try store.setValue(String(minutes), for: extendMinKey)
    }

    /// 없거나 읽기 실패·형식이 틀리면 06:00.
    public static func readDayStart(from store: some SettingsStore) -> DayStart {
        guard let text = try? store.value(for: dayStartKey), let dayStart = DayStart(text: text) else {
            return Defaults.dayStart
        }
        return dayStart
    }

    public static func writeDayStart(_ dayStart: DayStart, to store: some SettingsStore) throws {
        try store.setValue(dayStart.text, for: dayStartKey)
    }

    /// 값이 정확히 `true`일 때만 끝낸 것. 그 밖(없음, 읽기 실패 포함)이면 온보딩을 보인다.
    public static func isOnboardingDone(in store: some SettingsStore) -> Bool {
        (try? store.value(for: onboardingDoneKey)) == "true"
    }

    public static func markOnboardingDone(in store: some SettingsStore) throws {
        try store.setValue("true", for: onboardingDoneKey)
    }
}
