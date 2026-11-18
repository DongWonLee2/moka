# Data Model: 일시 중지와 급한 일 끼워 넣기 (spec 008)

규칙, 값, 모양의 원본이다. 이름은 [GLOSSARY.md](../../GLOSSARY.md)를 따르고, 새 코드 이름은 이 문서가 처음 정한다(research R19). 기준 `origin/main` `2629d8c`. `[Pn]` 표시는 [research.md](research.md)의 확정할 것이고, 정해지기 전에는 그 자리의 모양을 구현하지 않는다.

## §1 일시 중지 상태 (R-801~R-807)

메모리에만 둔다(R-807). 저장하지 않는다.

```swift
enum PauseLength: Equatable, Sendable {
    case minutes(Int)     // 1~180 [P10]
    case untilMorning     // "내일 아침까지"
}

enum PauseOrigin: Equatable, Sendable {
    case run(FrozenRun)   // 도는 중에서 멈춤
    case draft            // 초안에서 멈춤. 초안 값은 타이머에 그대로 있다
}

struct FrozenRun: Equatable, Sendable {
    var taskID: TaskID
    var remaining: TimeInterval  // 누른 시각의 끝 시각까지 남은 초. 멈춘 동안 줄지 않는다(R12)
    var quantumMin: Int
    var budgetDay: LocalDay?     // 그 작업 시간을 시작한 하루
}

enum PauseStage: Equatable, Sendable {
    case choosing                   // 길이를 고르는 중
    case notes(PauseLength)         // 두 줄을 적는 중(도는 중에서 멈췄을 때만)
    case holding(endsAt: Date)      // 멈춤. now ≥ endsAt이면 길이가 끝나 기다리는 중
}

struct PauseState: Equatable, Sendable {
    var origin: PauseOrigin
    var stage: PauseStage
    var pausedDay: LocalDay         // 누른 때의 하루(R-806 판정)
}
```

- 타이머 쪽 멈춤 표현은 `[P1]`이다. 어느 안이든 `FrozenRun`의 값을 들고 끝 시각이 없다.
- 끝 시각: `.minutes(m)`은 두 줄을 마친 시각 + m분, 초안이면 길이를 고른 시각 + m분이다. `.untilMorning`은 `DayBoundary.start(of: 그때의 하루 + 1일)`이다. 05:00에 고르면 그 시각의 하루는 전날이라 그날 06:00에 끝난다(US1-12).
- 남은 일시 중지 시간 = `endsAt − now`. 0 이하이면 숫자를 내지 않는다(R-803).

## §2 전이 (R-801~R-804, R-806)

| 지금 | 입력 | 결과 | 쓰기 |
|---|---|---|---|
| 도는 중 | "일시 중지" | `run` + `choosing`, 타이머 멈춤 | 없음 |
| 초안 | "일시 중지" | `draft` + `choosing` | 없음 |
| `run` + `choosing` | 길이 고름 | `notes(길이)` | 없음 |
| `draft` + `choosing` | 길이 고름 | `holding(끝 시각)` | 없음 |
| `run` + `choosing`·`notes` | 돌아가기(Esc) | 도는 중, 끝 시각 = 지금 + 남은 초 | 없음 |
| `draft` + `choosing` | 돌아가기(Esc) | 초안 그대로 | 없음 |
| `run` + `notes` | 등록·안 적기 | `holding(끝 시각)` | 체크포인트 `pause`, 로그 줄 `pause`, 첫 행동(§5) |
| `run` + `holding` | "다시 시작" | 도는 중, 끝 시각 = 지금 + 남은 초 | 로그 줄 `resume` |
| `draft` + `holding` | "다시 시작" | 일시 중지 끝, §6 순서로 화면 | 없음 |
| `draft` + `holding` | 길이 끝남 | 일시 중지 끝, 노치 펼침, §6 순서로 화면, 첫 초안은 입력 전 자동 시작 없음 | 없음 |
| `run` + `holding` | 길이 끝남 | 그대로 기다림, 노치 펼침 | 없음 |
| 멈춘 상태 | 하루 경계 뒤 첫 활성화, "다시 시작" | §4 | §4 |

- 두 줄이나 길이를 고르는 동안 하루 경계를 넘긴 경우는 `[P3]`이다.
- 쓰기가 실패하면 `run` + `notes`는 아무것도 남기지 않고 남은 초부터 이어 돌며 다시 해 달라는 한 줄을 보인다(R-802). "다시 시작"의 쓰기 실패는 research R14다.
- 시작 전 화면에서 구체화 게이트가 열려 있을 때의 "일시 중지"는 `[P11]`이다.

