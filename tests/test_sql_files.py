"""Static checks on the SQL files. No database needed."""
from __future__ import annotations

import re

import pytest

from src.load_data import ROOT

SQL_DIR = ROOT / "sql"
Q_FILES = sorted(SQL_DIR.glob("q[0-9][0-9]_*.sql"))
STAR = re.compile(r"\bselect\s+(distinct\s+)?\*|\b\w+\.\*", re.IGNORECASE)


def strip_comments(sql: str) -> str:
    """Remove '-- ...' comment lines so words inside comments are not checked."""
    return "\n".join(ln for ln in sql.splitlines() if not ln.strip().startswith("--"))


def test_all_ten_question_files_exist():
    assert len(Q_FILES) == 10


@pytest.mark.parametrize("path", Q_FILES, ids=lambda p: p.name)
def test_has_comment_block(path):
    head = path.read_text(encoding="utf-8")
    for label in ("-- Question:", "-- Approach:", "-- Assumptions:"):
        assert label in head, f"{path.name} is missing '{label}'"


@pytest.mark.parametrize("path", Q_FILES, ids=lambda p: p.name)
def test_no_select_star(path):
    code = strip_comments(path.read_text(encoding="utf-8"))
    assert not STAR.search(code), f"{path.name} uses SELECT * or alias.*"
