# The AI Layer — LLM Enrichment, RAG Analytics, and Natural Language Queries

**Last updated:** 2026-10-21

The ML layer (`ml-architecture.md`) handles structured prediction from tabular
features: routing scores, risk scores, reserve recommendations, churn
predictions. The AI layer handles tasks that tabular ML cannot: categorising
free-text, answering natural language questions over data, and enriching
records with semantic context.

These are three distinct products. They share the same DuckDB Gold layer as
their data source, the same Anthropic API client, and the same SQL safety
validator. They differ in audience, scope, and the security constraints that
apply to each.

Read `docs/data-engineering/README.md` (the lakehouse architecture) and
`docs/data-engineering/ml-architecture.md` (the ML models these AI products
feed and depend on) before this document.

---

## AI vs ML — What Each Solves

These terms are often used interchangeably. In Yagye's architecture they are
distinct tools that solve different classes of problem. Neither can replace
the other.

### ML (machine learning) — tabular prediction

Yagye's ML models (XGBoost, LightGBM) take **structured, numerical inputs**
and produce a **score or recommendation**:

- "Given this provider's recent success rate, this amount, and this hour of
  day — what is the probability this payment succeeds?" → `0.83`
- "Given this customer's velocity, their KYC tier, and the merchant's
  chargeback rate — what is the fraud risk of this transaction?" → `0.12`

The inputs are numbers and categories (integers, floats, encoded categoricals).
The model is trained on Yagye's own historical payment data. Inference runs
locally inside `yagye_scoring` via ONNX Runtime. No external API call.
Latency: < 1ms per prediction.

**Tabular ML cannot process free text.** An XGBoost model cannot read
"I did not authorise this transaction" and extract meaning from it. That string
must first be converted to a category (`unauthorised`) before the model can use
it as a feature.

### LLM / AI — language understanding

The Anthropic API (Claude) takes **free text** and produces **structured
interpretation or generated text**:

- "Given this dispute reason string — which category does it belong to?" →
  `unauthorised`
- "Given this natural language question and the Gold schema — write a SQL
  query that answers it" → a DuckDB SELECT statement

LLMs are trained on language, not on Yagye's payment data. They cannot be
retrained with transaction history. They cannot score a payment in < 1ms.
They cost money per token and require an external API call (300–2000ms latency).

**LLMs cannot replace tabular ML.** Claude cannot be asked to "score the
fraud risk of this transaction" in production — it has no knowledge of
Yagye's merchant chargeback history, no model of MoMo network behaviour, and
no SLA compatible with the payment critical path.

### How they work together

The dependency runs in one direction:

```
Free-text fields (dispute reasons, KYB notes, invoice descriptions)
    │
    │  Claude (LLM enrichment — Silver ETL step)
    ▼
Structured categories (dispute_category, gmv_category, kyb_flag)
    │
    │  These become features in the ML training dataset
    ▼
ML models (risk scorer, reserve recommender)
    │
    ▼
Scores served at inference time via yagye_scoring
```

Claude enriches unstructured text into structured columns. Those columns flow
into Gold as features. The ML models consume those features. If the Anthropic
API is unavailable, enrichment is skipped and the ML models receive a null
value for those features — they degrade gracefully, but they keep running.
Removing the Anthropic API does not stop ML inference; it removes one source
of signal. Removing Yagye's ML models does not stop enrichment; it removes
the scoring capability entirely.

---

---

## Table of Contents

