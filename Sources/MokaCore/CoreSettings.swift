import Foundation

public enum CoreSettingsError: Error, Equatable {
    case outOfRange
}

/// `default_extend_min`·`day_start`·`onboarding_done` 읽기·쓰기 규칙(data-model §6). `default_quantum_min`은 `QuantumSettings`.
public enum CoreSettings {
    public static let extendMinKey = "default_extend_min"
    public static let dayStartKey = "day_start"
    public static let onboardingDoneKey = "onboarding_done"
    public static let decisionProviderKey = "decision_provider"
    public static let microsoftEndpointKey = "microsoft_endpoint"
    public static let microsoftDeploymentKey = "microsoft_deployment"

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

    /// 설정 창 추가 시간 칸에 제출한 글자. 규칙은 `QuantumSettings.commitField`와 같다.
    public static func commitExtendField(_ text: String, to store: some SettingsStore) -> FieldCommit {
        FieldCommit.commit(text, read: { readExtendMin(from: store) }, write: { try writeExtendMin($0, to: store) })
    }

    public static func saveExtendField(_ minutes: Int, to store: some SettingsStore) -> FieldCommit {
        FieldCommit.save(minutes, read: { readExtendMin(from: store) }, write: { try writeExtendMin($0, to: store) })
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

    /// 고른 공급자 ID 글자(spec 006 research R8). 없으면 `nil`이고 `DecisionSelection`이 Jev로 본다.
    /// 읽기 실패는 없음과 다르므로 던진다(#128).
    public static func readDecisionProvider(from store: some SettingsStore) throws -> String? {
        try store.value(for: decisionProviderKey)
    }

    public static func writeDecisionProvider(_ id: ProviderID, to store: some SettingsStore) throws {
        try store.setValue(id.rawValue, for: decisionProviderKey)
    }

    /// 저장한 Microsoft 리소스 주소 글자. `DecisionSelection`이 주소 규칙으로 다시 본다. 읽기 실패는 던진다(#128).
    public static func readMicrosoftEndpoint(from store: some SettingsStore) throws -> String? {
        try store.value(for: microsoftEndpointKey)
    }

    /// `endpoint`는 `EndpointRule.check`를 통과한 주소다.
    public static func writeMicrosoftEndpoint(_ endpoint: URL, to store: some SettingsStore) throws {
        try store.setValue(endpoint.absoluteString, for: microsoftEndpointKey)
    }

    public static func readMicrosoftDeployment(from store: some SettingsStore) -> String? {
        (try? store.value(for: microsoftDeploymentKey)) ?? nil
    }

    /// 앞뒤 공백·줄바꿈을 지워 쓴다.
    public static func writeMicrosoftDeployment(_ deployment: String, to store: some SettingsStore) throws {
        try store.setValue(deployment.trimmingCharacters(in: .whitespacesAndNewlines), for: microsoftDeploymentKey)
    }
}
