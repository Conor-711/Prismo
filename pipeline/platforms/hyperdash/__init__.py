"""Read-only adapter for Hyperdash's public Smart Money GraphQL data."""

from .client import HyperdashGraphQLClient
from .normalizer import build_hyperdash_smart_money_payload

__all__ = ["HyperdashGraphQLClient", "build_hyperdash_smart_money_payload"]
