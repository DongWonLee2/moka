# ADR-0013: macOS 앱 시험 번들만 HTTP 판단 공급자를 컴파일해 가짜 URLProtocol로 연결부를 시험한다 (ADR-0001·ADR-0011 일부를 좁힘)

- 상태: Proposed
- 작성일 / 사람 승인일: 2026-11-17 / 미정. 이 문서는 PR 병합으로 확정한다
- 결정 책임자: 저장소 소유자
- 관련 Spec/R-ID: spec 003 SC-207, spec 006 R-606·R-618, 헌법 VIII, ADR-0001, ADR-0011, Issue #125
- 좁히는 범위: ADR-0001 "결정" 29번째 줄("URLSession으로 실제 decision API를 부르는 공급자는 앱 타깃에만 둔다. 테스트 타깃과 `moka-sim`은 그것을 링크하지 않는다")과 "포기하는 것" 41번째 줄("실제 네트워크 전송 코드는 자동 시험하지 않는다"), ADR-0011 검증 표의 "리디렉트 거부" 줄(81번째 줄). 대체하지 않고 좁힌다. ADR-0001·ADR-0011 본문은 고치지 않는다.

## 맥락

`App/Sources/Decision/HTTPDecisionProvider.swift`의 연결부(인증 헤더 고르기, 세션에 붙인 리디렉트 거부 대리자, 로그 한 곳)에 자동 시험이 없다(#125). ADR-0011은 리디렉트 거부를 사람 확인으로 두었지만, 그 확인(loopback에 3xx를 돌려주는 서버, spec 006 quickstart 64번째 줄)은 Microsoft 줄이 열리기 전에는 만들 수 없어 기약 없이 NOT_RUN이다. 세션에서 대리자가 빠지는 회귀는 인증 헤더를 리디렉트 대상 호스트로 보낼 수 있고, 키가 한 번 나가면 되돌릴 수 없다.

헌법 VIII(`.specify/memory/constitution.md` 69~71번째 줄)은 실제 decision API를 테스트·CI·검증에서 "부르지" 말라고 한다. 컴파일을 막는 조항은 아니다. ADR-0001은 그 성질을 빌드 구조(시험 타깃이 공급자를 링크하지 않음)로 지켰다.

## 결정

안 A′(좁히기). 추천안 토론(2026-11-16) 3:0.

1. SwiftPM 타깃(`MokaCoreTests`, `MokaStoreTests`, `moka-sim`, 리눅스 CI `core-test`)은 지금처럼 실제 공급자를 링크하지 않는다. ADR-0001의 빌드 구조 보장은 여기서 그대로다.
2. macOS 앱 시험 번들 `MokaAppTests`만 `App/Sources/Decision/HTTPDecisionProvider.swift`를 컴파일한다(`project.yml` 시험 소스에 파일 단위로 한 줄).
3. 실제 전송은 세 겹으로 막는다.
   - 세션 주입: 공급자에 기본 세션을 두지 않는다. 앱 조립처(`MokaApp.swift`의 `decisionSetup()`)가 `HTTPDecisionProvider.liveSession`을 넘긴다. 시험은 `protocolClasses = [가짜]`를 강제하는 도우미(`FakeDecisionURLProtocol.makeSession()`)로만 세션을 만든다.
   - URLProtocol 가짜: 요청을 기록하고 정해 둔 상태 코드로 답한다. 네트워크로 나가지 않는다.
   - `.invalid` 호스트: 시험 주소는 `.invalid`만 쓴다(RFC 2606). 가짜는 `.invalid`가 아닌 호스트의 요청을 실패시킨다.
4. ADR-0011 "리디렉트 거부" 줄은 이렇게 바뀐다. 대리자 연결(3xx를 따라가지 않고 `server(status)`, 두 번째 요청 없음)은 앱 시험 번들 자동 시험이 본다. 첫 실제 호출과 loopback 서버 확인은 사람이 한다.
5. 헌법 VIII 본문은 그대로다. 시험은 실제 decision API를 부르지 않는다.

시험(`App/Tests/MokaAppTests/HTTPDecisionProviderTests.swift`): Bearer 공급자는 키를 `Authorization`에만, `api-key` 공급자는 `api-key`에만 넣는다. 301·302·307·308을 따라가지 않는다. 실패 로그에 키·주소·호스트·경로가 없다(`OSLogStore`, 로그가 0건이면 실패해 빈 통과를 막음).

고장 낸 코드로 확인한 Red(2026-11-17, 커밋하지 않음): 세션 대리자를 빼면 리디렉트 시험이 실패한다(`network`, 리디렉트 대상으로 두 번째 요청이 생김). `Authorization`과 `api-key`를 서로 바꾸면 헤더 시험 둘이 실패한다.

## 대안

| 대안 | 장점 | 단점·위험 |
|---|---|---|
| A′. 앱 시험 번들만 컴파일, 세 겹 차단(이 ADR) | 대리자가 세션에 붙었는지까지 자동 시험 | 앱 시험 번들에서는 빌드 구조 보장이 약속(세션 주입)으로 바뀐다 |
| A. ADR-0001·0011을 통째로 대체 | 규칙이 하나 | 리눅스·`moka-sim`까지 보장을 잃을 이유가 없다 |
| B. 순수 부분(헤더 고르기, 로그 문구)과 대리자 파일만 빼서 시험 | ADR-0001 그대로 | 대리자가 세션에 붙었는지를 못 잡는다. 그 회귀가 되돌릴 수 없는 유일한 실패다 |
| C. 사람 확인 유지 | 바꿀 것 없음 | loopback 확인이 기약 없이 NOT_RUN |

## 위험

- 앱 시험 번들은 비필수 job `app-snapshots`(`continue-on-error: true`, `.github/workflows/ci.yml` 84번째 줄)에서만 돈다. 이 시험이 실패해도 병합을 막지 않는다. PR마다 그 job 결과를 사람이 본다.
- 시험이 가짜 도우미를 거치지 않고 `liveSession`을 쓰면 실제 네트워크로 나갈 수 있다. `.invalid` 호스트라 DNS에서 막히지만, 시험 리뷰에서 `liveSession`이 시험 번들 안에서 쓰이지 않는지 본다.
- `OSLogStore`는 같은 프로세스 로그만 읽는다. 로그 수집이 늦으면 로그 시험이 0건으로 실패할 수 있다(빈 통과가 아니라 거짓 실패 쪽).

## Agent의 추천과 근거

A′를 추천한다. 토론 기록 `.audit/debate/20261116-1650-adr-provider-test.md`(커밋하지 않음).
- Q1 안 A′ 3:0(2라운드에서 B 자리가 B → A′로 바꿈).
- 조건 1(공급자 기본 세션 제거, 조립처 주입) 2:1. 소수 의견: 운영 경로를 바꾸지 말고 internal 시험 주입과 `.invalid`만으로 충분하다.
- 물러설 조건: 대리자를 빼도 리디렉트 시험이 실패하지 않으면 리디렉트 연결은 사람 확인으로 두고 헤더·로그만 자동 시험한다. 위 Red 확인에서 실패했으므로 물러서지 않는다.

## 사람의 최종 결정과 실제 판단 이유

사용자 결정(2026-11-16): 새 ADR을 debate로 제안한다. 채택 여부는 PR 병합으로 정한다.
