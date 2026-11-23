"""Unit tests for the Core DB-backed training data extractors.

These tests run against the local dev DB (postgresql://postgres:postgres@localhost:5432/yagye_core_dev).
They are tagged :db and are excluded from pure-unit CI jobs.
"""

import pytest
import pandas as pd


# ── VelocityFromDB ─────────────────────────────────────────────────────────────

class TestVelocityFromDB:
    @pytest.fixture(scope="class")
    def velocity_df(self):
        from yagye_data.training.data.velocity_from_db import load_velocity_features
        return load_velocity_features()

    def test_returns_dataframe(self, velocity_df):
        assert isinstance(velocity_df, pd.DataFrame)

    def test_has_expected_columns(self, velocity_df):
        expected = {
            "msisdn_hash", "attempt_count_1h", "fail_count_1h", "txn_count_24h",
            "failure_rate", "distinct_merchant_count", "amount_minor",
            "is_momo", "hour_of_day", "day_of_week", "label",
        }
        assert expected.issubset(set(velocity_df.columns))

    def test_non_empty(self, velocity_df):
        assert len(velocity_df) > 0, "Expected at least one MSISDN in the DB"

    def test_labels_are_binary(self, velocity_df):
        assert set(velocity_df["label"].unique()).issubset({0, 1})

    def test_has_both_classes(self, velocity_df):
        assert velocity_df["label"].sum() > 0, "Expected at least one anomalous MSISDN"
        assert (velocity_df["label"] == 0).sum() > 0, "Expected at least one normal MSISDN"

    def test_failure_rate_in_range(self, velocity_df):
        assert (velocity_df["failure_rate"] >= 0).all()
        assert (velocity_df["failure_rate"] <= 1).all()

    def test_no_negative_counts(self, velocity_df):
        for col in ("attempt_count_1h", "fail_count_1h", "txn_count_24h"):
            assert (velocity_df[col] >= 0).all(), f"{col} has negative values"

    def test_burst_msisdns_labeled_anomalous(self, velocity_df):
        """MSISDNs with high 1h count must be labeled anomalous."""
        burst = velocity_df[velocity_df["attempt_count_1h"] >= 10]
        if not burst.empty:
            assert (burst["label"] == 1).all()


# ── ReconFromDB ────────────────────────────────────────────────────────────────

class TestReconFromDB:
    @pytest.fixture(scope="class")
    def recon_df(self):
        from yagye_data.training.data.recon_from_db import load_recon_features
        return load_recon_features(n_synthetic_per_class=50)

    def test_returns_dataframe(self, recon_df):
        assert isinstance(recon_df, pd.DataFrame)

    def test_has_expected_columns(self, recon_df):
        expected = {
            "amount_delta_minor", "abs_delta_minor", "relative_delta",
            "age_hours", "has_right_ref", "settlement_offset_days", "label",
        }
        assert expected.issubset(set(recon_df.columns))

    def test_all_four_classes_present(self, recon_df):
        expected_classes = {"timing_difference", "fee_discrepancy", "missing_on_right", "amount_mismatch"}
        assert expected_classes == set(recon_df["label"].unique())

    def test_relative_delta_capped_at_one(self, recon_df):
        assert (recon_df["relative_delta"] <= 1.0).all()
        assert (recon_df["relative_delta"] >= 0.0).all()

    def test_has_right_ref_binary(self, recon_df):
        assert set(recon_df["has_right_ref"].unique()).issubset({0, 1})

    def test_abs_delta_non_negative(self, recon_df):
        assert (recon_df["abs_delta_minor"] >= 0).all()

    def test_real_rows_present(self, recon_df):
        """Real DB rows exist — missing_on_right count should exceed synthetic (300)."""
        mr_count = (recon_df["label"] == "missing_on_right").sum()
        assert mr_count > 50, "Expected real DB rows to contribute missing_on_right examples"
