"""Build the 5 README charts from the CSVs exported by src.run_queries."""
from __future__ import annotations

import logging
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # no display needed
import matplotlib.pyplot as plt  # noqa: E402
import pandas as pd  # noqa: E402

from src.load_data import (  # noqa: E402
    ROOT,
    DataValidationError,
    load_config,
    setup_logging,
)

log = logging.getLogger(__name__)
LOG_FILE = ROOT / "logs" / "olist.log"


def load_chart_config() -> dict:
    """Read the `charts` section of config.yaml."""
    cfg = load_config()
    if "charts" not in cfg:
        raise KeyError("Missing 'charts' section in configs/config.yaml")
    return cfg["charts"]


def read_csv_checked(path: Path, required: list[str]) -> pd.DataFrame:
    """Read a CSV and check that it exists, is not empty and has the columns."""
    if not path.exists():
        raise FileNotFoundError(f"{path.name} not found. Run: python -m src.run_queries")
    df = pd.read_csv(path, encoding="utf-8-sig")
    if df.empty:
        raise DataValidationError(f"{path.name} is empty")
    missing = [c for c in required if c not in df.columns]
    if missing:
        raise DataValidationError(f"{path.name} is missing columns: {missing}")
    return df


def drop_low_sample(df: pd.DataFrame) -> pd.DataFrame:
    """Keep only rows where low_sample is false (handles bool or 'True' text)."""
    flag = df["low_sample"].astype(str).str.lower() == "true"
    return df.loc[~flag].copy()


def save(fig: plt.Figure, out_dir: Path, name: str, dpi: int) -> None:
    """Save a figure as PNG and close it."""
    fig.tight_layout()
    fig.savefig(out_dir / name, dpi=dpi)
    plt.close(fig)
    log.info("Saved %s", out_dir / name)


def chart_monthly_revenue(src: Path, out: Path, dpi: int, start_month: str) -> None:
    """Line chart of monthly revenue, low-sample months and early months removed."""
    df = drop_low_sample(
        read_csv_checked(src / "q01_monthly_revenue.csv",
                         ["order_month", "revenue", "low_sample"]))
    df = df[df["order_month"] >= start_month].copy()
    if df.empty:
        raise DataValidationError(f"q01: no months from {start_month} onwards")
    df["month"] = pd.to_datetime(df["order_month"])
    peak = df.loc[df["revenue"].idxmax()]
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.plot(df["month"], df["revenue"], marker="o")
    ax.set_title(f"Monthly revenue peaked at R${peak['revenue']:,.0f} in {peak['order_month']}")
    ax.set_xlabel("Month (low-sample months excluded)")
    ax.set_ylabel("Revenue (R$, excl. freight)")
    ax.grid(alpha=0.3)
    fig.autofmt_xdate()
    save(fig, out, "01_monthly_revenue.png", dpi)


def chart_category_pareto(src: Path, out: Path, dpi: int) -> None:
    """Bars for category revenue plus a cumulative-share line."""
    df = read_csv_checked(
        src / "q02_top_categories.csv",
        ["category", "revenue", "cumulative_share_pct", "revenue_rank"],
    ).sort_values("revenue_rank")
    top_share = df["cumulative_share_pct"].iloc[-1]
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.bar(df["category"], df["revenue"])
    ax.set_ylabel("Revenue (R$)")
    ax.set_xlabel("Category")
    ax.tick_params(axis="x", rotation=45)
    ax2 = ax.twinx()
    ax2.plot(df["category"], df["cumulative_share_pct"], color="tab:red", marker="o")
    ax2.set_ylabel("Cumulative share of total revenue (%)")
    ax2.set_ylim(0, 100)
    ax.set_title(f"Top {len(df)} categories bring {top_share:.1f}% of revenue")
    save(fig, out, "02_category_pareto.png", dpi)


