# Research: 일시 중지와 급한 일 끼워 넣기 (spec 008)

기준 `origin/main` `2629d8c`. 코드 근거는 그 기준의 파일:줄이다.

- **P1~P11**은 사람이 정할 설계 결정이다. 이 문서에는 안과 대가만 적고 추천을 넣지 않는다. 정해지면 절마다 "결정" 줄을 더하고 [data-model.md](data-model.md)와 [contracts/](contracts/)에 반영한다.
- **R12 이후**는 spec과 앞 spec을 근거로 에이전트가 정한 작은 가정이고 PR "가정"에 적는다.

## 지금 코드에서 확인한 사실

- F1. `NotchTimer`는 `empty`·`running`·`expired` 셋이고(`Sources/MokaCore/NotchTimer.swift:16-20`), 모든 이벤트 앞에서 끝 시각이 지난 `running`을 `expired`로 바꾼다(`:49-51`). `NotchSession.timer` 주석은 "타입과 기존 golden은 바꾸지 않는다"다(`Sources/MokaCore/NotchSession.swift:5`).
- F2. `.running`·`.expired`를 직접 다루는 파일은 소스 11개, 시험 18개다. 앱 쪽 자리는 `App/Sources/AppState.swift:2046-2047`(단계 이름), `App/Sources/Views/ExpandedView.swift:132·152`, `App/Sources/Views/CollapsedView.swift:60`이다.
- F3. 시뮬레이터 불변식은 빈 상태 타이머에 `active` 할 일이 있으면 위반으로 본다(`Sources/MokaCore/Sim/SimStorageRunner.swift:88-89`). 출력 `timer_state`는 셋이다(`Sources/MokaCore/Sim/SimOutput.swift:66-76`, `specs/001-notch-timer/contracts/moka-sim-v1.md` "상태와 이벤트"). 튜닝 코드는 `timer_state`를 읽지 않는다(`tuning/` 검색 0건).
- F4. 도는 중 지우기는 돌려주지 않는다. `NotchSession.taskDropped`(`NotchSession.swift:304-310`)는 세션만 비우고, `AppState.dropTasks`(`App/Sources/AppState.swift:620-645`)는 `useBudget`을 부르지 않는다. spec R-807은 멈춘 채 지우면 돌려준다고 정했다.
- F5. 남은 분이 0이면 `QuantumChip.cap`은 칩을 그대로 두고, `extendNeeded`는 nil이다(`Sources/MokaCore/QuantumChip.swift:118-127`). 그대로 쓰면 확인 없이 상한을 넘겨 시작한다.
- F6. 할 일 넣기와 묶음 쓰기는 따로다. `StoreBatch`에는 새 할 일 칸이 없고(`Sources/MokaCore/Storage.swift:13-28`), `insertTask`는 별도 메서드다(`:33`). R-812의 "둘 다 남기지 않음"은 지금 경계로 만들 수 없다.
- F7. `SchedulerMemory.on(today)`는 하루가 바뀌면 값을 새로 만들며 `pickedBy`와 `cursorDay`만 옮긴다(`Sources/MokaCore/Scheduler/SchedulerMemory.swift:30-33`).
- F8. `SessionAssembly`는 상태를 들지 않고(`Sources/MokaCore/SessionAssembly.swift:5`), `Schedule`은 호출마다 호출자가 만든다(`App/Sources/AppState.swift` `schedule(at:)`).
- F9. 1초 tick은 `running`일 때만 돈다(`App/Sources/AppState.swift:2026-2038`). 자동 시작은 한 번 타이머와 시험 창구 `autoStartDue`·`autoStartIfDue()`를 쓴다(`:985-1043`). 깨어나면 `tick()`과 `activate()`를 부른다(`:526-530`).
- F10. 두 줄 입력은 타이머가 도는 중이 아니면 닫힌다(`App/Sources/AppState.swift:111-114`). 멈춘 동안의 두 줄과, 입력 중 시간 끝이 오는 긴급 입력은 이 줄에 걸린다.
- F11. 판단 질의 실행기는 자리가 빌 때마다 다음 질의를 꺼낸다(`App/Sources/AppState.swift` `runQueries`). 멈춘 뒤에도 꺼내지 않게 막아야 R-803을 지킨다.
- F12. 긴급 고정된 할 일은 도는 동안 후보가 아니다. 고정이 고르기에 실제로 쓰이는 길은 멈춘 긴급 할 일이 하루 경계로 대기가 된 경우(R-806)뿐이다.
- F13. `day_budget`은 기록 하나만 저장한다(`Sources/MokaCore/CoreSettings.swift` `readDayBudget`). R-806의 전날 돌려주기는 오늘 답을 쓰기 전에 끝나야 한다.

