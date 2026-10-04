"""Run the whole project in order: load, audit, views, queries, charts."""
from __future__ import annotations

import logging
import subprocess
import sys
import time
from collections.abc import Callable, Sequence

from src.load_data import ROOT, load_config, setup_logging

log = logging.getLogger("olist.pipeline")

STEPS = [
    "src.load_data",
    "src.run_quality_audit",
    "src.create_views",
    "src.run_queries",
    "src.charts",
]


def run_module(module: str) -> int:
    """Run `python -m <module>` in its own process and return its exit code."""
    return subprocess.run([sys.executable, "-m", module], cwd=ROOT, check=False).returncode


def run_pipeline(steps: Sequence[str], runner: Callable[[str], int] = run_module) -> int:
    """Run steps in order. Stop at the first failure and return its exit code."""
    for module in steps:
        start = time.perf_counter()
        log.info("Pipeline step: %s", module)
        code = runner(module)
        if code != 0:
            log.error("Step %s failed with exit code %d. Stopping.", module, code)
            return code
        log.info("Finished %s in %.1fs", module, time.perf_counter() - start)
    log.info("Pipeline finished: %d steps OK", len(steps))
    return 0


def main() -> int:
    cfg = load_config()
    setup_logging(ROOT / cfg["paths"]["log_file"])
    return run_pipeline(STEPS)


if __name__ == "__main__":
    sys.exit(main())
