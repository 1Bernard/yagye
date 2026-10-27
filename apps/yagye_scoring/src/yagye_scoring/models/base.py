"""Base class for all ONNX-backed ML models.

Each subclass implements:
  - rule_based_predict(): replicates current static logic, used when ONNX not loaded
  - _build_feature_vector(): converts a features dict to a numpy array

At P20, all models start with is_loaded=False. After P22 training, ONNX files
are uploaded to S3 and the registry loads them on next startup.
"""

from __future__ import annotations

import os
from abc import ABC, abstractmethod
from typing import Any

import numpy as np

try:
    import onnxruntime as ort

    _ORT_AVAILABLE = True
except ImportError:
    _ORT_AVAILABLE = False

from yagye_scoring.shared.logging import get_logger

logger = get_logger(__name__)


class BaseMLModel(ABC):
    def __init__(self, model_name: str) -> None:
        self.model_name = model_name
        self.version: str = "rule_based_fallback"
        self.is_loaded: bool = False
        self._session: Any = None  # ort.InferenceSession when loaded
        self._input_name: str = ""

    def load_from_path(self, path: str) -> None:
        if not _ORT_AVAILABLE:
            logger.warning("onnxruntime not installed — staying on rule-based fallback")
            return
        if not os.path.exists(path):
            logger.warning("model_file_not_found", path=path, model=self.model_name)
            return
        try:
            self._session = ort.InferenceSession(path, providers=["CPUExecutionProvider"])
            self._input_name = self._session.get_inputs()[0].name
            self.is_loaded = True
            # Parse version from path: .../routing_native_rail/v1.0.0/model.onnx
            parts = path.split(os.sep)
            if "v" in "".join(parts[-3:]):
                self.version = next((p for p in reversed(parts) if p.startswith("v")), "v0.0.0")
            logger.info("model_loaded", model=self.model_name, version=self.version)
        except Exception as exc:
            logger.error("model_load_failed", model=self.model_name, error=str(exc))

    def _run_onnx(self, feature_vector: np.ndarray) -> float:
        output = self._session.run(None, {self._input_name: feature_vector})
        # Standard sklearn/XGBoost ONNX output: [labels, probabilities]
        # probabilities shape: (batch, 2) — index 1 is P(class=1)
        return float(output[1][0][1])

    @abstractmethod
    def _build_feature_vector(self, features: dict[str, Any]) -> np.ndarray:
        """Convert a features dict to a (1, n_features) float32 array."""

    @abstractmethod
    def rule_based_predict(self, features: dict[str, Any]) -> float:
        """Fallback prediction when ONNX model is not loaded."""

    def predict(self, features: dict[str, Any]) -> float:
        if self.is_loaded:
            try:
                x = self._build_feature_vector(features)
                return self._run_onnx(x)
            except Exception as exc:
                logger.warning(
                    "onnx_inference_failed_falling_back",
                    model=self.model_name,
                    error=str(exc),
                )
        return self.rule_based_predict(features)
