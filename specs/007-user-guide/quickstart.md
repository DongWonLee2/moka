# Quickstart: 사용 안내 확인 (spec 007)

결과는 PASS / FAIL / SKIP / NOT_RUN으로만 적는다. 실행하지 않은 것은 PASS로 적지 않는다. 가짜 할 일만 쓴다. 규칙은 [data-model.md](data-model.md), 글자는 확정 시안 `~/Dev/ai-platform/projects/moka/design/007-mockup.html` v2(시안 확정 2026-11-13(사용자))다.

## 1. 핵심 로직 (자동, 리눅스 CI `core-test`)

```
swift test
```

기대: `ReasonText.deadline`이 `.today`에 "D-day", `.overdue(2)`에 "D+2", `.left(3)`에 "D-3", `.none`에 "마감 없음"을 돌려준다. 기존 시험과 시뮬레이터 golden은 그대로 PASS다.

## 2. 앱 빌드 (자동, CI `app-build`)

```
xcodegen generate && xcodebuild build -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

## 3. 앱 시험 (로컬 macOS, `MokaAppTests`)

```
xcodegen generate && xcodebuild test -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MokaAppTests
```

기대:

- 도움말 글: 따옴표 안 글자가 모두 `HelpContent.quotes`에 있음, 항목 여덟 글이 spec 글자와 같음(단축 동작 표는 리뷰 반영 뒤 글자), 문장 수 2~5, 목차 순서와 요약, 항목 줄 VoiceOver 값 "펼침"·"접힘" (R-703~R-705, R-716, SC-703)
- 펼침: `helpExpanded`에 둘을 넣고 빼면 집합이 맞게 바뀜, 처음 빈 집합, 저장소에 쓰기 0건 (R-707, SC-702)
- 안내 장: `GuideButtons.make` 여섯 경우 표, 안내 장 글의 따옴표 안 글자가 화면 상수(`NotchText`, `GateDisplay`)와 같음, 그림 설명 셋, `GateDisplay.detachesStartShortcut(isIllustration: true)`가 참이고 `requestsFocus(isIllustration: true)`가 거짓 (R-705, R-710, R-712, R-716, data-model §4)
- 온보딩 단계: 키 단계 있음 1~3 안내 장, 4 키, 5 일정, 6 기본값, 총 6. 없음 총 5. 첫째·둘째 장 `skipGuide()`가 안내 장이 아닌 첫 쪽으로. 셋째 장 `next()`가 첫 설정 단계로. 4/6에서 키 저장이 실패하면 4/6에 머물고 성공하면 5/6. 안내 장 쪽에서 `submitKey`가 `onSave`를 부르지 않고 `canFinish`가 거짓. 기존 키 단계 시험은 `hasGuide: false`로 기대값 그대로 PASS (R-711, SC-704~SC-706)
- 기존 사용자: `AppLifecycleTests`의 `test_FR21_R116_firstLaunchShowsOnboarding`, `test_FR21_R116_finishSavesContextSettingsAndHidesOnboarding`가 그대로 PASS(온보딩 끝냄 표시가 있으면 온보딩이 뜨지 않음, 새 설정 키 없음) (R-715)
- 시트: `GuideSheetState`가 1/3에서 시작, 셋째 장 `primary()`가 닫으라는 참, `cancel()`이 참, 건너뛰기 없음, 주 버튼 "다 봤어요". 생성 인자에 저장소가 없음(컴파일로 보장) (R-713·R-714, SC-705)

## 4. 화면 스냅샷 (로컬, CI `app-snapshots` 경고만)

data-model §7 이름 전부(라이트·다크, 도움말 항목 펼침은 라이트). 탭 줄이 들어간 기존 설정 창 그림과 온보딩 설정 단계 그림은 바뀌고 PR에 이유를 적는다. 그 밖의 그림은 그대로다(SC-707). 확정 시안과 나란히 보는 비교 페이지를 `~/Dev/ai-platform/projects/moka/design/pr-<번호>/index.html`에 만든다(ADR-0009).

## 5. 사람 확인 준비

확인 순서를 적기 전에 그 상태를 지금 빌드에서 만들 수 있는지 먼저 본다. 모든 확인은 그 단위 PR 브랜치의 확인용 빌드(개인 팀 서명)로 한다. 에이전트는 실제 앱 DB와 Keychain을 열거나 지우지 않는다.

## 6. 사람 확인 (단위 순서대로)

| # | 단위 | 확인 | 상태를 만드는 법 | 대응 |
|---|---|---|---|---|
| 6-1 | 1 | 메뉴 막대 Moka 메뉴의 "설정…"을 누르면 설정 창 탭 줄 맨 끝에 "도움말"이 보인다. 누르면 맨 위에 "노치, 순위, 첫 행동 칸 안내를 한 장씩 다시 볼 수 있어요."와 "안내 다시 보기"가 있고 아래 여덟 항목이 접혀 있다. "이유 줄"과 "첫 행동 칸"을 눌러 둘 다 펼치고 "기본" 탭에 갔다 오면 둘 다 펼친 채다. 설정 창을 닫았다 다시 열어도 펼친 채다. VoiceOver를 켜고 항목 줄로 가면 펼친 항목은 "펼침", 접힌 항목은 "접힘"으로 읽는다 | 지금 쓰는 앱에 확인용 빌드를 켬 | US1-1~6, SC-701·SC-702, R-716 |
| 6-2 | 3 | 도움말 탭의 "안내 다시 보기"를 누르면 설정 창 위에 시트가 내려오고 "1/3 할 일은 노치에 떠요"가 보인다. Enter를 두 번 눌러 3/3으로 가고 "다 봤어요"를 누르면 시트가 닫히고 도움말 탭 그대로다. 다시 열어 esc를 누르면 닫힌다. 시트가 열린 채 설정 창 빨간 버튼을 누르면 창이 닫히지 않고 시트도 그대로다(R-714, macOS 시트의 기본 동작). 그동안 노치 타이머는 그대로 돈다 | 6-1과 같은 빌드. 타이머는 노치에서 가짜 할 일로 시작 | US3-1~6, R-714 |
| 6-2b | 3 | 시트가 열린 동안 탭 요청: 노치 펼친 화면의 "키 확인"을 누르면 시트는 열린 채이고, 시트를 닫으면 설정 창이 "기본" 탭이다 | 기본 탭에 가짜 문자열을 키로 저장하고 가짜 할 일을 저장해 키 확인 한 줄을 만든다(spec 006 quickstart 6-5와 같은 방법). 확인 뒤 키를 지운다 | R-714, Edge Cases |
| 6-3 | 2·3 | 새 사용자 계정 온보딩. (1) Moka를 처음 켜면 "Moka 시작하기" 창에 1/6 노치 안내가 보인다. (2) Enter를 누르면 2/6으로 넘어간다(그림 속 "시작"이 Enter를 가로채지 않음). (3) 2/6에서 "이전"을 누르면 1/6으로 돌아온다. (4) 다시 2/6으로 가서 "안내 건너뛰기"를 누르면 4/6 키 단계로 간다. 키 단계에 "이전"이 없다. (5) 창을 빨간 버튼으로 닫고 다시 켜 1/6부터 Enter 세 번으로 3/6까지 가면 첫 행동 칸 그림의 칸이 포커스를 가져가지 않고, Enter로 4/6에 간다. (6) 온보딩 창을 둔 채 메뉴 막대 "설정…" > "도움말" > "안내 다시 보기"를 누르면 설정 창 위에 시트가 열리고 온보딩 창은 그대로 4/6이다. 시트를 닫는다. (7) 키 건너뛰기, 일정 건너뛰기, "시작하기"로 끝낸 뒤 가짜 할 일을 넣으면 노치에 뜬다. 다시 켜면 온보딩이 보이지 않는다 | macOS 새 사용자 계정(spec 004 위험 6과 같은 방법). 확인용 빌드를 지금 계정에서 만든 뒤 `/Users/Shared/`에 `Moka.app`을 복사하고, 새 계정에서 그 사본을 연다(처음 열 때 Gatekeeper가 막으면 Finder에서 우클릭 > 열기) | US2-1·3~8, R-714, SC-704 |
| 6-4 | 2 | 지금 쓰는 계정(온보딩을 이미 끝냄)에서 확인용 빌드를 켜면 안내 장이 뜨지 않는다 | 6-1과 같은 빌드 | US3-7, R-715 |
| 6-5 | 1·2·3 | 비교 페이지에서 새 스냅샷이 확정 시안 1~15번과 같은 글자인지, 기존 그림 가운데 탭 줄·단계 표시 밖이 바뀐 것이 없는지 본다 | 4의 비교 페이지 | R-717, SC-707 |

키 단계가 없는 온보딩(n/5)은 판단 기능이 꺼진 빌드(질문 파일을 읽지 못함)에서만 생긴다. 사람 확인으로 만들 수 없어 스냅샷(`test_R711_guideCard1WithoutKeyStep`)과 앱 시험만으로 보고, 사람 확인은 NOT_RUN으로 적는다.
