# Research: 노치와 타이머 (spec 001)

승인 항목 D1~D4는 토론(`.audit/debate/20261028-0920-spec001-approvals.md`, 커밋 안 함)으로 추천안을 만들었고 사용자가 2026-10-28 "전부 승인"했다. 기술 설계서(`~/Dev/ai-platform/projects/moka/tech-design.md`, 이하 "설계서")는 재료로 쓰고, 채택된 ADR과 어긋나면 ADR을 따른다.

## R1. 타이머 모델 (R-005·R-008·R-010)

- **Decision**: 타이머는 실제로 잠들지 않는 값 타입 상태기계다. 상태는 `empty / running / expired` 셋. `running`은 시작 시각과 끝 시각(= 시작 + quantum)을 가진다. 상태는 시각을 붙인 이벤트(`start(at:)`, `tick(now:)`, `complete(at:)`)로만 바뀐다. 남은 시간은 `끝 시각 − now`를 초 단위로 **올림**한 값이고(시계를 되돌려도 `quantumMin·60`을 넘지 않게 자른다), 0 이하가 되는 첫 `tick`에서 `expired`로 간다. 시작 전 단계(제목·칩 초안)도 이 값 타입의 `empty(draft:)`가 가진다(data-model §2, EGM 리뷰 뒤 토론 Q1 (b), 사용자 승인 2026-10-28).
- **Rationale**: ADR-0003 "타이머는 실제로 잠들지 않는 상태기계다. 시각을 붙인 이벤트(`tick(now:)` 등)로만 상태가 바뀐다". 끝 시각 기준이라 잠자기·시계 변경과 무관하다(사용자 결정 grilling Q11). 올림이면 "남은 0초 ⇔ 시간 끝"이 같은 뜻이 되어 화면과 `moka-sim` 출력이 흔들리지 않는다(D2).
- **Alternatives**: 남은 초를 1초마다 깎는 카운터(잠자기 동안 멈춤, 사용자가 거절), 내림(0:00이 1초 일찍 보임), monotonic 시계(`ContinuousClock`, 잠자기 포함·시계 변경 무관이지만 `MokaClock`과 `moka-sim`의 ISO 시각 입력과 맞지 않아 이번 범위에서 뺌).
- 시각은 `MokaClock`으로 주입한다. 앱은 1초 주기 화면 갱신 타이머로 `tick(now:)`를 부를 뿐 상태를 직접 바꾸지 않는다. 잠자기에서 깨어나면 `NSWorkspace.didWakeNotification`(`NSWorkspace.shared.notificationCenter`에 등록, `NotificationCenter.default`에는 오지 않음)에서 한 번 더 `tick(now:)`를 부른다(R-008 "깨어날 때"). 갱신 타이머는 `running` 동안만 돈다.

## R2. 기본 작업 시간 저장 (R-012·R-013, D1 채택)

