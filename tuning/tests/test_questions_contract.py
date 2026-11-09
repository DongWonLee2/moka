import json
from pathlib import Path

QUESTIONS = Path(__file__).resolve().parents[2] / "Sources" / "MokaCore" / "Resources" / "questions.json"


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


def test_thresholds_for_fixed_model():
    data = load_questions()
    thresholds = data["thresholds"][data["model"]]
    assert {"concrete", "avoiding"} <= set(thresholds)
    assert all(0 <= value <= 1 for value in thresholds.values())


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
