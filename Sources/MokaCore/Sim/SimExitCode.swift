public enum SimExitCode {
    /// 0 정상, 1 불변식 위반, 2 입력 오류.
    public static func code(for result: Result<String, SimError>) -> Int32 {
        switch result {
        case .success: 0
        case .failure(let error): error.kind == .invariantViolation ? 1 : 2
        }
    }
}