- **Decision**: GRDB `settings(key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)`. 마이그레이션 `v1_settings` 하나, seed 행 없음. 마이그레이션 이름 시험(리터럴 `["v1_settings"]` == `migrator.migrations`), `schema/moka-schema.sql` 스냅샷 비교(질의·형식은 data-model §4), DB 경로 가드 시험(테스트 도우미 쪽, 제품 코드 분기 없음)을 같이 넣는다. MokaCore에 `SettingsStore` 프로토콜, 값 규칙(정수 1~180, 없거나 범위 밖·숫자 아님이면 25)은 MokaCore. 앱은 `~/Library/Application Support/dev.dongwon.moka/moka.sqlite`(ADR-0004)를 `DatabaseQueue`로 연다. 열기 전에 상위 폴더를 만든다(첫 실행에는 폴더가 없다). 그래도 못 열면 메모리 저장소로 동작하고(25, 저장 안 남음) `os.Logger`에 오류 종류를 남긴다. pytest 계약 시험은 튜닝 테이블이 생기는 spec에서.
- **Rationale**: PRD 9장 `settings | key, value`. 검증기(ADR-0004 30~31행)를 테이블 하나로 먼저 돌려 리눅스·macOS `sqlite_master` 텍스트 차이(ADR-0004 49행 재검토 트리거)를 실제 할 일이 쌓이기 전에 드러낸다.
- **Alternatives**: UserDefaults(마일스톤 2에서 이전 코드가 생기고, `~/Library/Preferences/dev.dongwon.moka.plist`는 deny 규칙 밖). 막히면 같은 프로토콜 뒤에 UserDefaults(테스트는 임시 suite)를 꽂는 후퇴 경로를 둔다.
- 값 형식: 정수를 10진 문자열로 저장한다. 설계서 §2 ERD는 `settings.value`를 "JSON 문자열"로 적었다. D1(TEXT, 키마다 형식)과 다르며 D1을 따른다. 정수 하나는 두 해석에서 같은 텍스트다.
- 저널 모드: GRDB `DatabaseQueue` 기본값으로 둔다. WAL은 spec 002 plan에서 정한다([승인 P] Q4).
- 선행 확인: 리눅스 컨테이너(`swift:6.3.3-noble`)와 macOS에서 스냅샷 시험을 둘 다 돌려 텍스트가 같은지 구현 첫 커밋 전에 본다(D1 보강).

## R3. `moka-sim` 시나리오 형식 v1 (R-015, D2 채택)

- **Decision**: [contracts/moka-sim-v1.md](contracts/moka-sim-v1.md). JSON 파일 하나 입력, 이벤트마다 JSON Lines 한 줄 출력. EGM 리뷰 뒤 보강(사용자 승인 2026-10-28): 상태×이벤트 표, 암묵 tick, 필드 이름 `quantum_min`·`timer_state`(GLOSSARY Avoid `minutes`, `state`는 판단 모델 입력), 시간 끝 칩은 기본값, 성공 시에만 출력, 직접 직렬화, 오류 픽스처 `errors/`. `expect` 필드와 사람용 텍스트 출력은 없다. 시나리오 타입과 실행기는 MokaCore, CLI는 파일 읽기와 출력만.
- **Rationale**: ADR-0003 33행 "시나리오 JSON 입력". 출력 형식이 하나여야 계약이 하나다. FAIL 경로는 MokaCore golden 시험과 불변식 위반 종료 코드로 충분하다(3라운드 3:0).
- **Alternatives**: `"format": "moka-sim/1"` 표기(B 소수 의견), 상대 시각(+N초, 06:00 경계를 넣을 때 version 2가 거의 확실).

## R4. DynamicNotchKit 연결과 spike (D3 채택)

- **Decision**: `project.yml` `packages`에 `DynamicNotchKit: {url: https://github.com/MrKai77/DynamicNotchKit, revision: cd0b3e52d537db115ad3a9d89601f20e0bee8d27}`(주석 `# 1.1.0`). 앱 타깃만 연결, `Package.swift`에는 넣지 않는다. SHA는 `git ls-remote --tags`로 확인했다(2026-10-28, 경량 태그 `refs/tags/1.1.0`). 릴리스 페이지와의 대조는 spike에서 한다.
- **spike (UI 작업 전, 사람이 있는 낮, 버리는 브랜치, 병합 안 함, 상한 반나절)**, 결과는 PASS/FAIL로 ADR-0001 "결정 검증"과 이 파일에 적는다.
  1. 앱 타깃 Swift 6 모드 빌드
  2. 노치 위에 마우스를 올리면 펼침(라이브러리에 자동 펼침 코드가 없으면 직접 구현 전제)
  3. `LSUIElement` 앱에서 펼친 화면 `TextField`에 키 입력이 들어감(R-002)
  4. 코드로 펼칠 때 키보드 포커스를 가져가지 않음(R-009, SC-003)
  5. 노치 없는 화면에서 직접 만든 떠 있는 창이 뜨고 펼쳐짐(R-011)
  6. 직접 만든 `.nonactivatingPanel`을 노치 위치에 노치 모양으로 띄우고 펼침. 2·4가 직접 구현·덮어쓰기이고 6이 반나절 안에 PASS면 DynamicNotchKit은 제거 후보다. 사람이 spike 끝에 정하고, 빼면 ADR로 남긴다(토론 Q3, 3:0)
  - 같은 세션에서 스냅샷 도우미 첫 시험(TextField가 든 뷰 하나, R8).
