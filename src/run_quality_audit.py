"""Run sql/00_quality_checks.sql and write docs/data_quality_report.md."""
from __future__ import annotations

import logging
import re
import sys
from datetime import datetime
from pathlib import Path

import pandas as pd
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from src.load_data import ROOT, ConfigError, load_config, make_engine, setup_logging

log = logging.getLogger("olist.audit")
BLOCK = re.compile(r"^-- name:\s*(\w+)\s*$", re.MULTILINE)


def parse_blocks(path: Path) -> dict[str, str]:
    """Split the audit file into {block_name: sql} using '-- name:' markers."""
    if not path.exists():
        raise FileNotFoundError(f"Audit SQL file not found: {path}")
    parts = BLOCK.split(path.read_text(encoding="utf-8"))
    blocks = {parts[i]: parts[i + 1].strip().rstrip(";") for i in range(1, len(parts), 2)}
    if not blocks:
        raise ValueError(f"No '-- name:' blocks found in {path}")
    return blocks


def add_pct(df: pd.DataFrame) -> pd.DataFrame:
    """Add pct = issue_count / total_rows * 100, leaving it empty when total_rows is 0."""
    if {"issue_count", "total_rows"} <= set(df.columns):
        total = df["total_rows"].astype(float).where(df["total_rows"] != 0)
        df["pct"] = (100 * df["issue_count"].astype(float) / total).round(2)
    return df


def to_markdown(df: pd.DataFrame) -> str:
    """Render a DataFrame as a markdown table."""
    if df.empty:
        return "_No rows._"
    cols = list(df.columns)
    lines = ["| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]
    for row in df.itertuples(index=False):
        lines.append("| " + " | ".join("" if pd.isna(v) else str(v) for v in row) + " |")
    return "\n".join(lines)


def main() -> int:
    cfg = load_config()
    setup_logging(ROOT / cfg["paths"]["log_file"])
    try:
        blocks = parse_blocks(ROOT / cfg["paths"]["audit_sql"])
        engine = make_engine()
        sections: list[str] = []
        with engine.connect() as conn:
            for name, sql in blocks.items():
                try:
                    df = add_pct(pd.read_sql_query(text(sql), conn))
                except SQLAlchemyError as exc:
                    raise RuntimeError(f"Check '{name}' failed: {exc}") from exc
                shown = df[df["issue_count"] > 0] if "issue_count" in df.columns else df
                log.info("\n== %s ==\n%s", name,
                         shown.to_string(index=False) if not shown.empty else "(no issues)")
                sections.append(f"## {name}\n\n{to_markdown(df)}")
        report = ROOT / cfg["paths"]["quality_report"]
        report.parent.mkdir(parents=True, exist_ok=True)
        header = f"# Data Quality Report\n\nGenerated: {datetime.now():%Y-%m-%d %H:%M}\n\n"
        report.write_text(header + "\n\n".join(sections) + "\n", encoding="utf-8")
        log.info("Report written to %s", report)
    except (ConfigError, FileNotFoundError, ValueError, KeyError, RuntimeError) as exc:
        log.error("Audit failed: %s", exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
