# ADR-0009: 화면 스냅샷은 XCTest 단위 번들에서 NSHostingView로 PNG를 만들고 sanity만 단언한다 (ADR-0003 앱 UI 테스트 문구 보완)

- 상태: Accepted
- 작성일 / 사람 승인일: 2026-10-29 / 2026-10-28(D4 결정 승인). 이 문서는 PR 병합으로 확정한다
- 결정 책임자: 저장소 소유자
- 관련 Spec/R-ID: spec 001 R-001·R-002·R-003·R-004·R-006·R-008·R-009·R-010·R-011, SC-005, research R8, tasks T009·T037·T038·T039, plan D4
- 대체 범위: ADR-0003 "Agent의 추천과 근거"의 문장 "앱 UI 테스트만 XCTest(XCUITest)"를 보완한다. 화면 스냅샷은 XCUITest가 아니라 XCTest 단위 번들에서 만든다. ADR-0003의 나머지(Swift Testing, 시계 주입, 사람이 노치 화면을 확인)는 그대로다. ADR-0003 본문은 고치지 않는다.
- 사용한 외부 근거: Apple 문서 `ImageRenderer`("most types of UIKit and AppKit views. In those cases, ImageRenderer displays a placeholder image"), swift-snapshot-testing의 macOS 전략(같은 `cacheDisplay` 경로), T009 첫 시험(2026-10-28, research R8 "결정 검증")

## 맥락

spec 001의 화면 상태(빈 상태, 입력, 칩 펼침, 도는 중, 시간 끝, 떠 있는 창)를 라이트·다크로 사람에게 보여 줄 그림이 필요하다. 시안(`~/Dev/ai-platform/projects/moka/design/001-mockup.html`)과 나란히 보아 색·간격 결정을 내리기 위해서다. 앱을 띄워 사람이 상태를 하나씩 만들어 캡처하는 방법은 느리고, 실제 할 일이 화면에 보일 수 있다.

제약:
- 의존성을 늘리지 않는다(ADR-0001). swift-snapshot-testing 같은 라이브러리는 승인이 필요하다.
- 앱을 테스트 호스트로 쓰면 `AppSettings`가 실제 앱 DB 경로(`~/Library/Application Support/dev.dongwon.moka/`)를 열고 마이그레이션이 돈다(ADR-0004·ADR-0006 위반 위험).
- `ImageRenderer`는 `TextField` 같은 AppKit 기반 컨트롤을 자리표시로 그린다.
- CI 러너(macOS)에서 그림이 매번 같은 픽셀로 나온다는 보장이 없다(글꼴·렌더러 차이).

## 평가 기준

1. 새 의존성 없음 2. 앱 DB·실제 할 일에 닿지 않음 3. `TextField`가 실제 컨트롤로 그려짐 4. 라이트·다크 5. 깨지기 쉬운 픽셀 비교를 피함 6. 만드는 비용

## 대안

| 대안 | 장점 | 단점·위험 |
|---|---|---|
| A. XCTest 단위 번들 `MokaAppTests`(TEST_HOST 없음, `App/Sources/Views/` 직접 컴파일) + `NSHostingView` + `cacheDisplay(in:to:)`, sanity 단언만 | 의존성 없음, 앱 DB를 열지 않음, AppKit 컨트롤이 그려짐(T009 PASS) | 기준 이미지 비교가 없어 회귀를 자동으로 잡지 못함. 뷰가 `AppState`를 모르게 짜야 함(T016에서 이미 그렇게 함) |
| B. XCUITest로 앱을 띄워 캡처 | ADR-0003 문구 그대로 | 앱이 실제 DB를 엶. 노치 패널은 nonactivating이라 UI 테스트 조작이 어렵고 느림 |
| C. swift-snapshot-testing 기준 이미지 비교 | 회귀 자동 감지 | 새 의존성(승인 필요), 러너마다 픽셀 차이로 깨지기 쉬움 |
| D. `ImageRenderer` | 코드가 가장 짧음 | `TextField`가 자리표시로 그려짐 |

## Agent의 추천과 근거

