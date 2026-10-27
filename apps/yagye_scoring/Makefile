.PHONY: install dev lint format typecheck test run

install:
	uv sync --all-extras

dev:
	uv run uvicorn yagye_scoring.main:app --reload --host 0.0.0.0 --port 8000

lint:
	uv run ruff check src tests

format:
	uv run ruff format src tests

typecheck:
	uv run mypy src

test:
	uv run pytest

test-cov:
	uv run pytest --cov=yagye_scoring --cov-report=html
