from moka_tuning import health


def test_health():
    assert health() == "ok"
