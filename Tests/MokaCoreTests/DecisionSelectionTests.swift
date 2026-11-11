import Foundation
import MokaCore
import Testing

// spec 006 data-model §6 "정하기". 가짜 주소·가짜 배포 이름·가짜 기준 모델만 쓴다.

private let bundled = try! QuestionSet.bundled()

/// Microsoft 줄(`fake-ms-base`)을 더한 시험용 질문 파일.
private let withMicrosoft = try! QuestionSet(
    json: questionsJSON { root in
        root["models"] = ["typesafe": "jev-1.13.0", "microsoft": "fake-ms-base"]
        root["thresholds"] = [
            "jev-1.13.0": ["concrete": 0.5, "avoiding": 0.7],
            "fake-ms-base": ["concrete": 0.4, "avoiding": 0.6],
        ]
    })

/// 첫 호출을 확인한 것처럼 Microsoft를 연 가짜 공급자 표.
private let openMicrosoft: [ProviderConfig] = ProviderCatalog.all.map { row in
    guard row.id == .microsoft else { return row }
    return ProviderConfig(
        id: row.id, displayName: row.displayName, endpoint: row.endpoint, auth: row.auth, shape: row.shape,
        issueURL: row.issueURL, issueURLConfirmed: row.issueURLConfirmed, firstCallConfirmed: true)
}

private func resolve(
    _ providerID: String?, endpoint: String? = nil, deployment: String? = nil, questions: QuestionSet = bundled,
    catalog: [ProviderConfig] = ProviderCatalog.all
) -> DecisionSelection.Resolution {
    DecisionSelection.resolve(
        providerID: providerID, microsoftEndpoint: endpoint, microsoftDeployment: deployment, questions: questions,
        catalog: catalog)
}

private func ready(_ resolution: DecisionSelection.Resolution) -> DecisionSelection.Ready? {
    guard case .ready(let value) = resolution else { return nil }
    return value
}

@Suite struct DecisionSelectionResolveTests {
    @Test("ADR-0011 R-614: 설정이 없으면 TypeSafe Jev로 보고 기준 모델 ID를 보낼 모델 이름으로 쓴다")
    func defaultsToTypeSafe() throws {
        let value = try #require(ready(resolve(nil)))
        #expect(value.config.id == .typesafe)
        #expect(value.url == URL(string: "https://api.typesafe.ai/v1/systemone"))
        #expect(value.baseModel == "jev-1.13.0")
        #expect(value.requestModel == "jev-1.13.0")
        #expect(ready(resolve("typesafe")) == value)
    }

    @Test("ADR-0011 R-614: 공급자 표에 없는 ID면 끈다", arguments: ["fake", "fallback", "", "TypeSafe", "fake-unknown"])
    func unknownProvider(id: String) {
        #expect(resolve(id) == .off(.unknownProvider))
    }

    @Test(
        "ADR-0011 R-617: 첫 호출을 확인하지 않은 공급자는 끈다",
        arguments: [ProviderID.microsoft, .liquid, .perplexity, .openai])
    func closedProvider(id: ProviderID) {
        #expect(resolve(id.rawValue) == .off(.closedProvider(id)))
    }

