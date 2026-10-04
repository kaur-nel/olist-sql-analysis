"""Tests for the pipeline runner and the health check."""
from __future__ import annotations

from src import healthcheck
from src.load_data import ConfigError
from src.pipeline import STEPS, run_pipeline


def test_steps_are_in_the_right_order():
    assert STEPS == [
        "src.load_data",
        "src.run_quality_audit",
        "src.create_views",
        "src.run_queries",
        "src.charts",
    ]


def test_pipeline_runs_every_step_when_all_succeed():
    seen = []
    code = run_pipeline(["a", "b", "c"], runner=lambda m: seen.append(m) or 0)
    assert code == 0
    assert seen == ["a", "b", "c"]


def test_pipeline_stops_at_first_failure():
    seen = []

    def runner(module):
        seen.append(module)
        return 3 if module == "b" else 0

    assert run_pipeline(["a", "b", "c"], runner=runner) == 3
    assert seen == ["a", "b"]


def test_healthcheck_fails_cleanly_without_settings(monkeypatch):
    def boom():
        raise ConfigError("no settings")

    monkeypatch.setattr(healthcheck, "make_engine", boom)
    assert healthcheck.main() == 1
