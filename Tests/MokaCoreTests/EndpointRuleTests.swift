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
            ("http://LOCALHOST", "http://localhost"),
            ("http://127.0.0.1:9000", "http://127.0.0.1:9000"),
            ("http://[::1]:8080", "http://[::1]:8080"),
            ("https://example-resource.invalid:8443", "https://example-resource.invalid:8443"),
            ("HTTPS://example-resource.invalid", "https://example-resource.invalid"),
            ("  https://example-resource.invalid/ \n", "https://example-resource.invalid"),
        ])
    func accepted(text: String, expected: String) {
        #expect(EndpointRule.check(text, allowsPath: false).map(\.absoluteString) == .success(expected))
    }

    @Test(
        "ADR-0011 R-605 #139: 대소문자만 다른 스킴·호스트는 같은 주소(ASCII 소문자)로 받고 포트는 그대로",
        arguments: [
            ("https://Example-Resource.invalid", "https://example-resource.invalid"),
            ("HTTPS://EXAMPLE-RESOURCE.INVALID/", "https://example-resource.invalid"),
            ("HtTpS://Example-Resource.Invalid:8443", "https://example-resource.invalid:8443"),
            ("HTTP://LocalHost:8080", "http://localhost:8080"),
            ("http://[::1]:8080", "http://[::1]:8080"),
        ])
    func hostCaseFolded(text: String, expected: String) {
        #expect(EndpointRule.check(text, allowsPath: false).map(\.absoluteString) == .success(expected))
    }

    @Test("ADR-0011 R-605 R-606 #149: 대문자 IPv6 호스트는 소문자로 받고 보내는 곳도 같은 값이다")
    func uppercaseIPv6() throws {
        let url = try EndpointRule.check("https://[FE80::1]:8443/", allowsPath: false).get()
        #expect(url.absoluteString == "https://[fe80::1]:8443")
        #expect(EndpointRule.host(of: url) == "fe80::1")
        #expect(EndpointRule.check("HTTP://[::1]", allowsPath: false).map(\.absoluteString) == .success("http://[::1]"))
    }

    @Test("ADR-0011 R-605 R-606 #149: 퍼센트 인코딩 호스트는 받고, 16진수를 소문자로 바꿔도 보내는 곳은 같다")
    func percentEncodedHost() throws {
        let upper = try EndpointRule.check("https://example%2Dresource.invalid", allowsPath: false).get()
        let lower = try EndpointRule.check("https://EXAMPLE%2dresource.invalid", allowsPath: false).get()
        #expect(upper.absoluteString == "https://example%2dresource.invalid")
        #expect(lower.absoluteString == upper.absoluteString)
        #expect(EndpointRule.host(of: upper) == "example-resource.invalid")
    }

    @Test("ADR-0011 R-605 R-606 #149: zone id가 있는 IPv6는 loopback이 아니고, https로는 받아 zone id까지 보내는 곳에 보인다")
    func ipv6ZoneID() throws {
        #expect(EndpointRule.check("http://[fe80::1%25en0]:8080", allowsPath: false) == .failure(.scheme))
        #expect(EndpointRule.check("http://[::1%25lo0]:8080", allowsPath: false) == .failure(.scheme))
        let url = try EndpointRule.check("https://[FE80::1%25EN0]:8080", allowsPath: false).get()
        #expect(url.absoluteString == "https://[fe80::1%25en0]:8080")
        #expect(EndpointRule.host(of: url) == "fe80::1%en0")
    }

    @Test("ADR-0011 R-605 #139: 경로의 대소문자는 바꾸지 않는다")
    func pathCaseKept() {
        #expect(
            EndpointRule.check("HTTPS://Example-Resource.invalid/OpenAI/V1/", allowsPath: true).map(\.absoluteString)
                == .success("https://example-resource.invalid/OpenAI/V1"))
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
        let resource = try #require(URL(string: "https://example-resource.invalid"))
        let hosts = ProviderCatalog.all.compactMap { $0.url(resource: resource).map(EndpointRule.host) }
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