## 확정할 것

### P1. `NotchTimer`에 멈춤 상태를 넣는 모양 (R-802, R-803, R-834)

- 배경: spec은 타이머에 멈춤이 생긴다고 정했고 모양은 plan에 맡겼다. 지금 주석은 타입을 바꾸지 않는다고 적어 두었다(F1).
- 안과 대가:
  - A. `NotchTimer`에 새 case `paused(title:quantumMin:remainingSeconds:)`를 더한다. 빠뜨린 `switch`를 컴파일러가 잡는다. 대신 공개 타입이 바뀌고, 단위 1에 앱이 컴파일되도록 고치는 줄이 들어가며, 주석도 고친다.
  - B. `NotchTimer`는 그대로 두고 `NotchSession`에 멈춘 작업 시간 칸을 더하며 타이머는 `.empty(draft: nil)`로 둔다. spec 001 타입은 그대로다. 대신 빈 상태와 멈춤이 겹쳐 고르기, 모드, 시뮬레이터 불변식(F3), 화면 `switch`마다 직접 갈라야 하고 빠뜨려도 컴파일러가 잡지 못한다.
  - C. 타이머는 `.running` 그대로 두고 `NotchSession`에 멈춘 시각 칸을 더한다. 화면과 `switch`는 거의 그대로다. 대신 암묵 tick(F1)과 남은 초 계산을 부르는 자리마다 막아야 하고, 하나라도 빠지면 멈춘 동안 시간 끝이 온다.
  - D. `.running`에 연관값 `pausedAt: Date?`를 더한다. 암묵 tick은 한 곳에서 막는다. 대신 `.running(...)` 패턴을 쓰는 소스와 시험을 모두 고치고(F2), 끝 시각이 있는 멈춤이라 spec의 "끝 시각이 없다"와 어긋난다.
- `moka-sim`·golden 영향: 넷 모두 새 이벤트가 없는 시나리오의 출력은 바이트 그대로여야 한다. 출력 `timer_state`의 넷째 값 `paused`는 넷 모두 세션에서 만들어 낼 수 있어, 어느 안이든 계약 덧붙임(승인 항목 4)이다.
- 근거: `Sources/MokaCore/NotchTimer.swift:16-20·49-51`, `Sources/MokaCore/NotchSession.swift:5`, `Sources/MokaCore/Sim/SimStorageRunner.swift:86-92`, `Sources/MokaCore/Sim/SimOutput.swift:66-76`, spec Key Entities "타이머".

### P2. 긴급 칩을 고를 때 남은 분이 0인 경우 (R-811)

- 배경: 끊긴 할 일에서 돌려받을 시간을 더해도 오늘 남은 분이 1분 미만일 때의 처리를 spec이 plan에 넘겼다. 그날 마지막 작업 시간의 끝 무렵에 생긴다. 지금 함수는 이 경우 확인 없이 지나간다(F5).
- 안과 대가:
  - A. 늘리기 확인으로 시작한다. 칩은 설정 기본 작업 시간으로 채운다. 긴급 입력은 늘 된다. 대신 "남은 분이 0이면 늘리기 없음"(spec 005 data-model §11)을 긴급에서만 풀고 확인 문구가 하나 는다.
  - B. "+긴급"을 끄고 이유 한 줄을 보인다. 구현이 가장 작다. 대신 그 구간에는 긴급을 넣을 수 없고, Q12에서 기각한 "남은 분 이하만"과 같은 제약이 남는다.
  - C. 확인 없이 칩만큼 가용 시간을 늘려 시작한다. 입력이 가장 빠르다. 대신 사용자가 모르게 오늘 정한 시간이 바뀌어 spec 005 R-421의 확인 관례와 다르다.
  - D. 입력 화면에서 "더 할래요"로 그날 상한을 풀고 시작한다. 이미 있는 동작을 쓴다. 대신 그날 상한이 통째로 사라져 늘린 만큼만 더 쓰는 R-421과 결과가 다르다.
