import Foundation

/// 판단 공급자 ID. 원시값이 판단 결과·설정에 적는 공급자 ID다(GLOSSARY). 시험의 `fake`는 들지 않는다.
public enum ProviderID: String, CaseIterable, Sendable {
    case typesafe
    case microsoft
    case liquid
    case perplexity
    case openai
}

/// 키를 넣는 헤더. `bearer`는 `Authorization: Bearer <키>`, `apiKeyHeader`는 `api-key: <키>`다.
public enum AuthStyle: Equatable, Sendable {
    case bearer
    case apiKeyHeader
}

/// 요청을 보낼 주소. `userResource`는 사용자가 넣은 리소스 주소에 앱이 경로를 붙인다.
public enum ProviderEndpoint: Equatable, Sendable {
    case fixed(URL)
    case userResource(path: String)
}

/// 공급자 표의 한 줄(spec 006 data-model §1, research R4).
public struct ProviderConfig: Equatable, Sendable {
    public let id: ProviderID
    public let displayName: String
    public let endpoint: ProviderEndpoint
    public let auth: AuthStyle
    public let shape: RequestShape
    public let issueURL: URL?
    /// 사람이 공식 문서에서 발급 링크를 확인했는지. 거짓이면 화면에 링크를 보이지 않는다.
    public let issueURLConfirmed: Bool
    /// 사람이 첫 실제 호출을 확인했는지. 거짓이면 고를 수 없다(research R1).
    public let firstCallConfirmed: Bool

    public init(
        id: ProviderID, displayName: String, endpoint: ProviderEndpoint, auth: AuthStyle, shape: RequestShape,
        issueURL: URL?, issueURLConfirmed: Bool, firstCallConfirmed: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.endpoint = endpoint
        self.auth = auth
        self.shape = shape
        self.issueURL = issueURL
        self.issueURLConfirmed = issueURLConfirmed
        self.firstCallConfirmed = firstCallConfirmed
    }

    /// 고정 주소면 그 주소, 사용자 리소스면 `resource`에 경로를 붙인 주소다. 리소스가 없으면 `nil`이다.
    /// `resource`는 `EndpointRule.check`를 통과해 끝 `/`를 뗀 주소다.
    public func url(resource: URL?) -> URL? {
        switch endpoint {
        case .fixed(let url):
            return url
        case .userResource(let path):
            guard let resource else { return nil }
            return URL(string: resource.absoluteString + path)
        }
    }
}

/// 공급자 표 한 벌(spec 006 R-601).
public enum ProviderCatalog {
    /// research R4 순서의 다섯 줄. 주소 글자를 읽지 못한 줄은 빠지고, 표 시험이 그것을 잡는다.
    public static let all: [ProviderConfig] = [
        fixedRow(
            .typesafe, "TypeSafe Jev", url: "https://api.typesafe.ai/v1/systemone", shape: .systemOne,
            issueURL: nil, firstCallConfirmed: true),
        ProviderConfig(
            id: .microsoft, displayName: "Microsoft-Decision-1",
            endpoint: .userResource(path: "/providers/microsoft/v1/systemone"), auth: .apiKeyHeader,
            shape: .systemOne, issueURL: nil, issueURLConfirmed: false, firstCallConfirmed: false),
        fixedRow(
            .liquid, "Liquid d1-ultra", url: "https://api.liquid.ai/decisions/v1/systemone", shape: .systemOne,
            issueURL: "https://console.liquid.ai", firstCallConfirmed: false),
        fixedRow(
            .perplexity, "Perplexity Decider v1.2", url: "https://api.perplexity.ai/v1/decisions",
            shape: .systemOne, issueURL: "https://console.perplexity.ai", firstCallConfirmed: false),
        fixedRow(
            .openai, "OpenAI Decisions", url: "https://api.openai.com/v1/decisions", shape: .openAI,
            issueURL: "https://platform.openai.com/api-keys", firstCallConfirmed: false),
    ].compactMap { $0 }

    /// 주입한 표에서 그 ID 줄을 찾는다. 없으면 `nil`이다.
    public static func config(_ id: ProviderID, in catalog: [ProviderConfig] = all) -> ProviderConfig? {
        catalog.first { $0.id == id }
    }

    /// 그 줄의 첫 호출을 확인했고 질문 파일 `models`에 기준 모델 ID가 있을 때만 고를 수 있다(spec 006 R-617).
    /// 주입한 표에 줄이 없으면 거짓이다.
    public static func isOpen(_ id: ProviderID, questions: QuestionSet, catalog: [ProviderConfig] = all) -> Bool {
        guard let row = config(id, in: catalog) else { return false }
        return row.firstCallConfirmed && questions.models[id.rawValue] != nil
    }

    private static func fixedRow(
        _ id: ProviderID, _ displayName: String, url: String, shape: RequestShape, issueURL: String?,
        firstCallConfirmed: Bool
    ) -> ProviderConfig? {
        guard let endpoint = URL(string: url) else { return nil }
        return ProviderConfig(
            id: id, displayName: displayName, endpoint: .fixed(endpoint), auth: .bearer, shape: shape,
            issueURL: issueURL.flatMap { URL(string: $0) }, issueURLConfirmed: false,
            firstCallConfirmed: firstCallConfirmed)
    }
}