- **Swift 6 실패 시**: ADR-0001 32행대로 첫 실패에서 앱 타깃만 `SWIFT_VERSION: 5.0`, 두 번째 시도 없음.
- **알려진 구멍**: DynamicNotchKit이 받는 `swift-docc-plugin`(`from: "1.0.0"`)은 우리 쪽에서 고정되지 않는다. 앱 쪽 `Package.resolved`는 `*.xcodeproj/` 제외로 커밋되지 않는다(`.gitignore` 48행). `app-build` 로그로 해석된 버전을 본다.
- spike PASS 전에는 UI tasks를 `ai-ready` 후보로 올리지 않는다.
- **설계서와의 어긋남**: 설계서 초안 ADR-0005는 "노치 없는 맥은 라이브러리 floating 스타일 그대로, hover·제스처는 기본값"이다. 라이브러리 `.floating`은 `compact()`를 `hide()`로 바꾸므로 R-011을 지킬 수 없고, R-009는 기본 hover 동작을 바꾼다. spec(사용자 결정)을 따른다([승인 P] Q6).

## R5. 표시 위치와 떠 있는 창 (R-011)

- **Decision**: 화면 고르기는 순수 함수로 MokaCore에 둔다. 입력은 화면 목록(내장 여부, 노치 여부, 주 화면 여부), 출력은 `notch(화면)` 또는 `floating(화면)`. 규칙: 노치가 있는 내장 화면이 있으면 그 화면의 노치, 없으면 주 화면(메뉴 막대가 있는 화면)의 떠 있는 창. 앱은 `NSScreen`에서 이 입력을 만들고(노치 여부는 `safeAreaInsets.top > 0`), `NSApplication.didChangeScreenParametersNotification`에서 다시 고른다. 떠 있는 창은 직접 만든 `.nonactivatingPanel` 패널(메뉴 막대 아래 중앙 고정, 드래그 없음)이고, 접힘(제목 + 남은 시간)과 펼침을 둘 다 보인다.
- **Rationale**: 화면 연결 변경 규칙을 리눅스 `swift test`로 시험할 수 있다. 라이브러리 floating은 접힘을 숨긴다(R4).
- **Alternatives**: 라이브러리 floating(접힘 없음), 메뉴 막대 글자(ADR-0005 "메뉴 막대는 설정과 종료만"을 바꿔야 함, 사용자가 grilling Q8에서 (a)를 고름).

## R6. 앱 구조: AppState, NotchHost, 동시성 ([승인 P] Q6·Q7에서 이 plan으로 넘어옴)

- **Decision**:
  - `@Observable @MainActor final class AppState` 하나가 화면 상태(펼침 여부, 자동 펼침 고정 여부, 입력 중 제목, 고른 분)와 MokaCore 타이머 값을 가진다. 타이머 규칙은 MokaCore 값 타입이고 AppState는 이벤트를 전달할 뿐이다(설계서 §1 "AppCoordinator(타이머·트리거·하루 경계를 Core에 전달)"와 같은 역할, 이름은 AppState 하나로 줄인다).
  - DynamicNotchKit은 `App/Sources/Notch/NotchHost.swift` 한 파일만 import한다. 떠 있는 창은 `App/Sources/Notch/FloatingHost.swift`. 둘은 같은 SwiftUI 뷰(`App/Sources/Views/`)를 띄운다.
  - MokaStore는 GRDB `DatabaseQueue`가 직렬화를 맡으므로 actor로 감싸지 않는다. Store를 actor로 할지는 동시 접근이 생기는 spec에서 정한다.