- 근거: spec R-811·Edge Case "긴급 칩을 고를 때 가용 시간의 남은 분이 0", `Sources/MokaCore/QuantumChip.swift:118-127`, `specs/005-scheduler/data-model.md` §11 "늘리기".

### P3. 일시 중지 두 줄을 적는 동안 하루 경계를 넘기는 경우 (R-802, R-806)

- 배경: 타이머는 "일시 중지"를 누른 순간 멈추지만 체크포인트는 두 줄을 마칠 때 남는다. 그 사이 하루 경계를 넘길 수 있고, 길이를 고르는 동안도 같다. R-802와 R-806만으로는 어느 기록을 남길지 정해지지 않는다.
- 안과 대가:
  - A. 입력을 끝까지 받고, 제출하면 `pause` 체크포인트와 로그 줄을 남긴 뒤 같은 처리에서 R-806대로 `day_end` 빈 체크포인트로 끝낸다. 적은 글을 지키고 두 규칙을 그대로 잇는다. 대신 실제로는 멈춘 적 없는 일시 중지 기록이 하나 남고 체크포인트가 둘이다.
  - B. 입력을 끝까지 받고, 제출하면 `pause` 없이 두 줄을 담은 `day_end` 체크포인트 하나로 끝낸다. 로그 줄은 남기지 않는다. 기록이 깔끔하다. 대신 R-806의 "빈 체크포인트"와 R-815의 줄 규칙에 예외가 생긴다.
  - C. 하루 경계 뒤 첫 활성화에서 입력을 닫고 바로 R-806대로 끝낸다. 규칙이 가장 짧다. 대신 적던 두 줄을 잃는다.
- 함께 정할 것: 하루 경계를 넘긴 뒤 돌아가기(Esc)를 누르면 (가) R-802대로 남은 초부터 이어 돌고 spec 005 R-417처럼 표시만 붙이거나, (나) R-806대로 끝낸다. (가)는 R-802 글자를 지키고, (나)는 멈춘 뒤 하루가 바뀌면 끝낸다는 규칙을 예외 없이 지킨다.
- 근거: spec R-802·R-806, Edge Case "두 줄을 적는 동안", `App/Sources/AppState.swift:1190-1200`(펼침마다 활성화).

### P4. 도는 중 할 일을 설정 창에서 지울 때 남은 초를 돌려줄지 (R-805, R-807)

- 배경: 지금 도는 중에 지우면 돌려주지 않는데, spec은 멈춘 채 지우면 돌려준다고 정했다(F4). 같은 지우기의 결과가 갈린다.
- 안과 대가:
  - A. 그대로 둔다. 도는 중은 돌려주지 않고 멈춘 채는 돌려준다. 앞 spec을 건드리지 않는다. 대신 도는 중에 지운 시간은 그날 쓴 시간에 남아 오늘 끝이 일찍 올 수 있다.
  - B. 도는 중 지우기도 남은 초를 돌려준다. 두 길이 같아지고 SC-806과 맞는다. 대신 `taskDropped`와 `dropTasks`를 고쳐 spec 005 동작이 바뀌고, 그 줄에 대체 표기가 더 붙는다.
  - C. 멈춘 채 지워도 돌려주지 않는다. 두 길이 같아지고 코드가 가장 작다. 대신 이미 정한 R-805·R-807·SC-806 글자를 고쳐야 한다.
  - D. 이 spec에서는 A로 두고 B를 별도 Issue로 넘긴다. 이 spec 범위가 그대로다. 대신 불일치가 그 Issue까지 남고 새 Issue가 하나 는다.
- 근거: `Sources/MokaCore/NotchSession.swift:296-310`, `App/Sources/AppState.swift:620-645`, `specs/005-scheduler/data-model.md` §11, spec R-807.

