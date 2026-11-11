import Foundation
import MokaCore
import Testing

private struct ExpectedRow {
    let id: ProviderID
    let displayName: String
    let endpoint: ProviderEndpoint
    let auth: AuthStyle
    let shape: RequestShape
    let issueURL: String?
}

private func url(_ text: String) throws -> URL {
    try #require(URL(string: text))
}

/// research R4 표.
private func expectedRows() throws -> [ExpectedRow] {
    [
        ExpectedRow(
            id: .typesafe, displayName: "TypeSafe Jev",
            endpoint: .fixed(try url("https://api.typesafe.ai/v1/systemone")), auth: .bearer, shape: .systemOne,
            issueURL: nil),
        ExpectedRow(
            id: .microsoft, displayName: "Microsoft-Decision-1",
            endpoint: .userResource(path: "/providers/microsoft/v1/systemone"), auth: .apiKeyHeader,
            shape: .systemOne, issueURL: nil),
        ExpectedRow(
            id: .liquid, displayName: "Liquid d1-ultra",
            endpoint: .fixed(try url("https://api.liquid.ai/decisions/v1/systemone")), auth: .bearer,
            shape: .systemOne, issueURL: "https://console.liquid.ai"),
        ExpectedRow(
            id: .perplexity, displayName: "Perplexity Decider v1.2",
            endpoint: .fixed(try url("https://api.perplexity.ai/v1/decisions")), auth: .bearer, shape: .systemOne,
            issueURL: "https://console.perplexity.ai"),
        ExpectedRow(
            id: .openai, displayName: "OpenAI Decisions",
            endpoint: .fixed(try url("https://api.openai.com/v1/decisions")), auth: .bearer, shape: .openAI,
            issueURL: "https://platform.openai.com/api-keys"),
    ]
}

@Suite struct ProviderCatalogTests {
    @Test("ADR-0011 R-601: 공급자 ID 원시값은 다섯이고 fake·fallback은 들지 않는다")
    func providerIDs() {
        #expect(ProviderID.allCases.map(\.rawValue) == ["typesafe", "microsoft", "liquid", "perplexity", "openai"])
        #expect(ProviderID(rawValue: "fake") == nil)
        #expect(ProviderID(rawValue: "fallback") == nil)
    }

    @Test("ADR-0011 R-601: 공급자 표는 research R4 순서의 다섯 줄이다")
    func rowOrder() {
        #expect(ProviderCatalog.all.map(\.id) == [.typesafe, .microsoft, .liquid, .perplexity, .openai])
    }

    @Test("ADR-0011 R-601: 줄마다 화면 이름, 주소, 인증, 요청 모양, 발급 링크가 표와 같다")
    func rowValues() throws {
        let expected = try expectedRows()
        #expect(ProviderCatalog.all.count == expected.count)
        for (row, want) in zip(ProviderCatalog.all, expected) {
            #expect(row.id == want.id)
            #expect(row.displayName == want.displayName)
            #expect(row.endpoint == want.endpoint)
            #expect(row.auth == want.auth)
            #expect(row.shape == want.shape)
            #expect(row.issueURL?.absoluteString == want.issueURL)
        }
    }

    @Test("ADR-0011 R-601: 발급 링크는 아직 아무것도 확인되지 않았다")
    func issueURLsUnconfirmed() {
        #expect(ProviderCatalog.all.allSatisfy { !$0.issueURLConfirmed })
    }

    @Test("ADR-0011 R-601: 첫 실제 호출이 확인된 줄은 typesafe 하나다")
    func firstCallConfirmed() {
        #expect(ProviderCatalog.all.filter(\.firstCallConfirmed).map(\.id) == [.typesafe])
    }

    @Test("ADR-0011 R-601: 고정 주소 공급자의 url은 리소스와 상관없이 표의 주소다")
    func fixedURL() throws {
        let typesafe = try #require(ProviderCatalog.config(.typesafe))
        let resource = try url("https://example-resource.invalid")
        #expect(typesafe.url(resource: nil)?.absoluteString == "https://api.typesafe.ai/v1/systemone")
        #expect(typesafe.url(resource: resource)?.absoluteString == "https://api.typesafe.ai/v1/systemone")
    }

    @Test(
        "ADR-0011 R-601: Microsoft url은 리소스 주소에 경로를 붙인다",
        arguments: [
            ("https://example-resource.invalid", "https://example-resource.invalid/providers/microsoft/v1/systemone"),
            ("http://localhost:8080", "http://localhost:8080/providers/microsoft/v1/systemone"),
            ("http://[::1]:8080", "http://[::1]:8080/providers/microsoft/v1/systemone"),
        ])
    func microsoftURL(resource: String, expected: String) throws {
        let microsoft = try #require(ProviderCatalog.config(.microsoft))
        #expect(microsoft.url(resource: try url(resource))?.absoluteString == expected)
    }

    @Test("ADR-0011 R-601: Microsoft url은 리소스 주소가 없으면 nil이다")
    func microsoftWithoutResource() throws {
        let microsoft = try #require(ProviderCatalog.config(.microsoft))
        #expect(microsoft.url(resource: nil) == nil)
    }

    @Test("ADR-0011 R-601: config는 표에서 그 ID 줄을 찾는다")
    func configFindsRow() {
        for id in ProviderID.allCases {
            #expect(ProviderCatalog.config(id)?.id == id)
        }
    }

    @Test("ADR-0011 R-601: config는 주입한 표에서 찾고 없는 ID면 멈추지 않고 nil이다")
    func configInjectedCatalog() throws {
        let fakeMicrosoft = ProviderConfig(
            id: .microsoft, displayName: "가짜 Microsoft", endpoint: .userResource(path: "/fake"), auth: .apiKeyHeader,
            shape: .systemOne, issueURL: nil, issueURLConfirmed: false, firstCallConfirmed: true)
        let catalog = [fakeMicrosoft]
        #expect(ProviderCatalog.config(.microsoft, in: catalog) == fakeMicrosoft)
        #expect(ProviderCatalog.config(.typesafe, in: catalog) == nil)
        #expect(ProviderCatalog.config(.openai, in: []) == nil)
    }
}
