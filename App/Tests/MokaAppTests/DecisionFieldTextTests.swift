import MokaCore
import XCTest

/// 설정 창 판단 모델 칸과 할 일 탭 키 확인 한 줄의 글자(spec 006 data-model §9). 글자는 확정 시안(2026-11-12) 그대로다.
final class DecisionFieldTextTests: XCTestCase {
    /// 시안 1번: 칸 제목은 고른 공급자 이름을 따른다. 고른 공급자가 없으면 이름을 붙이지 않는다.
    func test_ADR0011_R620_titleFollowsSelectedProvider() {
        XCTAssertEqual(DecisionFieldText.title("TypeSafe Jev"), "판단 모델 키 (TypeSafe Jev)")
        XCTAssertEqual(DecisionFieldText.title("Microsoft-Decision-1"), "판단 모델 키 (Microsoft-Decision-1)")
        XCTAssertEqual(DecisionFieldText.title(nil), "판단 모델 키")
    }

    /// 시안 1·3·4·6번 글자.
    func test_ADR0011_R620_R622_fieldTexts() {
        XCTAssertEqual(
            DecisionFieldText.switchNotice, "공급자를 바꾸면 할 일을 모두 새 판단 모델에 다시 물어요. 그동안은 마감이 가까운 순으로 떠요.")
        XCTAssertEqual(DecisionFieldText.closedNote, "아직 연결을 확인하는 중이라 고를 수 없어요.")
        XCTAssertEqual(DecisionFieldText.destinationPrefix, "할 일 제목이 가는 곳: ")
        XCTAssertEqual(DecisionFieldText.selectFailed, "공급자를 바꾸지 못했어요. 다시 해 주세요.")
        XCTAssertEqual(DecisionFieldText.issueLink("TypeSafe Jev"), "TypeSafe에서 키 받기")
        XCTAssertEqual(DecisionFieldText.issueLink("Perplexity Decider v1.2"), "Perplexity에서 키 받기")
    }

    /// 시안 4번.
    func test_ADR0011_R621_provisionalText() {
        XCTAssertEqual(
            DecisionFieldText.provisionalNotice, "이 판단 모델은 순서를 정하는 기준값을 아직 맞추는 중이에요. 순서가 조금 다를 수 있어요.")
    }

    /// 시안 7·9·10번.
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

    /// 시안 8번: 거부 이유마다 다른 문구. 쿼리와 조각, 읽지 못함과 빈 호스트는 같은 문구다.
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

    /// 꺼진 이유 안내. Microsoft 주소·배포 이름이 없을 때는 시안 7번 글자다.
    func test_ADR0011_R623_offNotes() {
        let needsAddress = "주소와 배포 이름을 넣기 전에는 판단 모델에 묻지 않아요. 할 일은 마감이 가까운 순으로 떠요."
        XCTAssertEqual(DecisionFieldText.offNote(.needsEndpoint), needsAddress)
        XCTAssertEqual(DecisionFieldText.offNote(.needsDeployment), needsAddress)
        XCTAssertEqual(
            DecisionFieldText.offNote(.closedProvider(.liquid)),
            "이 판단 모델은 아직 연결을 확인하는 중이라 묻지 않아요. 할 일은 마감이 가까운 순으로 떠요.")
        XCTAssertEqual(DecisionFieldText.offNote(.unknownProvider), "고른 판단 모델을 찾지 못했어요. 공급자를 다시 골라 주세요.")
    }

    /// spec 004 시안 15번(사용자 확정 2026-11-10).
    func test_FR14_R627_taskTabKeyNoticeTexts() {
        XCTAssertEqual(TaskListText.keyNotice, "키가 맞지 않아 새 할 일은 판단 모델에 묻지 못하고 있어요.")
        XCTAssertEqual(TaskListText.keyNoticeButton, "기본 탭에서 확인")
    }
}
