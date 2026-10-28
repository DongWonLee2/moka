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

## R4. DynamicNotchKit spike와 제거 (D3 → ADR-0008)

- **Decision**: DynamicNotchKit을 쓰지 않는다. 노치 화면과 노치 없는 화면 모두 직접 만든 `.nonactivatingPanel` 하나(`App/Sources/Notch/NotchPanelHost.swift`, R6)로 그린다. `project.yml`에 패키지를 더하지 않는다. [ADR-0008](../../adr/ADR-0008-drop-dynamicnotchkit.md), 추천안 토론 3:0(`.audit/debate/20261028-1700-dynamicnotchkit-keep.md`, 커밋 안 함), 사용자 선택 2026-10-28. D3(앱 타깃에만 1.1.0 `cd0b3e52d537db115ad3a9d89601f20e0bee8d27` 연결)은 이 결정으로 대체된다.
- **spike 결과** (T008, 사람이 있는 낮 세션, 버리는 브랜치, 병합 안 함, 사람 확인 2026-10-28):

| # | 확인 | 결과 | 비고 |
|---|---|---|---|
| 1 | 앱 타깃 Swift 6 모드로 DynamicNotchKit import 빌드 | PASS | 경고 없음 |
| 2 | 노치에 마우스를 올리면 펼침 | PASS | 라이브러리에 없어 `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)`로 직접 구현 |
| 3 | `LSUIElement` 앱 펼친 판 `TextField`에 키 입력(한글 포함), 첫 클릭으로 포커스(R-002) | PASS | |
| 4 | 코드로 펼쳐도 키보드 포커스를 가져가지 않음(R-009, SC-003) | PASS | "key window=없음, 앱 활성=false". `.nonactivatingPanel` + `orderFrontRegardless()` |
| 5 | 직접 만든 `.nonactivatingPanel` 떠 있는 창(R-011) | PASS(노치 화면에서) | 외부 모니터 NOT_RUN → T036 사람 확인 |
| 6 | 직접 만든 `.nonactivatingPanel`을 노치 위치에 노치 모양으로 띄우고 펼침 | PASS | 사용자 "정상" |
| 추가 | 펼친 상태에서 노치 옆 메뉴 막대 클릭을 가로채지 않음 | PASS | |
| 관찰 | 이 맥의 메뉴 막대가 넘쳐 다른 앱 아이콘이 노치 뒤로 숨음 | — | macOS 동작, 공식 문서 없음. spec R-012 우클릭 메뉴로 대비 |

- **Rationale**: 사람이 spike 끝에 결정했다. 2는 직접 구현이고, 4는 라이브러리 기본 동작이지만 같은 동작을 직접 만든 패널에서도 확인했다(spike 5·6). 라이브러리 1.1.0은 화면이 바뀔 때마다 첫 화면으로 창을 다시 만든다(`DynamicNotch.swift:144-153` `initializeWindow(screen: NSScreen.screens.first)`, `:350-352` 기존 창 닫기, `:387-389` `orderFrontRegardless()`, `:173`·`:219` 기본 인자 `NSScreen.screens[0]`). 이는 R-011(우리가 고른 화면, 타이머·고정 상태 유지)과 다툰다. 호스트를 하나로 두면 포커스 규칙(data-model §6)을 한 번 구현하고 한 번 확인한다.
- **Alternatives**: 유지(노치는 라이브러리, 노치 없는 화면은 직접 패널), 유지하되 기한(문제가 생기면 제거). 둘 다 ADR-0008 대안 표.
- **직접 만드는 몫**: 모양은 시안 v3.5 치수대로(위쪽 양 끝 안쪽 오목 곡선 8pt, 아래 둥근 모서리). 라이브러리 `NotchShape`는 MIT라 옮겨 쓸 수 있고 옮기면 출처 주석. 애니메이션은 SwiftUI 크기 전환으로 시작하고 손질은 사람 확인(SC-004).
- **되돌림 조건**: 모양·애니메이션이 같은 원인으로 두 번 사람 확인에 미달하면 라이브러리로 되돌린다(헌법 IV). 그때 `style: .notch`를 명시하고 화면은 직접 넘긴다. 의존성 추가라 사람 승인이 다시 필요하다.
- spike 그 밖 메모: `LSUIElement` 앱에서 SwiftUI `Window` scene은 실행 시 자동으로 열리지 않았다(spike에서는 AppKit 창으로 대체).
- 설계서 초안 ADR-0005("노치 없는 맥은 라이브러리 floating 스타일 그대로, hover·제스처는 기본값")와 다르다. 라이브러리 `.floating`은 `compact()`를 `hide()`로 바꿔 R-011을 지킬 수 없고, R-009는 기본 hover 동작을 바꾼다. spec(사용자 결정)과 ADR-0008을 따른다([승인 P] Q6).

## R5. 표시 위치와 떠 있는 창 (R-011)

