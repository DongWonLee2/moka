# ADR-0008: DynamicNotchKit을 빼고 직접 만든 패널 하나로 노치를 그린다 (ADR-0001 의존성 목록 정정)

- 상태: Accepted
- 작성일 / 사람 승인일: 2026-10-28 / 2026-10-28
- 결정 책임자: 저장소 소유자
- 관련 Spec/R-ID: spec 001 R-002·R-009·R-011·R-012, SC-003·SC-004, research R4·R5·R6, tasks T008·T015·T032·T036
- 대체 범위: ADR-0001 "맥락"의 승인된 외부 의존성 목록에서 DynamicNotchKit만 뺀다. ADR-0001의 나머지(모듈 구조, 언어 모드, GRDB·XcodeGen)와 ADR-0005(앱 실행 형태)는 그대로다.
- 사용한 외부 근거: DynamicNotchKit 1.1.0(`cd0b3e52d537db115ad3a9d89601f20e0bee8d27`) 소스 `Sources/DynamicNotchKit/DynamicNotch.swift`, `LICENSE`(MIT), spike(사람 확인, 2026-10-28)

## 맥락

ADR-0001은 DynamicNotchKit을 승인된 의존성으로 두었고, spec 001 plan(D3)은 앱 타깃에만 연결하기로 했다. 아직 `project.yml`에 연결하지 않았다. tasks T008은 UI 작업 전에 버리는 브랜치에서 spike를 돌리고, "2·4가 직접 구현·덮어쓰기이고 6이 반나절 안에 PASS면 제거 후보, 사람이 spike 끝에 정하고 빼면 ADR로 남긴다"고 정했다.

spike 결과(사람이 직접 확인, 2026-10-28):

| # | 확인 | 결과 | 비고 |
|---|---|---|---|
| 1 | 앱 타깃 Swift 6 모드로 DynamicNotchKit import 빌드 | PASS | 경고 없음 |
| 2 | 노치에 마우스를 올리면 펼침 | PASS | 라이브러리에 없음(`hoverBehavior`는 keepVisible·hapticFeedback·increaseShadow뿐). `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)`로 직접 구현 |
| 3 | `LSUIElement` 앱 펼친 판 입력칸에 한글 포함 키 입력, 첫 클릭으로 포커스 | PASS | |
| 4 | 코드로 펼쳐도 키보드 포커스를 가져가지 않음 | PASS | 기록 "key window=없음, 앱 활성=false". `.nonactivatingPanel` + `orderFrontRegardless()` 조합의 동작 |
| 5 | 직접 만든 `.nonactivatingPanel` 떠 있는 창 | PASS(노치 화면에서) | 외부 모니터 NOT_RUN |
| 6 | 직접 만든 `.nonactivatingPanel`을 노치 위치에 노치 모양으로 띄우고 펼침 | PASS | 사용자 "정상" |
| 추가 | 펼친 상태에서 노치 옆 메뉴 막대 클릭을 가로채지 않음 | PASS | |
| 관찰 | 이 맥의 메뉴 막대가 넘쳐 다른 앱 아이콘이 노치 뒤로 숨음 | — | macOS 동작, 공식 문서 없음. spike 앱에는 메뉴 막대 항목이 없어 Moka 아이콘이 숨은 관찰은 아니다 |

그 밖 spike 메모: `LSUIElement` 앱에서 SwiftUI `Window` scene은 실행 시 자동으로 열리지 않았다(spike에서는 AppKit 창으로 대체).

2·4는 라이브러리 기능이 아니라 직접 구현이거나 `.nonactivatingPanel`의 동작이고, 6이 PASS했다. 라이브러리 소스에서 확인한 결함(1.1.0, `Sources/DynamicNotchKit/DynamicNotch.swift`):

- `:144-153` `observeScreenParameters()`가 `NSApplication.didChangeScreenParametersNotification`마다 `initializeWindow(screen: NSScreen.screens.first)`를 부른다. 우리가 고른 화면(R-011, `chooseDisplayTarget`)과 상관없이 첫 화면으로 창을 다시 만든다.
- `:350-352` `initializeWindow`의 첫 줄이 `deinitializeWindow()`로 기존 창을 닫는다. 입력 중 포커스와 `isPinnedOpen`(R-009)을 잃을 수 있다.
- `:387-389` 새 창을 `orderFrontRegardless()`로 띄운다.
- `:173`·`:219` 화면 인자의 기본값이 `NSScreen.screens[0]`이다.

노치 없는 화면은 어느 쪽이든 직접 만든 패널이다(라이브러리 `.floating`은 `compact()`를 `hide()`로 바꿔 R-011을 지킬 수 없다, research R4).

## 평가 기준

1. R-002·R-009(포커스를 가져가지 않음)와 R-011(화면 고르기, 화면 변경에 타이머·고정 상태 유지)을 지키는가 2. 포커스 규칙(data-model §6)을 몇 번 구현하고 사람이 몇 번 확인하는가 3. 직접 만들어야 하는 몫(모양, 애니메이션)의 비용 4. 의존성을 늘리지 않는가 5. 되돌리기 비용

