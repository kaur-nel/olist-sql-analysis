"""Checks on the real Kaggle data. Read-only. Skipped when the real data is not loaded."""
from __future__ import annotations

import pytest
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from src.load_data import ConfigError, make_engine


@pytest.fixture(scope="module")
def real():
    try:
        engine = make_engine()
        with engine.connect() as conn:
            has_orders = conn.execute(
                text("SELECT to_regclass('public.orders') IS NOT NULL")).scalar()
            n = conn.execute(text("SELECT COUNT(*) FROM orders")).scalar() if has_orders else 0
    except (ConfigError, SQLAlchemyError) as exc:
        pytest.skip(f"Real database not available: {exc}")
    if n < 1000:
        pytest.skip("Real Olist data is not loaded")
    yield engine
    engine.dispose()


def scalar(engine, sql: str):
    with engine.connect() as conn:
        return conn.execute(text(sql)).scalar()


@pytest.mark.parametrize(
    ("table", "expected"),
    [("orders", 99441), ("order_items", 112650), ("geolocation", 1000163)],
)
def test_known_raw_counts(real, table, expected):
    assert scalar(real, f"SELECT COUNT(*) FROM {table}") == expected


def test_reviews_clean_count(real):
    assert scalar(real, "SELECT COUNT(*) FROM v_reviews_clean") == 98673


def test_sales_total_reconciles(real):
    total = scalar(real, "SELECT ROUND(SUM(price), 2) FROM v_sales")
    assert float(total) == pytest.approx(13494400.74)