- **Decision**: 화면 고르기는 순수 함수로 MokaCore에 둔다. 입력은 화면 목록(내장 여부, 노치 여부, 주 화면 여부), 출력은 `notch(화면)` 또는 `floating(화면)`. 규칙: 노치가 있는 내장 화면이 있으면 그 화면의 노치, 없으면 주 화면(메뉴 막대가 있는 화면)의 떠 있는 창. 앱은 `NSScreen`에서 이 입력을 만들고(노치 여부는 `safeAreaInsets.top > 0`), `NSApplication.didChangeScreenParametersNotification`에서 다시 고른다. 두 위치 모두 같은 직접 만든 `.nonactivatingPanel`(`NotchPanelHost`, R4·R6)이 그린다. 떠 있는 창은 메뉴 막대 아래 중앙 고정, 드래그 없음이고, 접힘(제목 + 남은 시간)과 펼침을 둘 다 보인다.
- **Rationale**: 화면 연결 변경 규칙을 리눅스 `swift test`로 시험할 수 있다. 화면은 `ScreenWatcher`만 고르고 패널은 그 결과를 받는다(라이브러리처럼 첫 화면으로 다시 만들지 않는다, R4).
- **Alternatives**: 라이브러리 floating(접힘 없음), 메뉴 막대 글자(ADR-0005 "메뉴 막대는 설정과 종료만"을 바꿔야 함, 사용자가 grilling Q8에서 (a)를 고름).

## R6. 앱 구조: AppState, NotchPanelHost, 동시성 ([승인 P] Q6·Q7에서 이 plan으로 넘어옴)

- **Decision**:
  - `@Observable @MainActor final class AppState` 하나가 화면 상태(펼침 여부, 자동 펼침 고정 여부, 입력 중 제목, 고른 분)와 MokaCore 타이머 값을 가진다. 타이머 규칙은 MokaCore 값 타입이고 AppState는 이벤트를 전달할 뿐이다(설계서 §1 "AppCoordinator(타이머·트리거·하루 경계를 Core에 전달)"와 같은 역할, 이름은 AppState 하나로 줄인다).
  - 패널은 `App/Sources/Notch/NotchPanelHost.swift` 한 파일이 맡는다. 노치 위치(노치 모양)와 떠 있는 창(메뉴 막대 아래 중앙) 둘 다 이 파일의 직접 만든 `.nonactivatingPanel`이고, 같은 SwiftUI 뷰(`App/Sources/Views/`)를 띄운다. 외부 노치 라이브러리는 import하지 않는다(ADR-0008).
  - 패널 구성: `NSPanel` 하위 클래스(`canBecomeKey = true`), styleMask `[.borderless, .nonactivatingPanel]`, `backgroundColor = .clear`, `hasShadow = false`, `collectionBehavior = [.canJoinAllSpaces, .stationary]`. level은 노치 위치 `.screenSaver`, 떠 있는 창 `.statusBar`(둘 다 spike PASS 설정). 프레임은 내용 크기(접힘 크기 ↔ 펼침 크기)로 `setFrame(_:display:animate:)`, 큰 투명 패널을 쓰지 않는다. 띄우기는 `orderFrontRegardless()`(key를 가져가지 않음). 펼친 판 클릭 → `makeKey()`, 시작·완료 → `resignKey()`(이전 앱으로 key가 돌아가는지는 사람 확인, T015).
  - hover: 전역 모니터(spike 2) 대신 호스팅 뷰의 `NSTrackingArea`(`.mouseEnteredAndExited`, `.activeAlways`, `.inVisibleRect`). 접힌 패널이 노치 자리에 늘 있으므로 들어옴·나감을 같은 방식으로 받는다.
  - 화면: `ScreenWatcher`가 `NSScreen` 목록 → `[ScreenInfo]` → `chooseDisplayTarget`으로 고르고(`NSScreen.screens.first`를 직접 쓰지 않는다), 화면 변경 때 `NotchPanelHost.move(to:)`를 부른다. 호스트는 `setFrame`으로 옮기고 창을 다시 만들지 않는다(ADR-0008 결함 사유).
  - MokaStore는 GRDB `DatabaseQueue`가 직렬화를 맡으므로 actor로 감싸지 않는다. Store를 actor로 할지는 동시 접근이 생기는 spec에서 정한다.
- **Rationale**: 패널·포커스·hover 코드를 한 파일에 모아 포커스 규칙을 한 번만 구현한다. ADR-0008 되돌림 조건으로 라이브러리를 다시 쓰게 되어도 고칠 곳이 이 파일 하나다(설계서 §1의 초안 ADR-0005 "NotchHost 한 파일"을 받음). 뷰를 `App/Sources/Views/`에 모아야 스냅샷 테스트 번들이 앱 호스트 없이 뷰 소스를 직접 컴파일한다(D4).
- **Alternatives**: AppCoordinator + AppState 둘(이번 범위에는 과함), Store actor(지금 동시 접근 없음).

