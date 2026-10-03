"""Shared fixtures: a throwaway Postgres database loaded from tests/fixtures/mini."""
from __future__ import annotations

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.exc import SQLAlchemyError

from src.load_data import (
    ROOT,
    ConfigError,
    apply_constraints,
    copy_table,
    create_schema,
    get_column_types,
    load_config,
    make_engine,
    read_csv_validated,
    read_statements,
)

FIXTURES = ROOT / "tests" / "fixtures" / "mini"
TEST_DB = "olist_test"  # separate database so real data is never touched


@pytest.fixture(scope="session")
def db():
    """Engine for a test database loaded from the mini fixtures, with all views created."""
    cfg = load_config()
    try:
        admin = make_engine()
    except ConfigError as exc:
        pytest.skip(f"No database settings: {exc}")
    try:
        with admin.execution_options(isolation_level="AUTOCOMMIT").connect() as conn:
            exists = conn.execute(
                text("SELECT 1 FROM pg_database WHERE datname = :n"), {"n": TEST_DB}
            ).scalar()
            if not exists:
                conn.execute(text(f"CREATE DATABASE {TEST_DB}"))
    except SQLAlchemyError as exc:
        admin.dispose()
        pytest.skip(f"PostgreSQL not available: {exc}")
    url = admin.url.set(database=TEST_DB)
    admin.dispose()

    engine = create_engine(url)
    create_schema(engine, ROOT / cfg["paths"]["schema_sql"])
    for t in cfg["tables"]:
        with engine.begin() as conn:
            col_types = get_column_types(conn, t["name"])
            df = read_csv_validated(FIXTURES / t["file"], col_types, t["name"])
            copy_table(conn, t["name"], df)
    apply_constraints(engine, ROOT / cfg["paths"]["constraints_sql"])
    with engine.begin() as conn:
        for stmt in read_statements(ROOT / cfg["paths"]["views_sql"]):
            conn.exec_driver_sql(stmt)
    yield engine
    engine.dispose()


@pytest.fixture
def q(db):
    """Run a SQL string against the test database and return all rows."""

    def run(sql: str, **params):
        with db.connect() as conn:
            return conn.execute(text(sql), params).all()

    return run