## 대안

| 대안 | 장점 | 단점·위험 |
|---|---|---|
| A. 유지 — 노치 화면은 라이브러리(`NotchHost`), 노치 없는 화면은 직접 패널(`FloatingHost`), hover는 직접 | 노치 모양·열고 닫는 애니메이션을 받아 씀 | 화면 변경 때 라이브러리가 `screens.first`로 창을 다시 만들어 R-011·R-009와 다툼(위 결함). 호스트가 둘이라 포커스 규칙 구현과 사람 확인이 두 번. `swift-docc-plugin`(`from: "1.0.0"`)이 고정되지 않는 구멍 |
| B. 제거 — 노치·노치 없는 화면 모두 직접 만든 `.nonactivatingPanel` 하나(`NotchPanelHost`) | 호스트 하나, 포커스 규칙 한 번, 화면 선택을 우리 `ScreenWatcher`만 정함, 의존성 하나 줄어듦 | 노치 모양(오목 곡선)과 애니메이션을 직접 만듦 |
| C. 유지하되 기한 — spec 001은 라이브러리, 문제가 생기면 제거 | 지금 일이 가장 적음 | 제거 조건(화면 변경 결함)이 이미 소스로 확정이라 결정을 미룰 뿐. 두 호스트를 다 쓴 뒤 빼면 재작업이 커짐 |

## Agent의 추천과 근거

B를 추천한다(추천안 토론 3:0, 2라운드, 소수 의견 없음. 1라운드에 B 자리(실행)가 C였다가 2라운드에 B로 바꿨다. 바꾼 이유: 제거 조건으로 두었던 화면 변경 결함이 소스로 이미 확정이고, 호스트 둘은 포커스 규칙의 구현과 사람 확인을 두 배로 만든다).
- `App/Sources/Notch/NotchPanelHost.swift` 하나가 직접 만든 `.nonactivatingPanel`을 노치 위치(노치 화면) 또는 메뉴 막대 아래 중앙(노치 없는 화면)에 띄운다. 화면은 `ScreenWatcher`가 `chooseDisplayTarget`으로 고른 값을 받는다.
- 펼침은 코드에서 `orderFrontRegardless()`로 띄우고 key window로 만들지 않는다(spike 4). hover는 `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)`(spike 2).
- 모양은 시안 v3.5 치수대로 직접 그린다: 위쪽 양 끝은 안쪽으로 오목한 곡선 8pt, 아래는 둥근 모서리. 라이브러리 `NotchShape`는 MIT라 옮겨 쓸 수 있고, 옮기면 파일에 출처(저장소 URL, revision, 라이선스) 주석을 단다.
- 애니메이션은 SwiftUI의 단순한 크기 전환으로 시작한다. 손질은 사람 확인 항목(SC-004)이다.

## 사람의 최종 결정과 실제 판단 이유

Agent 추천안 채택. 판단 이유: 사용자 위임(토론 채택안 선택, 2026-10-28)

## 포기하는 것·운영 영향

- 트레이드오프: 노치 모양(`NotchShape`)과 열고 닫는 애니메이션을 라이브러리에서 받지 않고 직접 만든다. 애니메이션의 완성도는 처음에 라이브러리보다 낮을 수 있다.
- 운영 영향: `project.yml`에 패키지를 더하지 않는다. `swift-docc-plugin` 고정 구멍(research R4)이 사라진다.
- 되돌림 조건: 모양이나 애니메이션이 같은 원인으로 두 번 사람 확인에 미달하면 대안 A로 되돌린다(헌법 IV). 되돌릴 때는 `style: .notch`를 명시하고, 화면은 `ScreenWatcher`가 고른 `NSScreen`을 직접 넘긴다(기본 인자 `NSScreen.screens[0]`에 맡기지 않는다). 화면 변경 결함은 그때 다시 따진다.
- 되돌리기 비용: `NotchPanelHost` 안의 노치 화면 경로만 바꾸고 `project.yml`에 패키지 한 줄을 더한다. 의존성 추가라 사람 승인이 다시 필요하다.

## 결정 검증

- 실행할 실험: T015 구현 PR에서 사람이 노치 모양이 시안 v3.5와 같은지(위쪽 오목 곡선, 아래 둥근 모서리), 펼침·접힘이 바로 보이는지(SC-004), 포커스 규칙(data-model §6)을 확인한다. T036에서 노치 없는 화면(외부 모니터만) 배치와 화면 변경을 확인한다(spike 5의 외부 모니터 NOT_RUN 몫).
- 성공 판정: 사람 확인 PASS, 화면 변경 뒤 타이머와 `isPinnedOpen`이 유지됨(R-011).
- 재검토 트리거: 위 되돌림 조건, macOS 업데이트로 `.nonactivatingPanel`의 포커스 동작이 바뀜, 노치 크기를 얻는 공개 API(`safeAreaInsets`, `auxiliaryTopLeftArea`·`auxiliaryTopRightArea`)가 바뀜.
