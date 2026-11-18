# Quickstart: 일시 중지와 급한 일 끼워 넣기 확인 (spec 008)

결과는 PASS / FAIL / SKIP / NOT_RUN으로만 적는다. 실행하지 않은 것은 PASS로 적지 않는다. 가짜 할 일만 쓴다. 규칙은 [data-model.md](data-model.md), 화면 글자는 확정 시안 `~/Dev/ai-platform/projects/moka/design/008-mockup.html`(확정 전)이다. 에이전트는 실제 앱 DB, Keychain, 실제 판단 API를 열지 않는다(R-835).

## 1. 핵심 로직 (자동, 리눅스 CI `core-test`)

```
swift test
```

기대:

- 타이머(`NotchTimerTests`, `NotchSessionPauseTests`, 주입한 시계): 25분 가운데 10분 돈 뒤 멈추면 15분 남음, 30분이 흘러도 15분이고 시간 끝이 오지 않음, 이어 돌면 끝 시각이 누른 시각 + 15분, 누른 시각의 남은 초를 지킴, 돌아가기(Esc)는 기록 없이 남은 초부터 이어 돎, 쓰기 실패면 아무것도 남지 않고 이어 돎(R-802~R-804). 컴파일러가 못 잡는 자리: 멈춘 채 `quit` 체크포인트와 돌려주기, 멈춘 채 `sleep` 체크포인트 0건(data-model §12).
- 기록: 체크포인트 `pause` 경과 10분과 로그 줄 `pause` 하나, 이어 돈 뒤 `resume` 줄 하나, 초안 일시 중지는 체크포인트·줄 0개, 이어 돈 뒤 끝난 체크포인트의 경과 분에 멈춘 시간이 없음(R-802, R-815, SC-808).
- 쓴 시간(`DayBudgetTests`): data-model §3 표의 길마다 돌려줄 초, 멈춘 동안 바뀌지 않음, "더 할래요" 전 `used_s ≤ 가용 시간`(R-805, R-833, SC-806).
- 하루 경계(`NotchSessionPauseTests`, `SessionAssemblyTests`): 05:59와 06:00, 멈춘 채 넘긴 뒤 첫 활성화와 "다시 시작"에서 `day_end` 빈 체크포인트, 전날 기록에 돌려줌, 첫 행동이 멈출 때 받은 다음 줄 그대로, 이월 카드부터, 05:00에 고른 "내일 아침까지"는 그날 06:00에 끝남(R-806, SC-802, US1-5·9·12). 두 줄을 적는 동안 경계를 넘긴 제출은 `pause`와 `day_end`가 한 묶음이고 실패하면 글이 남음, 경계를 넘긴 돌아가기는 `day_end` 빈 체크포인트로 끝나고 `resume` 줄 0개, 입력 중 활성화는 입력을 끝내지 않고 붙은 `dueDecision`이 제출 뒤에도 남음(P3).
- 모드(`NotchModeTests`): data-model §6 표 일곱 줄, 멈춘 동안 카드·질문·오늘 끝이 뜨지 않음(R-831).
- 자동 시작(`AutoStartTests`): 멈춘 동안, 길이가 끝나 돌아온 첫 초안, 앱을 다시 켠 뒤 첫 초안은 입력 전 시작 0건, "다시 시작"으로 끝낸 초안은 3초 규칙, 깨어남·기본 작업 시간 변경·자동 시작 설정 변경·판 클릭 뒤에도 시작 0건(R-832, SC-808, data-model §7).
- 긴급(`NotchSessionUrgentTests`, `SchedulerPickTests`, `PriorityOrderTests`): 끊긴 할 일의 체크포인트 `urgent`와 줄 하나, 미룬 횟수 그대로, 마감 없으면 오늘, 판단 결과와 상관없이 1위, 완료 뒤 복귀 제안(`urgent_return_v1`, 몫 상태 그대로), 미루기·바꾸기 뒤 복귀 제안 0건, 오늘 끝과 이월 카드가 복귀 제안보다 먼저, 둘째 긴급은 복귀 한 단계, 쓰기 실패면 둘 다 남지 않음, 남은 분 0이면 늘리기 확인과 "돌아가기", 제출 시각의 실제 남은 초로 칩을 줄임, 줄인 결과가 1분 미만이면 확인, `budgetDay`가 오늘이 아니면 돌려받을 초를 더하지 않음(R-811~R-815, SC-803, SC-804, SC-806, P2·P9).
- 지우기(`NotchSessionPauseTests`): 도는 중과 멈춘 채 지우면 남은 초를 `budgetDay` 기록에 돌려줌(P4).
- 저장(`MokaCoreTests`의 메모리 구현, `MokaStoreTests`의 GRDB 구현): 긴급 전용 메서드에 실패를 주입하면 새 할 일, 끊긴 할 일 갱신, 체크포인트, 로그가 모두 0건(P7), 스키마 스냅샷은 그대로.
- 시뮬레이터(`SimGoldenTests`, `SimScenarioTests`): 새 golden과 새 오류 픽스처, 기존 golden 전부 바이트 그대로(R-834).
- 실제 판단 호출 0번(SC-807): 시험 번들이 `HTTPDecisionProvider`를 컴파일하지 않음(기존 시험 그대로).

