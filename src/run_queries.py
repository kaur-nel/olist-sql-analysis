"""Run sql/qNN_*.sql files and export each result set to outputs/ as CSV."""
from __future__ import annotations

import logging
import re
import sys
from pathlib import Path

import pandas as pd
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from src.load_data import ROOT, ConfigError, load_config, make_engine, setup_logging

log = logging.getLogger("olist.queries")
RESULT = re.compile(r"^-- result:\s*(\w+)\s*$", re.MULTILINE)


def split_results(sql_text: str) -> dict[str, str]:
    """Split a file into {result_name: sql}. A file without '-- result:' markers is one result."""
    parts = RESULT.split(sql_text)
    if len(parts) == 1:
        return {"": sql_text.strip().rstrip(";")}
    return {parts[i]: parts[i + 1].strip().rstrip(";") for i in range(1, len(parts), 2)}


def main() -> int:
    cfg = load_config()
    setup_logging(ROOT / cfg["paths"]["log_file"])
    prefix = sys.argv[1] if len(sys.argv) > 1 else ""  # e.g. "q03" to run one file
    try:
        min_n = int(cfg["analysis"]["min_sample_size"])
        if min_n < 1:
            raise ConfigError("analysis.min_sample_size must be >= 1")
        files = sorted((ROOT / cfg["paths"]["queries_dir"]).glob("q[0-9][0-9]_*.sql"))
        files = [f for f in files if f.name.startswith(prefix)]
        if not files:
            raise FileNotFoundError(f"No query files found (prefix='{prefix}')")
        out_dir = ROOT / cfg["paths"]["outputs_dir"]
        out_dir.mkdir(parents=True, exist_ok=True)
        engine = make_engine()
        with engine.connect() as conn:
            for path in files:
                sql_text = path.read_text(encoding="utf-8").replace("{{MIN_SAMPLE_SIZE}}", str(min_n))
                for name, sql in split_results(sql_text).items():
                    if "{{" in sql:
                        raise ValueError(f"{path.name}: unknown placeholder in SQL")
                    try:
                        df = pd.read_sql_query(text(sql), conn)
                    except SQLAlchemyError as exc:
                        raise RuntimeError(f"{path.name} [{name or 'main'}] failed: {exc}") from exc
                    out = out_dir / (f"{path.stem}__{name}.csv" if name else f"{path.stem}.csv")
                    df.to_csv(out, index=False, encoding="utf-8-sig")  # sig = Excel-friendly accents
                    log.info("%s -> %s (%d rows)", path.name, out.name, len(df))
    except (ConfigError, FileNotFoundError, ValueError, KeyError, RuntimeError) as exc:
        log.error("Run failed: %s", exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())