A를 추천한다(추천안 토론 D4, 3:0).
- 도우미 하나: `renderPNG(view:size:appearance:) -> Data`(`App/Tests/MokaAppTests/SnapshotHelper.swift`). `NSHostingView`에 뷰를 넣고 `NSBitmapImageRep`에 `cacheDisplay(in:to:)`로 2배 해상도로 그린다. 라이트·다크는 `NSAppearance(named: .aqua)`·`.darkAqua`. 바탕은 `.frame` 뒤에 칠해 다크 위쪽 투명 띠를 막는다(T009 주의 1).
- 번들: `project.yml`의 `MokaAppTests`(type `bundle.unit-test`, sources `App/Sources/Views`·`App/Tests/MokaAppTests`, `MokaCore`만 의존, `SWIFT_VERSION: "6.0"`, `GENERATE_INFOPLIST_FILE: YES`, TEST_HOST 없음). `MokaApp.swift`·`AppState`·`App/Sources/Notch`·`App/Sources/Settings`는 넣지 않는다. `Moka` 스킴의 testTargets에 둔다.
- 단언은 sanity 3종만: 크기 0 아님, 단색 아님, 라이트≠다크. 기준 이미지와 비교하지 않는다.
- 출력: `TEST_RUNNER_MOKA_SNAPSHOT_DIR`(xcodebuild가 접두사를 떼고 `MOKA_SNAPSHOT_DIR`로 넘김) 또는 `#filePath`로 구한 저장소 루트의 `.verify/snapshots/001/`(커밋 안 함, `.gitignore`의 `.verify/`). 도우미가 폴더를 만든다.
- 할 일 제목은 가짜 예시만 쓴다.
- spec 001에서는 CI job을 두지 않는다. 마일스톤 1 완료 조건이 아니다.

### 생성 PASS는 화면 정합 증거가 아니다

테스트 PASS는 "그림이 만들어졌고 비어 있지 않다"는 뜻일 뿐이다. 시안과 같은지, 색·간격이 맞는지는 사람이 비교 페이지(`~/Dev/ai-platform/projects/moka/design/pr-<PR번호>/index.html`, 저장소 밖)에서 시안과 나란히 보고 정한다. PR에는 생성 결과와 사람 확인을 따로 적는다.

### ADR-0003과 다른 점

ADR-0003은 "앱 UI 테스트만 XCTest(XCUITest)"라고 적었다. 이 결정의 스냅샷은 XCUITest(앱을 띄워 조작하는 UI 테스트)가 아니라 XCTest 단위 테스트 번들이고, 앱을 호스트로 쓰지 않는다(TEST_HOST 없음). 테스트 프레임워크가 XCTest라는 점은 같다. 앱을 띄워 조작하는 UI 테스트가 필요해지면 그때 ADR-0003 문구대로 XCUITest를 따로 정한다.

### 소수 의견

토론 A 자리(가이드·교훈): CI는 무기한 미루지 말고, 첫 야간 확인 뒤 비필수(required 아님) `app-snapshots` job을 chore PR로 제안한다. B·C 자리는 이 일을 `ai-found` Issue로 남기는 쪽이었다. 판정은 spec 001에서 CI job 없음이다.

## 사람의 최종 결정과 실제 판단 이유

Agent 추천안 채택(D4, 2026-10-28). 판단 이유: 사용자 위임(토론 채택안 승인).

## 포기하는 것·운영 영향

- 트레이드오프: 기준 이미지 비교가 없어 화면 회귀를 자동으로 잡지 못한다. 회귀는 사람이 비교 페이지로 본다.
- 운영 영향: `project.yml`에 테스트 타깃 하나와 스킴 testTargets가 생긴다. CI(`app-build`)는 빌드만 하고 이 번들을 돌리지 않는다. 앱 쪽 연결부(`NotchPanelHost`, `ScreenWatcher`, `SettingsView`)는 번들에 들지 않아 이 번들로 시험할 수 없다.
- 되돌리기 비용: 낮음. 타깃과 `App/Tests/MokaAppTests/`를 지우면 된다.

## 결정 검증

- 실행할 실험: `xcodegen generate && TEST_RUNNER_MOKA_SNAPSHOT_DIR=<절대 경로> xcodebuild test -scheme Moka -destination 'platform=macOS' -only-testing:MokaAppTests CODE_SIGNING_ALLOWED=NO`로 상태별 라이트·다크 PNG가 그 폴더에 생기는지 본다. 사람이 비교 페이지에서 시안과 나란히 본다.
- 성공 판정: 테스트 PASS(생성) + 사람 확인(정합)은 따로 판정한다.
- 재검토 트리거: macOS 업데이트로 `cacheDisplay`가 SwiftUI 내용을 빈 그림으로 그림, 뷰가 `AppState`나 앱 전용 타입에 기대게 되어 번들이 컴파일되지 않음, 사람이 자동 회귀 감지를 원함(대안 C나 CI job, 소수 의견 참고).
