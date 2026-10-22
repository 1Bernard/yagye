"""Silver ETL: Bronze Parquet → validated, typed, deduplicated Silver Parquet.

Entry point (called by yagye-silver CLI and scripts/run_silver_etl.py):

    from yagye_data.pipeline.silver import main
    main()
"""

import sys
from datetime import UTC, datetime, timedelta

from yagye_data.config import settings
from yagye_data.shared.logging import configure_logging, get_logger
from yagye_data.pipeline.silver import merchants, payments, reconciliation, settlements

logger = get_logger(__name__)


def run(lookback_hours: int | None = None) -> None:
    hours = lookback_hours or settings.silver_etl_lookback_hours
    window_end = datetime.now(UTC)
    window_start = window_end - timedelta(hours=hours)

    logger.info("silver_etl.start", window_start=window_start.isoformat(), window_end=window_end.isoformat())

    for module in (payments, settlements, merchants, reconciliation):
        module.run(window_start, window_end)

    logger.info("silver_etl.done")


def main() -> None:
    configure_logging(use_json=settings.use_json_logging)
    run()
    sys.exit(0)