def chart_review_by_delivery(src: Path, out: Path, dpi: int) -> None:
    """Bar chart of bad-review rate per delivery-time bucket."""
    df = read_csv_checked(
        src / "q04_delivery_vs_review__by_delivery_bucket.csv",
        ["delivery_bucket", "bad_review_rate_pct", "orders"],
    ).sort_values("delivery_bucket")
    worst = df.loc[df["bad_review_rate_pct"].idxmax()]
    fig, ax = plt.subplots(figsize=(8, 5))
    bars = ax.bar(df["delivery_bucket"], df["bad_review_rate_pct"])
    ax.bar_label(bars, fmt="%.1f%%")
    ax.set_title(f"Bad-review rate reaches {worst['bad_review_rate_pct']:.1f}% "
                 f"for '{worst['delivery_bucket']}'")
    ax.set_xlabel("Delivery time (purchase to customer)")
    ax.set_ylabel("Bad-review rate (% of reviewed orders)")
    ax.tick_params(axis="x", rotation=15)
    save(fig, out, "03_review_by_delivery.png", dpi)


def chart_cohort_heatmap(src: Path, out: Path, dpi: int, max_offset: int = 12) -> None:
    """Heatmap of cohort retention for months 1..max_offset (month 0 is always 100%)."""
    df = drop_low_sample(read_csv_checked(
        src / "q05_retention__cohort_retention.csv",
        ["cohort_month", "months_since_first", "retention_pct", "low_sample"]))
    df = df[(df["months_since_first"] >= 1) & (df["months_since_first"] <= max_offset)]
    if df.empty:
        raise DataValidationError("q05: no cohort rows left after filtering")
    grid = df.pivot(index="cohort_month", columns="months_since_first",
                    values="retention_pct").sort_index()
    fig, ax = plt.subplots(figsize=(10, 8))
    im = ax.imshow(grid.values, aspect="auto", cmap="Blues")
    ax.set_xticks(range(len(grid.columns)), labels=grid.columns)
    ax.set_yticks(range(len(grid.index)), labels=grid.index)
    for i in range(grid.shape[0]):
        for j in range(grid.shape[1]):
            val = grid.values[i, j]
            if pd.notna(val):
                ax.text(j, i, f"{val:.1f}", ha="center", va="center", fontsize=7)
    fig.colorbar(im, ax=ax, label="Customers active again (%)")
    ax.set_title("Few customers come back: monthly retention stays low")
    ax.set_xlabel("Months since first order")
    ax.set_ylabel("Cohort (first order month; low-sample cohorts excluded)")
    save(fig, out, "04_cohort_retention.png", dpi)


def chart_late_by_state(src: Path, out: Path, dpi: int) -> None:
    """Horizontal bars of late-delivery rate per state, low-sample excluded."""
    df = drop_low_sample(read_csv_checked(
        src / "q03_late_delivery__by_state.csv",
        ["customer_state", "late_rate_pct", "low_sample"]))
    df = df.sort_values("late_rate_pct")
    top = df.iloc[-1]
    fig, ax = plt.subplots(figsize=(8, 8))
    ax.barh(df["customer_state"], df["late_rate_pct"])
    ax.set_title(f"{top['customer_state']} has the highest late rate: "
                 f"{top['late_rate_pct']:.1f}%")
    ax.set_xlabel("Late deliveries (% of delivered orders)")
    ax.set_ylabel("Customer state (low-sample states excluded)")
    save(fig, out, "05_late_rate_by_state.png", dpi)


def main() -> None:
    """Build all charts into the configured images folder."""
    setup_logging(LOG_FILE)
    cfg = load_chart_config()
    src = ROOT / cfg["outputs_dir"]
    out = ROOT / cfg["images_dir"]
    out.mkdir(parents=True, exist_ok=True)
    dpi = int(cfg["dpi"])
    chart_monthly_revenue(src, out, dpi, str(cfg["revenue_start_month"]))
    for fn in (chart_category_pareto, chart_review_by_delivery,
               chart_cohort_heatmap, chart_late_by_state):
        fn(src, out, dpi)
    log.info("All charts done")


if __name__ == "__main__":
    main()