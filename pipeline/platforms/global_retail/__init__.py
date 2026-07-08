"""Global retail platform adapter."""

from .adapter import crawl_regional_discussions, fetch_quotes, import_xueqiu_export

__all__ = ["crawl_regional_discussions", "fetch_quotes", "import_xueqiu_export"]

