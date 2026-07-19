from __future__ import annotations

import re

from pipeline.domain.tickers.youtube_uploads import _map_video


def _map(title: str, description: str = "") -> list[str]:
    aliases = {
        "apple": "AAPL",
        "micron": "MU",
        "microstrategy": "MSTR",
        "nvidia": "NVDA",
    }
    pattern = re.compile(r"(?<!\w)(" + "|".join(aliases) + r")(?!\w)")
    found, _, _ = _map_video(
        title,
        description,
        valid_tickers={"AAPL", "MU", "MSTR", "NVDA"},
        stoplist={"AI", "ALL"},
        aliases=aliases,
        alias_pattern=pattern,
        max_tickers=6,
    )
    return [item["ticker"] for item in found]


def test_maps_company_name_in_finance_title():
    assert _map("Micron stock could double after earnings") == ["MU"]


def test_maps_explicit_cashtags_without_extra_context():
    assert _map("$NVDA vs $AAPL: which one wins?") == ["AAPL", "NVDA"]


def test_does_not_treat_every_company_word_as_finance_content():
    assert _map("How to make the perfect apple pie") == []


def test_uses_description_cashtag_only_after_finance_title_context():
    assert _map("My next stock investment", "A full $NVDA valuation and earnings review") == [
        "NVDA"
    ]


def test_ignores_company_names_in_channel_boilerplate_description():
    assert _map(
        "My complete fitness routine",
        "This video is sponsored by Apple. More investing videos about Nvidia stock here.",
    ) == []


def test_does_not_inherit_finance_context_from_description():
    assert _map("How to make the perfect apple pie", "Nvidia stock valuation") == []


def test_maps_explicit_company_comparison_without_stock_keyword():
    assert _map("Nvidia stock vs Apple stock: which company wins?") == ["AAPL", "NVDA"]


def test_ignores_short_ticker_outside_finance_context():
    aliases = {"micron": "MU"}
    found, _, _ = _map_video(
        "CIL MT 2026 | Double Integrals Concepts",
        "",
        valid_tickers={"MT", "MU"},
        stoplist=set(),
        aliases=aliases,
        alias_pattern=re.compile(r"(?<!\w)(micron)(?!\w)"),
        max_tickers=6,
    )
    assert found == []


def test_ignores_ambiguous_industry_acronym_as_bare_ticker():
    aliases = {"micron": "MU"}
    found, _, _ = _map_video(
        "HBM demand is rising",
        "",
        valid_tickers={"HBM", "MU"},
        stoplist=set(),
        aliases=aliases,
        alias_pattern=re.compile(r"(?<!\w)(micron)(?!\w)"),
        max_tickers=6,
    )
    assert found == []


def test_ignores_common_word_that_is_also_a_ticker():
    aliases = {"cloudflare": "NET"}
    found, _, _ = _map_video(
        "TOP PENNY STOCK TO BUY FOR NEXT WEEK",
        "",
        valid_tickers={"NEXT", "NET"},
        stoplist=set(),
        aliases=aliases,
        alias_pattern=re.compile(r"(?<!\w)(cloudflare)(?!\w)"),
        max_tickers=6,
    )
    assert found == []


def test_still_maps_ambiguous_ticker_as_cashtag():
    aliases = {"cloudflare": "NET"}
    found, _, _ = _map_video(
        "$NET stock analysis",
        "",
        valid_tickers={"NET"},
        stoplist=set(),
        aliases=aliases,
        alias_pattern=re.compile(r"(?<!\w)(cloudflare)(?!\w)"),
        max_tickers=6,
    )
    assert [item["ticker"] for item in found] == ["NET"]


def test_maps_ambiguous_symbol_when_title_explicitly_calls_it_a_stock():
    aliases = {"cloudflare": "NET"}
    found, _, _ = _map_video(
        "NET Stock Analysis: Is Cloudflare a Buy?",
        "",
        valid_tickers={"NET"},
        stoplist=set(),
        aliases=aliases,
        alias_pattern=re.compile(r"(?<!\w)(cloudflare)(?!\w)"),
        max_tickers=6,
    )
    assert [item["ticker"] for item in found] == ["NET"]


def test_smr_sector_acronym_requires_explicit_stock_evidence():
    found, _, _ = _map_video(
        "US SMR construction boom benefits the energy sector",
        "",
        valid_tickers={"SMR"},
        stoplist=set(),
        aliases={},
        alias_pattern=None,
        max_tickers=6,
    )
    assert found == []
