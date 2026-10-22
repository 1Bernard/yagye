"""Feature SQL library.

Each module exposes a `build_features(con, training_window_days)` function that
returns a DuckDB relation. The SAME SQL is used at training time (Gold Parquet)
and at serving time (yagye_scoring FastAPI via Redis cache), ensuring no
training-serving skew.
"""
