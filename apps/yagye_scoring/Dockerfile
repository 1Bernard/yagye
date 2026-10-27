# ── Builder ───────────────────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

COPY --from=ghcr.io/astral-sh/uv:0.5.1 /uv /usr/local/bin/uv

WORKDIR /app

# Resolve dependencies before copying source — maximises layer cache hits.
COPY pyproject.toml uv.lock* ./
RUN uv sync --no-dev --frozen --no-install-project

COPY src/ ./src/
RUN uv sync --no-dev --frozen

# ── Runtime ───────────────────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

RUN groupadd -r yagye && useradd -r -g yagye yagye

WORKDIR /app

COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/src   /app/src

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    APP_ENV=production

USER yagye

EXPOSE 8000

CMD ["uvicorn", "yagye_scoring.main:app", "--host", "0.0.0.0", "--port", "8000"]
