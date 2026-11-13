import Foundation

/// 사용자가 넣은 주소를 받지 않은 이유(spec 006 data-model §4). 화면 거부 문구의 종류다.
public enum EndpointRejection: Error, Equatable, Sendable {
    case unparseable
    case scheme
    case emptyHost
    case userInfo
    case query
    case fragment
    case path
}

/// 사용자가 넣는 주소의 허용 조건과 보내는 곳(spec 006 R-605, R-606).
public enum EndpointRule {
    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    /// 앞뒤 공백·줄바꿈을 지우고 data-model §4 순서로 처음 걸린 거부 이유를 돌려준다. 통과하면 끝 `/`를 떼고
    /// 스킴·호스트를 ASCII 소문자로 바꾼 주소다. 경로와 포트는 그대로 둔다.
    public static func check(_ text: String, allowsPath: Bool) -> Result<URL, EndpointRejection> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased(),
            let host = components.host
        else { return .failure(.unparseable) }
        if components.user != nil || components.password != nil { return .failure(.userInfo) }
        if host.isEmpty { return .failure(.emptyHost) }
        let isLoopback = loopbackHosts.contains(bare(host))
        guard scheme == "https" || (scheme == "http" && isLoopback) else { return .failure(.scheme) }
        if components.query != nil { return .failure(.query) }
        if components.fragment != nil { return .failure(.fragment) }
        if !allowsPath && !components.path.isEmpty && components.path != "/" { return .failure(.path) }
        let kept = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard let url = URL(string: lowercasingSchemeAndHost(kept)) else { return .failure(.unparseable) }
        return .success(url)
    }

    /// 보내는 곳. 대괄호를 벗긴 소문자 호스트이고 포트는 넣지 않는다.
    public static func host(of url: URL) -> String {
        let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host ?? url.host ?? ""
        return bare(host)
    }

    /// 사용자 정보·쿼리·조각은 이미 거부했으므로 `://` 뒤 첫 `/` 앞까지가 호스트와 포트다.
    private static func lowercasingSchemeAndHost(_ text: String) -> String {
        guard let separator = text.range(of: "://") else { return text }
        let hostEnd = text[separator.upperBound...].firstIndex(of: "/") ?? text.endIndex
        let head = text[..<hostEnd].unicodeScalars.map { $0.isASCII ? String($0).lowercased() : String($0) }
        return head.joined() + text[hostEnd...]
    }

    private static func bare(_ host: String) -> String {
        let lowered = host.lowercased()
        guard lowered.hasPrefix("["), lowered.hasSuffix("]") else { return lowered }
        return String(lowered.dropFirst().dropLast())
    }
}

/// 리디렉트를 따라가지 않는다(spec 006 research R7). 앱 세션 대리자는 이 값을 그대로 돌려준다.
public enum RedirectRule {
    public static func follow(status: Int, to target: URL?) -> URL? {
        nil
    }
}
