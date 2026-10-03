"""Load the 9 Olist CSVs into PostgreSQL. Idempotent: safe to re-run."""
from __future__ import annotations

import io
import logging
import os
import sys
from pathlib import Path

import pandas as pd
import psycopg2
import yaml
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL, Connection, Engine
from sqlalchemy.exc import IntegrityError, SQLAlchemyError

ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "configs" / "config.yaml"
REQUIRED_ENV = ["POSTGRES_USER", "POSTGRES_PASSWORD", "POSTGRES_DB",
                "POSTGRES_HOST", "POSTGRES_PORT"]

log = logging.getLogger("olist.load")


class ConfigError(Exception):
    """Raised when config or environment settings are missing or invalid."""


class DataValidationError(Exception):
    """Raised when a CSV does not match the expected table schema."""


def setup_logging(log_file: Path) -> None:
    """Log to both console and file."""
    log_file.parent.mkdir(parents=True, exist_ok=True)
    fmt = logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    for handler in (logging.FileHandler(log_file, encoding="utf-8"),
                    logging.StreamHandler()):
        handler.setFormatter(fmt)
        root.addHandler(handler)


def load_config() -> dict:
    """Read configs/config.yaml."""
    if not CONFIG_PATH.exists():
        raise ConfigError(f"Config file not found: {CONFIG_PATH}")
    with CONFIG_PATH.open(encoding="utf-8") as f:
        return yaml.safe_load(f)


def make_engine() -> Engine:
    """Build a database engine from .env settings."""
    load_dotenv(ROOT / ".env", override=True)
    missing = [k for k in REQUIRED_ENV if not os.getenv(k)]
    if missing:
        raise ConfigError(f"Missing in .env: {missing}. Copy .env.example to .env.")
    url = URL.create(
        "postgresql+psycopg2",
        username=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
        host=os.environ["POSTGRES_HOST"],
        port=int(os.environ["POSTGRES_PORT"]),
        database=os.environ["POSTGRES_DB"],
    )
    return create_engine(url)


def read_statements(path: Path) -> list[str]:
    """Split a .sql file into individual statements (comment lines removed)."""
    if not path.exists():
        raise FileNotFoundError(f"SQL file not found: {path}")
    lines = [ln for ln in path.read_text(encoding="utf-8").splitlines()
             if not ln.strip().startswith("--")]
    return [s.strip() for s in "\n".join(lines).split(";") if s.strip()]


def create_schema(engine: Engine, path: Path) -> None:
    """Drop and recreate all tables."""
    with engine.begin() as conn:
        for stmt in read_statements(path):
            conn.exec_driver_sql(stmt)


def get_column_types(conn: Connection, table: str) -> dict[str, str]:
    """Return {column: sql_type} for a table, in column order."""
    rows = conn.execute(
        text("SELECT column_name, data_type FROM information_schema.columns "
             "WHERE table_schema = 'public' AND table_name = :t "
             "ORDER BY ordinal_position"),
        {"t": table},
    ).all()
    return {name: dtype for name, dtype in rows}


def cast_column(s: pd.Series, sql_type: str, table: str, col: str) -> pd.Series:
    """Parse a string column into the type the database expects. Bad values become NULL."""
    if sql_type.startswith("timestamp"):
        out = pd.to_datetime(s, errors="coerce", format="%Y-%m-%d %H:%M:%S")
    elif sql_type == "integer":
        out = pd.to_numeric(s, errors="coerce")
        try:
            out = out.astype("Int64")
        except TypeError as exc:
            raise DataValidationError(
                f"{table}.{col}: non-whole numbers in integer column") from exc
    elif sql_type in ("numeric", "double precision"):
        out = pd.to_numeric(s, errors="coerce")
    else:
        return s
    lost = int(s.notna().sum() - out.notna().sum())
    if lost:
        log.warning("%s.%s: %d values could not be parsed -> NULL", table, col, lost)
    return out


def read_csv_validated(path: Path, col_types: dict[str, str], table: str) -> pd.DataFrame:
    """Read a CSV, check its columns against the table, and cast types."""
    if not path.exists():
        raise DataValidationError(f"{table}: file not found: {path}")
    try:
        df = pd.read_csv(path, dtype=str, keep_default_na=False,
                         na_values=[""], encoding="utf-8")
    except (pd.errors.EmptyDataError, UnicodeDecodeError) as exc:
        raise DataValidationError(f"{table}: cannot read {path.name}: {exc}") from exc
    if df.empty:
        raise DataValidationError(f"{table}: {path.name} has no rows")
    expected = list(col_types)
    missing, extra = set(expected) - set(df.columns), set(df.columns) - set(expected)
    if missing or extra:
        raise DataValidationError(
            f"{table}: column mismatch. missing={sorted(missing)} extra={sorted(extra)}")
    df = df[expected]
    for col, sql_type in col_types.items():
        df[col] = cast_column(df[col], sql_type, table, col)
    return df


def copy_table(conn: Connection, table: str, df: pd.DataFrame) -> int:
    """Bulk-load a DataFrame with Postgres COPY, then verify the row count."""
    buf = io.StringIO()
    df.to_csv(buf, index=False, header=False, lineterminator="\n")
    buf.seek(0)
    sql = f"COPY {table} ({', '.join(df.columns)}) FROM STDIN WITH (FORMAT csv, NULL '')"
    try:
        with conn.connection.cursor() as cur:
            cur.copy_expert(sql, buf)
    except psycopg2.Error as exc:
        raise DataValidationError(f"{table}: database rejected the data: {exc}") from exc
    loaded = conn.execute(text(f"SELECT COUNT(*) FROM {table}")).scalar_one()
    if loaded != len(df):
        raise DataValidationError(f"{table}: loaded {loaded} rows but CSV has {len(df)}")
    return loaded


def apply_constraints(engine: Engine, path: Path) -> None:
    """Add foreign keys and indexes. A violated foreign key is logged, not fatal."""
    for stmt in read_statements(path):
        try:
            with engine.begin() as conn:
                conn.exec_driver_sql(stmt)
        except IntegrityError:
            log.warning("Skipped (existing data violates it, see data-quality audit): %s",
                        stmt[:90])


def main() -> int:
    cfg = load_config()
    setup_logging(ROOT / cfg["paths"]["log_file"])
    try:
        engine = make_engine()
        raw_dir = ROOT / cfg["paths"]["raw_data"]
        log.info("Creating schema")
        create_schema(engine, ROOT / cfg["paths"]["schema_sql"])
        for t in cfg["tables"]:
            with engine.begin() as conn:  # one transaction per table
                col_types = get_column_types(conn, t["name"])
                df = read_csv_validated(raw_dir / t["file"], col_types, t["name"])
                n = copy_table(conn, t["name"], df)
            log.info("Loaded %-35s %9d rows", t["name"], n)
        apply_constraints(engine, ROOT / cfg["paths"]["constraints_sql"])
    except (ConfigError, DataValidationError, FileNotFoundError, SQLAlchemyError) as exc:
        log.error("Load failed: %s", exc)
        log.error("Is Docker running? Try: docker compose ps")
        return 1
    log.info("Done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
