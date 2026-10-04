"""Exit 0 if the database answers, 1 if not. Used by the Docker HEALTHCHECK."""
from __future__ import annotations

import sys

from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from src.load_data import ConfigError, make_engine


def check_database() -> bool:
    """Return True if `SELECT 1` works on the configured database."""
    try:
        engine = make_engine()
        with engine.connect() as conn:
            return conn.execute(text("SELECT 1")).scalar() == 1
    except (ConfigError, SQLAlchemyError) as exc:
        print(f"Health check failed: {exc}", file=sys.stderr)
        return False


def main() -> int:
    return 0 if check_database() else 1


if __name__ == "__main__":
    sys.exit(main())
