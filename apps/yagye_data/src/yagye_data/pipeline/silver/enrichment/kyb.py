"""LLM enrichment: KYB business description → structured industry embedding.

Converts free-text business descriptions into:
  - industry_category: standardised ISIC-like category
  - risk_flag: boolean (true if description suggests elevated AML risk)
  - description_embedding: reserved for future vector-store integration (P22+)

Used as a feature in the KYB risk scorer (ml-architecture §15.6).
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

_SYSTEM_PROMPT = """You are a KYB (Know Your Business) classification system for an African PSP.
Given a business description, return a JSON array where each element has:
  - "industry_category": one of [retail, hospitality, logistics, finance_services, agriculture,
      technology, healthcare, education, real_estate, manufacturing, other]
  - "risk_flag": boolean (true if the description suggests cash-intensive, high-churn, or
      politically-exposed business activity)
  - "description_quality": one of [detailed, vague, suspicious]

Return ONLY the JSON array, no prose."""


@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
def _call_llm(client: Anthropic, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    texts = [r.get("business_description", "") for r in rows]
    response = client.messages.create(
        model=_MODEL,
        max_tokens=1024,
        system=_SYSTEM_PROMPT,
        messages=[{"role": "user", "content": json.dumps(texts)}],
    )
    return json.loads(response.content[0].text)  # type: ignore[index]


def enrich_batch(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Enrich KYB merchant rows with structured industry labels."""
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
            logger.exception("enrichment.kyb.batch_failed", batch_index=i)
            for row in batch:
                enriched.append({
                    **row,
                    "industry_category": None,
                    "risk_flag": None,
                    "description_quality": None,
                })

    return enriched
