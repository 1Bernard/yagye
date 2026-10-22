"""Gold ETL: Silver Parquet → pre-aggregated, business-ready Gold Parquet.

Entry point (called by yagye-gold CLI and scripts/run_gold_etl.py):

    from yagye_data.pipeline.gold import main
    main()
"""

import sys
import time
import uuid
from datetime import UTC, datetime, timedelta

import structlog

from yagye_data.config import settings
from yagye_data.pipeline.gold import ops_mart, payments_mart, risk_mart
from yagye_data.shared.logging import configure_logging, get_logger

logger = get_logger(__name__)


def run(lookback_hours: int | None = None) -> None:
    run_id = str(uuid.uuid4())
    structlog.contextvars.bind_contextvars(run_id=run_id, etl="gold")

    hours = lookback_hours or settings.gold_etl_lookback_hours
    window_end = datetime.now(UTC)
    window_start = window_end - timedelta(hours=hours)

    t0 = time.monotonic()
    logger.info(
        "gold_etl.start",
        window_start=window_start.isoformat(),
        window_end=window_end.isoformat(),
        lookback_hours=hours,
    )

    for module in (payments_mart, risk_mart, ops_mart):
        t_mod = time.monotonic()
        module.run(window_start, window_end)
        logger.info(
            "gold_etl.module_done",
            module=module.__name__.split(".")[-1],
            duration_s=round(time.monotonic() - t_mod, 2),
        )

    logger.info("gold_etl.done", duration_s=round(time.monotonic() - t0, 2))
    structlog.contextvars.unbind_contextvars("run_id", "etl")


def main() -> None:
    configure_logging(use_json=settings.use_json_logging)
    run()
    sys.exit(0)
