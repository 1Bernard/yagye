"""Structured logging via structlog.

Call configure_logging() once at process startup before any other imports
that use the logger.
"""

import logging
import os
import socket

import structlog


def configure_logging(use_json: bool = False) -> None:
    shared_processors: list[structlog.types.Processor] = [
        structlog.contextvars.merge_contextvars,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso", utc=True),
        structlog.processors.StackInfoRenderer(),
    ]

    if use_json:
        processors: list[structlog.types.Processor] = [
            *shared_processors,
            structlog.processors.format_exc_info,
            structlog.processors.JSONRenderer(),
        ]
        formatter = structlog.stdlib.ProcessorFormatter(
            processors=processors,
            foreign_pre_chain=shared_processors,
        )
    else:
        processors = [
            *shared_processors,
            structlog.dev.ConsoleRenderer(colors=True),
        ]
        formatter = structlog.stdlib.ProcessorFormatter(
            processors=processors,
            foreign_pre_chain=shared_processors,
        )

    handler = logging.StreamHandler()
    handler.setFormatter(formatter)

    root_logger = logging.getLogger()
    root_logger.handlers = [handler]
    root_logger.setLevel(logging.INFO)

    structlog.configure(
        processors=processors,
        wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )

    # Bind static fields that appear on every log line — mirrors Core's Erlang
    # primary metadata (runtime.exs) and Portal's lograge custom_options so
    # Loki queries like {service="yagye_data"} work consistently across apps.
    structlog.contextvars.bind_contextvars(
        service="yagye_data",
        environment=os.getenv("APP_ENV", "dev"),
        release=os.getenv("RELEASE_SHA", "local"),
        host=socket.gethostname(),
    )


def get_logger(name: str) -> structlog.stdlib.BoundLogger:
    return structlog.get_logger(name)