## R7. 로그 방침 ([승인 P] Q7에서 이 plan으로 넘어옴)

- **Decision**: MokaCore·MokaStore는 로그를 남기지 않고 값이나 오류를 돌려준다. `moka-sim`은 표준 출력이 결과물이다(R3). 앱은 `os.Logger`(subsystem `dev.dongwon.moka`)로 상태 전이 이름과 오류 종류만 남긴다. 할 일 제목, 설정 값 외의 사용자 입력, 키는 남기지 않는다.
- **Rationale**: `os`는 Apple 플랫폼 모듈이라 리눅스 CI에서 빌드되는 Package 타깃에 두지 않는다. 공개 저장소 원칙(실제 할 일이 로그·캡처로 새지 않게).

## R8. 화면 스냅샷 (D4 채택)

- **Decision**: 새 의존성 없이 `NSHostingView` + `bitmapImageRepForCachingDisplay`·`cacheDisplay(in:to:)`로 PNG를 만드는 도우미 `renderPNG(view:size:appearance:) -> Data` 하나. macOS 단위 테스트 번들 `MokaAppTests`(XCTest, TEST_HOST 없음, `App/Sources/Views/`를 직접 컴파일하고 `MokaApp.swift`는 넣지 않음). 라이트·다크는 `NSAppearance(.aqua/.darkAqua)`. 기준 이미지 비교는 하지 않고 sanity 단언(크기 0 아님, 단색 아님, 라이트≠다크)만 한다. 출력 폴더는 `TEST_RUNNER_MOKA_SNAPSHOT_DIR`로 넘긴다(`xcodebuild test`는 `TEST_RUNNER_` 접두사가 붙은 변수만 접두사를 떼고 테스트 프로세스에 넘긴다). 없으면 `#filePath`로 구한 저장소 루트의 `.verify/snapshots/001/`(커밋 안 함, `.gitignore`의 `.verify/` 규칙). 도우미가 폴더를 만든다. `project.yml`에서 `Moka` 스킴의 test 대상에 `MokaAppTests`를 넣는다. 마일스톤 1 완료 조건이 아니며 밀리면 버퍼(11/8~9)로 간다(토론 Q2, 3:0). spec 001에서는 CI job을 두지 않는다. 방법은 구현 PR에서 ADR(다음 번호)로 기록한다.
- **Rationale**: Apple 문서 `ImageRenderer` "most types of UIKit and AppKit views. In those cases, ImageRenderer displays a placeholder image". swift-snapshot-testing의 macOS 전략도 같은 `cacheDisplay` 경로를 쓴다. 앱을 호스트로 쓰면 실제 DB 경로에서 마이그레이션이 돈다.
- 생성 PASS는 "그림이 만들어졌다"는 뜻이지 화면이 맞다는 증거가 아니다. 화면 정합은 사람이 시안과 나란히 본다.
- **결정 검증** (T009 스냅샷 도우미 첫 시험, 2026-10-28 21:04, spike 브랜치, 버리는 코드): PASS.
  - `NSHostingView` + `bitmapImageRepForCachingDisplay`·`cacheDisplay(in:to:)`로 `TextField`가 든 뷰를 라이트(`NSAppearance(named: .aqua)`)·다크(`.darkAqua`) PNG로 만들었다. 각 약 15KB, 서로 다르고, `TextField`가 placeholder가 아니라 실제 컨트롤로 그려졌다.
  - `project.yml`에 `MokaAppTests`(`bundle.unit-test`, TEST_HOST 없음, `SWIFT_VERSION: "6.0"`, `GENERATE_INFOPLIST_FILE: YES`)와 `Moka` 타깃 `scheme: { testTargets: [MokaAppTests] }`를 두면 `xcodebuild test -scheme Moka -only-testing:MokaAppTests`가 돈다.
  - `TEST_RUNNER_MOKA_SNAPSHOT_DIR=<절대 경로>`가 테스트 프로세스에 `MOKA_SNAPSHOT_DIR`로 전달되는 것을 확인했다.
  - 주의 1: 다크 그림 위쪽에 밝은 띠가 남았다. 배경을 `.frame` 바깥에 칠하지 않아 투명 영역이 남은 것이다. 도우미는 `.frame` 뒤에 배경을 칠한다(T037).
  - 주의 2: xctest 로그에 `com.apple.linkd.autoShortcut` 연결 경고가 나오지만 결과와 무관하다.

## R9. 화면 시안 (조언 노트 2026-10-28 09:05)

- plan 다음, tasks 전에 `~/Dev/ai-platform/projects/moka/design/001-mockup.html`(한 파일, 외부 CDN 없음, 라이트·다크, 가짜 할 일). 사용자가 "시안 확정"하면 경로를 spec에 적고 tasks를 만든다. 확정 전에는 UI tasks를 시작하지 않는다. MokaCore·MokaStore·`moka-sim` 작업은 시안과 무관하다.
