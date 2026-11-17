import Foundation

/// 3초 뒤 자동 시작(spec 005 R-410, data-model §17). 시각은 부르는 쪽이 주입한 시계로 넘긴다.
public enum AutoStart {
    /// 켜짐, 모드가 세션이고 초안이 떠 있음(`draftShownAt`), 게이트가 묻거나 확인하는 중이 아님, 늘리기 확인 줄이 닫힘,
    /// 시작 실패 문구가 없음이면 초안이 뜬 시각과 마지막 입력 가운데 늦은 쪽에서 `Defaults.autoStartDelay` 뒤. 아니면 nil.
    public static func dueAt(
        enabled: Bool, mode: NotchMode, draftShownAt: Date?, lastInputAt: Date?, gateBusy: Bool, extendNeeded: Int?,
        startFailed: Bool
    ) -> Date? {
        guard enabled, mode == .session, let draftShownAt, !gateBusy, extendNeeded == nil, !startFailed else {
            return nil
        }
        return max(draftShownAt, lastInputAt ?? draftShownAt).addingTimeInterval(Defaults.autoStartDelay)
    }

    public static func shouldStart(
        enabled: Bool, mode: NotchMode, draftShownAt: Date?, lastInputAt: Date?, gateBusy: Bool, extendNeeded: Int?,
        startFailed: Bool, now: Date
    ) -> Bool {
        guard
            let due = dueAt(
                enabled: enabled, mode: mode, draftShownAt: draftShownAt, lastInputAt: lastInputAt,
                gateBusy: gateBusy, extendNeeded: extendNeeded, startFailed: startFailed)
        else { return false }
        return now >= due
    }
}
