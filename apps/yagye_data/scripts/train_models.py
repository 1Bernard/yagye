#!/usr/bin/env python
"""CLI entry point: train all ML models and upload ONNX artefacts.

Usage:
    uv run python scripts/train_models.py
    uv run python scripts/train_models.py --model routing_predictor
"""

import argparse

from yagye_data.config import settings
from yagye_data.shared.logging import configure_logging, get_logger
from yagye_data.training.models import (
    churn_predictor,
    reserve_recommender,
    risk_scorer,
    routing_predictor,
)

logger = get_logger(__name__)

_MODELS = {
    "routing_predictor": routing_predictor,
    "risk_scorer": risk_scorer,
    "reserve_recommender": reserve_recommender,
    "churn_predictor": churn_predictor,
}


def main() -> None:
    configure_logging(use_json=settings.use_json_logging)

    parser = argparse.ArgumentParser(description="Train Yagye ML models")
    parser.add_argument(
        "--model",
        choices=list(_MODELS.keys()),
        default=None,
        help="Train only the specified model (default: all)",
    )
    args = parser.parse_args()

    targets = {args.model: _MODELS[args.model]} if args.model else _MODELS
    for name, module in targets.items():
        logger.info("train.start", model=name)
        module.train()
        logger.info("train.done", model=name)


if __name__ == "__main__":
    main()