## 2. 튜닝 계약 (자동, CI `tuning-test`)

```
cd tuning && python3 -m pytest
```

기대: [contracts/storage-values-008.md](contracts/storage-values-008.md) §6의 값이 들어감, 기존 시험 그대로.

## 3. 시뮬레이터 직접 실행 (자동)

```
swift run moka-sim run Tests/MokaCoreTests/Fixtures/sim/storage-008-pause.json
swift run moka-sim run Tests/MokaCoreTests/Fixtures/sim/storage-008-urgent.json
```

기대: 각 `.expected.jsonl`과 같은 바이트, 종료 코드 0. 출력에 할 일 제목이 없음(ASCII만).

## 4. 앱 빌드와 앱 시험 (로컬 macOS, CI `app-build`)

```
xcodegen generate && xcodebuild build -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
xcodegen generate && xcodebuild test -scheme Moka -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:MokaAppTests
```

기대(단위별):

- 단위 3: 멈춘 동안 새 판단 질의 0건과 이미 나간 질의의 결과 저장, 1초 타이머가 멈춘 동안 돌고 기다리는 동안 꺼짐, 끝 펼침 한 번, 잠든 동안 끝나도 깨어나 펼침, 멈춘 채 종료·지우기와 도는 중 지우기의 돌려주기, 일시 중지 두 줄이 쓰기 실패 뒤에도 남음, 일시 중지 중 게이트가 열리지 않고 끝날 때 다시 판정, 설정 키 읽기(SC-801).
- 단위 4: 길이 고르기, 직접 입력 오류 문구, 게이트가 열린 동안 일시 중지를 누를 수 없음, 멈춘 화면의 버튼이 "다시 시작"만임, 기본 탭 칸이 다음 일시 중지에 반영됨(US1-10·11).
- 단위 5: 긴급 제출부터 도는 데까지의 흐름, 입력 중 시간 끝이 와도 입력이 닫히지 않음, 복귀 제안.
- 단위 6: 긴급 입력, 늘리기 확인, 복귀 제안 화면.
- 단위 7: `HelpContentTests`가 확정 시안 글자와 같고 항목 수·순서가 그대로임(R-837).

## 5. 화면 스냅샷 (로컬, CI `app-snapshots` 경고만)

data-model §13 이름 전부(라이트·다크). 확정 시안과 나란히 보는 비교 페이지를 `~/Dev/ai-platform/projects/moka/design/pr-<번호>/index.html`에 만든다(ADR-0009).

## 6. 사람 확인 (단위 순서대로)

확인 순서를 적기 전에 그 상태를 지금 빌드에서 만들 수 있는지 먼저 본다. 모든 확인은 그 단위 PR 브랜치의 확인용 빌드로 한다. 하루 경계는 설정 창 "하루 시작 시각"을 지금 시각 바로 뒤로 바꿔 만든다.

| # | 단위 | 확인 | 상태를 만드는 법 | 대응 |
|---|---|---|---|---|
| 6-1 | 4 | 가짜 할 일을 25분으로 시작하고 노치를 펼쳐 "일시 중지"를 누른다. 30분이 골라져 있다. 직접 입력에 181을 적으면 "3시간(180분)까지 정할 수 있어요"가 보이고 멈출 수 없다 | 가짜 할 일 하나 | US1-10 |
| 6-2 | 4 | 직접 입력에 1을 적고 두 줄을 "안 적기"로 넘긴다. 접힌 노치에 남은 일시 중지 시간이 보이고, 펼치면 버튼은 "다시 시작"뿐이다. 1분 뒤 노치가 저절로 펼쳐지고 타이머는 멈춘 채다. "다시 시작"을 누르면 멈춘 자리부터 돈다 | 6-1에 이어서. 실제로 1분 기다린다 | US1-1·3·6 |
| 6-3 | 4 | 멈춘 채 하루 시작 시각을 1분 뒤로 바꾸고 1분 지나 노치를 펼치면 이월 카드부터 보인다 | 6-2처럼 멈춘 상태. 확인 뒤 06:00으로 되돌림 | US1-5, SC-802 |
| 6-4 | 6 | 도는 중 "+긴급"에 가짜 제목과 15분을 넣고 두 줄을 마치면 10초 안에 그 일이 돈다. 완료를 누르면 끊긴 할 일이 시작 전 화면에 다시 뜬다 | 가짜 할 일 하나를 시작한 상태 | US2-1·4, SC-803 |
| 6-5 | 7 | 설정 창 도움말 (1) 노치 설명이 확정 시안과 같다 | 확인용 빌드 | R-837 |
