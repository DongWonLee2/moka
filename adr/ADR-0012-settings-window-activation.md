# ADR-0012: 설정·온보딩 창이 열린 동안만 Dock·Command+Tab에 보인다 (ADR-0005 일부 대체)

- 상태: Accepted
- 작성일 / 사람 승인일: 2026-11-13 / 2026-11-13(사용자 결정). 이 문서는 PR 병합으로 확정한다
- 결정 책임자: 저장소 소유자
- 관련 Spec/R-ID: spec 001 R-012, spec 002 R-116, spec 004 plan "앱 연결"(노치 키 확인 한 줄이 설정 창을 엶), ADR-0005, ADR-0008, Issue #45·#105
- 대체 범위: ADR-0005 "Agent의 추천과 근거"의 `LSUIElement = YES`(메뉴 막대 전용) 줄을 일부 대체한다. ADR-0005 본문은 그 줄 끝에 포인터만 붙이고 고치지 않는다. `LSUIElement = YES`는 그대로 두고, 설정 창이나 온보딩 창이 열려 있는 동안만 실행 중에 Dock·Command+Tab에 보이게 바꾼다. 메뉴 막대 항목은 설정과 종료만이라는 부분(R-012)과 ADR-0005의 나머지(Sandbox, 서명, Keychain)는 그대로다.
- 사용한 외부 근거: Apple 문서 `NSApplication.activate()`("calling this method doesn't guarantee app activation"), `NSWindow.orderFrontRegardless()`, `NSWindow.CollectionBehavior.moveToActiveSpace`, `NSApplication.setActivationPolicy(_:)`. 실험은 아래 "원인".

## 맥락

사용자 지적(spec 003 사람 확인, 2026-11-10): 설정 창이 다른 앱 창 뒤로 가면 다시 꺼내기 어렵다. Moka는 `LSUIElement` 앱이라 Dock과 Command+Tab에 나오지 않는다. 메뉴 막대 "설정…"이나 노치의 설정 열기를 눌러도 이미 열린 설정 창이 앞으로 오지 않을 때가 있다.

추천안 토론(2026-11-12, Q1)은 3:0으로 "설정…이 이미 열린 창을 늘 앞으로 꺼낸다(LSUIElement 그대로)"를 냈다. 사용자는 2026-11-13에 둘 다 불편하다며 "앞으로 꺼내기"와 "열린 동안 Dock·Command+Tab에 보이기"를 함께 고르기로 했다. 뒤쪽이 ADR-0005의 "메뉴 막대 전용"을 바꾸므로 이 ADR로 제안한다.

## 원인

#45 이후 `SettingsWindowRaiser.open`은 `NSApp.activate()` → `openSettings()` → 다음 틱 `raise()`(`makeKeyAndOrderFront` + `orderFrontRegardless`) 순서다. 세 후보를 확인했다.

| 후보 | 판정 | 근거 |
|---|---|---|
| 협력 활성화에서 `activate()`가 받아들여지지 않음 | 원인으로 본다 | Apple 문서: `activate()`는 요청이고 활성을 보장하지 않는다. 실험에서 활성이 받아들여진 경우(10회 모두)는 창이 맨 앞에 왔고, 활성이 거절된 경우(1회, `isActive=false`)는 `orderFrontRegardless` 뒤에도 창이 다른 앱 창 뒤(z=1)에 남았다. 활성이 다음 틱보다 늦게 오는 경우도 있었다(다음 틱 `isActive=false`, 0.1초 뒤 `true`) |
| `LSUIElement` 앱에서 창 참조를 찾지 못함 | 아니다 | 같은 구성의 SwiftUI `Settings` 복제 앱에서 앵커가 창을 한 번 찾았고, 창을 닫아도 같은 `NSWindow`가 살아 있어 다시 열 때 그대로 쓰였다 |
| 설정 창이 다른 Space에 있음 | 막을 수 있어 막는다(실험 못 함) | 창의 기본 `collectionBehavior`는 처음 연 Space에 머문다. 노치 패널은 `.canJoinAllSpaces`라 어느 Space에서든 설정 열기를 누를 수 있다. Space 전환은 자동 실험으로 만들 수 없어 사람 확인 항목으로 둔다 |

실험 환경: macOS 27.2(26B123), 이 저장소 밖 임시 디렉터리의 복제 앱(`MenuBarExtra` + `Settings` + 같은 앵커·`open` 순서, `.accessory`). 다른 앱(Orca)을 앞에 둔 뒤 `open`을 부르고 `CGWindowListCopyWindowInfo`로 창 순서를 쟀다. 메뉴 막대 항목을 실제로 누르는 경로는 자동으로 만들 수 없어 재지 못했다.

## 결정