    @Test("ADR-0011 R-609: 표에서 열려도 질문 파일 models에 기준 모델 ID가 없으면 끈다")
    func openButNoBaseModel() {
        #expect(
            resolve(
                "microsoft", endpoint: "https://example-resource.invalid", deployment: "fake-deploy",
                catalog: openMicrosoft) == .off(.closedProvider(.microsoft)))
    }

    @Test("ADR-0011 R-610: Microsoft는 저장된 주소에 경로를 붙이고 배포 이름을 보낼 모델 이름으로 쓴다")
    func microsoftReady() throws {
        let value = try #require(
            ready(
                resolve(
                    "microsoft", endpoint: " https://example-resource.invalid/ ", deployment: " fake-deploy ",
                    questions: withMicrosoft, catalog: openMicrosoft)))
        #expect(value.config.id == .microsoft)
        #expect(value.url == URL(string: "https://example-resource.invalid/providers/microsoft/v1/systemone"))
        #expect(value.baseModel == "fake-ms-base")
        #expect(value.requestModel == "fake-deploy")
    }

    @Test(
        "ADR-0011 R-610: Microsoft 주소가 없거나 주소 규칙에 걸리면 주소가 필요하다고 끈다",
        arguments: [
            nil, "", "   ", "http://example-resource.invalid", "https://example-resource.invalid/openai",
            "https://example-resource.invalid?x=1", "example-resource.invalid",
        ] as [String?])
    func microsoftNeedsEndpoint(endpoint: String?) {
        #expect(
            resolve(
                "microsoft", endpoint: endpoint, deployment: "fake-deploy", questions: withMicrosoft,
                catalog: openMicrosoft) == .off(.needsEndpoint))
    }

    @Test("ADR-0011 R-610: Microsoft 배포 이름이 비면 배포 이름이 필요하다고 끈다", arguments: [nil, "", "  \n"] as [String?])
    func microsoftNeedsDeployment(deployment: String?) {
        #expect(
            resolve(
                "microsoft", endpoint: "https://example-resource.invalid", deployment: deployment,
                questions: withMicrosoft, catalog: openMicrosoft) == .off(.needsDeployment))
    }

    @Test("ADR-0011 R-610: 주소와 배포 이름이 둘 다 없으면 주소부터 묻는다")
    func endpointBeforeDeployment() {
        #expect(
            resolve("microsoft", questions: withMicrosoft, catalog: openMicrosoft) == .off(.needsEndpoint))
    }

    @Test("ADR-0011 R-610: 고정 주소 공급자는 Microsoft 칸 값과 상관없이 표의 주소와 기준 모델 ID를 쓴다")
    func fixedIgnoresMicrosoftFields() throws {
        let value = try #require(
            ready(resolve("typesafe", endpoint: "http://example-resource.invalid", deployment: "fake-deploy")))
        #expect(value.url == URL(string: "https://api.typesafe.ai/v1/systemone"))
        #expect(value.requestModel == "jev-1.13.0")
    }

    @Test("ADR-0011 R-617: 주입한 표에 그 공급자 줄이 없으면 멈추지 않고 끈다")
    func missingRow() {
        let withoutTypeSafe = ProviderCatalog.all.filter { $0.id != .typesafe }
        #expect(resolve(nil, catalog: withoutTypeSafe) == .off(.closedProvider(.typesafe)))
        #expect(resolve("typesafe", catalog: []) == .off(.closedProvider(.typesafe)))
    }
}

@Suite struct ProviderCatalogOpenTests {
    @Test("ADR-0011 R-617: 기본 표와 번들 질문 파일에서 열린 공급자는 TypeSafe Jev 하나다")
    func onlyTypeSafeOpen() {
        let open = ProviderID.allCases.filter { ProviderCatalog.isOpen($0, questions: bundled) }
        #expect(open == [.typesafe])
    }

    @Test("ADR-0011 R-617: 주입한 표로 연 Microsoft는 질문 파일에 기준 모델 ID가 있을 때만 열린다")
    func injectedCatalog() {
        #expect(ProviderCatalog.isOpen(.microsoft, questions: withMicrosoft, catalog: openMicrosoft))
        #expect(!ProviderCatalog.isOpen(.microsoft, questions: bundled, catalog: openMicrosoft))
        #expect(!ProviderCatalog.isOpen(.microsoft, questions: withMicrosoft))
    }

    @Test("ADR-0011 R-617: 주입한 표에 없는 ID면 isOpen은 거짓, config는 nil이다")
    func missingFromCatalog() {
        let withoutTypeSafe = ProviderCatalog.all.filter { $0.id != .typesafe }
        #expect(!ProviderCatalog.isOpen(.typesafe, questions: bundled, catalog: withoutTypeSafe))
        #expect(!ProviderCatalog.isOpen(.typesafe, questions: bundled, catalog: []))
        #expect(ProviderCatalog.config(.typesafe, in: withoutTypeSafe) == nil)
        #expect(ProviderCatalog.config(.microsoft, in: openMicrosoft)?.firstCallConfirmed == true)
    }
}
