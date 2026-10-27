"""Tests for BaseMLModel fallback behaviour."""

from typing import Any

import numpy as np
import pytest

from yagye_scoring.models.base import BaseMLModel


class ConcreteModel(BaseMLModel):
    def _build_feature_vector(self, features: dict[str, Any]) -> np.ndarray:
        return np.array([[features.get("x", 0.0)]], dtype=np.float32)

    def rule_based_predict(self, features: dict[str, Any]) -> float:
        return 0.42


def test_rule_based_predict_used_when_not_loaded() -> None:
    model = ConcreteModel("test_model")
    assert not model.is_loaded
    assert model.predict({"x": 1.0}) == pytest.approx(0.42)


def test_version_is_fallback_string_when_not_loaded() -> None:
    model = ConcreteModel("test_model")
    assert model.version == "rule_based_fallback"


def test_load_from_nonexistent_path_does_not_raise() -> None:
    model = ConcreteModel("test_model")
    model.load_from_path("/nonexistent/path/model.onnx")
    assert not model.is_loaded
    assert model.predict({}) == pytest.approx(0.42)
