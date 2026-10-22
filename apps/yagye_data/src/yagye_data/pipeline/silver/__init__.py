"""Silver ETL: Bronze Parquet → validated, typed, deduplicated Silver Parquet.

Entry point (called by yagye-silver CLI and scripts/run_silver_etl.py):

    from yagye_data.pipeline.silver import main
    main()
"""

import sys
import time
import uuid
from datetime import UTC, datetime, timedelta

import structlog

from yagye_data.config import settings
from yagye_data.pipeline.silver import merchants, payments, reconciliation, settlements
from yagye_data.shared.logging import configure_logging, get_logger

logger = get_logger(__name__)


def run(lookback_hours: int | None = None) -> None:
    run_id = str(uuid.uuid4())
    structlog.contextvars.bind_contextvars(run_id=run_id, etl="silver")

    hours = lookback_hours or settings.silver_etl_lookback_hours
    window_end = datetime.now(UTC)
    window_start = window_end - timedelta(hours=hours)

    t0 = time.monotonic()
    logger.info(
        "silver_etl.start",
        window_start=window_start.isoformat(),
        window_end=window_end.isoformat(),
        lookback_hours=hours,
    )

    for module in (payments, settlements, merchants, reconciliation):
        t_mod = time.monotonic()
        module.run(window_start, window_end)
        logger.info(
            "silver_etl.module_done",
            module=module.__name__.split(".")[-1],
            duration_s=round(time.monotonic() - t_mod, 2),
        )

    logger.info("silver_etl.done", duration_s=round(time.monotonic() - t0, 2))
    structlog.contextvars.unbind_contextvars("run_id", "etl")


def main() -> None:
    configure_logging(use_json=settings.use_json_logging)
    run()
    sys.exit(0)
