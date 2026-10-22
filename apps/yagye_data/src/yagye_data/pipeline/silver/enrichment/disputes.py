"""LLM enrichment: dispute free-text → structured categories.

Uses Claude Haiku in 50-row batches (cost-efficient). The enriched columns
are appended to the Silver reconciliation partition and used as ML features
in the risk scorer.

Batch size of 50 is deliberate:
  - Haiku's 200K context fits ~200 rows but 50 keeps latency under 2s per call
  - Each row's dispute_reason is ~200 tokens on average
"""

import json
from typing import Any

from anthropic import Anthropic
from tenacity import retry, stop_after_attempt, wait_exponential

from yagye_data.config import settings
from yagye_data.shared.logging import get_logger

logger = get_logger(__name__)

_BATCH_SIZE = 50
_MODEL = "claude-haiku-4-5"

_SYSTEM_PROMPT = """You are a PSP dispute classification system. Given dispute reason text,
return a JSON array where each element has:
  - "dispute_category": one of
    [duplicate, fraud, not_received, quality, subscription_cancelled, other]
  - "dispute_sentiment": one of [high_urgency, standard, unclear]
  - "contains_pii": boolean (true if the text contains names, phone numbers, or IDs)

Return ONLY the JSON array, no prose."""


@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
def _call_llm(client: Anthropic, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    texts = [r.get("dispute_reason", "") for r in rows]
    prompt = json.dumps(texts)

    response = client.messages.create(
        model=_MODEL,
        max_tokens=1024,
        system=_SYSTEM_PROMPT,
        messages=[{"role": "user", "content": prompt}],
    )

    return json.loads(response.content[0].text)  # type: ignore[index]


def enrich_batch(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Enrich a list of dispute rows with structured LLM-derived categories."""
    if not rows:
        return []

    client = Anthropic(api_key=settings.anthropic_api_key)
    enriched: list[dict[str, Any]] = []

    for i in range(0, len(rows), _BATCH_SIZE):
        batch = rows[i : i + _BATCH_SIZE]
        try:
            labels = _call_llm(client, batch)
            for row, label in zip(batch, labels, strict=False):
                enriched.append({**row, **label})
        except Exception:
            logger.exception("enrichment.disputes.batch_failed", batch_index=i)
            # Fall back: pass rows through without enrichment rather than dropping
            for row in batch:
                enriched.append(
                    {
                        **row,
                        "dispute_category": None,
                        "dispute_sentiment": None,
                        "contains_pii": None,
                    }
                )

    return enriched
