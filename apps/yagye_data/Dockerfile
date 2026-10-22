# ── Builder ───────────────────────────────────────────────────────────────────
# Install uv and resolve/install all dependencies into /app/.venv
FROM python:3.12-slim AS builder

# libgomp1 is OpenMP for XGBoost/LightGBM on Linux — no manual install needed
# (unlike macOS where `brew install libomp` is required for local dev)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:0.5.1 /uv /usr/local/bin/uv

WORKDIR /app

# Layer-cache the dependency resolution separately from the source code.
# uv only re-resolves when pyproject.toml or uv.lock changes.
COPY pyproject.toml uv.lock* ./
RUN uv sync --all-extras --no-dev --frozen --no-install-project

# Now install the project itself (source code layer — changes most often)
COPY src/ ./src/
RUN uv sync --all-extras --no-dev --frozen

# ── Runtime ───────────────────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Non-root user — least-privilege principle
RUN groupadd -r yagye && useradd -r -g yagye yagye

WORKDIR /app

# Copy the fully-resolved venv from the builder stage
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/src   /app/src

# Scripts are plain Python files — no separate COPY needed if src is mounted.
COPY scripts/ ./scripts/

# Activate venv for all subsequent commands
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    APP_ENV=production

USER yagye

# Default entrypoint runs Silver ETL; override CMD in docker-compose / ECS task
# to run Gold ETL (`python scripts/run_gold_etl.py`) or training (`python scripts/train_models.py`)
ENTRYPOINT ["python"]
CMD ["scripts/run_silver_etl.py"]