## §3 남은 초, 경과 분, 쓴 시간 (R-802, R-805, R-833)

- 돈 초 = `quantumMin × 60 − remaining`. `pause`, `quit`, `day_end` 체크포인트의 경과 분은 `floor(돈 초 / 60)`이고 `0...quantumMin`으로 자른다.
- 이어 돌 때 끝 시각 = 누른 시각 + `remaining`, 시작 시각 = 끝 시각 − `quantumMin × 60`이다(research R13). 그 뒤 끝나는 체크포인트는 기존 식 그대로 멈춘 시간을 뺀 분이 된다.
- 멈춘 동안과 이어 돌 때 쓴 시간은 더하지도 빼지도 않는다.

| 끝나는 길 | 돌려줄 초 | 체크포인트 | 로그 줄 |
|---|---|---|---|
| 이어 돈 뒤 완료·미루기·바꾸기 | `endsAt − now`(기존) | 기존 | 기존 |
| 이어 돈 뒤 긴급으로 끊김 | `endsAt − now` | `urgent` | `urgent` |
| 이어 돈 뒤 정상 종료 | `endsAt − now`(기존) | `quit`(기존) | 없음 |
| 멈춘 채 정상 종료 | `floor(remaining)` | `quit`, 빈 두 줄 | 없음 |
| 멈춘 채 하루 경계 | `floor(remaining)`을 `budgetDay` 기록에 | `day_end`, 빈 두 줄 | 없음 |
| 멈춘 채 설정 창에서 지움 | `floor(remaining)`을 `budgetDay` 기록에 | 없음 | 없음 |
| 도는 중 설정 창에서 지움 | `[P4]` | 없음 | 없음 |
| 멈춘 채 잠자기 | 없음(이어짐) | 없음 | 없음 |
| 비정상 종료 | 돌려받지 못함 | 없음 | 없음 |

## §4 멈춘 채 하루 경계를 넘김 (R-806)

판정: 활성화와 "다시 시작"에서 `today != pausedDay`이면 이어 돌지 않고 아래를 한다. 순서를 못박는다.

1. 도는 중에서 멈췄으면 할 일을 대기로 돌리고 `day_end` 빈 체크포인트를 쓴다(한 묶음). 비어 있는 다음 줄은 첫 행동을 덮지 않는다.
2. 저장한 남은 초를 `budgetDay` 기록에 돌려준다. `day_budget`은 기록 하나뿐이라 오늘 답을 쓰기 전에 끝나야 한다(research F13).
3. 일시 중지를 푼다.
4. `SessionAssembly.activate`의 차례를 그대로 돈다: 반복 리셋 → 이월 판정 → 모드 → 고르기.

1~3은 `SessionAssembly.activate` 안에서 이월 판정보다 먼저 한다. `Activated`는 돌려줄 쓴 시간을 함께 돌려준다. "다시 시작"에서 이 길로 끝나면 `resume` 줄을 남기지 않는다(R-815).

## §5 첫 행동과 판단 질의 (R-802, R-803)

- `pause` 체크포인트의 다음 줄이 비어 있지 않으면 첫 행동을 바꾼다(`takeNextNote` 그대로). 그 판단 질의는 일시 중지가 끝날 때 보낸다.
- 일시 중지 동안 질의 실행기는 새 질의를 꺼내지 않는다. 이미 나간 질의의 결과는 저장하고 화면을 바꾸지 않는다(research F11).
- 끝나는 때: `run`은 "다시 시작"으로 이어 돌 때와 §4, `draft`는 일시 중지가 끝날 때다.

## §6 노치 모드 (R-831)

`NotchMode`에 `.paused`를 더한다. 순서:

| 순서 | 조건 | 모드 | 고르기 |
|---|---|---|---|
| 1 | 앱 DB를 열 수 없음 | `.storageUnavailable` | 없음 |
| 2 | 도는 중(멈춤 제외) 또는 시간 끝 | `.session` | 없음 |
| 3 | 일시 중지 중 | `.paused` | 없음 |
| 4 | 카드에 오를 할 일이 있음 | `.carryCard` | 없음 |
| 5 | 오늘 기록이 없음 | `.askBudget` | 없음 |
| 6 | 오늘 끝 | `.dayEnd` | 없음 |
| 7 | 그 밖 | `.session` | 빈 상태면 고르기 |

