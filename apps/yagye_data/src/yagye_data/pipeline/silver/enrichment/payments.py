"""LLM enrichment: payment.risk_flagged events → fraud narrative.

Uses Claude Haiku in 30-row batches. For each flagged payment, generates a
concise fraud_narrative — a human-readable summary of why the payment was
flagged based on its risk signals.

The narrative appears in the SAR PDF and the ops risk queue to give analysts
context without having to read raw signal values.

PII rule: risk_score and risk_decision are safe to send. MSISDN and merchant
names are never included — only public_id, risk_decision, and risk_score.
"""

import json
from typing import Any

from anthropic import Anthropic
from tenacity import retry, stop_after_attempt, wait_exponential

from yagye_data.config import settings
from yagye_data.shared.logging import get_logger

logger = get_logger(__name__)

_BATCH_SIZE = 30
_MODEL = "claude-haiku-5-5"

_SYSTEM_PROMPT = """You are a PSP fraud analysis system for Yagye Payments (Ghana).
Given a list of flagged payment events, return a JSON array where each element has:
  - "fraud_narrative": a 1-2 sentence analyst-readable explanation of why this
    payment was flagged, referencing the risk_score and risk_decision.
    Use plain language. Example: "High-risk score (0.94) triggered automatic
    review. Payment flagged for manual disposition due to anomalous signals."

Return ONLY the JSON array in the same order as the input. No prose, no markdown."""


@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
def _call_llm(client: Anthropic, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    # Send only safe, non-PII fields to the LLM
    safe_rows = [
        {
            "risk_decision": r.get("risk_decision"),
            "risk_score": r.get("risk_score"),
            "mode": r.get("mode"),
        }
        for r in rows
    ]
    prompt = json.dumps(safe_rows)

    response = client.messages.create(
        model=_MODEL,
        max_tokens=2048,
        system=_SYSTEM_PROMPT,
        messages=[{"role": "user", "content": prompt}],
    )

    return json.loads(response.content[0].text)  # type: ignore[index]


def enrich_batch(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Enrich a list of risk_flagged rows with LLM-generated fraud narratives."""
    if not rows:
        return []

    if not settings.anthropic_api_key:
        logger.warning("enrichment.payments.skipped", reason="no_api_key")
        return [{**r, "fraud_narrative": None} for r in rows]

    client = Anthropic(api_key=settings.anthropic_api_key)
    enriched: list[dict[str, Any]] = []

    for i in range(0, len(rows), _BATCH_SIZE):
        batch = rows[i : i + _BATCH_SIZE]
        try:
            labels = _call_llm(client, batch)
            for row, label in zip(batch, labels, strict=False):
                enriched.append({**row, "fraud_narrative": label.get("fraud_narrative")})
        except Exception:
            logger.exception("enrichment.payments.batch_failed", batch_index=i)
            for row in batch:
                enriched.append({**row, "fraud_narrative": None})

    return enriched
