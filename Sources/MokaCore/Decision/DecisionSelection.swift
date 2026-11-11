import Foundation

/// 고른 공급자 정하기(spec 006 data-model §6 "정하기"). 설정 값과 질문 파일만 보는 순수 함수다.
public enum DecisionSelection {
    public enum Resolution: Equatable, Sendable {
        case ready(Ready)
        case off(OffReason)
    }

    /// 판단 기능을 켤 때 쓰는 값. `baseModel`은 임계값과 판단 결과 해석의 기준, `requestModel`은 요청에 보낼 모델 이름이다.
    public struct Ready: Equatable, Sendable {
        public let config: ProviderConfig
        public let url: URL
        public let baseModel: String
        public let requestModel: String

        public init(config: ProviderConfig, url: URL, baseModel: String, requestModel: String) {
            self.config = config
            self.url = url
            self.baseModel = baseModel
            self.requestModel = requestModel
        }
    }

    /// 꺼진 이유. 화면 안내와 로그 한 줄에 종류만 쓴다.
    public enum OffReason: Equatable, Sendable {
        case unknownProvider
        case closedProvider(ProviderID)
        case needsEndpoint
        case needsDeployment
    }

    /// `providerID`가 `nil`이면 TypeSafe Jev로 본다. Microsoft 칸 값은 Microsoft일 때만 본다.
    public static func resolve(
        providerID: String?, microsoftEndpoint: String?, microsoftDeployment: String?, questions: QuestionSet,
        catalog: [ProviderConfig] = ProviderCatalog.all
    ) -> Resolution {
        guard let id = ProviderID(rawValue: providerID ?? ProviderID.typesafe.rawValue) else {
            return .off(.unknownProvider)
        }
        guard ProviderCatalog.isOpen(id, questions: questions, catalog: catalog),
            let config = ProviderCatalog.config(id, in: catalog), let baseModel = questions.models[id.rawValue]
        else { return .off(.closedProvider(id)) }
        guard case .userResource = config.endpoint else {
            guard let url = config.url(resource: nil) else { return .off(.needsEndpoint) }
            return .ready(Ready(config: config, url: url, baseModel: baseModel, requestModel: baseModel))
        }
        guard let text = microsoftEndpoint, case .success(let resource) = EndpointRule.check(text, allowsPath: false),
            let url = config.url(resource: resource)
        else { return .off(.needsEndpoint) }
        let deployment = microsoftDeployment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !deployment.isEmpty else { return .off(.needsDeployment) }
        return .ready(Ready(config: config, url: url, baseModel: baseModel, requestModel: deployment))
    }
}
