"""Local fixture and seed data operations."""
from __future__ import annotations


def load_sample_data() -> dict:
    """Load bundled sample data into the local database."""
    from .sample_data import load_sample

    return load_sample()
