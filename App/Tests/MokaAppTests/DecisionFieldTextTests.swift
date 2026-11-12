import MokaCore
import XCTest

final class DecisionFieldTextTests: XCTestCase {
    func test_ADR0011_R620_titleFollowsSelectedProvider() {
        XCTAssertEqual(DecisionFieldText.title("TypeSafe Jev"), "판단 모델 키 (TypeSafe Jev)")
        XCTAssertEqual(DecisionFieldText.title("Microsoft-Decision-1"), "판단 모델 키 (Microsoft-Decision-1)")
        XCTAssertEqual(DecisionFieldText.title(nil), "판단 모델 키")
    }

    func test_ADR0011_R620_R622_fieldTexts() {
        XCTAssertEqual(
            DecisionFieldText.switchNotice, "공급자를 바꾸면 할 일을 모두 새 판단 모델에 다시 물어요. 그동안은 마감이 가까운 순으로 떠요.")
        XCTAssertEqual(DecisionFieldText.closedNote, "아직 연결을 확인하는 중이라 고를 수 없어요.")
        XCTAssertEqual(DecisionFieldText.destinationPrefix, "판단을 받으러 보내는 곳: ")
        XCTAssertEqual(DecisionFieldText.selectFailed, "공급자를 바꾸지 못했어요. 다시 해 주세요.")
        XCTAssertEqual(DecisionFieldText.issueLink("TypeSafe Jev"), "TypeSafe에서 키 받기")
        XCTAssertEqual(DecisionFieldText.issueLink("Perplexity Decider v1.2"), "Perplexity에서 키 받기")
    }

    func test_ADR0011_R621_provisionalText() {
        XCTAssertEqual(
            DecisionFieldText.provisionalNotice, "이 판단 모델은 순서를 정하는 기준값을 아직 맞추는 중이에요. 순서가 조금 다를 수 있어요.")
    }

    func test_ADR0011_R623_microsoftTexts() {
        XCTAssertEqual(DecisionFieldText.microsoftHeading, "Azure 배포")
        XCTAssertEqual(DecisionFieldText.endpointLabel, "리소스 주소")
        XCTAssertEqual(DecisionFieldText.deploymentLabel, "배포 이름")
        XCTAssertEqual(DecisionFieldText.endpointPlaceholder, "https://로 시작하는 Azure 리소스 주소")
        XCTAssertEqual(DecisionFieldText.deploymentPlaceholder, "Azure에서 만든 배포 이름")
        XCTAssertEqual(DecisionFieldText.saveMicrosoftButton, "주소 저장")
        XCTAssertEqual(DecisionFieldText.keyResetNotice, "주소를 바꾸면 저장된 키를 지워요. 키를 다시 넣어 주세요.")
        XCTAssertEqual(DecisionFieldText.keyCleared, "주소가 바뀌어서 키를 지웠어요. 이 주소에서 쓸 키를 다시 넣어 주세요.")
    }

    func test_ADR0011_R623_rejectionTexts() {
        XCTAssertEqual(
            DecisionFieldText.rejection(.scheme), "https로 시작하는 주소만 받아요. 내 컴퓨터 주소(localhost)는 http도 돼요.")
        XCTAssertEqual(DecisionFieldText.rejection(.userInfo), "주소에 아이디나 비밀번호를 넣지 말아 주세요.")
        XCTAssertEqual(DecisionFieldText.rejection(.query), "주소 뒤의 ?나 # 부분은 빼 주세요.")
        XCTAssertEqual(DecisionFieldText.rejection(.fragment), "주소 뒤의 ?나 # 부분은 빼 주세요.")
        XCTAssertEqual(DecisionFieldText.rejection(.path), "리소스 주소까지만 넣어 주세요. 뒤의 경로는 앱이 붙여요.")
        XCTAssertEqual(DecisionFieldText.rejection(.unparseable), "주소를 읽지 못했어요. https://로 시작하는지 봐 주세요.")
        XCTAssertEqual(DecisionFieldText.rejection(.emptyHost), "주소를 읽지 못했어요. https://로 시작하는지 봐 주세요.")
    }

    func test_ADR0011_R623_offNotes() {
        let needsAddress = "주소와 배포 이름을 넣기 전에는 판단 모델에 묻지 않아요. 할 일은 마감이 가까운 순으로 떠요."
        XCTAssertEqual(DecisionFieldText.offNote(.needsEndpoint), needsAddress)
        XCTAssertEqual(DecisionFieldText.offNote(.needsDeployment), needsAddress)
        XCTAssertEqual(
            DecisionFieldText.offNote(.closedProvider(.liquid)),
            "이 판단 모델은 아직 연결을 확인하는 중이라 묻지 않아요. 할 일은 마감이 가까운 순으로 떠요.")
        XCTAssertEqual(DecisionFieldText.offNote(.unknownProvider), "고른 판단 모델을 찾지 못했어요. 공급자를 다시 골라 주세요.")
    }

    /// "주소 저장"은 두 칸이 차 있고, 주소 규칙으로 정규화한 값이 저장된 값과 다를 때만 켜진다(PR #136 리뷰 중간 2).
    func test_ADR0011_R623_saveButtonComparesNormalizedValues() {
        let saved = "https://example-resource.invalid"
        func canSave(_ endpoint: String, _ deployment: String, saved: String? = saved, deploy: String? = "fake-deploy")
            -> Bool
        {
            MicrosoftFieldRule.canSave(
                endpoint: endpoint, deployment: deployment, savedEndpoint: saved, savedDeployment: deploy)
        }
        XCTAssertFalse(canSave("https://example-resource.invalid/", "fake-deploy"), "끝 / 는 같은 주소")
        XCTAssertFalse(canSave(" https://example-resource.invalid \n", " fake-deploy "), "앞뒤 공백은 같은 값")
        XCTAssertTrue(canSave("https://other-resource.invalid", "fake-deploy"))
        XCTAssertTrue(canSave("https://example-resource.invalid/", "fake-deploy-2"))
        XCTAssertTrue(canSave("http://example-resource.invalid", "fake-deploy"), "거부할 주소도 눌러 이유를 본다")
        XCTAssertFalse(canSave(" ", "fake-deploy"))
        XCTAssertFalse(canSave("https://other-resource.invalid", " "))
        XCTAssertTrue(canSave("https://example-resource.invalid/", "fake-deploy", saved: nil, deploy: nil))
    }

    /// 저장에 성공하면 칸 글자를 저장된 모양(앞뒤 공백, 끝 / 뗌)으로 바꾼다.
    func test_ADR0011_R623_fieldTextAfterSaveIsNormalized() {
        XCTAssertEqual(
            MicrosoftFieldRule.normalized(endpoint: " https://example-resource.invalid/ ", deployment: " fake-deploy "),
            MicrosoftFieldRule.Values(endpoint: "https://example-resource.invalid", deployment: "fake-deploy"))
        XCTAssertNil(MicrosoftFieldRule.normalized(endpoint: "http://example-resource.invalid", deployment: "a"))
    }

    func test_FR14_R627_taskTabKeyNoticeTexts() {
        XCTAssertEqual(TaskListText.keyNotice, "키가 맞지 않아 새 할 일은 판단 모델에 묻지 못하고 있어요.")
        XCTAssertEqual(TaskListText.keyNoticeButton, "기본 탭에서 확인")
    }
}
