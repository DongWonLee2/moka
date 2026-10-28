import Foundation

public struct SimCommandResult: Equatable, Sendable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32
}

public enum SimCommand {
    public static let usage = "사용법: moka-sim run <scenario.json>"

    /// `arguments`는 프로그램 이름을 뺀 인자. 오류면 표준 출력은 비고 표준 오류에 한 줄.
    public static func run(arguments: [String], readFile: (String) -> Data?) -> SimCommandResult {
        let result: Result<String, SimError>
        switch arguments.first {
        case nil:
            result = .failure(SimError(kind: .usage, seq: nil, message: "인자 없음. \(usage)"))
        case "run" where arguments.count == 2:
            if let data = readFile(arguments[1]) {
                result = SimRunner.run(data)
            } else {
                result = .failure(SimError(kind: .fileUnreadable, seq: nil, message: "파일을 읽지 못했다: \(arguments[1])"))
            }
        case "run":
            result = .failure(SimError(kind: .usage, seq: nil, message: "run은 시나리오 파일 하나를 받는다. \(usage)"))
        case .some(let command):
            result = .failure(SimError(kind: .usage, seq: nil, message: "모르는 하위 명령 \"\(command)\". \(usage)"))
        }

        switch result {
        case .success(let output):
            return SimCommandResult(stdout: output, stderr: "", exitCode: SimExitCode.code(for: result))
        case .failure(let error):
            return SimCommandResult(stdout: "", stderr: "\(error)\n", exitCode: SimExitCode.code(for: result))
        }
    }
}
