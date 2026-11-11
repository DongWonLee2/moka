import Foundation
import MokaCore
import Testing

@Suite struct EndpointRuleTests {
    @Test(
        "ADR-0011 R-605: 허용 조건을 지킨 주소는 끝 /를 떼고 받는다",
        arguments: [
            ("https://example-resource.invalid", "https://example-resource.invalid"),
            ("https://example-resource.invalid/", "https://example-resource.invalid"),
            ("http://localhost:8080", "http://localhost:8080"),
            ("http://LOCALHOST", "http://LOCALHOST"),
            ("http://127.0.0.1:9000", "http://127.0.0.1:9000"),
            ("http://[::1]:8080", "http://[::1]:8080"),
            ("https://example-resource.invalid:8443", "https://example-resource.invalid:8443"),
            ("HTTPS://example-resource.invalid", "HTTPS://example-resource.invalid"),
            ("  https://example-resource.invalid/ \n", "https://example-resource.invalid"),
        ])
    func accepted(text: String, expected: String) {
        #expect(EndpointRule.check(text, allowsPath: false).map(\.absoluteString) == .success(expected))
    }

    @Test(
        "ADR-0011 R-605: 허용 조건을 어긴 주소는 처음 걸린 거부 이유를 돌려준다",
        arguments: [
            ("http://example-resource.invalid", EndpointRejection.scheme),
            ("ftp://example-resource.invalid", .scheme),
            ("http://127.0.0.2", .scheme),
            ("http://localhost.invalid", .scheme),
            ("https://", .emptyHost),
            ("https://:8080", .emptyHost),
            ("https://user:pass@example-resource.invalid", .userInfo),
            ("https://user@example-resource.invalid", .userInfo),
            ("https://@example-resource.invalid", .userInfo),
            ("https://example-resource.invalid?x=1", .query),
            ("https://example-resource.invalid?", .query),
            ("https://example-resource.invalid#a", .fragment),
            ("https://example-resource.invalid#", .fragment),
            ("https://example-resource.invalid/openai", .path),
            ("example-resource.invalid", .unparseable),
            ("https:example-resource.invalid", .unparseable),
            ("mailto:fake@example-resource.invalid", .unparseable),
            ("https://example resource.invalid", .unparseable),
            ("", .unparseable),
        ])
    func rejected(text: String, expected: EndpointRejection) {
        #expect(EndpointRule.check(text, allowsPath: false).map(\.absoluteString) == .failure(expected))
    }

    @Test(
        "ADR-0011 R-605: 거부 이유는 data-model §4 순서로 처음 걸린 것이다",
        arguments: [
            ("http://user@example-resource.invalid?x=1#a", EndpointRejection.userInfo),
            ("ftp://user@", .userInfo),
            ("ftp://", .emptyHost),
            ("http://example-resource.invalid/openai?x=1", .scheme),
            ("https://example-resource.invalid/openai?x=1#a", .query),
            ("https://example-resource.invalid/openai#a", .fragment),
        ])
    func rejectionOrder(text: String, expected: EndpointRejection) {
        #expect(EndpointRule.check(text, allowsPath: false).map(\.absoluteString) == .failure(expected))
    }

    @Test("ADR-0011 R-605: allowsPath가 참이면 경로를 받고 끝 /만 뗀다")
    func pathAllowed() {
        #expect(
            EndpointRule.check("https://example-resource.invalid/openai/", allowsPath: true).map(\.absoluteString)
                == .success("https://example-resource.invalid/openai"))
        #expect(
            EndpointRule.check("https://example-resource.invalid/openai?x=1", allowsPath: true).map(\.absoluteString)
                == .failure(.query))
    }

    @Test(
        "ADR-0011 R-606: 보내는 곳은 대괄호를 벗긴 소문자 호스트이고 포트가 없다",
        arguments: [
            ("https://api.typesafe.ai/v1/systemone", "api.typesafe.ai"),
            ("https://Example-Resource.invalid:8443", "example-resource.invalid"),
            ("http://LOCALHOST:8080", "localhost"),
            ("http://[::1]:8080", "::1"),
            ("http://127.0.0.1:9000", "127.0.0.1"),
        ])
    func host(text: String, expected: String) throws {
        #expect(EndpointRule.host(of: try #require(URL(string: text))) == expected)
    }

    @Test("ADR-0011 R-606: 공급자 표의 고정 주소에서 보내는 곳을 꺼낸다")
    func catalogHosts() throws {
        let hosts = try ProviderCatalog.all.compactMap { config in
            try config.url(resource: #require(URL(string: "https://example-resource.invalid"))).map(EndpointRule.host)
        }
        #expect(
            hosts == [
                "api.typesafe.ai", "example-resource.invalid", "api.liquid.ai", "api.perplexity.ai", "api.openai.com",
            ])
    }

    @Test(
        "ADR-0011 R-618: 리디렉트(301, 302, 307, 308)는 따라가지 않는다",
        arguments: [301, 302, 307, 308])
    func redirectNotFollowed(status: Int) throws {
        let target = try #require(URL(string: "https://example-other.invalid/v1/systemone"))
        #expect(RedirectRule.follow(status: status, to: target) == nil)
        #expect(RedirectRule.follow(status: status, to: nil) == nil)
    }
}