### P5. 긴급 고정과 복귀 상태를 둘 곳 (R-813, R-814)

- 배경: 고정된 할 일과 끊긴 할 일은 메모리에만 둔다. 고르기, 후보 순서, 버튼 뒤 복귀 제안, 시뮬레이터 출력이 함께 읽고, 하루 경계를 넘어도 남아야 한다.
- 안과 대가:
  - A. `SchedulerMemory`에 칸 둘을 더한다. 버튼 함수와 `SchedulerPick`이 이미 들고 다니는 값이다. 대신 `on(today)`가 값을 새로 만들어(F7) 옮겨 적어야 하고, "복귀 제안은 스케줄러 메모리를 바꾸지 않는다"(R-814)는 말과 같은 값 안에 섞인다.
  - B. `NotchSession`에 새 칸 `urgent`를 더한다. 스케줄러 메모리는 그대로이고 세션 수명과 같다. 대신 세션을 새로 만드는 자리(`NotchSession.swift:306·437`)마다 옮겨야 하고, 고르기에는 입력 칸으로 넘겨야 한다.
  - C. `SessionAssembly.Schedule`에 둔다. 조립 순서 한 곳에서 다룬다. 대신 `Schedule`은 호출마다 만드는 값이라(F8) 앱과 시뮬레이터가 상태를 따로 들어야 하고, 이월·가용 시간이 꺼진 시나리오에는 없다.
- 근거: `Sources/MokaCore/Scheduler/SchedulerMemory.swift:30-33`, `Sources/MokaCore/NotchSession.swift:306·437`, `Sources/MokaCore/SessionAssembly.swift:5·9-20`, spec R-813·R-814.

### P6. 일시 중지 끝 시각을 재는 타이머와 주입 시계 (R-803, R-804, R-835)

- 배경: 정한 길이가 끝나면 노치를 펼쳐야 한다. 지금 1초 tick은 도는 중에만 돌고, 잠든 동안에는 어떤 타이머도 돌지 않는다(F9). 모든 안에서 시각은 주입한 `MokaClock`으로 읽고 깨어날 때 다시 판정한다.
- 안과 대가:
  - A. 1초 타이머 하나를 멈춘 동안에도 돌려 표시와 끝 판정을 함께 한다. 길이 하나이고 시험은 `tick()`만 부르면 된다. 대신 "내일 아침까지"처럼 몇 시간 동안 1초 타이머가 돈다.
  - B. 끝 판정은 한 번 타이머(자동 시작과 같은 무늬, `pauseEndDue`·`pauseEndIfDue()`)로 하고 표시는 1초 타이머로 한다. 끝 시각이 정확하고 시험 창구가 이미 있는 무늬다. 대신 타이머가 둘이고 다시 거는 길이 는다.
  - C. 끝 판정은 한 번 타이머로 하고 표시는 1분마다 갱신한다. 오래 멈출 때 깨어나는 횟수가 가장 적다. 대신 접힌 노치에 초를 보일 수 없어 시안 글자가 분 단위로 바뀌고, 타이머는 여전히 둘이다.
- 근거: `App/Sources/AppState.swift:526-530·985-1043·2026-2038`, spec R-803·R-804, ADR-0003(주입한 시계).

### P7. 긴급 입력을 한 번에 쓰는 저장 경계 (R-812)

- 배경: 긴급 할 일 넣기와 끊긴 할 일 갱신은 둘 다 되거나 둘 다 남지 않아야 하는데 지금 경계로는 묶을 수 없다(F6). spec에 없던 모듈 경계 변경이라 승인 항목이다.
- 안과 대가:
  - A. `TaskRepository`에 긴급 전용 메서드 하나를 더한다(새 할 일과 묶음을 한 트랜잭션으로 쓰고 새 할 일을 돌려줌). spec 005 Q1-B의 `applyCarryJudgment`와 같은 무늬다. 대신 GRDB와 메모리 구현에 메서드가 하나씩 는다.
  - B. `StoreBatch`에 새 할 일 칸을 더하고 `apply`가 새 할 일을 돌려주게 한다. 일반적인 길이 된다. 대신 `apply` 서명이 바뀌어 모든 호출 자리와 저장 계약 시험을 고친다.
  - C. 경계를 바꾸지 않고 넣기 → 묶음 쓰기 순서로 쓰고 실패하면 넣은 할 일을 버림으로 바꾼다. 승인 항목이 없다. 대신 버림 쓰기도 실패할 수 있고, 성공해도 버린 줄이 남아 R-812 글자와 다르다.
