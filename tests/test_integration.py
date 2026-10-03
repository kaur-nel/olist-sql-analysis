"""Integration tests on the mini fixtures. Expected values were worked out by hand."""
from __future__ import annotations

from decimal import Decimal

import pytest
from sqlalchemy import text

from src.load_data import ROOT, load_config
from src.run_queries import split_results

SQL_DIR = ROOT / "sql"
Q_FILES = sorted(SQL_DIR.glob("q*.sql"))


@pytest.mark.parametrize(
    ("table", "expected"),
    [
        ("customers", 7), ("sellers", 2), ("products", 3),
        ("product_category_name_translation", 1), ("geolocation", 6),
        ("orders", 7), ("order_items", 7), ("order_payments", 7), ("order_reviews", 4),
    ],
)
def test_raw_row_counts(q, table, expected):
    assert q(f"SELECT COUNT(*) FROM {table}")[0][0] == expected


def test_reviews_clean_one_row_per_order_keeps_latest(q):
    total, distinct = q("SELECT COUNT(*), COUNT(DISTINCT order_id) FROM v_reviews_clean")[0]
    assert total == distinct == 3
    row = q("SELECT * FROM v_reviews_clean WHERE order_id = 'o1'")[0]
    assert "r2" in tuple(row) and "r1" not in tuple(row)


def test_geolocation_one_row_per_zip(q):
    assert q("SELECT COUNT(*) FROM v_geolocation_clean")[0][0] == 3


def test_customer_city_and_state_normalised(q):
    row = tuple(q("SELECT * FROM v_customers_clean WHERE customer_id = 'c1'")[0])
    assert "são paulo" in row and "SP" in row


def test_payments_clean_drops_not_defined(q):
    assert q("SELECT COUNT(*) FROM v_payments_clean")[0][0] == 6
    assert q("SELECT COUNT(*) FROM v_payments_clean WHERE order_id = 'o4'")[0][0] == 1


def test_orders_clean_revenue_flag(q):
    assert q("SELECT COUNT(*) FROM v_orders_clean")[0][0] == 7
    assert q("SELECT COUNT(*) FROM v_orders_clean WHERE is_revenue_order")[0][0] == 5


def test_sales_excludes_canceled_and_unavailable(q):
    orders = {r[0] for r in q("SELECT DISTINCT order_id FROM v_sales")}
    assert "o3" not in orders and "o7" not in orders
    assert q("SELECT COUNT(*) FROM v_sales")[0][0] == 6


def test_is_late_null_unless_properly_delivered(q):
    late = {r[0]: r[1] for r in q("SELECT DISTINCT order_id, is_late FROM v_sales")}
    assert not late["o1"]            # delivered on time
    assert late["o2"]                # delivered after estimate
    for order_id in ("o4", "o5", "o6"):  # shipped / no date / delivered before purchase
        assert late[order_id] is None


def test_delivery_days(q):
    days = q("SELECT DISTINCT delivery_days FROM v_sales WHERE order_id = 'o1'")[0][0]
    assert float(days) == pytest.approx(5)


def test_category_fallbacks(q):
    cat = {(r[0], r[1]): r[2] for r in q("SELECT order_id, order_item_id, category FROM v_sales")}
    assert cat[("o1", 1)] == "health_beauty"
    assert cat[("o2", 2)] == "unknown"
    assert cat[("o4", 1)] == "categoria_sem_traducao"


def test_person_with_two_customer_ids_counts_once(q):
    n = q("SELECT COUNT(DISTINCT customer_unique_id) FROM v_sales "
          "WHERE order_id IN ('o1', 'o2')")[0][0]
    assert n == 1


def test_revenue_by_month_hand_computed(q):
    rows = q("SELECT CAST(purchase_month AS TEXT), SUM(price) FROM v_sales GROUP BY 1")
    by_month = {r[0][:7]: r[1] for r in rows}
    assert by_month == {"2017-01": Decimal("100.00"), "2017-02": Decimal("200.00"),
                        "2017-03": Decimal("160.00")}


@pytest.mark.parametrize("path", Q_FILES, ids=lambda p: p.name)
def test_every_question_runs_without_error(db, path):
    min_sample = load_config()["analysis"]["min_sample_size"]
    sql_text = path.read_text(encoding="utf-8").replace("{{MIN_SAMPLE_SIZE}}", str(min_sample))
    for _name, sql in split_results(sql_text).items():
        with db.connect() as conn:
            conn.execute(text(sql)).fetchall()


def test_q01_revenue_reconciles_with_sales(db):
    min_sample = load_config()["analysis"]["min_sample_size"]
    sql_text = (SQL_DIR / "q01_monthly_revenue.sql").read_text(encoding="utf-8")
    sql = split_results(sql_text.replace("{{MIN_SAMPLE_SIZE}}", str(min_sample)))[""]
    with db.connect() as conn:
        rows = conn.execute(text(sql)).mappings().all()
    assert sum(float(r["revenue"]) for r in rows) == pytest.approx(460.00)