1. `AppWindowPresence`(MokaCore, 순수 규칙)가 열린 앱 창(설정, 온보딩)을 센다. 하나라도 열려 있으면 `.regular`, 모두 닫히면 `.accessory`다. 노치 패널은 세지 않는다.
2. 앱의 `AppWindowActivation`이 이 규칙을 `NSApp.setActivationPolicy`에 옮긴다. 여는 쪽: `SettingsWindowRaiser.open`(메뉴 막대 "설정…", 우클릭 "설정…", 노치 키 확인 한 줄)과 설정 화면 `onAppear`(앱 메뉴 "설정…"처럼 `open`을 거치지 않는 경로), 온보딩 `show()`. 닫는 쪽: 창의 `NSWindow.willCloseNotification`. 빨간 버튼, ⌘W(앱 메뉴 "닫기"), 코드의 `close()`가 모두 이 알림을 거친다.
3. `open`은 `.regular`로 바꾼 뒤 활성을 요청한다. 활성이 늦게 오면 `didBecomeActiveNotification`에서 한 번 더 올린다. 그사이 창을 닫았으면 올리지 않는다.
4. 설정 창에 `.moveToActiveSpace`를 더해 다른 Space에서 열어도 지금 Space로 따라오게 한다.
5. 온보딩 창에도 같은 규칙을 쓴다. 온보딩 창도 다른 앱 뒤로 가면 꺼낼 길이 없기 때문이다.
6. `project.yml`의 `INFOPLIST_KEY_LSUIElement: YES`는 바꾸지 않는다. 앱은 켜질 때 Dock에 나오지 않고 메뉴 막대 앱으로 시작한다.

## 대안

| 대안 | 장점 | 단점·위험 |
|---|---|---|
| A. 앞으로 꺼내기만(`LSUIElement` 그대로, 토론 3:0) | ADR-0005 그대로 | 활성이 거절되면 창이 여전히 뒤에 남는다. Command+Tab·Dock으로 찾는 길이 없다(사용자 지적) |
| B. 열린 동안 `.regular`/닫히면 `.accessory`(이 ADR) | Dock·Command+Tab으로 찾을 수 있고, 일반 앱 활성화가 된다 | 앱 메뉴가 생긴다. 앱 아이콘이 없어 Dock에 기본 아이콘이 보인다. 정책 전환이 노치 패널 포커스에 주는 영향은 사람 확인 |
| C. `LSUIElement = NO`(늘 Dock에 보임) | 구현이 가장 단순 | 메뉴 막대 앱 성격이 사라진다. 사용자가 고른 것은 "열린 동안만"이다 |
| D. `TransformProcessType`(Carbon) | 옛 방식 | 같은 일을 하는 공개 AppKit API(`setActivationPolicy`)가 있다 |

## 위험

- 노치 패널(`.nonactivatingPanel`, ADR-0008)은 포커스를 가져가지 않아야 한다(SC-003). 정책을 `.regular`로 바꿔도 nonactivating 패널을 누르면 앱이 활성되지 않는 성질은 패널 스타일에서 온다고 보지만, 실제 앱에서 확인하지 못했다. 설정 창이 열린 채 다른 앱에서 노치를 누를 때 그 앱이 활성으로 남는지 사람이 확인한다.
- `.accessory`로 돌아갈 때 Moka가 활성이면 앱 메뉴가 사라지고 키 입력이 직전 앱으로 바로 돌아가지 않을 수 있다. 바꾸기 전에도 설정 창을 닫은 뒤에는 Moka가 활성으로 남았으므로 나빠지지 않는다고 보지만 사람이 확인한다.
- `.regular`인 동안 SwiftUI가 만든 앱 메뉴(Moka, 파일, 편집, 보기, 윈도우, 도움말)가 화면 위 메뉴 막대에 보인다. "Moka 종료"(⌘Q)는 메뉴 막대 "종료"와 같은 `terminate` 경로라 종료 체크포인트(R-110)를 남긴다. "닫기"(⌘W)는 위 닫기 알림을 거친다. "Moka에 관하여"는 기본 정보 창을 띄운다. 메뉴 막대 항목(상태 아이콘의 "설정…"·"종료", R-012)은 바뀌지 않는다.
- 앱 아이콘(`AppIcon`)이 아직 없어 Dock과 Command+Tab에 기본 앱 아이콘이 보인다. 아이콘은 이 결정 밖이며 따로 다룬다.

## Agent의 추천과 근거

B를 추천한다. 사용자 결정(2026-11-13, 토론 기록 Q1 뒤 "둘 다")을 따르고, 방법은 오케스트레이터가 준 `setActivationPolicy(.regular/.accessory)` 전환을 그대로 쓴다. 공개 AppKit API이고 `project.yml`과 의존성을 바꾸지 않으며, 규칙을 MokaCore 순수 함수로 시험할 수 있다.
- 사람이 방법(둘 다)을 직접 정해 debate를 생략했다. 앞선 debate 기록은 `.audit/debate/20261112-small-decisions.md` Q1(3:0 A, 커밋 안 함)이다.

## 사람의 최종 결정과 실제 판단 이유

사용자 결정(2026-11-13): 두 가지 모두 불편하니 둘 다 고친다. PR 병합으로 확정한다.

## 포기하는 것·운영 영향

- 트레이드오프: 설정·온보딩 창이 열린 동안에는 메뉴 막대 전용 앱이 아니다. 앱 메뉴와 Dock 아이콘이 잠깐 생긴다.
- 운영 영향: 없음. `project.yml`, 의존성, CI는 그대로다.
- 되돌리기: `AppWindowActivation`의 `opened`·`observeClose` 호출을 빼면 ADR-0005 상태로 돌아간다.

## 결정 검증

- 실행할 실험: PR의 사람 확인 순서(설정 창 앞으로 꺼내기, Dock·Command+Tab, 닫는 두 길, 다른 Space, 노치 포커스, 온보딩).
- 성공 판정: 사람 확인 PASS.
- 재검토 트리거: 노치 패널이 설정 창이 열린 동안 포커스를 가져감, macOS 업데이트로 정책 전환 동작이 바뀜, 앱 아이콘을 정할 때.