- 근거: `Sources/MokaCore/Storage.swift:13-44`, spec R-812, `specs/005-scheduler/research.md` Q1.

### P8. `moka-sim`의 일시 중지 입력 모양 (R-834, 승인 항목 4)

- 배경: 앱에서는 누름, 길이 고름, 두 줄 제출이 서로 다른 시각이고 돌아가기도 있다. 시나리오 형식은 공개 계약이라 한 번 정하면 바꾸기 어렵다.
- 안과 대가:
  - A. 이벤트 하나 `pause`(길이, 두 줄 또는 안 적기). 계약이 가장 작다. 대신 누른 시각과 제출 시각이 같아져 돌아가기와 P3 경우를 시뮬레이터로 볼 수 없고 단위 시험에만 남는다.
  - B. 이벤트 셋 `pause_begin`·`pause_commit`·`pause_cancel`. 앱 흐름을 그대로 재현한다. 대신 계약 표면이 가장 크고 단계 오류 픽스처가 는다.
  - C. 이벤트 하나 `pause`에 필드 `pressed_at`을 더한다. 줄 수가 적고 두 시각을 본다. 대신 이벤트 `at`이 줄어들지 않는다는 규칙 밖의 시각이 생기고, 돌아가기는 볼 수 없다.
- 근거: spec R-834, `specs/001-notch-timer/contracts/moka-sim-v1.md` "입력", `specs/005-scheduler/contracts/moka-sim-v1-additions-005.md`.

### P9. 긴급 입력 동안 줄어드는 돌려받을 시간 (R-811, R-812, SC-806)

- 배경: 긴급 입력과 두 줄을 적는 동안 끊길 할 일의 타이머는 계속 돈다. 12분 돌려받을 때 12분 칩을 고르고 두 줄에 1분을 쓰면 제출 때 1분이 모자라 쓴 시간이 가용 시간을 넘는다. spec은 칩을 고르는 때만 다룬다.
- 안과 대가:
  - A. 제출 때 모자란 만큼 확인 없이 늘린다. 흐름이 끊기지 않고 불변식을 지킨다. 대신 묻지 않고 가용 시간이 조금 늘어난다(`extended_min`에는 남는다).
  - B. 제출 때 칩을 실제 남은 분으로 줄인다. 가용 시간이 그대로다. 대신 고른 칩과 다른 길이로 돈다.
  - C. "+긴급"을 누른 순간의 남은 초로 돌려줄 값을 정한다. 셈이 고정돼 모자람이 생기지 않는다. 대신 입력 동안 실제로 돈 시간이 쓴 시간에서 빠지고, "입력 중 타이머가 끝나면 돌려줄 시간이 없다"는 Edge Case와 어긋난다.
  - D. 제출 때 모자라면 늘리기 확인을 한 번 더 보인다. 사용자가 늘 안다. 대신 단계가 늘어 10초 기준(R-812)에 불리하다.
- 근거: spec R-811·R-812·SC-806, Edge Case "긴급 입력 중 원래 타이머가 끝남", `Sources/MokaCore/Scheduler/DayBudget.swift`(`refundSeconds`).

### P10. 일시 중지 직접 입력 범위 상수 (R-801, R-808)

- 배경: spec Assumptions가 spec 001 범위 상수를 같이 쓸지를 plan에 맡겼다. 값은 지금 둘 다 1~180이다.
- 안과 대가:
  - A. `Defaults.quantumMinRange`를 같이 쓴다. 값이 한 곳이고 오류 문구를 그대로 쓴다. 대신 작업 시간 범위를 바꾸면 일시 중지 범위도 함께 바뀐다.
  - B. `Defaults.pauseMinRange = 1...180`을 새로 둔다. 따로 바꿀 수 있다. 대신 값이 둘이 되고, 범위가 갈리면 "작업 시간 칩과 같은 문구"(R-801)를 다시 정해야 한다.
