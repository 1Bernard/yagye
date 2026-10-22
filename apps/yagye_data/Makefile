.DEFAULT_GOAL := help

.PHONY: help install install-dev lint format typecheck test test-unit test-cov \
        precommit silver gold train clean

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

install: ## Install runtime dependencies (uv)
	uv sync

install-dev: ## Install all dependencies including dev + training extras
	uv sync --all-extras

lint: ## Run ruff linter
	uv run ruff check src tests scripts

format: ## Format code with ruff
	uv run ruff format src tests scripts

typecheck: ## Run mypy type checker
	uv run mypy src

test: ## Run full test suite
	uv run pytest

test-unit: ## Run tests excluding integration (no S3/DB required)
	uv run pytest -m "not integration"

test-cov: ## Run tests with HTML coverage report
	uv run pytest --cov-report=html
	@echo "Open htmlcov/index.html to view coverage"

precommit: ## Run format + lint + typecheck + tests (mirrors CI gate)
	uv run ruff format src tests scripts
	uv run ruff check src tests scripts
	uv run mypy src
	uv run pytest

silver: ## Run Silver ETL (reads from Bronze, writes Silver Parquet)
	uv run python scripts/run_silver_etl.py

gold: ## Run Gold ETL (reads from Silver, writes Gold Parquet)
	uv run python scripts/run_gold_etl.py

train: ## Train all ML models and export ONNX artefacts
	uv run python scripts/train_models.py

clean: ## Remove build artefacts and caches
	rm -rf dist/ .mypy_cache/ .ruff_cache/ .pytest_cache/ htmlcov/ .coverage
	find . -type d -name __pycache__ -exec rm -rf {} +
