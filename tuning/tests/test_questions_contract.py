import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QUESTIONS = ROOT / "Sources" / "MokaCore" / "Resources" / "questions.json"
HISTORY = ROOT / "questions-history"
# ADR-0011 승인 항목 2a(B안): v1 사본은 v1을 마지막으로 담은 커밋의 파일을 그대로 꺼낸 것
V1_SHA256 = "e302020530edacf468001b9b35d254582907c8e3b99c8f3bb11ddcfffdbd9538"
# v2 사본은 v2를 마지막으로 담은 커밋(9f07336)의 파일 그대로
V2_SHA256 = "39792c7ddd157813b6b016a367d77f60446639e4ffee905cc6d480a791e6f29e"


def load_questions():
    return json.loads(QUESTIONS.read_text(encoding="utf-8"))


def test_four_questions_with_types():
    questions = load_questions()["questions"]
    assert set(questions) == {"urgency", "impact", "concrete", "avoiding"}
    assert {name: q["type"] for name, q in questions.items()} == {
        "urgency": "score",
        "impact": "score",
        "concrete": "noul",
        "avoiding": "noul",
    }


def test_thresholds_for_every_base_model():
    # ADR-0011 R-612: models의 모든 값(기준 모델 ID)에 concrete·avoiding 임계값이 0~1로 있다
    data = load_questions()
    assert data["models"]
    for base_model in data["models"].values():
        thresholds = data["thresholds"][base_model]
        assert {"concrete", "avoiding"} <= set(thresholds)
        assert all(0 <= value <= 1 for value in thresholds.values())


def test_provisional_is_subset_of_models():
    # ADR-0011 R-612: provisional은 models 값의 부분집합이고 중복이 없다
    data = load_questions()
    provisional = data["provisional"]
    assert len(provisional) == len(set(provisional))
    assert set(provisional) <= set(data["models"].values())


def test_probs_json_example_reads_with_json_loads():
    # data-model §2: 질문 이름 순, 옵션 번호 순, Swift 최단 숫자 표기(1.0, 1e-05)
    example = (
        '{"avoiding":{"noul":1e-05},"concrete":{"noul":1.0},'
        '"impact":{"score":1.2,"confidence":0.6,"probabilities":{"0":0.2,"1":0.4,"2":0.4}},'
        '"urgency":{"score":2.1,"confidence":0.7,"probabilities":{"0":0.05,"1":0.15,"2":0.4,"3":0.4}}}'
    )
    probs = json.loads(example)
    assert probs["avoiding"]["noul"] == 1e-05
    assert probs["concrete"]["noul"] == 1.0
    assert set(probs["urgency"]["probabilities"]) == {"0", "1", "2", "3"}


def test_current_questions_match_history_copy():
    # ADR-0011 R-612: 지금 파일은 questions-history/<version>.json과 바이트까지 같다
    current = QUESTIONS.read_bytes()
    version = json.loads(current)["version"]
    assert (HISTORY / f"{version}.json").read_bytes() == current


def test_v1_history_copy_is_fixed():
    # ADR-0011 R-612: 지난 사본 v1의 SHA-256 고정
    data = (HISTORY / "v1.json").read_bytes()
    assert hashlib.sha256(data).hexdigest() == V1_SHA256
    assert json.loads(data)["version"] == "v1"


def test_v2_history_copy_is_fixed():
    # ADR-0011 R-612: 지난 사본 v2의 SHA-256 고정
    data = (HISTORY / "v2.json").read_bytes()
    assert hashlib.sha256(data).hexdigest() == V2_SHA256
    assert json.loads(data)["version"] == "v2"
