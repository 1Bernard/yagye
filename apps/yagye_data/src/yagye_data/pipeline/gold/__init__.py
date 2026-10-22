"""Gold ETL: Silver Parquet → pre-aggregated, business-ready Gold Parquet.

Entry point (called by yagye-gold CLI and scripts/run_gold_etl.py):

    from yagye_data.pipeline.gold import main
    main()
"""

import sys
from datetime import UTC, datetime, timedelta

from yagye_data.config import settings
from yagye_data.shared.logging import configure_logging, get_logger
from yagye_data.pipeline.gold import ops_mart, payments_mart, risk_mart

logger = get_logger(__name__)


def run(lookback_hours: int | None = None) -> None:
    hours = lookback_hours or settings.gold_etl_lookback_hours
    window_end = datetime.now(UTC)
    window_start = window_end - timedelta(hours=hours)

    logger.info(
        "gold_etl.start",
        window_start=window_start.isoformat(),
        window_end=window_end.isoformat(),
    )

    for module in (payments_mart, risk_mart, ops_mart):
        module.run(window_start, window_end)

    logger.info("gold_etl.done")


def main() -> None:
    configure_logging(use_json=settings.use_json_logging)
    run()
    sys.exit(0)
