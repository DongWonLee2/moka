import Foundation

public struct SimCommandResult: Equatable, Sendable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32
}

public enum SimCommand {
    /// `arguments`는 프로그램 이름을 뺀 인자.
    public static func run(arguments: [String], readFile: (String) -> Data?) -> SimCommandResult {
        SimCommandResult(stdout: "", stderr: "", exitCode: 0)
    }
}