- **Rationale**: 라이브러리를 바꾸거나 떼어낼 때 고칠 곳을 한 파일로 줄인다(설계서 §1의 초안 ADR-0005 "NotchHost 한 파일"을 받음). 뷰를 `App/Sources/Views/`에 모아야 스냅샷 테스트 번들이 앱 호스트 없이 뷰 소스를 직접 컴파일한다(D4).
- **Alternatives**: AppCoordinator + AppState 둘(이번 범위에는 과함), Store actor(지금 동시 접근 없음).

## R7. 로그 방침 ([승인 P] Q7에서 이 plan으로 넘어옴)

- **Decision**: MokaCore·MokaStore는 로그를 남기지 않고 값이나 오류를 돌려준다. `moka-sim`은 표준 출력이 결과물이다(R3). 앱은 `os.Logger`(subsystem `dev.dongwon.moka`)로 상태 전이 이름과 오류 종류만 남긴다. 할 일 제목, 설정 값 외의 사용자 입력, 키는 남기지 않는다.
- **Rationale**: `os`는 Apple 플랫폼 모듈이라 리눅스 CI에서 빌드되는 Package 타깃에 두지 않는다. 공개 저장소 원칙(실제 할 일이 로그·캡처로 새지 않게).

## R8. 화면 스냅샷 (D4 채택)

- **Decision**: 새 의존성 없이 `NSHostingView` + `bitmapImageRepForCachingDisplay`·`cacheDisplay(in:to:)`로 PNG를 만드는 도우미 `renderPNG(view:size:appearance:) -> Data` 하나. macOS 단위 테스트 번들 `MokaAppTests`(XCTest, TEST_HOST 없음, `App/Sources/Views/`를 직접 컴파일하고 `MokaApp.swift`는 넣지 않음). 라이트·다크는 `NSAppearance(.aqua/.darkAqua)`. 기준 이미지 비교는 하지 않고 sanity 단언(크기 0 아님, 단색 아님, 라이트≠다크)만 한다. 출력 폴더는 `TEST_RUNNER_MOKA_SNAPSHOT_DIR`로 넘긴다(`xcodebuild test`는 `TEST_RUNNER_` 접두사가 붙은 변수만 접두사를 떼고 테스트 프로세스에 넘긴다). 없으면 `#filePath`로 구한 저장소 루트의 `.verify/snapshots/001/`(커밋 안 함, `.gitignore`의 `.verify/` 규칙). 도우미가 폴더를 만든다. `project.yml`에서 `Moka` 스킴의 test 대상에 `MokaAppTests`를 넣는다. 마일스톤 1 완료 조건이 아니며 밀리면 버퍼(11/8~9)로 간다(토론 Q2, 3:0). spec 001에서는 CI job을 두지 않는다. 방법은 구현 PR에서 ADR(다음 번호)로 기록한다.
- **Rationale**: Apple 문서 `ImageRenderer` "most types of UIKit and AppKit views. In those cases, ImageRenderer displays a placeholder image". swift-snapshot-testing의 macOS 전략도 같은 `cacheDisplay` 경로를 쓴다. 앱을 호스트로 쓰면 실제 DB 경로에서 마이그레이션이 돈다.
- 생성 PASS는 "그림이 만들어졌다"는 뜻이지 화면이 맞다는 증거가 아니다. 화면 정합은 사람이 시안과 나란히 본다.

## R9. 화면 시안 (조언 노트 2026-10-28 09:05)

- plan 다음, tasks 전에 `~/Dev/ai-platform/projects/moka/design/001-mockup.html`(한 파일, 외부 CDN 없음, 라이트·다크, 가짜 할 일). 사용자가 "시안 확정"하면 경로를 spec에 적고 tasks를 만든다. 확정 전에는 UI tasks를 시작하지 않는다. MokaCore·MokaStore·`moka-sim` 작업은 시안과 무관하다.
