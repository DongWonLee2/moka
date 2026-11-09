"""튜닝 스크립트와 앱이 함께 쓰는 decisions_log 계약 시험(spec 002 research R16, ADR-0004).

schema/moka-schema.sql로 메모리 DB를 만들고 decisions_log 열 이름과 판단 칸 CHECK만 본다.
다른 표의 CHECK는 Swift 시험(StoreConstraintTests)이 덮는다.
"""

import sqlite3
from pathlib import Path

import pytest

SCHEMA = Path(__file__).resolve().parents[2] / "schema" / "moka-schema.sql"

# research R5: PRD 9장 열 전부와 model_snapshot.
DECISIONS_LOG_COLUMNS = {
    "id",
    "task_id",
    "question_version",
    "provider",
    "probs_json",
    "state_hash",
    "model_snapshot",
    "scheduler_choice",
    "user_action",
    "created_at",
}

JUDGMENT_COLUMNS = ("question_version", "probs_json", "state_hash", "model_snapshot")


@pytest.fixture
def db():
    # 외래 키는 켜지 않는다(파이썬 sqlite3 기본값). tasks 줄 없이 decisions_log만 본다.
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA.read_text(encoding="utf-8"))
    yield conn
    conn.close()


def insert_decision(conn, **judgment):
    columns = {
        "task_id": 1,
        "scheduler_choice": "rotate_by_id_v0",
        "user_action": "done",
        "created_at": "2026-10-26T07:33:20Z",
        **judgment,
    }
    names = ", ".join(columns)
    marks = ", ".join("?" for _ in columns)
    conn.execute(f"INSERT INTO decisions_log({names}) VALUES ({marks})", tuple(columns.values()))


def test_decisions_log_columns(db):
    columns = {row[1] for row in db.execute("PRAGMA table_info(decisions_log)")}
    assert columns == DECISIONS_LOG_COLUMNS


def test_row_without_judgment_is_allowed(db):
    insert_decision(db)
    assert db.execute("SELECT COUNT(*) FROM decisions_log").fetchone() == (1,)


def test_fallback_row_with_provider_only_is_allowed(db):
    insert_decision(db, provider="fallback")
    row = db.execute(
        "SELECT provider, question_version, probs_json, state_hash, model_snapshot FROM decisions_log"
    ).fetchone()
    assert row == ("fallback", None, None, None, None)


@pytest.mark.parametrize("column", JUDGMENT_COLUMNS)
def test_judgment_column_without_provider_is_rejected(db, column):
    with pytest.raises(sqlite3.IntegrityError, match="CHECK constraint failed"):
        insert_decision(db, **{column: "fake"})
    assert db.execute("SELECT COUNT(*) FROM decisions_log").fetchone() == (0,)


SCORES_COLUMNS = {
    "task_id",
    "question_version",
    "provider",
    "model_snapshot",
    "urgency",
    "impact",
    "concrete",
    "avoiding",
    "probs_json",
    "state_hash",
    "scored_at",
}


def test_scores_columns(db):
    columns = {row[1] for row in db.execute("PRAGMA table_info(scores)")}
    assert columns == SCORES_COLUMNS
