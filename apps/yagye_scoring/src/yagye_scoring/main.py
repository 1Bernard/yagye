"""FastAPI application factory."""

from __future__ import annotations

from contextlib import asynccontextmanager
from typing import AsyncGenerator

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse

from yagye_scoring.config import settings
from yagye_scoring.registry import ModelRegistry
from yagye_scoring.routers import churn, reserve, risk, routing
from yagye_scoring.shared.logging import configure_logging, get_logger

logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    configure_logging(use_json=settings.use_json_logging)
    logger.info("scoring_service_starting", env=settings.app_env)

    registry = await ModelRegistry.load()
    app.state.registry = registry

    logger.info("scoring_service_ready")
    yield

    logger.info("scoring_service_stopping")


app = FastAPI(
    title="Yagye Scoring Service",
    version="0.1.0",
    description="ML scoring for routing, risk, reserve and churn decisions.",
    lifespan=lifespan,
)

app.include_router(routing.router)
app.include_router(risk.router)
app.include_router(reserve.router)
app.include_router(churn.router)


@app.get("/health", tags=["ops"])
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/ready", tags=["ops"])
async def ready(request: Request) -> JSONResponse:
    """Kubernetes / Docker readiness probe.

    Returns 200 when all models are registered and Redis is reachable.
    Returns 503 with a check breakdown when any dependency is unhealthy.
    """
    registry: ModelRegistry = request.app.state.registry
    checks = registry.health_checks()
    all_ok = all(checks.values())

    if all_ok:
        return JSONResponse({"status": "ready", "checks": checks})
    raise HTTPException(status_code=503, detail=checks)
