import Foundation

public enum SimRunner {
    public static func run(_ data: Data) -> Result<String, SimError> {
        .success("")
    }

    public static func checkInvariant(_ timer: NotchTimer, at now: Date, seq: Int) -> SimError? {
        nil
    }
}
