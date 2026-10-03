"""Unit tests for loader helpers, SQL block splitters and chart helpers."""
from __future__ import annotations

import pandas as pd
import pytest

from src.charts import drop_low_sample, read_csv_checked
from src.load_data import (
    DataValidationError,
    cast_column,
    read_csv_validated,
    read_statements,
)
from src.run_quality_audit import add_pct, parse_blocks
from src.run_queries import split_results

COL_TYPES = {
    "order_id": "character varying",
    "qty": "integer",
    "created": "timestamp without time zone",
}


def write(tmp_path, content: str, name: str = "t.csv"):
    p = tmp_path / name
    p.write_text(content, encoding="utf-8")
    return p


# ---- read_statements
def test_read_statements_drops_comments_and_splits(tmp_path):
    p = write(tmp_path, "-- note\nSELECT 1;\n-- another\nSELECT 2;\n", "a.sql")
    assert read_statements(p) == ["SELECT 1", "SELECT 2"]


def test_read_statements_missing_file(tmp_path):
    with pytest.raises(FileNotFoundError):
        read_statements(tmp_path / "nope.sql")


# ---- cast_column
def test_cast_timestamp_bad_value_becomes_null():
    s = pd.Series(["2017-01-01 10:00:00", "not a date", None])
    out = cast_column(s, "timestamp without time zone", "t", "c")
    assert out.isna().tolist() == [False, True, True]


def test_cast_integer_ok_and_bad_value():
    out = cast_column(pd.Series(["1", "x", "3"]), "integer", "t", "c")
    assert out.isna().tolist() == [False, True, False]
    assert out.dropna().tolist() == [1, 3]


def test_cast_integer_non_whole_number_raises():
    with pytest.raises(DataValidationError):
        cast_column(pd.Series(["1.5", "2"]), "integer", "t", "c")


def test_cast_numeric_bad_value_becomes_null():
    out = cast_column(pd.Series(["1.50", "abc"]), "numeric", "t", "c")
    assert out.isna().tolist() == [False, True]


def test_cast_text_is_unchanged():
    s = pd.Series(["a", "b"])
    assert cast_column(s, "character varying", "t", "c") is s


# ---- read_csv_validated
def test_read_csv_validated_happy_path_and_column_order(tmp_path):
    p = write(tmp_path, "created,order_id,qty\n2017-01-01 10:00:00,o1,2\nbad,o2,3\n")
    df = read_csv_validated(p, COL_TYPES, "t")
    assert list(df.columns) == list(COL_TYPES)
    assert df["created"].isna().tolist() == [False, True]
    assert df["qty"].tolist() == [2, 3]


def test_read_csv_validated_missing_file(tmp_path):
    with pytest.raises(DataValidationError, match="not found"):
        read_csv_validated(tmp_path / "nope.csv", COL_TYPES, "t")


def test_read_csv_validated_empty_file(tmp_path):
    with pytest.raises(DataValidationError):
        read_csv_validated(write(tmp_path, ""), COL_TYPES, "t")


def test_read_csv_validated_header_only(tmp_path):
    with pytest.raises(DataValidationError, match="no rows"):
        read_csv_validated(write(tmp_path, "order_id,qty,created\n"), COL_TYPES, "t")


def test_read_csv_validated_missing_column(tmp_path):
    with pytest.raises(DataValidationError, match="mismatch"):
        read_csv_validated(write(tmp_path, "order_id,qty\no1,1\n"), COL_TYPES, "t")


def test_read_csv_validated_extra_column(tmp_path):
    with pytest.raises(DataValidationError, match="mismatch"):
        read_csv_validated(
            write(tmp_path, "order_id,qty,created,extra\no1,1,2017-01-01 10:00:00,x\n"),
            COL_TYPES,
            "t",
        )


def test_read_csv_validated_non_integer(tmp_path):
    with pytest.raises(DataValidationError):
        read_csv_validated(write(tmp_path, "order_id,qty,created\no1,1.5,\n"), COL_TYPES, "t")


# ---- parse_blocks / split_results
def test_parse_blocks_splits_and_strips_semicolon(tmp_path):
    p = write(tmp_path, "-- name: a\nSELECT 1;\n-- name: b\nSELECT 2;\n", "audit.sql")
    assert parse_blocks(p) == {"a": "SELECT 1", "b": "SELECT 2"}


def test_parse_blocks_no_markers(tmp_path):
    with pytest.raises(ValueError):
        parse_blocks(write(tmp_path, "SELECT 1;", "audit.sql"))


def test_parse_blocks_missing_file(tmp_path):
    with pytest.raises(FileNotFoundError):
        parse_blocks(tmp_path / "nope.sql")


def test_split_results_with_markers():
    text_ = "-- header\n-- result: one\nSELECT 1;\n-- result: two\nSELECT 2;\n"
    assert split_results(text_) == {"one": "SELECT 1", "two": "SELECT 2"}


def test_split_results_without_markers_is_single_result():
    assert split_results("SELECT 1;\n") == {"": "SELECT 1"}


# ---- add_pct
def test_add_pct_normal():
    df = add_pct(pd.DataFrame({"issue_count": [1, 5], "total_rows": [4, 10]}))
    assert df["pct"].tolist() == [25.0, 50.0]


def test_add_pct_zero_total_is_empty():
    df = add_pct(pd.DataFrame({"issue_count": [3], "total_rows": [0]}))
    assert pd.isna(df.loc[0, "pct"])


def test_add_pct_without_columns_is_unchanged():
    df = add_pct(pd.DataFrame({"x": [1]}))
    assert "pct" not in df.columns


# ---- chart helpers
def test_read_csv_checked_missing_file(tmp_path):
    with pytest.raises(FileNotFoundError):
        read_csv_checked(tmp_path / "nope.csv", ["a"])


def test_read_csv_checked_empty(tmp_path):
    with pytest.raises(DataValidationError, match="empty"):
        read_csv_checked(write(tmp_path, "a,b\n"), ["a"])


def test_read_csv_checked_missing_columns(tmp_path):
    with pytest.raises(DataValidationError, match="missing columns"):
        read_csv_checked(write(tmp_path, "a\n1\n"), ["a", "b"])


def test_read_csv_checked_ok(tmp_path):
    df = read_csv_checked(write(tmp_path, "a,b\n1,2\n"), ["a", "b"])
    assert len(df) == 1


@pytest.mark.parametrize("values", [[True, False], ["True", "False"]])
def test_drop_low_sample_handles_bool_and_text(values):
    df = pd.DataFrame({"low_sample": values, "n": [1, 2]})
    assert drop_low_sample(df)["n"].tolist() == [2]