- 근거: spec R-801·Assumptions 승인 항목, `Sources/MokaCore/Defaults.swift:5`, `Sources/MokaCore/QuantumChip.swift:83-93`.

### P11. 구체화 게이트가 열린 초안에서 일시 중지 (R-801, R-803)

- 배경: 일시 중지 중에는 게이트가 돌지 않는다고 정했지만, 게이트가 묻거나 확인하는 중에 "일시 중지"를 누를 수 있는지는 정하지 않았다.
- 안과 대가:
  - A. 게이트가 열린 동안 "일시 중지"를 숨긴다. 상태가 늘지 않는다. 대신 자리를 뜨기 전에 게이트에 답하거나 건너뛰어야 한다.
  - B. 보이고, 누르면 게이트를 닫았다가 끝난 뒤 처음부터 다시 묻는다. 언제든 멈출 수 있다. 대신 적던 답을 잃고 제출 횟수를 어떻게 셀지 정해야 한다.
  - C. 보이고, 누르면 게이트 단계와 적던 답을 그대로 얼렸다가 끝난 뒤 복원한다. 잃는 것이 없다. 대신 확인 중에 도착한 판단 결과를 처리하는 분기가 늘어난다.
- 근거: spec R-803, Edge Case "일시 중지 끝과 판단 결과 기다림", `App/Sources/AppState.swift`(`gatePhase`), `App/Sources/Views/ExpandedView.swift:171-173`.

## 에이전트가 정한 작은 가정 (PR "가정")

### R12. 멈춘 남은 초의 정밀도

`endsAt − 누른 시각`을 소수 초 그대로 들고, 화면은 올림(`NotchTimer.remainingSeconds` 무늬), 돌려주기는 내림(`DayBudget.refundSeconds` 무늬)으로 쓴다. 정수로 먼저 자르면 이어 돌 때마다 1초 안쪽 오차가 쌓인다.

### R13. 이어 돌 때 시작 시각을 옮긴다

이어 돌 때 끝 시각은 "누른 시각 + 남은 초"이고, 시작 시각은 "끝 시각 − 고른 분"으로 옮긴다. 그러면 경과 분 계산(`Checkpoint.elapsedMinutes`)과 남은 초 상한을 바꾸지 않아도 멈춘 시간이 빠진다.

### R14. "다시 시작" 쓰기가 실패할 때

`resume` 로그 줄 쓰기가 실패하면 이어 돌지 않고 멈춘 채 다시 해 달라는 한 줄을 보인다. R-802의 쓰기 실패 규칙과 같게 맞췄다.

### R15. 기본 작업 시간을 일시 중지 동안 바꿔도 초안 칩은 그대로

R-804의 "같은 칩 값으로 돌아온다"가 spec 001 R-013(기본값을 따르는 칩)보다 앞선다.

### R16. 긴급 할 일을 설정 창에서 지우면

고정을 풀고 복귀 제안 없이 스케줄러가 고른다. 미루기·바꾸기와 같게 맞췄다.

### R17. 일시 중지 끝의 활성화

이미 펼쳐져 있으면 `updateExpansion`이 활성화를 부르지 않으므로(`App/Sources/AppState.swift:1190-1200`) 길이가 끝날 때 활성화를 직접 부른다. R-804의 "이 펼침은 활성화로 본다"를 지키기 위해서다.

### R18. 시뮬레이터 켜는 법

새 이벤트가 하나라도 있으면 spec 005 켜짐(이월·가용 시간)도 함께 켠다. R-834가 노치 모드와 쓴 시간 출력을 요구하기 때문이다. spec 005 Q3-C와 같은 무늬다.

### R19. 코드 이름

`PauseState`, `PauseOrigin`, `FrozenRun`, `PauseLength`, `PauseText`, `UrgentInput`. 이름은 구현 PR에서 GLOSSARY에 맞춰 고칠 수 있다.