- `.paused.clearsDraft`는 거짓이다. 초안에서 멈춘 일시 중지가 끝날 때 이 표로 다시 보고 7일 때만 같은 초안을 띄운다. 그 할 일이 대기가 아니면 스케줄러가 고른다.
- 일시 중지 중 빠른 입력은 저장만 하고 초안을 바꾸지 않는다(`NotchSession.addedTask`가 멈춘 동안 그대로 돌아가게 막는다).
- 다시 띄운 초안의 `pickedBy`는 처음 떴을 때 값 그대로이고 스케줄러 메모리를 바꾸지 않는다.

## §7 자동 시작 (R-832)

`AutoStart`에 조건 하나를 더한다: `awaitsFirstInput`이면 시작하지 않는다.

- 참이 되는 때: 초안에서 멈춘 일시 중지가 길이가 끝나 돌아왔을 때, 앱을 다시 켠 뒤 첫 초안.
- 거짓이 되는 때: 칩, 버튼, 키 입력(`noteInput`). "다시 시작"을 눌러 끝낸 초안은 그 누름이 입력이라 참이 되지 않는다.

## §8 긴급 입력 (R-811, R-812)

입력 값 `UrgentInput { title, chipMin, notes, extend }`. 제출 순서:

1. 제목 규칙(spec 002 R-101)과 칩 범위를 본다.
2. 돌려줄 초 = 도는 중이면 `endsAt − now`, 입력 중 시간 끝이 왔으면 0.
3. 칩 상한: 남은 분 = 오늘 기록의 남은 분 + 돌려받을 분. 남은 분이 0이면 `[P2]`, 입력 동안 돌려받을 시간이 줄어 제출 때 모자라면 `[P9]`이다.
4. 한 번에 쓴다 `[P7]`: 새 할 일(진행 중, 마감이 없으면 오늘), 끊긴 할 일(대기, 미룬 횟수 그대로, 첫 행동), 체크포인트 `urgent`, 로그 줄 `urgent`.
5. `day_budget`을 한 번 쓴다: 늘린 분 + 끊긴 할 일 돌려주기 + 긴급 칩 더하기. 쓰기가 실패하면 로그 한 줄만 남긴다(spec 005 data-model §9 끝).
6. `last_start_day`를 쓴다.
7. 세션을 긴급 할 일로 바꾼다. `pickedBy = urgent_pin_v1`.

- 끊긴 할 일의 `budgetDay`가 오늘과 다르면 돌려주기는 그 하루 기록에만 하고, 오늘 기록이 없으면 긴급 칩은 어느 하루에도 더하지 않는다.
- 입력 중 시간 끝이 와도 입력을 닫지 않는다. 지금은 두 줄 입력이 도는 중이 아니면 닫히므로(research F10) 긴급 입력은 따로 다룬다. 체크포인트 경과 분은 고른 분이다.

## §9 긴급 고정과 복귀 제안 (R-813, R-814)

값 둘: 고정된 할 일(`pinnedTaskID`), 끊긴 할 일(`returnTaskID`). 둘 곳은 `[P5]`이고 하루 경계를 넘어도 남는다.

| 사건 | 고정 | 끊긴 할 일 |
|---|---|---|
| 긴급 시작 | 새 긴급 할 일 | 지금 끊은 할 일(앞 값을 덮음, 한 단계만) |
| 긴급 할 일 완료 | 풀림 | 남김(아래 띄움에서 씀) |
| 긴급 할 일 미루기·바꾸기·지우기 | 풀림 | 지움 |
| 일시 중지, 다시 시작, "N분 더" | 그대로 | 그대로 |
| 앱 재시작 | 풀림 | 지움 |

- 고르기: 고정된 할 일이 후보이면 워밍업과 가중 순환보다 먼저 고른다. 바꾸기·미루기 직후 빼는 규칙(R-408)은 그대로다. 이름은 `urgent_pin_v1`이다.
- 후보 순서: `PriorityOrder.order`가 고정된 할 일을 맨 앞에 둔다. 할 일 탭 순위와 "다음"도 이 순서다.
- 띄움: 모드 판정(§6)이 7이고 끊긴 할 일이 대기이면 고르기 대신 그 할 일을 초안으로 띄운다. 이름은 `urgent_return_v1`이고 스케줄러 메모리(몫, 최근 고르기)를 바꾸지 않는다. 대기가 아니면 지우고 스케줄러가 고른다. 오늘 끝이나 이월 카드가 먼저이면 7이 될 때까지 남겨 둔다("더 할래요" 뒤 포함).
- 앱에서 고정이 고르기에 쓰이는 길은 멈춘 긴급 할 일이 하루 경계로 대기가 된 경우뿐이다(research F12). 시험은 이 길로 한다.

