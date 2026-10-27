"""FastAPI dependency injection helpers."""

from typing import Annotated

from fastapi import Depends, Request

from yagye_scoring.registry import ModelRegistry


def get_registry(request: Request) -> ModelRegistry:
    return request.app.state.registry  # type: ignore[no-any-return]


Registry = Annotated[ModelRegistry, Depends(get_registry)]
