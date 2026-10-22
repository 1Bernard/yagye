#!/usr/bin/env python
"""CLI entry point: Bronze → Silver ETL.

Usage:
    uv run python scripts/run_silver_etl.py
    uv run python scripts/run_silver_etl.py --hours 4
"""

import argparse

from yagye_data.config import settings
from yagye_data.pipeline.silver import run
from yagye_data.shared.logging import configure_logging


def main() -> None:
    configure_logging(use_json=settings.use_json_logging)

    parser = argparse.ArgumentParser(description="Run Silver ETL")
    parser.add_argument(
        "--hours",
        type=int,
        default=None,
        help="Override lookback window in hours (default: from config)",
    )
    args = parser.parse_args()

    run(lookback_hours=args.hours)


if __name__ == "__main__":
    main()
