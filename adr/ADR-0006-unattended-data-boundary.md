# ADR-0006: 무인 실행의 실제 데이터 경계와 알려진 구멍

- 상태: Accepted
- 작성일 / 사람 승인일: 2026-10-28 / 2026-10-28
- 결정 책임자: 저장소 소유자
- 관련 Spec/R-ID: 헌법 VIII(실제 API·실제 데이터), FR-18(튜닝 스크립트), ADR-0004(DB 경로), ADR-0005(Sandbox 끔)
- 사용한 외부 근거: Claude Code 권한 문서(code.claude.com/docs/en/permissions), Claude Code sandboxing 문서(code.claude.com/docs/en/sandboxing)

## 맥락

저장소는 공개이고, 밤 무인 실행은 사람 검토 없이 브랜치를 push하고 초안 PR을 남긴다. 사용자는 11월 초부터 실제 할 일을 앱 DB(`~/Library/Application Support/dev.dongwon.moka/`)에 쌓는다. 라벨셋은 저장소 밖(`~/Dev/ai-platform/projects/moka/`)에 있다. 에이전트가 이 데이터를 읽어 PR·커밋·픽스처에 옮기면 되돌릴 수 없는 공개가 된다.

권한 문서: Read·Edit deny 규칙은 내장 파일 도구와 Claude Code가 알아보는 Bash 파일 명령(`cat`, `head` 등)에 적용되고, 파일을 스스로 여는 Python·Node 같은 하위 프로세스에는 적용되지 않는다. Bash 규칙은 문자열 패턴이라 보안 경계가 아니다.

Sandboxing 문서: sandbox를 켜면 하위 프로세스까지 막고 권한 규칙의 경로가 sandbox 설정에 합쳐진다. 다만 macOS에서 SSH 원격 `git push`가 sandbox 안에서 실패하고, `gh`는 Seatbelt에서 TLS 검증에 실패할 수 있으며, `docker`는 sandbox와 호환되지 않는다.

## 평가 기준

1. 밤 실행이 멈추지 않는가 2. 실제 데이터가 공개 저장소로 갈 경로를 줄이는가 3. 막지 못하는 것을 숨기지 않는가 4. 비용

## 대안

| 대안 | 장점 | 단점·위험 | 근거·실험 |
|---|---|---|---|
| A. 구조 분리 + Bash deny(실수 방지) + 실패 시험 + 알려진 구멍 기록, sandbox는 낮에 따로 시험 | 밤 실행이 멈추지 않음, 싸다 | 하위 프로세스가 경로를 조립하면 권한 규칙으로 못 막음 | 아래 실패 시험 |
| B. Claude Code sandbox를 지금 켬 | 하위 프로세스까지 막음 | `git push`·`gh`·`docker`가 실패해 첫 밤 실행이 멈출 위험, `excludedCommands`로 빼면 그 명령은 다시 보호 밖 | sandboxing 문서 |
| C. 아무것도 안 함 | 비용 없음 | Read deny만 있어 `cat`·`sqlite3`가 통과 | 권한 문서 |

## Agent의 추천과 근거

A를 추천한다(추천안 토론 3:0).
- 구조 분리: 테스트는 메모리 DB, `moka-sim`과 튜닝 스크립트는 DB 경로 인자를 필수로 하고 기본값을 두지 않는다. 튜닝 스크립트는 `~/Library` 아래 경로를 `--allow-real-data` 없이 거부하고, 이 동작을 pytest로 고정한다(튜닝 스크립트를 만드는 Issue에서).
- 실수 방지(`.claude/settings.json` deny): 앱 데이터 경로의 Read·Edit, 앱 데이터 경로가 들어간 Bash(공백·`\ ` 두 표기), 라벨셋 경로 `*ai-platform/projects/moka/labels*`, 사람 전용 인자 `*--allow-real-data*`. 라벨셋 패턴은 저장소의 `labels.example.csv`를 막지 않도록 좁혔다.
- Claude Code sandbox는 `ai-found` Issue로 두고, 실제 데이터가 쌓이기 전(11/2 낮 세션)에 사람이 있을 때 시험한 뒤 켤지 정한다.

## 사람의 최종 결정과 실제 판단 이유

Agent 추천안 채택. 판단 이유: 사용자 위임(토론 채택안 "전부 승인", 2026-10-28)

## 포기하는 것·운영 영향 (알려진 구멍)

- 경로 문자열을 나눠 조립하는 Python·Node 등 하위 프로세스는 권한 규칙으로 막지 못한다. 2026-10-28 실패 시험에서 이 시도는 권한 규칙이 아니라 auto 모드 분류기가 막았다. 분류기는 보장된 경계가 아니다.
- `Bash(*Application Support/dev.dongwon.moka*)`는 그 경로가 들어간 진단 명령(로그 조회 등)도 막는다.
- 진짜 경계는 sandbox(미적용)와 main 보호(사람이 병합)다. PR 리뷰어는 diff·본문·픽스처에 실제 데이터가 없는지 본다.
- 되돌리기: 쉬움(설정 파일).

## 결정 검증

실패 시험(2026-10-28, 앱 데이터 폴더에 파일을 만들지 않고 권한 단계에서 막히는지 확인):

| 시도 | 결과 | 막은 층 |
|---|---|---|
| Read 도구로 `…/dev.dongwon.moka/moka.sqlite` | 막힘 | Read deny |
| `cat "<경로>"` | 막힘 | Bash deny |
| `ls -d …/Application\ Support/dev.dongwon.moka` | 막힘 | Bash deny(`\ ` 표기) |
| `sqlite3 "<경로>" .tables` | 막힘 | Bash deny |
| `--allow-real-data`가 든 명령 | 막힘 | Bash deny |
| 경로를 조립한 `python3 -c` | 막힘 | auto 모드 분류기(권한 규칙 아님) |

- 재검토 트리거: sandbox 시험 결과(11/2 낮), 실제 데이터가 필요한 Issue가 생김(그 전에 sandbox `denyRead` 하네스 PR이 먼저), 무인 실행이 deny 때문에 정상 작업에서 멈춤.
