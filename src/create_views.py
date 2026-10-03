"""Create the cleaned views from sql/01_clean_views.sql (all-or-nothing)."""
from __future__ import annotations

import logging
import sys

from sqlalchemy.exc import SQLAlchemyError

from src.load_data import (
    ROOT,
    ConfigError,
    load_config,
    make_engine,
    read_statements,
    setup_logging,
)

log = logging.getLogger("olist.views")


def main() -> int:
    cfg = load_config()
    setup_logging(ROOT / cfg["paths"]["log_file"])
    try:
        statements = read_statements(ROOT / cfg["paths"]["views_sql"])
        engine = make_engine()
        with engine.begin() as conn:  # one transaction: all views or none
            for stmt in statements:
                conn.exec_driver_sql(stmt)
        log.info("Ran %d statements", len(statements))
    except (ConfigError, FileNotFoundError, KeyError, SQLAlchemyError) as exc:
        log.error("View creation failed: %s", exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
