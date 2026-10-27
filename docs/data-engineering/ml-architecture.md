# ML Architecture

**Last updated:** 2026-10-21

Yagye's ML layer (planned for P20) adds four models to the payment processing
pipeline. This document is the definitive reference for what each model does,
how it is engineered, how it is trained, validated, served, and how it degrades
gracefully when unavailable.

Read `docs/data-engineering/README.md` first — the training pipeline and
feature store are defined there. Read ADR-0023 for the serving architecture
decision.

---

## Table of Contents

1. [Why ML in a PSP — The Business Case](#1-why-ml-in-a-psp--the-business-case)
2. [The Four Models](#2-the-four-models)
3. [Feature Engineering](#3-feature-engineering)
4. [Training Pipeline](#4-training-pipeline)
5. [Model Evaluation and Validation](#5-model-evaluation-and-validation)
6. [Model Registry and Versioning](#6-model-registry-and-versioning)
7. [ONNX Export and Serving](#7-onnx-export-and-serving)
8. [The FastAPI Scoring Service](#8-the-fastapi-scoring-service)
9. [Integration with Yagye Core](#9-integration-with-yagye-core)
10. [A/B Testing and Shadow Mode](#10-ab-testing-and-shadow-mode)
11. [Feedback Loops and Ground Truth](#11-feedback-loops-and-ground-truth)
12. [Graceful Degradation](#12-graceful-degradation)
13. [The Elixir Migration Path](#13-the-elixir-migration-path)
14. [Monitoring and Model Health](#14-monitoring-and-model-health)
15. [Additional ML Opportunities (P22+)](#15-additional-ml-opportunities-p22)

---

## 1. Why ML in a PSP — The Business Case

A PSP generates uniquely valuable labeled training data: for every payment
attempted, it knows exactly what happened — which provider was used, the
exact outcome, latency, amount, time of day, customer risk tier, merchant
sector. This labeled, timestamped, high-volume dataset is precisely what
supervised ML requires.

The four problems ML solves at Yagye:

### Routing: The static health-threshold failure mode

A critical constraint first: **MoMo provider selection is MSISDN-deterministic.**
A customer's phone number belongs to exactly one network. An MTN MSISDN can only
be charged via MTN MoMo. A Vodafone MSISDN can only be charged via Vodafone Cash.
There is no cross-network fallback — the MoMo rails do not allow it. The routing
engine never considers Vodafone as a candidate for an MTN payment.

What the routing engine *can* influence: timing, aggregator selection (if Yagye
ever uses multiple gateway paths to the same network), and the decision to
attempt immediately vs. defer given current provider health.

The static health model is binary: MTN is "up" (circuit closed) or "down"
(circuit open). It misses the gradient:

- MTN's API degrades for specific amount buckets (e.g. > GHS 500) while working
  normally for smaller amounts. The binary circuit treats MTN as uniformly
  available when it is only partially functional.
- Degradation follows time-of-day patterns. MTN consistently shows elevated
  failure rates at peak hours (e.g. weekday afternoons) due to network load.
  A static circuit breaker cannot anticipate this — it only opens *after*
  consecutive failures have already occurred.
- When Yagye operates through multiple aggregators for the same network (e.g.
  two gateway partners both supporting MTN MoMo), the static rule has no basis
  for selecting between them beyond manual priority. The model scores each
  aggregator path against current health signals.

A 5% improvement in attempt success rate has direct revenue impact: fewer failed
payments → fewer refund requests → fewer support tickets → higher merchant
retention.

### Risk: The flat limit failure mode

Flat velocity limits (`max GHS 5000/day for tier_1 customers`) treat all customers
in the same tier as identical. A customer who has successfully processed GHS 50k
over 6 months without a chargeback is not the same risk as a new account making
its first transaction. The risk scorer provides per-transaction risk scores that
enable fine-grained thresholds beyond what flat rules can express.

### Reserve: The fixed percentage failure mode

A fixed rolling reserve (e.g. 5% of volume withheld for 30 days) is conservative
by design — it covers the average merchant's chargeback rate with margin. But
a low-chargeback merchant overpays: their cash flow is locked unnecessarily.
A high-risk merchant underpays: 5% may not cover their actual chargeback exposure.
The reserve recommender calibrates per merchant.

### Churn: The reactive support failure mode

Without churn prediction, Yagye learns a merchant is leaving when they stop
processing payments or submit an account closure request. At that point, retention
is difficult. With churn prediction (behavioural signal analysis), intervention
happens 30–60 days before a merchant reduces volume — when retention is actionable.

---

## 2. The Four Models

### 2.1 Routing Health Predictor

#### Who this model serves

This model is primarily a **Model B (enterprise orchestration) feature**.
Model B merchants connect their own PSP credentials (Stripe, Flutterwave,
Paystack, a second MTN aggregator) via `merchant_provider_connections`. When
multiple providers are eligible for a payment, this model ranks them by
predicted success probability. The merchant's routing graph pre-selects
eligible candidates; the model scores what it is given.

For **Model A (Yagye native rails)** merchants, there is typically one provider
per MNO network — the MSISDN determines the network, and the network determines
the provider. In this case the candidate list has a single item and the model
returns a **go/hold signal**: if the predicted success probability is below the
configured threshold, the payment is queued briefly rather than dispatched
immediately. This is a predictive layer on top of the existing reactive circuit
breaker — it acts before consecutive failures have occurred.

#### The MNO MSISDN constraint

Mobile money networks in Ghana (MTN, Telecel, AirtelTigo) operate independent
subscriber bases. An MTN MSISDN can only be debited via MTN MoMo rails. Telecel
cannot charge an MTN wallet on MTN's behalf, and vice versa. This constraint is
enforced by the MNO settlement infrastructure — it is not a Yagye policy.

**Core enforces this constraint before calling the scoring service.** The routing
engine resolves eligible providers (MSISDN prefix → network → eligible
provider_codes) and passes only those candidates to `/score/routing`. The
scoring service never makes cross-network substitutions — it only scores
pre-filtered candidates.

The only routing choices within a MoMo payment are:
- **Multiple aggregator paths to the same network**: e.g. a Model B merchant
  has both Hubtel-MTN and Expresspay-MTN credentials. Same network, two
  aggregator paths. The model scores which path has a better current success
  rate.
- **Go/hold signal for a single path**: e.g. a Model A merchant with only
  Yagye's native MTN rail. One candidate, one score. Score below threshold →
  brief hold.

For non-MoMo methods (card, bank transfer), there is no MSISDN constraint. A
merchant with Paystack and Flutterwave can route any card payment through either.
This is where multi-candidate ranking provides the most value.

#### Model type

Gradient-boosted trees (XGBoost). Tabular features with non-linear interactions
(provider health × time of day × amount bucket × provider kind). Tree models
consistently outperform linear models on this problem type. Neural networks are
not warranted — the feature space is small and interpretability is important for
ops to trust routing decisions.

Two separate model instances are trained and served:
- `routing_native_rail` — trained on Model A payment data (single aggregator
  path per network). Optimises the go/hold decision.
- `routing_external_psp` — trained on Model B payment data (multiple PSP
  options exercised). Optimises provider selection across PSPs.

The correct instance is selected at inference time based on `provider_kind` in
the request candidates.

#### Input features at inference time

| Feature | Source | Type |
|---|---|---|
| `provider_code` | Pre-filtered by Core routing engine | Categorical |
| `provider_kind` | `providers.kind` (`native_rail` / `external_psp`) | Categorical |
| `network_code` | MTN / Telecel / AirtelTigo (from MSISDN prefix, null for card) | Categorical |
| `payment_method` | `mobile_money` / `card` / `bank_transfer` | Categorical |
| `amount_minor` | Payment params | Continuous |
| `amount_bucket` | `FLOOR(amount / 10000)` | Integer |
| `hour_of_day` | UTC hour of request | Integer (0–23) |
| `day_of_week` | ISO weekday | Integer (0–6) |
| `recent_success_rate_1h` | Gold: provider_health_hourly | Float (0–1) |
| `recent_success_rate_24h` | Gold: provider_health_hourly | Float (0–1) |
| `avg_latency_ms_1h` | Gold: provider_health_hourly | Float |
| `circuit_breaker_state` | Core: in-memory | Categorical (0/1/2) |
| `candidate_count` | len(provider_candidates) in request | Integer |

**Data pipeline note:** `provider_kind` must be carried through the Bronze
event envelope and Silver ETL so it is available as a training feature. The
Silver payments ETL adds a `provider_kind` column joined from the providers
reference (added at P20 Step 0 before training begins).

#### Output

Per-candidate probability score (0–1), sorted descending. Response also
includes `routing_mode` so Core knows which interpretation to apply:

- `routing_mode: "provider_selection"` — multiple candidates, pick the
  highest-scoring one above threshold.
- `routing_mode: "go_hold"` — single candidate, score is a dispatch signal.
  Below threshold: hold briefly and retry; above threshold: dispatch now.

If the score falls below threshold for all candidates: return `routing_mode:
"hold_all"` — Core queues the payment for a brief hold regardless.

**Prediction latency target:** < 10ms at p99. This is on the payment dispatch
critical path. An unresponsive model blocks the payment. (See §12 for degradation.)

**Label:** `CASE WHEN status = 'succeeded' THEN 1 ELSE 0 END` — binary.

**Retraining schedule:** Weekly (Sunday 02:00 UTC). Uses the trailing 90 days
of live payment attempts. Models are trained separately per `provider_kind`
to prevent the Model A distribution from dominating the Model B signal.

#### Shadow mode launch policy

At P20 launch, no real trained models exist — training happens post-P22 when
live payment data has accumulated. The scoring service ships rule-based
fallbacks that replicate Core's current static priority logic. All scoring is
in shadow mode: Core logs both the rule-based decision and the model score, but
acts on the rule-based one. ML activates as champion only after:

1. ≥ 10,000 labeled payments per `provider_kind` per model instance.
2. Offline evaluation passes (AUCPR > baseline, calibration within 5%).
3. 7-day shadow run shows challenger agrees with champion > 90% and improves
   outcomes on disagreements.

---

### 2.2 Risk Scorer

**Question answered:** What is the probability that this transaction is
fraudulent or will result in a chargeback?

**Model type:** Gradient-boosted trees (LightGBM). Faster inference than XGBoost
for this problem, with comparable accuracy on tabular fraud features.

**Input features at inference time:**

| Feature | Source | Type |
|---|---|---|
| `amount_minor` | Payment params | Continuous |
| `amount_z_score` | `(amount - merchant_mean) / merchant_std` | Float |
| `customer_msisdn_hash` | Payment params (hashed) | Categorical |
| `customer_attempt_count_1h` | Gold: risk_features_hourly | Integer |
| `customer_fail_count_1h` | Gold: risk_features_hourly | Integer |
| `customer_distinct_merchants_1h` | Gold: risk_features_hourly | Integer |
| `customer_amount_total_1h` | Gold: risk_features_hourly | Integer |
| `customer_kyc_tier` | Core: customer record | Categorical |
| `merchant_chargeback_rate_30d` | Gold: merchant_features_weekly | Float |
| `merchant_sector` | Reference: merchants | Categorical |
| `hour_of_day` | UTC hour | Integer |
| `day_of_week` | ISO weekday | Integer |
| `is_new_customer` | Core: customer created_at < 7 days ago | Boolean |
| `is_new_msisdn_for_merchant` | Core: first time this MSISDN for merchant | Boolean |

**Output:** Risk score 0–1. Thresholds:
- `score < 0.3` → allow, no additional friction
- `0.3 ≤ score < 0.7` → allow, flag for ops review queue
- `score ≥ 0.7` → block, return `payment_blocked_risk_score` error

Thresholds are configurable in the database (`risk_thresholds` table),
not hardcoded. Compliance can tune without a code deployment.

**Label:** `1` if the payment resulted in a chargeback within 90 days, else `0`.
This requires a 90-day label lag — the model can only train on payments where
the chargeback window has closed. Training data must exclude the most recent 90
days.

**Class imbalance:** Fraud rates are typically 0.1–1% of volume. The training
dataset is heavily imbalanced. Mitigations:
- `scale_pos_weight = (negative_count / positive_count)` in LightGBM
- Evaluation metric: AUCPR (area under Precision-Recall curve) — not AUC-ROC
  which is misleading for imbalanced classes
- Threshold tuning on the validation set to hit a target precision at 70% recall

**Retraining schedule:** Weekly. Label lag: exclude last 90 days (chargeback
window must close before labeling). Minimum positive examples required: 500
chargebacks in the training window. If fewer, retrain is skipped and an alert fires.

---

### 2.3 Reserve Recommender

**Question answered:** What rolling reserve percentage and duration is
appropriate for this specific merchant?

**Model type:** XGBoost regression (predicts optimal reserve percentage).
This is a regression problem, not classification — the output is a continuous
reserve rate, not a category.

**Input features:**

| Feature | Source | Type |
|---|---|---|
| `merchant_id` | Merchant record | Categorical (embedding) |
| `monthly_volume_ghs` | Gold: merchant_features_weekly | Continuous |
| `chargeback_rate_90d` | Gold: merchant_features_weekly | Float |
| `chargeback_rate_180d` | Gold: merchant_features_weekly | Float |
| `dispute_rate_90d` | Gold: merchant_features_weekly | Float |
| `settlement_failure_count_90d` | Gold: merchant_features_weekly | Integer |
| `merchant_sector` | Reference | Categorical |
| `merchant_kyb_tier` | Core: merchant record | Categorical |
| `merchant_age_days` | Core: merchant created_at | Integer |
| `avg_payment_amount` | Gold: merchant_features_weekly | Continuous |
| `payment_amount_std` | Gold: merchant_features_weekly | Continuous |
| `peak_volume_ratio` | max_daily / avg_daily (seasonality) | Float |

**Label (target variable):** The required reserve rate such that 99.5% of
potential chargeback exposures are covered. This is computed actuarially from
historical chargeback data:

```python
# Label computation
def compute_required_reserve_rate(merchant_id: str, window: int = 90) -> float:
    chargebacks = get_chargebacks(merchant_id, last_n_days=window)
    volume = get_volume(merchant_id, last_n_days=window)
    if len(chargebacks) < 5:
        return default_reserve_rate  # insufficient data
    # 99.5th percentile of chargeback exposure as % of volume
    return np.percentile(chargeback_amounts / volume, 99.5)
```

**Output:** Recommended reserve rate (float, e.g. 0.035 = 3.5%) and duration
(integer days, e.g. 30). The ops team reviews the recommendation in the portal
before applying it — the model advises, humans decide. No automated reserve
changes.

**Retraining schedule:** Monthly (1st Sunday). Reserve calibration does not
need weekly freshness — merchant risk profiles change slowly.

---

### 2.4 Merchant Churn Predictor

**Question answered:** What is the probability that this merchant will reduce
volume by > 50% or close their account in the next 30 days?

**Model type:** XGBoost binary classification. The churn signal is sparse (most
merchants don't churn in any given month), so gradient boosted trees with
`scale_pos_weight` tuning are appropriate.

**Input features (trailing 90 days per merchant):**

| Feature | Source | Type |
|---|---|---|
| `volume_trend_90d` | Slope of weekly volume over 90 days | Float |
| `volume_week_over_week` | (last_week / prev_week) - 1 | Float |
| `active_days_30d` | Days with at least one payment | Integer |
| `success_rate_30d` | Succeeded / total attempts | Float |
| `support_ticket_count_30d` | From CRM (future) | Integer |
| `api_error_rate_30d` | 4xx + 5xx / total API calls | Float |
| `failed_webhook_count_30d` | portal_webhook_deliveries failures | Integer |
| `last_login_days_ago` | portal_audit_events | Integer |
| `merchant_age_days` | created_at | Integer |
| `merchant_sector` | Reference | Categorical |
| `has_active_dispute` | Core: open disputes | Boolean |
| `pricing_change_30d` | Did plan change recently | Boolean |

**Label:** `1` if merchant volume dropped > 50% or account closed within the
next 30 days. This requires a 30-day forward-looking label — training uses
historical windows with known outcomes.

**Output:** Churn probability score 0–1. Merchants with `score > 0.65` appear
in the ops dashboard's churn risk queue. The account management team follows up.

**Retraining schedule:** Monthly.

---

## 3. Feature Engineering

### The fundamental rule: training features = serving features

Training-serving skew is the most common source of model accuracy degradation
in production. It occurs when the feature computation at training time differs
from the computation at serving time.

Example of skew:
```python
# Training: "success_rate_1h" computed from 90-day historical batch
training_df["success_rate_1h"] = training_df.groupby(
    ["provider_code", "hour"]
)["succeeded"].transform("mean")  # ← computes mean over the ENTIRE window

# Serving: "success_rate_1h" computed from the actual last 1 hour
select count(succeeded) / count(*) from payment_attempts
where provider_code = $code
  and effective_at >= now() - interval '1 hour'
```

These are different computations. The model was trained on group means;
it is served actual 1-hour windows. This is skew.

**Yagye's approach:** Feature computation is centralised in DuckDB SQL,
run identically for training (on historical data) and for Gold table population
(for serving). The same SQL query is the source of truth for both.

```python
# features.py — shared between training and serving
PROVIDER_SUCCESS_RATE_1H = """
  SELECT
    provider_code,
    DATE_TRUNC('hour', effective_at) AS hour,
    AVG(CASE WHEN status = 'succeeded' THEN 1.0 ELSE 0.0 END) AS success_rate_1h
  FROM silver_payments
  WHERE mode = 'live'
  GROUP BY 1, 2
"""
```

At training time: this SQL runs over 90 days of Silver data.
For Gold table population: this SQL runs over the last 1 hour, writes to
`provider_health_hourly`, and the serving layer reads from there.

### Categorical feature encoding

Tree models handle categorical features natively if encoded consistently.
Yagye uses integer encoding (not one-hot) for categories with cardinality > 10:

```python
from sklearn.preprocessing import OrdinalEncoder

encoder = OrdinalEncoder(
    handle_unknown="use_encoded_value",
    unknown_value=-1
)

categorical_features = ["provider_code", "network_code", "merchant_sector"]
X[categorical_features] = encoder.fit_transform(X[categorical_features])
```

The fitted encoder is saved as part of the model artifact (alongside the ONNX
model) so that serving uses the same category → integer mapping.

### Missing feature handling

Some features are unavailable at inference time (e.g. `recent_success_rate_1h`
is null if the Gold table is stale). The training pipeline introduces synthetic
null values at the feature engineering step:

```python
# During training: randomly null out 5% of real-time features
# so the model learns to handle missing values
import numpy as np

for col in realtime_features:
    mask = np.random.random(len(X)) < 0.05
    X.loc[mask, col] = np.nan
```

XGBoost and LightGBM handle NaN values natively — they route NaN examples to
the branch that minimises loss. This means the model degrades gracefully when
real-time features are unavailable, rather than crashing.

---

## 4. Training Pipeline

### Pipeline architecture

```
Weekly cron (Sunday 02:00 UTC):
  1. Extract training dataset (DuckDB → Parquet)
  2. Feature engineering (DuckDB SQL → feature_matrix.parquet)
  3. Train candidate model (Python: XGBoost / LightGBM)
  4. Evaluate against holdout set (metrics)
  5. Compare to production model (challenger vs champion)
  6. If challenger wins: register new model version
  7. Shadow deploy (serve alongside champion, compare predictions)
  8. If shadow metrics hold: promote to champion (gradual rollout)
  9. Archive old model version (keep in S3 indefinitely)
```

### Step 1 & 2: Dataset extraction

```python
# scripts/training/routing_predictor_features.py
import duckdb
import boto3

con = duckdb.connect()
con.execute(f"""
  INSTALL httpfs; LOAD httpfs;
  SET s3_endpoint = '{S3_ENDPOINT}';

  COPY (
    SELECT
      p.payment_id,
      p.provider_code,
      p.network_code,
      FLOOR(p.amount_minor / 10000.0)::INTEGER AS amount_bucket,
      EXTRACT(HOUR FROM p.effective_at)::INTEGER AS hour_of_day,
      EXTRACT(DOW FROM p.effective_at)::INTEGER AS day_of_week,
      COALESCE(ph.success_rate_1h, 0.85) AS recent_success_rate_1h,
      COALESCE(ph.success_rate_24h, 0.85) AS recent_success_rate_24h,
      COALESCE(ph.p95_latency_ms, 2000.0) AS avg_latency_ms_1h,
      CASE WHEN p.status = 'succeeded' THEN 1 ELSE 0 END AS label
    FROM read_parquet('s3://yagye-lake-silver/payments/**/*.parquet') p
    LEFT JOIN read_parquet('s3://yagye-lake-gold/provider_health_hourly/**/*.parquet') ph
      ON ph.provider_code = p.provider_code
      AND ph.hour = DATE_TRUNC('hour', p.effective_at)
    WHERE p.effective_date BETWEEN CURRENT_DATE - 90 AND CURRENT_DATE - 1
      AND p.mode = 'live'
      AND p.payment_method_type = 'mobile_money'
    ORDER BY RANDOM()  -- shuffle for training
  ) TO 's3://yagye-lake-gold/ml_training/routing_predictor/snapshot_{today}.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
""")
```

### Step 3: Training

```python
import xgboost as xgb
import pandas as pd
from sklearn.model_selection import train_test_split

df = pd.read_parquet(f"s3://yagye-lake-gold/ml_training/routing_predictor/snapshot_{today}.parquet")

feature_cols = [
    "provider_code_enc", "network_code_enc", "amount_bucket",
    "hour_of_day", "day_of_week",
    "recent_success_rate_1h", "recent_success_rate_24h", "avg_latency_ms_1h"
]

X = df[feature_cols]
y = df["label"]

# Time-based split: train on first 80 days, validate on last 10 days
# (not random split — avoids temporal leakage)
cutoff = df["effective_date"].quantile(0.9)
X_train, X_val = X[df["effective_date"] < cutoff], X[df["effective_date"] >= cutoff]
y_train, y_val = y[df["effective_date"] < cutoff], y[df["effective_date"] >= cutoff]

model = xgb.XGBClassifier(
    n_estimators=500,
    max_depth=6,
    learning_rate=0.05,
    subsample=0.8,
    colsample_bytree=0.8,
    eval_metric="aucpr",  # PR-AUC for imbalanced classes
    early_stopping_rounds=20,
    tree_method="hist",   # fast training
)

model.fit(
    X_train, y_train,
    eval_set=[(X_val, y_val)],
    verbose=50
)
```

### Time-based train/validation split

A critical training discipline: **never use random splits on time-series data.**

If the dataset is split randomly, examples from the future (e.g. December) appear
in the training set, and the model learns from them. At serving time, December
is still in the future — the model was trained on information it cannot have.
This is temporal leakage, and it produces optimistic training metrics that collapse
in production.

Yagye always splits on a date cutoff:
- Training set: days 1–80 of the 90-day window
- Validation set: days 81–90

The validation set comes after the training set chronologically. Metrics on the
validation set are a reliable predictor of production performance.

---

## 5. Model Evaluation and Validation

### Metrics by model

| Model | Primary metric | Secondary metrics | Minimum threshold |
|---|---|---|---|
| Routing predictor | AUC-PR | Accuracy@top-1, lift vs static rules | AUC-PR > 0.75 |
| Risk scorer | AUC-PR | Precision@70% recall, false positive rate | AUC-PR > 0.65 |
| Reserve recommender | MAE (mean absolute error) | Coverage @99.5% | MAE < 0.5% |
| Churn predictor | AUC-PR | Precision@top-20% merchants | AUC-PR > 0.70 |

### Champion-challenger comparison

A new model version is only promoted to production if it outperforms the current
champion on both:
1. The holdout validation set (fresh data not used in training)
2. Shadow mode metrics (see §10)

```python
# Model comparison
champion_auc = evaluate_model(champion_model, X_val, y_val)
challenger_auc = evaluate_model(challenger_model, X_val, y_val)

if challenger_auc > champion_auc + 0.02:  # 2% improvement threshold
    register_as_candidate(challenger_model)
    start_shadow_mode(challenger_model)
else:
    archive_challenger(challenger_model)
    log_no_improvement(champion_auc, challenger_auc)
```

The 2% improvement threshold prevents constant model churn from noise in the
validation metrics.

### Feature importance and interpretability

XGBoost's `feature_importances_` are logged with every trained model:

```python
importances = pd.Series(
    model.feature_importances_,
    index=feature_cols
).sort_values(ascending=False)
# Log to MLflow / S3 for audit
```

This serves two purposes:
1. **Debugging.** If the routing predictor starts routing everything to Vodafone,
   the feature importances reveal which feature changed (e.g. `recent_success_rate_1h`
   became dominant after MTN's degradation period).
2. **Regulatory auditability.** A regulator asking "why was this payment routed
   through provider X?" deserves an answer based on observable features, not a
   black-box "the model said so."

---

## 6. Model Registry and Versioning

### What the model registry stores

Every trained model version is stored in S3 with full provenance:

```
s3://yagye-ml-models/
  routing_predictor/
    v1.0.0/
      model.onnx                    ← the model (runtime-agnostic)
      encoder.pkl                   ← fitted OrdinalEncoder for categorical features
      feature_config.json           ← feature names, types, defaults
      training_metadata.json        ← training date, data window, metrics
      champion.flag                 ← present if this is the current champion
    v1.1.0/
      model.onnx
      ...
  risk_scorer/
    v2.0.0/
      model.onnx
      ...
```

`training_metadata.json` example:

```json
{
  "model_type": "routing_predictor",
  "version": "1.1.0",
  "trained_at": "2026-10-13T02:00:00Z",
  "training_window_start": "2026-07-14",
  "training_window_end": "2026-10-12",
  "training_rows": 1847293,
  "positive_rate": 0.823,
  "validation_auc_pr": 0.831,
  "champion_auc_pr": 0.809,
  "improvement_pct": 2.7,
  "feature_importance": {
    "recent_success_rate_1h": 0.41,
    "hour_of_day": 0.18,
    "provider_code_enc": 0.15,
    ...
  }
}
```

### Semantic versioning for models

- `MAJOR.MINOR.PATCH`
- `MAJOR` — breaking change to input feature schema (requires serving layer update)
- `MINOR` — new features added (backward-compatible with serving layer)
- `PATCH` — same features, retraining only (hyperparameter change, more data)

The serving layer (FastAPI) always loads the model version pinned in the
`champion.flag` marker. Promoting a new champion is an S3 write — no code
deployment required.

---

## 7. ONNX Export and Serving

### Why ONNX

ONNX (Open Neural Network Exchange) is an open format for ML model exchange.
It represents a trained model as a computation graph that any ONNX-compatible
runtime can execute.

Training in Python (XGBoost, LightGBM, scikit-learn) and serving in Python
(FastAPI + ONNX Runtime) works. But ONNX also provides a migration path to
Elixir serving (Nx/Ortex) without retraining — the same ONNX file runs in both
runtimes. This is why we export to ONNX rather than serving the native XGBoost
model.

```python
# Export XGBoost → ONNX
from skl2onnx.common.data_types import FloatTensorType
import onnxmltools

initial_type = [("float_input", FloatTensorType([None, len(feature_cols)]))]
onnx_model = onnxmltools.convert_xgboost(
    model,
    initial_types=initial_type,
    target_opset=17
)

with open("model.onnx", "wb") as f:
    f.write(onnx_model.SerializeToString())
```

### ONNX Runtime inference

```python
import onnxruntime as ort
import numpy as np

class RoutingPredictor:
    def __init__(self, model_path: str):
        self.session = ort.InferenceSession(
            model_path,
            providers=["CPUExecutionProvider"]
        )
        self.input_name = self.session.get_inputs()[0].name

    def predict(self, features: dict) -> float:
        # Build feature vector in correct column order
        x = np.array([[
            features["provider_code_enc"],
            features["network_code_enc"],
            features["amount_bucket"],
            features["hour_of_day"],
            features["day_of_week"],
            features.get("recent_success_rate_1h", 0.85),  # default on null
            features.get("recent_success_rate_24h", 0.85),
            features.get("avg_latency_ms_1h", 2000.0)
        ]], dtype=np.float32)

        output = self.session.run(None, {self.input_name: x})
        return float(output[1][0][1])  # probability of class 1 (success)
```

ONNX Runtime inference is:
- **Fast.** Single-row inference in < 1ms on CPU. The p99 SLA (10ms) includes
  network, serialisation, and feature fetch — the model inference itself is
  well under 1ms.
- **Thread-safe.** `ort.InferenceSession` is thread-safe. The FastAPI scoring
  service uses a single loaded session shared across all request handlers.
- **Memory-efficient.** The ONNX model is loaded once at startup and held in
  memory. A typical XGBoost ONNX model is 2–20 MB.

---

## 8. The FastAPI Scoring Service

### Architecture

```
yagye_core (Elixir)
    │ Req.post/2 (non-blocking)
    │ POST http://scoring:8000/score/routing
    │ body: {provider_candidates: [...], payment_context: {...}}
    ▼
scoring service (FastAPI / Python)
    │
    ├─ Feature fetch: Redis cache → Gold Parquet fallback
    │
    ├─ Feature assembly: build numpy array from features + payment context
    │
    ├─ ONNX Runtime: session.run() → probabilities
    │
    └─ Response: {provider_scores: [{provider_code, score}, ...]}
    ▼
yagye_core
    Select highest-scoring provider that has an active routing rule
```

### Service structure

```
scoring/
  main.py               ← FastAPI app factory
  routers/
    routing.py          ← POST /score/routing
    risk.py             ← POST /score/risk
    reserve.py          ← POST /score/reserve
    churn.py            ← POST /score/churn
  models/
    routing_predictor.py  ← model loading + inference
    risk_scorer.py
    reserve_recommender.py
    churn_predictor.py
  features/
    provider_health.py    ← Redis + Parquet feature fetch
    merchant_risk.py
    customer_risk.py
  config.py             ← model paths, Redis config, S3 config
```

### Routing endpoint

Core calls this endpoint after its routing engine has already applied the MSISDN
network constraint and merchant entitlement filters. The scoring service only
scores what it is given — it never makes cross-network substitutions.

```python
# routers/routing.py
from fastapi import APIRouter
from pydantic import BaseModel
from typing import Literal

router = APIRouter()

class ProviderCandidate(BaseModel):
    provider_code: str
    provider_kind: Literal["native_rail", "external_psp"]

class RoutingScoringRequest(BaseModel):
    payment_id: str
    # Pre-filtered by Core: MSISDN constraint + merchant entitlements already applied.
    # 1 candidate → go/hold signal (Model A). N candidates → provider selection (Model B).
    provider_candidates: list[ProviderCandidate]
    payment_method: str           # "mobile_money" | "card" | "bank_transfer"
    network_code: str | None      # MTN/Telecel/AirtelTigo for MoMo; null for card/bank
    amount_minor: int
    hour_of_day: int              # UTC hour
    day_of_week: int              # ISO weekday (0=Mon)

class ProviderScore(BaseModel):
    provider_code: str
    provider_kind: str
    score: float                  # P(success), 0–1

class RoutingScoringResponse(BaseModel):
    payment_id: str
    # Sorted descending by score. Pick provider_scores[0] for provider selection.
    provider_scores: list[ProviderScore]
    routing_mode: Literal["provider_selection", "go_hold", "hold_all"]
    # provider_selection: multiple candidates, pick highest above threshold
    # go_hold:           single candidate, score is a dispatch signal
    # hold_all:          all candidates below threshold, queue for retry
    model_version: str
    feature_source: Literal["realtime", "degraded_cache", "static_fallback"]

@router.post("/score/routing", response_model=RoutingScoringResponse)
async def score_routing(req: RoutingScoringRequest):
    features, source = await feature_service.get_provider_features(
        [c.provider_code for c in req.provider_candidates]
    )

    # Select model instance based on provider_kind of the first candidate.
    # Mixed-kind candidate lists (rare in practice) use external_psp model.
    kinds = {c.provider_kind for c in req.provider_candidates}
    model = routing_model_external if "external_psp" in kinds else routing_model_native

    scores = []
    for candidate in req.provider_candidates:
        score = model.predict({
            "provider_code_enc": encoder.transform([[candidate.provider_code]])[0][0],
            "provider_kind_enc": encoder.transform([[candidate.provider_kind]])[0][0],
            "payment_method_enc": encoder.transform([[req.payment_method]])[0][0],
            "network_code_enc": encoder.transform([[req.network_code or "none")])[0][0],
            "amount_bucket": req.amount_minor // 10000,
            "hour_of_day": req.hour_of_day,
            "day_of_week": req.day_of_week,
            "candidate_count": len(req.provider_candidates),
            **features.get(candidate.provider_code, DEFAULT_FEATURES)
        })
        scores.append(ProviderScore(
            provider_code=candidate.provider_code,
            provider_kind=candidate.provider_kind,
            score=score,
        ))

    sorted_scores = sorted(scores, key=lambda s: s.score, reverse=True)
    threshold = settings.routing_score_threshold  # default 0.60

    if all(s.score < threshold for s in sorted_scores):
        routing_mode = "hold_all"
    elif len(sorted_scores) == 1:
        routing_mode = "go_hold"
    else:
        routing_mode = "provider_selection"

    return RoutingScoringResponse(
        payment_id=req.payment_id,
        provider_scores=sorted_scores,
        routing_mode=routing_mode,
        model_version=model.version,
        feature_source=source,
    )
```

### Health and readiness endpoints

```python
@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/ready")
def ready():
    # Confirm all models are loaded and Redis is reachable
    checks = {
        "routing_model": routing_model.is_loaded,
        "risk_model": risk_model.is_loaded,
        "redis": redis_client.ping()
    }
    if all(checks.values()):
        return {"status": "ready", "checks": checks}
    raise HTTPException(503, detail=checks)
```

Kubernetes (or Docker Compose in dev) uses `/ready` for readiness probes.
The service is only added to the upstream pool after all models are loaded.
Model loading at startup can take 2–3 seconds for large ONNX files.

---

## 9. Integration with Yagye Core

### The routing integration point

The routing engine in `YagyeCore.Routing` calls the scoring service for all
merchants once ML is activated (post-P22, after model training). During P20
launch, all calls are in shadow mode — the rule-based decision is used, but
both decisions are logged for comparison.

The MSISDN network constraint is applied by Core before this call. The scoring
service receives only pre-filtered candidates — it never makes cross-network
substitutions.

```elixir
defmodule YagyeCore.Routing do
  # Called by PaymentDispatchWorker after eligible providers are resolved.
  # candidates: list of %{provider_id, provider_code, provider_kind} maps —
  # already filtered for MSISDN network constraint + circuit breaker state.
  def evaluate_with_ml(candidates, payment_attrs) do
    if ml_shadow_or_active?() do
      score_with_ml(candidates, payment_attrs)
    else
      static_priority(candidates)
    end
  end

  defp score_with_ml(candidates, payment_attrs) do
    payload = %{
      payment_id: payment_attrs.payment_id,
      provider_candidates: Enum.map(candidates, fn c ->
        %{provider_code: c.provider_code, provider_kind: c.provider_kind}
      end),
      payment_method: payment_attrs.method,
      network_code: payment_attrs.network_code,
      amount_minor: payment_attrs.amount,
      hour_of_day: DateTime.utc_now().hour,
      day_of_week: Date.day_of_week(Date.utc_today())
    }

    case Req.post(scoring_url("/score/routing"), json: payload, receive_timeout: 5_000) do
      {:ok, %{status: 200, body: body}} ->
        handle_routing_response(body, candidates, payment_attrs)

      {:error, _} ->
        # Scoring service unreachable → static fallback (see §12)
        static_priority(candidates)
    end
  end

  defp handle_routing_response(body, candidates, payment_attrs) do
    routing_mode = body["routing_mode"]
    top_score = List.first(body["provider_scores"])

    # Always log for shadow-mode comparison and feedback loop
    Logger.info(%{
      event: "routing.ml_scored",
      payment_id: payment_attrs.payment_id,
      routing_mode: routing_mode,
      ml_top_provider: top_score["provider_code"],
      ml_top_score: top_score["score"],
      feature_source: body["feature_source"],
      model_version: body["model_version"]
    })

    case routing_mode do
      "hold_all" ->
        # All candidates below threshold — queue briefly and retry
        {:hold, :ml_low_confidence}

      "go_hold" when top_score["score"] < @hold_threshold ->
        {:hold, :ml_low_confidence}

      _ ->
        # provider_selection or go_hold above threshold — use ML top choice
        # if ML is champion; use static_priority if ML is still in shadow mode
        if ml_active?() do
          provider_code = top_score["provider_code"]
          Enum.find(candidates, fn c -> c.provider_code == provider_code end)
        else
          static_priority(candidates)  # shadow mode: log but don't act
        end
    end
  end
end
```

**Model A (single native_rail candidate):** `routing_mode` will be `"go_hold"`
or `"hold_all"`. Core's `PaymentDispatchWorker` respects `:hold` by scheduling
a brief delay before the next dispatch attempt — a predictive layer on top of
the existing reactive circuit breaker.

**Model B (multiple PSP candidates):** `routing_mode` will be
`"provider_selection"`. Core picks the top-scoring provider. The merchant's
routing graph already pre-filtered which PSPs are eligible; ML ranks them.

### Risk score integration point

The risk scorer is called in `YagyeCore.Payments.create_payment/2` before the
idempotency claim:

```elixir
def create_payment(merchant_id, attrs) do
  with :ok <- check_velocity(merchant_id, attrs),
       {:ok, score} <- RiskScorer.score(merchant_id, attrs),
       :ok <- check_risk_threshold(score),
       ... do
    # proceed
  end
end
```

A risk score above the `high` threshold returns `{:error, :payment_blocked_risk_score}`
which maps to HTTP 422 with error code `payment_blocked_risk_score`.

The risk score is stored on the `payment_attempts` row:
```sql
payment_attempts.risk_score float  -- 0.0 to 1.0, null if scoring unavailable
```

This enables post-hoc analysis: "of all payments that scored > 0.7, what was
the actual chargeback rate?" — the feedback loop that validates model accuracy.

---

## 10. A/B Testing and Shadow Mode

### P20 launch: everything starts in shadow mode

At P20 launch, no trained ML models exist — training happens post-P22 when
live payment data has accumulated. The scoring service ships with rule-based
fallbacks that replicate Core's current static priority logic.

During P20–P22:
- The scoring service is called on every payment dispatch.
- The rule-based fallback is the **de facto champion** (Core acts on it).
- The scoring service response is logged but not acted on.
- This shadow period builds the comparison dataset before real models are trained.

ML activates as champion only after all three gates pass per model instance:

| Gate | Requirement |
|---|---|
| Data volume | ≥ 10,000 labeled payments per `provider_kind` |
| Offline eval | AUCPR > rule-based baseline; calibration within 5% |
| Shadow run | 7 days; agreement with rule-based > 90%; challenger improves outcomes on disagreements |

Activation is a DB flag (`routing_ml_rollout_percent`) — no code deployment.
Set to 0 (shadow only) → 5 → 20 → 50 → 100 over 14 days. Instant rollback by
setting back to 0.

### Shadow mode: the safe way to validate a new model version

Once ML is active as champion, a new model version runs in shadow mode before
replacing it:
1. The champion model makes the routing decision (actual traffic).
2. The challenger model is called simultaneously (shadow).
3. Both predictions are logged.
4. No business logic uses the challenger's prediction.

```elixir
defp score_with_ml(candidates, payment_attrs) do
  champion_task = Task.async(fn -> call_scoring_service(:champion, ...) end)
  challenger_task = Task.async(fn -> call_scoring_service(:challenger, ...) end)

  champion_result = Task.await(champion_task, 5_000)
  challenger_result = Task.await(challenger_task, 5_000)

  # Log both predictions for offline comparison
  Logger.info(%{
    champion_provider: champion_result.provider,
    challenger_provider: challenger_result.provider,
    payment_id: payment_attrs.payment_id,
    mode: "shadow"
  })

  # Only the champion's result is used
  champion_result
end
```

After 7 days of shadow mode, the comparison dashboard shows:
- Do champion and challenger agree on provider selection? (agreement rate)
- On disagreements: which model's choice has higher success rate?
- What is the challenger's latency distribution?

If challenger agreement rate with champion is > 95% (models mostly agree) and
challenger disagrees suggest better providers (challenger choice leads to success
more often when they differ): promote challenger to champion.

### Percentage rollout

After shadow mode, a new champion can be rolled out gradually:
- Day 1: 5% of payments use the new model
- Day 3: 20%
- Day 7: 50%
- Day 14: 100%

Rollout percentage is controlled by a `routing_ml_rollout_percent` config in
the database — adjustable without a code deployment. If error rates spike
during rollout, the percentage is set back to 0 (instant rollback).

---

## 11. Feedback Loops and Ground Truth

### Why feedback loops are critical

A model trained on historical data degrades over time as the world changes.
Provider networks evolve. Customer behaviour shifts. Fraud patterns adapt to
detection. Without feedback loops, a model trained 6 months ago continues to
run on stale assumptions.

Feedback loops close the circuit: **the model's predictions influence actions,
actions generate outcomes, outcomes flow back as labels for the next training run.**

### Routing predictor feedback loop

```
Payment dispatched using ML-selected provider
    │ (payment_attempts.provider_code, routing_score stored)
    ▼
Payment outcome: succeeded | failed | timed_out
    │ (payment_attempts.status updated)
    ▼
Silver ETL joins payment attempts with their outcomes
    │ (effective_date of outcome is the label date)
    ▼
Gold table: provider_health_hourly updated
    ▼
Next week's training dataset includes new outcomes
    ▼
Challenger model trained on updated data
    ▼
Shadow mode comparison: does challenger outperform champion on new data?
```

The key: `payment_attempts.routing_score` stores the ML score at dispatch time.
Post-hoc analysis can answer: "did the model's confidence correlate with actual
success?" — the calibration check.

### Risk scorer feedback loop

```
Payment allowed with risk_score = 0.45 (below threshold)
    │ (payment_attempts.risk_score stored)
    ▼
90 days later: chargeback received or not
    │ (disputes table, chargeback_received_at)
    ▼
Silver ETL joins payment attempts with dispute outcomes
    │ Label: 1 if chargeback within 90 days, else 0
    ▼
Next monthly training dataset includes new labelled examples
    ▼
Risk scorer retrained with new fraud patterns
```

The 90-day chargeback window creates a label lag. The risk scorer training
dataset always excludes the most recent 90 days — those payments' chargeback
status is not yet known.

### Data drift monitoring

Model accuracy degrades when the input feature distribution changes (data drift).
Yagye monitors for drift weekly:

```python
# Drift detection: compare feature distributions
# between current week and the training window
from evidently import Report
from evidently.metrics import DatasetDriftMetric

reference_df = load_training_features(last_training_date)
current_df = load_serving_features(last_7_days)

report = Report(metrics=[DatasetDriftMetric()])
report.run(reference_data=reference_df, current_data=current_df)

if report.as_dict()["metrics"][0]["result"]["dataset_drift"]:
    alert_ml_team("Feature drift detected — consider retraining")
```

Significant drift without a concurrent retraining is a model health alert.

---

## 12. Graceful Degradation

### The scoring service is on the payment critical path

The routing predictor call is made during payment dispatch. If the scoring
service is unavailable and the call blocks, the payment is delayed or fails.
This is unacceptable.

**Hard timeout:** `Req.post` has a `receive_timeout: 5_000` (5 seconds). After
5 seconds, the call times out and the fallback activates.

**Three-tier fallback:**

```
Tier 1 (preferred): ML routing — scoring service healthy, real-time features fresh
  → call scoring service, use ML scores

Tier 2 (degraded): Static routing with stale features
  → scoring service unavailable, but circuit breaker metrics in Redis
  → use circuit_breaker_state to avoid known-down providers
  → use static priority rules for remaining providers

Tier 3 (bare fallback): Static priority rules only
  → both scoring service AND Redis unavailable
  → use routing_rules.priority column, ordered by priority ASC
```

```elixir
defp route_with_fallback(candidates, payment_attrs) do
  cond do
    scoring_service_healthy?() ->
      score_with_ml(candidates, payment_attrs) |> handle_ml_result(candidates)

    redis_healthy?() ->
      # Use static rules but skip providers with open circuit breakers
      filter_by_circuit_breaker(candidates) |> static_priority()

    true ->
      static_priority(candidates)
  end
end
```

**Degradation is always logged.** A payment routed via Tier 2 or Tier 3 logs:

```json
{
  "routing_tier": 2,
  "reason": "scoring_service_timeout",
  "payment_id": "pay_018e...",
  "selected_provider": "mtn_momo_gh"
}
```

This allows post-hoc analysis: "what was our success rate during the scoring
service outage?" — necessary for SLA reporting and model value quantification.

### Risk scorer degradation

If the risk scorer is unavailable:
1. The risk score on `payment_attempts` is stored as `null`.
2. Velocity limits (§11 of engineering-concepts.md) still apply — this is
   the backstop that the risk scorer enhances, not replaces.
3. Flat velocity limits alone means we miss model-detected risk patterns,
   but we never disable ALL risk protection.

A scoring service that's been unavailable for > 15 minutes triggers a
Grafana alert. Risk assessment without ML is acceptable as a temporary state
but requires ops awareness.

---

## 13. The Elixir Migration Path

### Why migrate from Python to Elixir?

At P20, the scoring service is a Python FastAPI process. This is correct for
the ML serving task — Python has the richest ML ecosystem. But it introduces:

- An additional network hop on the payment critical path (Core → scoring service)
- A separate service to deploy, scale, and monitor
- Language boundary between Core (Elixir) and scoring (Python)

The Elixir migration path uses **Nx** (Elixir's numerical computing library)
and **Ortex** (ONNX Runtime bindings for Elixir):

```elixir
# Native Elixir ONNX inference
defmodule YagyeCore.ML.RoutingPredictor do
  @model Ortex.load("priv/models/routing_predictor_v1.onnx")

  def predict(features) do
    input = Nx.tensor([feature_vector(features)], type: :f32)
    {_class, probabilities} = Ortex.run(@model, {input})
    probabilities[0][1] |> Nx.to_number()  # P(success)
  end
end
```

Benefits after migration:
- Zero network hop — inference is in-process (< 0.1ms)
- No separate service to scale
- Model loaded at Core startup, not on first request
- ONNX files are identical — no retraining required

**Migration trigger:** When the scoring service's latency is measurably
affecting payment dispatch times, or when the operational cost of running the
Python service outweighs the network hop. Estimated: P22+ when traffic justifies it.

---

## 14. Monitoring and Model Health

### Key metrics by model

**Routing predictor:**

| Metric | Alert threshold | Cadence |
|---|---|---|
| Prediction latency p99 | > 50ms | 5 min |
| Provider agreement with static rules | < 80% | Daily |
| Success rate (ML-routed) | Drops > 5% week-over-week | Daily |
| Scoring service error rate | > 1% | 5 min |

**Risk scorer:**

| Metric | Alert threshold | Cadence |
|---|---|---|
| Block rate (score > threshold) | Jumps > 2x week-over-week | Daily |
| False positive rate | > 2% of blocked payments cleared by ops | Weekly |
| Feature freshness | any feature > 2h stale | Hourly |

**Model health dashboard (Grafana):**

```
┌─────────────────────────────────────────────────────────────────────┐
│  ML Routing Predictor — Last 24h                                     │
│                                                                     │
│  Success rate (ML)    85.3%    +1.2% vs static     Champion v1.1.0  │
│  Score latency p99    8ms      within SLA           Shadow: v1.2.0  │
│  Feature freshness    4 min    OK                   Agreement: 94%  │
│                                                                     │
│  Provider predictions today:                                        │
│    mtn_momo_gh    62% chosen  |  success rate: 87.1%               │
│    vodafone_cash  31% chosen  |  success rate: 82.4%               │
│    airteltigo      7% chosen  |  success rate: 79.2%               │
└─────────────────────────────────────────────────────────────────────┘
```

### Post-hoc calibration check

Weekly: compare the model's predicted scores against actual outcomes:

```python
# Calibration: does score 0.8 mean 80% actual success?
from sklearn.calibration import calibration_curve

prob_true, prob_pred = calibration_curve(y_true, y_score, n_bins=10)
# Plot and check Brier score

brier = mean_squared_error(y_true, y_score)
if brier > 0.15:
    alert_ml_team("Routing predictor calibration degraded — retrain or recalibrate")
```

An uncalibrated model (score 0.8 but actual success 60%) still ranks providers
correctly — the highest-scoring provider is still preferred. But calibration
matters for threshold-based decisions (risk scorer block threshold) where the
absolute value of the score, not just the ranking, determines behaviour.

### Automated retraining gate

The weekly retraining pipeline includes a gate that prevents deploying a
degraded challenger:

```python
# training/gate.py
def should_promote(champion_metrics, challenger_metrics):
    # Challenger must improve by at least 2%
    if challenger_metrics["auc_pr"] <= champion_metrics["auc_pr"] + 0.02:
        return False, "insufficient_improvement"

    # Challenger must not be worse than champion on any major subgroup
    for subgroup in ["mtn", "vodafone", "airtel", "amount_high", "amount_low"]:
        champ_sub = champion_metrics["subgroup"][subgroup]["auc_pr"]
        chal_sub = challenger_metrics["subgroup"][subgroup]["auc_pr"]
        if chal_sub < champ_sub - 0.05:  # 5% regression on any subgroup
            return False, f"regression_on_{subgroup}"

    return True, "promoted"
```

Subgroup evaluation is critical for fairness: a model that improves overall
accuracy by routing away from a specific network (e.g. always avoiding
AirtelTigo) is a business failure, even if overall AUC-PR improves.

---

## 15. Additional ML Opportunities (P22+)

The four models in §2 are the P20 foundation. They solve the most direct
business problems with the clearest training signals. The opportunities below
are the next wave — higher build cost, longer data accumulation required, or
dependent on the foundation models being stable first.

They are listed in priority order for Yagye's MoMo-first, Ghana market context.
None are in scope before P22.

---

### 15.1 Smart Retry Prediction

**Why this is the highest-priority gap**

MoMo failure modes are not uniform, and retrying a terminal failure wastes a
USSD prompt (which confuses the customer) and adds latency. The current system
retries based on static rules. A model can predict:

- Is this failure transient (worth retrying) or terminal (pointless)?
- If transient: how long to wait before retrying?

| Failure class | Example codes | Retry behaviour |
|---|---|---|
| Terminal | `insufficient_funds`, `account_blocked` | Do not retry — outcome is deterministic |
| Transient — network | `network_timeout`, `provider_unavailable` | Retry after 15 min |
| Transient — user | `ussd_session_timeout`, `no_response` | Retry at a different time of day |

**Model type:** Two-stage. Stage 1: binary classifier (`should_retry`).
Stage 2: regression (`optimal_retry_delay_minutes`) applied only when
Stage 1 outputs retry=true.

**Input features:**
- `error_class`, `response_code` (already on `payment.failed`)
- `provider_code`, `network_code`
- `hour_of_day`, `day_of_week`
- `customer_attempt_count_1h` (velocity)
- `provider_error_rate_1h` (is this a provider-wide issue?)
- `amount_minor`

**Label:**
- Stage 1: did a retry within 2 hours succeed? (1 = yes, retry was worth it)
- Stage 2: how many minutes after failure did the successful retry occur?

**Data dependency:** Requires `latency_ms` in `payment.failed` events (known
gap — see the data engineering feasibility notes). Otherwise buildable from
existing data.

**Retraining:** Weekly.

---

### 15.2 Volume Forecasting

**Why this matters for a float-holding PSP**

Yagye holds float (pre-funded balances at banks/telcos to cover same-day
settlements). Predicting daily and weekly payment volume determines how much
to pre-fund. Under-funding causes settlement delays. Over-funding locks up
working capital unnecessarily.

**Model type:** Time-series forecasting. Facebook Prophet or a simple LSTM.
Prophet is preferred for interpretability and its native handling of Ghanaian
public holiday effects and payroll seasonality (last working day of month =
volume spike).

**Input features:**
- Historical daily volume (from `fact_payments` Gold)
- Day of week, month, public holiday flag (Ghana calendar)
- End-of-month payroll flag (salary transfer rush)
- Major event flag (football match days → elevated consumer MoMo traffic)
- Trailing 7-day and 30-day volume trends

**Output:** Predicted total volume for next 7 days and 30 days with 80%
and 95% confidence intervals per network/currency.

**Data dependency:** None — fully buildable from existing `fact_payments` Gold
data. The historical signal exists from day one of live transactions.

**Retraining:** Monthly (volume patterns are stable; weekly retraining is
unnecessary cost).

---

### 15.3 AML Transaction Monitoring

**Why this is a regulatory requirement, not a product feature**

Bank of Ghana's AML/CFT framework (aligned with FATF Recommendation 16) requires
PSPs to file Suspicious Transaction Reports (STRs). Manual review does not scale.
At volume, ML-based pattern detection is necessary to catch:

- **Structuring:** A customer splits a GHS 5,200 payment into three transactions
  (GHS 1,800 + GHS 1,700 + GHS 1,700) to stay below reporting thresholds.
- **Velocity layering:** Funds enter via one merchant and exit via unrelated
  merchants in rapid succession — consistent with money mule patterns.
- **Round-tripping:** A merchant receives payments and makes payments back to
  the same MSISDN set — funds cycling.

**Model type:** Two-layer:
1. **Unsupervised anomaly detector** (Isolation Forest) — flags transactions
   statistically unlike the population. Handles the cold-start problem: works
   even with few labelled fraud examples.
2. **Supervised classifier** (LightGBM) — trained on labelled STR outcomes
   (compliance team's historical review decisions). Improves over time as labels
   accumulate.

**Training label:** `1` if compliance filed an STR on this transaction/customer
within 30 days of the activity, else `0`. Requires a `compliance.str_filed`
event (not yet emitted — must be added when building this).

**Key features:**
- `customer_distinct_merchants_1h` (already in risk_features_hourly)
- `customer_amount_total_24h` (same)
- Transaction round-number flag (`amount_minor % 100_000 == 0`)
- Structural similarity score to known STR patterns

**Output:** Suspicion score 0–1. Scores above threshold surface in the
compliance team's review queue (portal). Filing remains a human decision —
ML flags, compliance decides.

---

### 15.4 Network Health Forecasting (Proactive)

**Current limitation:** The routing predictor uses `recent_success_rate_1h` —
a backward-looking signal. The circuit breaker opens *after* failures occur.
The system is reactive.

**What this adds:** A forward-looking degradation forecast. MTN MoMo degrades
predictably:
- Weekday afternoons 13:00–16:00 UTC+0 (peak consumer traffic)
- Last working day of the month (payroll settlement rush)
- Major football match events

A time-series model trained on historical degradation windows can warn:
"MTN is 73% likely to degrade between 14:00–16:00 today — advise merchants
and pre-position ops."

**Model type:** Binary classifier on hourly buckets (will provider success rate
drop below 80% in this hour?). Features: hour of day, day of week, end-of-month
flag, trailing 7-day rolling degradation rate for this provider/hour combination.

**Integration:** The forecast feeds the routing predictor as an additional
input feature (`predicted_degradation_score`) — making the routing predictor
itself forward-looking, not just reactive.

**Data dependency:** None — historical `provider_health_hourly` Gold data is
the training set. Buildable as soon as 6+ months of Gold history exists.

---

### 15.5 Cross-Merchant MSISDN Fraud Signal

**The gap in the current risk scorer**

The risk scorer computes `customer_fail_count_1h` and similar features *within
a single merchant's context*. A fraud ring that hits three different merchants
with the same MSISDN — each below individual velocity thresholds — is invisible
to per-merchant velocity checking.

A platform-level feature aggregates across all merchants:

```sql
-- Gold: customer_risk_global_hourly
SELECT
  customer_msisdn_hash,
  COUNT(DISTINCT merchant_code) AS distinct_merchants_global_1h,
  SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS fail_count_global_1h,
  SUM(amount_minor) AS amount_total_global_1h
FROM silver_payments
WHERE mode = 'live'
  AND effective_at >= NOW() - INTERVAL '1 hour'
GROUP BY customer_msisdn_hash
```

This is a new Gold table (`customer_risk_global_hourly`) added to the Risk Mart.
Once built, `distinct_merchants_global_1h` becomes a high-signal feature for the
risk scorer's next retraining cycle.

**Data dependency:** None — all payment data is already in Silver. Requires
adding this Gold table and exposing it via the feature store (Redis cache).

---

### 15.6 KYB Risk Scoring (Onboarding Automation)

**The manual review bottleneck**

Every merchant onboarding today requires a compliance analyst review. At scale
this is the binding constraint on merchant acquisition. An ML model that
auto-approves low-risk applications reduces manual review to edge cases.

**Model type:** XGBoost binary classifier (auto-approve vs requires-review).

**Input features:**
- Business sector (encoded)
- Registration age in days
- Beneficial owner count
- Country of registration
- Business description embedding (from LLM enrichment — a Silver column)
- KYB document completeness score (% of required documents submitted)

**Label:** Historical compliance outcome (approved / approved-with-restrictions /
rejected → binary: auto-approve candidate vs not). Requires 12+ months of
labelled KYB decisions to produce a reliable training set.

**Output:** `{recommended_tier: int, auto_approve: bool, review_flags: [str]}`.
The model advises; a compliance analyst makes the final call. Auto-approval
is only enabled once the model achieves > 98% precision on the auto-approve
class (very few false approvals).

**Data dependency:** `compliance.onboarding_submitted` and subsequent
`merchant.approved` / rejection events provide the labels. The LLM enrichment
step (from `ai-layer.md` §1) provides the business description embedding.

---

### 15.7 Settlement Anomaly Detection

**The problem**

Yagye reconciles settlement reports from MoMo networks against its own ledger.
Rule-based reconciliation catches exact mismatches. ML detects *systematic
drift*:

- "MTN's settlement reports have included 0.3% fewer transactions than Yagye's
  records for the last 3 weeks — this is a pattern, not noise."
- "AirtelTigo settlement amounts have higher variance than expected for the
  GMV reported — possible fee calculation discrepancy."

**Model type:** Unsupervised — Isolation Forest on settlement delta features
(expected vs received transaction count, expected vs received gross amount,
fee rate variance from pricing rules). No labelled fraud examples required.

**Input features** (from `fact_settlement_items` Gold):
- `delta_transaction_count = yagye_count - provider_reported_count`
- `delta_gross_amount = yagye_gross - provider_reported_gross`
- `fee_rate_variance = actual_fee_rate - contracted_fee_rate`
- Rolling 30-day mean and std of the above per provider

**Output:** Anomaly score per settlement batch. Batches above threshold surface
in the reconciliation review queue in the ops portal.

**Data dependency:** `fact_settlement_items` Gold table (already planned).
Requires 3+ months of settlement history for the Isolation Forest baseline.

---

### Priority summary

| Priority | Model | Business driver | New data needed |
|---|---|---|---|
| 1 | Smart retry prediction | Direct conversion rate lift on MoMo flakiness | `latency_ms` in `payment.failed` |
| 2 | Volume forecasting | Treasury / float management | None |
| 3 | AML transaction monitoring | BOG regulatory compliance | `compliance.str_filed` event |
| 4 | Network health forecasting | Proactive ops vs reactive circuit breaking | None (6 months Gold history) |
| 5 | Cross-merchant MSISDN signal | Platform-level fraud moat | New Gold table |
| 6 | KYB risk scoring | Onboarding scale / ops cost | 12 months labelled KYB outcomes |
| 7 | Settlement anomaly detection | Systematic provider under-reporting | 3 months settlement Gold history |