1. [LLM Enrichment at Ingestion](#1-llm-enrichment-at-ingestion)
2. [RAG Analytics Chatbot for Ops](#2-rag-analytics-chatbot-for-ops)
3. [Merchant-Facing Text-to-SQL](#3-merchant-facing-text-to-sql)
4. [Shared Infrastructure](#4-shared-infrastructure)
5. [Security Model](#5-security-model)
6. [Cost Governance](#6-cost-governance)
7. [Failure Modes and Graceful Degradation](#7-failure-modes-and-graceful-degradation)
8. [Build Order and Dependencies](#8-build-order-and-dependencies)

---

## 1. LLM Enrichment at Ingestion

### The problem

Merchants and customers submit free-text in several places across the
platform. This text is unstructured and cannot be used directly by tabular ML
models without categorisation:

- **Dispute reason text** — "I did not authorise this transaction" vs "wrong
  amount charged" vs "the merchant is a fraud operation"
- **Invoice line item descriptions** — "consulting services Q3" vs "hardware
  purchase" vs "software licence"
- **KYB application notes** — free-form business description entered by the
  merchant during onboarding

### Why categories matter downstream

**Dispute reason codes → risk scorer feature**

Repeated "I did not authorise" disputes from the same merchant are a fraud
signal. Repeated "wrong amount" disputes suggest an integration bug. The risk
scorer (`ml-architecture.md` §2.2) uses `dispute_category` as a feature.
Without categorisation, the raw text cannot be featurised into the tabular
input the model expects.

**Invoice categories → reserve recommender feature**

Merchants with high "hardware" GMV have different chargeback patterns from
"consulting" merchants. Hardware is physical — customers dispute delivery
failures. Consulting is intangible — dispute rates are generally lower. The
reserve recommender (`ml-architecture.md` §2.3) uses the merchant's GMV
category mix to calibrate the reserve percentage.

**KYB notes → compliance flag**

Mentions of "crypto", "gambling", "weapons", or "adult content" in the
business description trigger a heightened review flag for the compliance team.
An LLM can catch these mentions reliably across many phrasings — a keyword
filter would miss "USDT", "FX betting", or "adult film".

### Implementation

Enrichment runs as a Silver ETL step, after the dedup step and before the
Gold join. The enriched columns are written to Silver Parquet and flow
naturally into Gold fact tables.

```python
# data_engineering/silver/enrich_disputes.py

DISPUTE_CLASSIFICATION_PROMPT = """
You are a payment dispute classifier. Given a list of dispute reason strings
(one per line), classify each into exactly one of these categories:
  unauthorised       - customer claims they did not make the payment
  wrong_amount       - correct merchant, wrong amount charged
  non_delivery       - goods or service not received
  merchant_error     - merchant-side processing error
  suspected_fraud    - customer believes the merchant is fraudulent
  other              - does not fit the above categories

Return one category per line, in the same order as the input.
Never add explanation. Never skip a line.
"""

def enrich_dispute_reasons(df: pd.DataFrame, llm_client) -> pd.DataFrame:
    reasons = df["reason_text"].fillna("").tolist()
    categories = []

    for batch in chunked(reasons, 50):   # 50 rows per API call
        response = llm_client.messages.create(
            model="claude-haiku-5-5",
            max_tokens=256,
            system=DISPUTE_CLASSIFICATION_PROMPT,
            messages=[{"role": "user", "content": "\n".join(batch)}]
        )
        raw = response.content[0].text.strip().split("\n")
        # Guard: if model returns wrong count, default to "other"
        if len(raw) != len(batch):
            raw = ["other"] * len(batch)
        categories.extend(raw)

    df["dispute_category"] = categories
    return df
```

### Cost controls

| Control | Detail |
|---|---|
| Model selection | `claude-haiku-5-5` for all classification — it handles short categorical tasks accurately at the lowest cost |
| Batch size | 50 rows per API call. One call per batch, not one call per row. |
| Result caching | The `dispute_category` column is written to Silver Parquet. On the next ETL run, rows with an existing non-null `dispute_category` are skipped — only new rows are enriched. |
| Cost logging | Token counts and estimated USD cost are emitted to structured telemetry per ETL run. A daily Oban job aggregates into `ai_cost_summary`. |
| Escalation threshold | If the LLM returns a low-confidence signal (measured by consistency across 3 calls on a 1% sample), that batch is flagged for human review rather than auto-classified. |

### What is NOT enriched by LLM

Payment amounts, provider codes, MSISDNs, timestamps, and structured fields
are never sent to the LLM — they are exact values and need no interpretation.
LLM enrichment is strictly for free-text fields where semantic understanding
adds value that a regex or lookup table cannot provide.

---

## 2. RAG Analytics Chatbot for Ops

### The problem

Ops analysts need answers to questions like:

- "What was MTN's decline rate last Tuesday for amounts over GHS 500?"
- "Which merchants had more than 5 failed settlements in September?"
- "Show me the top 10 merchants by volume in live mode this month."

Writing DuckDB SQL to answer these is correct but slow. Not all analysts are
SQL-fluent, and even fluent ones spend time on boilerplate `GROUP BY`,
`BETWEEN` predicates, and SCD joins.

### Architecture

```
Ops analyst (portal)
    │
    │  Types question in natural language
    ▼
Portal UI — Turbo Frame (Rails)
    │
    │  POST /internal/analytics/nl-query
    │  { question: "...", mode: "live" }
    │  X-Service-Token: <internal shared secret>
    ▼
Core analytics endpoint (yagye_core)
    │
    ├─ 1. Load Gold schema context
    │      (table names, column names, SCD notes, example queries)
    │
    ├─ 2. Build prompt:
    │      system = schema context + safety rules + few-shot examples
    │      user   = analyst's question
    │
    ├─ 3. Call Claude API → generated SQL
    │      model: claude-sonnet-5-5
    │
    ├─ 4. Validate SQL
    │      ├─ DuckDB parser: syntax check
    │      ├─ Assert SELECT only (no writes)
    │      ├─ Assert Gold tables only (no Bronze/Silver reads)
    │      └─ Inject WHERE mode = 'live' if absent
    │
    ├─ 5. Execute SQL via DuckDB
    │      Read-only connection, 10-second hard timeout
    │
    └─ 6. Return { rows, sql, execution_ms }
    │
    ▼
Portal renders:
  - Result as a paginated table
  - "View SQL" expandable section (the exact SQL that ran)
  - Execution time
  - "Export CSV" button (streams the full result)
```

### The schema context prompt

The Gold schema fits in a single system prompt at current table count (< 15
tables). It includes:

1. Table names and one-line purpose
2. Column names, types, and notable SCD columns (`valid_from`, `valid_to`)
3. Key join patterns (e.g. `fact_payments JOIN dim_merchants ON merchant_id AND event_at BETWEEN valid_from AND valid_to`)
4. Safety rules stated explicitly: "always filter on mode = 'live'", "never read Bronze or Silver tables"
5. Three few-shot examples of questions → correct SQL

### Why DuckDB, not a vector database

Traditional RAG retrieves semantically similar chunks from a vector store.
For structured analytics, this is the wrong retrieval mechanism:

- "Amounts over GHS 500" requires a range scan (`amount_minor > 50000`).
  A cosine similarity search on embeddings cannot evaluate a numerical
  predicate.
- "Group by provider, order by count" requires exact aggregation across
  millions of rows — not approximate nearest-neighbour retrieval.
- The Gold schema IS the retrieval context. It is small enough (< 4,000
  tokens) to fit entirely in the system prompt. There is no need to retrieve
  a subset.

DuckDB is better than a vector store here because the data is tabular and
the queries are relational.

### The `mode = 'live'` invariant

Every query executed by the ops chatbot must include `WHERE mode = 'live'`
(or an equivalent filter). The SQL validator adds it automatically if the
LLM omits it. This is non-negotiable — an ops analyst querying "all failed
payments this month" must see live data, not simulation or sandbox data.

---

## 3. Merchant-Facing Text-to-SQL

### The product

A portal UI feature for logged-in merchant users. A merchant types:

> "Show me all failed payments over GHS 500 in the last 7 days"

And receives a table, an optional chart, and an "Export CSV" button — all
scoped to their own data.

### Why this is architecturally different from the ops chatbot

| Dimension | Ops chatbot | Merchant text-to-SQL |
|---|---|---|
| Audience | Internal staff (ops_analyst, ops_manager) | Merchant users (owner, finance, developer) |
| Data scope | All merchants, mode=live | This merchant only, their mode |
| Schema exposed to LLM | Full Gold (all marts) | Payments mart only |
| Security invariant | `mode = 'live'` always injected | `merchant_code = current_user.merchant_code` always injected |
| Structural guarantee | Read-only DuckDB connection | Read-only + merchant_code filter in validator |

### The merchant_code injection

The SQL validator does not trust the LLM to include the merchant_code filter.
It injects it structurally:

```elixir
# In Core's analytics endpoint (merchant-scope variant)
defp enforce_merchant_scope(sql, merchant_code) do
  # Parse with DuckDB, then inject the filter into the AST
  # If the SQL already has WHERE, add AND merchant_code = '#{merchant_code}'
  # If it has no WHERE, add WHERE merchant_code = '#{merchant_code}'
  # If the SQL references any table outside the allowed set, reject
  validated_sql = SqlValidator.inject_merchant_filter(sql, merchant_code)
  {:ok, validated_sql}
end
```

This is a defence-in-depth measure. The LLM prompt also instructs the model
to always include the filter. But the validator does not rely on the LLM
following the instruction — it enforces the filter at the code level.

### Tables available to merchant queries

| Table | What merchants can see |
|---|---|
| `fact_payments` | Their own payments, filtered by merchant_code |
| `dim_providers` | Provider names and network types (read-only reference data, no merchant-specific info) |
| `dim_pricing_rules` | Their own pricing history (valid_from / valid_to) |

**Tables explicitly excluded from merchant queries:**

- `dim_merchants` — contains all merchants' data; a join would expose competitors
- Risk mart tables — proprietary risk signals; exposing them would let merchants game the risk model
- Platform-level tables (`portal_platform_*`) — Yagye internal financials

### LLM prompt guardrails for merchant queries

The system prompt states explicitly:

> "You are generating a SQL query for a single merchant. The merchant_code
> filter MUST appear in every query — it is a security requirement, not a
> suggestion. The merchant can only see their own data.
>
> Tables available: fact_payments, dim_providers, dim_pricing_rules.
> NEVER reference dim_merchants, dim_risk_signals, or any platform table.
>
> If the merchant's question cannot be answered with these three tables,
> say so in plain English — do not invent a table name."

### Failure modes

| Failure | Detection | Response |
|---|---|---|
| LLM omits merchant_code filter | SQL validator detects absence; re-prompts once | If still absent after retry: return error "query could not be safely generated" |
| LLM hallucinates a table name | DuckDB parser: `table does not exist` | Return "I don't have that data available — here's what I can query: [list]" |
| LLM generates a correct but slow query | 10-second DuckDB timeout | Return "your question required too much data — try narrowing by date range" |
| Merchant asks about another merchant | `merchant_code` injection makes this impossible | Injected filter is structural, not prompt-based |
| Claude API unavailable | Circuit breaker: 3 failures in 60s → open | Return "AI queries temporarily unavailable — use the filter panel instead" |

---

## 4. Shared Infrastructure

All three AI products are built on the same foundation.

### DuckDB Gold layer

Every query runs against Gold Parquet files in S3 (Floci locally). The Gold
layer is the only layer exposed to the AI products — Bronze and Silver are
internal ETL layers not visible to any query interface.

### Anthropic API client

```elixir
# lib/yagye_core/ai/client.ex
defmodule YagyeCore.AI.Client do
  @anthropic_api_key System.get_env("ANTHROPIC_API_KEY")

  def complete(model, system_prompt, user_message, opts \\ []) do
    Req.post("https://api.anthropic.com/v1/messages",
      headers: [
        {"x-api-key", @anthropic_api_key},
        {"anthropic-version", "2023-06-01"},
        {"content-type", "application/json"}
      ],
      json: %{
        model: model,
        max_tokens: Keyword.get(opts, :max_tokens, 1024),
        system: system_prompt,
        messages: [%{role: "user", content: user_message}]
      },
      receive_timeout: 30_000
    )
  end
end
```

The client is shared. Model selection is per call-site, not per client.

### SQL safety validator

```elixir
# lib/yagye_core/ai/sql_validator.ex
defmodule YagyeCore.AI.SqlValidator do
  @allowed_gold_tables ~w[fact_payments fact_settlement_items fact_webhook_deliveries
                           dim_merchants dim_providers dim_pricing_rules]

  def validate(sql, scope) do
    with {:ok, _ast} <- parse(sql),
         :ok         <- assert_select_only(sql),
         :ok         <- assert_gold_tables_only(sql, scope),
         {:ok, sql}  <- inject_required_filters(sql, scope) do
      {:ok, sql}
    end
  end

  defp assert_select_only(sql) do
    if String.match?(sql, ~r/^\s*SELECT/i), do: :ok,
    else: {:error, :write_operation_not_allowed}
  end

  defp inject_required_filters(sql, %{merchant_code: code}) when is_binary(code) do
    # Always inject merchant_code; also inject mode = sandbox/live/simulation
    {:ok, SqlInjector.add_where(sql, "merchant_code = '#{code}'")}
  end

  defp inject_required_filters(sql, %{ops: true}) do
    # Ops queries: inject mode = 'live' if absent
    {:ok, SqlInjector.ensure_mode_filter(sql, "live")}
  end
end
```

The validator is the single enforcement point. It runs before every DuckDB
execute call, regardless of which AI product generated the SQL.

---

## 5. Security Model

### Data isolation by construction

No AI product has a path to expose one merchant's data to another:

- **LLM enrichment** operates on individual rows in the ETL pipeline — no
  cross-merchant joins are possible in the enrichment step
- **Ops chatbot** is authenticated by `X-Service-Token` (internal endpoint
  only) and the portal's Pundit policy asserts `permitted?("analytics.query")`
  before the request reaches Core
- **Merchant text-to-SQL** has `merchant_code` structurally injected at the
  validator level — the LLM cannot bypass it

### The LLM is not trusted

The LLM generates SQL. The validator enforces correctness and security. The
validator does not assume the LLM followed the system prompt — it checks the
output independently. If the LLM produces SQL that passes the validator, it
runs. If it fails the validator, it is rejected (and optionally retried once
with a correction prompt).

This is the correct trust model: the LLM is a SQL generator, not a security
control.

### No financial data in prompts

The prompts sent to the LLM contain:
- The Gold schema (table and column names — metadata, not data)
- The analyst's question (text only)
- Few-shot examples (synthetic, not real merchant data)

They do NOT contain:
- Any actual payment amounts, merchant names, or transaction IDs
- API keys, signing secrets, or credentials
- PII (MSISDNs, customer names, email addresses)

The LLM never sees real merchant data. It only sees the schema and generates
SQL against it.

---

## 6. Cost Governance

Every LLM API call emits structured telemetry:

```json
{
  "event": "ai.api_call",
  "product": "enrichment | ops_chatbot | merchant_text_to_sql",
  "model": "claude-haiku-5-5",
  "input_tokens": 1240,
  "output_tokens": 48,
  "estimated_cost_usd": 0.000198,
  "user_id": "usr_018e...",
  "merchant_code": "MCH_...",
  "duration_ms": 312,
  "trace_id": "00-4bf92f..."
}
```

A daily Oban job (`AiCostSummaryWorker`) aggregates these into an
`ai_cost_summary` table in Core's DB:

| Column | Type | Purpose |
|---|---|---|
| day | date | Aggregation bucket |
| product | text | Which AI product |
| model | text | Which model |
| total_calls | int | Number of API calls |
| total_input_tokens | bigint | For cost modelling |
| total_output_tokens | bigint | For cost modelling |
| estimated_cost_usd | numeric(10,4) | Daily cost estimate |

An alert fires if `estimated_cost_usd` for any day exceeds a configured
threshold. This catches:
- A bug that calls the LLM in a tight loop
- A surge in analyst queries hitting the ops chatbot
- An enrichment job that processes a backfill without caching

The alert threshold is set conservatively at 3× the expected daily cost
based on current transaction volume.

---

## 7. Failure Modes and Graceful Degradation

The AI layer is never on the critical path for payment processing. Every
failure degrades gracefully.

| Product | Failure | Fallback |
|---|---|---|
| LLM enrichment | Claude API unavailable | Skip enrichment for this batch; `dispute_category` remains null; downstream ML uses fallback "no_category" feature value |
| LLM enrichment | Batch returns wrong count | Default all rows in batch to "other"; flag batch for human review in next ops queue |
| Ops chatbot | Claude API unavailable | Return "AI queries temporarily unavailable — use the table filter panel" |
| Ops chatbot | SQL validator rejects generated SQL | Re-prompt once with the validator error message appended; if still invalid, return "could not generate a safe query" |
| Ops chatbot | DuckDB timeout | Return "query timed out — try a narrower date range or fewer groupings" |
| Merchant text-to-SQL | Any failure | Return "AI queries temporarily unavailable — use the manual filter panel" |

The fallback for enrichment (null category) is handled by the ML models'
feature pipeline, which treats null as a known category ("enrichment
unavailable") rather than raising an error. This prevents an LLM outage from
blocking model inference.

---

## 8. Build Order and Dependencies

The three AI products have a natural build order based on their dependencies:

```
1. LLM Enrichment (Silver ETL step)
   └─ Depends on: Silver ETL pipeline (data-engineering/README.md §9–§11)
   └─ Unlocks: dispute_category and gmv_category as ML features

2. RAG Analytics Chatbot (Ops)
   └─ Depends on: Gold layer (fact_payments, dim_merchants, dim_providers)
   └─ Depends on: portal /internal analytics endpoint in Core
   └─ Does NOT depend on: ML models or enrichment

3. Merchant Text-to-SQL
   └─ Depends on: Gold layer
   └─ Depends on: SqlValidator (shared with ops chatbot)
   └─ Additional: merchant-scope schema context, portal UI component
```

**Current status:** All three are planned for P20+. The enrichment step is
the logical first build because its output (categorised free-text columns in
Silver) feeds the ML models that are also P20. The ops chatbot and merchant
text-to-SQL can be built in parallel after the Gold layer is stable.

**Prerequisite:** The Anthropic API key must be provisioned and stored in the
production environment secret store before any of these features ship. The
key is a single shared credential — all three products use the same key,
differentiated by model and system prompt.
