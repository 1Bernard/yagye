"""ML training entry point: train all models and export ONNX artefacts.

    from yagye_data.training import main
    main()
"""

import sys

from yagye_data.config import settings
from yagye_data.shared.logging import configure_logging, get_logger
from yagye_data.training.models import (
    churn_predictor,
    reserve_recommender,
    risk_scorer,
    routing_predictor,
)

logger = get_logger(__name__)


def run() -> None:
    logger.info("training.start")

    for module in (routing_predictor, risk_scorer, reserve_recommender, churn_predictor):
        module.train()

    logger.info("training.done")


def main() -> None:
    configure_logging(use_json=settings.use_json_logging)
    run()
    sys.exit(0)