## §10 행동 로그 값 (승인 항목 2·3)

`UserAction`에 더함: `pause = "pause"`, `resume = "resume"`, `urgent = "urgent"`.

`SchedulerChoice`에 더함: `urgentPinV1 = "urgent_pin_v1"`, `urgentReturnV1 = "urgent_return_v1"`.

| 줄 | 할 일 | `scheduler_choice` | 생기는 때 |
|---|---|---|---|
| `pause` | 멈춘 할 일 | 그 할 일의 `pickedBy` | 등록·안 적기(§2) |
| `resume` | 이어 돈 할 일 | 그 할 일의 `pickedBy` | "다시 시작"으로 이어 돌 때 |
| `urgent` | 끊긴 할 일 | 그 할 일의 `pickedBy` | 긴급 제출 |

줄을 남기지 않는 것: 긴급 할 일 만들기, 초안 일시 중지와 그 "다시 시작", 하루 경계로 끝나 이어 돌지 않은 "다시 시작". 판단 칸은 spec 003 R-212다. `ValueTypeTests`의 `allCases` 단언은 값을 끝에 더하는 것으로 고친다.

## §11 설정 키와 `Defaults` (승인 항목 5·6)

| 설정 키 | 값 | 기본 | 쓰는 곳 |
|---|---|---|---|
| `default_pause_min` | 정수 분 1~180 | 30 | 기본 탭, 길이 고르기 처음 값 |

읽기 실패와 형식 오류는 기본값으로 본다(`CoreSettings` 무늬). 기본값이 선택지에 없으면 직접 입력 칸에 채운다.

| `Defaults` 이름 | 값 | 근거 |
|---|---|---|
| `pauseMin` | 30 | R-801, R-808 |
| `pausePresets` | `[30, 60, 120]` | R-801 |
| 직접 입력 범위 | 1...180 `[P10]` | R-801 |

## §12 코드 영향 (단위 1·2의 고칠 자리)

| 자리 | 바뀌는 것 |
|---|---|
| `NotchTimer`, `NotchSession` | 멈춤 표현 `[P1]`, 일시 중지·다시 시작·긴급 함수, `edited`·`lifecycleCheckpoint`·`lifecycleRefund`·`nextMark`·`addedTask`의 멈춤 분기 |
| `NotchMode`, `SessionAssembly` | `.paused`, 활성화의 §4, 복귀 띄움 |
| `SchedulerPick`, `PriorityOrder` | 긴급 고정 |
| `AutoStart`, `NotchStatus`, `DecisionLog`, `CoreSettings`, `Defaults` | §7, 상태 글자, §10, §11 |
| `Storage`, `MokaStore` | `[P7]` |
| `Sim/*` | [contracts/moka-sim-v1-additions-008.md](contracts/moka-sim-v1-additions-008.md) |
| `AppState`, `ExpandedView`, `CollapsedView`, `GuideIllustration` | 단위 1은 컴파일에 필요한 줄만, 동작은 단위 3~6 |

## §13 화면 값과 스냅샷 이름

화면 글자는 확정 시안 `~/Dev/ai-platform/projects/moka/design/008-mockup.html`(저장소 밖)을 그대로 쓴다. 값을 끼워 넣는 글자는 MokaCore(`PauseText`, `NotchStatus`)에, 고정 글자는 뷰 상수(`NotchText`)에 둔다. 도움말은 화면 상수에서 인용한다(spec 007 R-705).

스냅샷 이름(라이트·다크): `test_R801_pauseButtons`, `test_R801_pauseLength`, `test_R801_pauseLengthCustomInvalid`, `test_R802_pauseNotes`, `test_R803_pausedExpanded`, `test_R803_pausedCollapsed`, `test_R804_waitingExpanded`, `test_R804_waitingCollapsed`, `test_R803_pausedDraft`, `test_R832_returnedDraft`, `test_R811_urgentInput`, `test_R812_urgentNotes`, `test_R811_urgentExtend`, `test_R814_returnProposal`, `test_R808_basicTabPause`.
