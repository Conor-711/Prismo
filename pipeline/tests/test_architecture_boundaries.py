from __future__ import annotations

import subprocess
import sys


def test_architecture_boundary_script_passes():
    result = subprocess.run(
        [sys.executable, "scripts/check_architecture.py"],
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stdout + result.stderr


def test_legacy_ingest_wrappers_still_delegate_to_platforms():
    from pipeline.ingest import (
        arctic_scrape,
        author_avatars,
        author_crawl,
        gr_quote,
        load_complete_x_ticker_universe,
        price_daily,
        reddit_ingest,
        refresh,
        sample_loader,
        sv_price_history,
        toss,
        twitter_match,
        x_pull,
        youtube_channels,
        youtube_crawl,
    )
    from pipeline.platforms.author_assets import avatars
    from pipeline.platforms.global_retail import quotes
    from pipeline.platforms.local import sample_data
    from pipeline.platforms.market_data import price_history, short_window_prices
    from pipeline.platforms.reddit import arctic, authors, realtime, refresh as reddit_refresh
    from pipeline.platforms.toss import community
    from pipeline.platforms.x import cloud_pull, complete_universe, ticker_match
    from pipeline.platforms.youtube import channels, discovery

    assert arctic_scrape.scrape is arctic.scrape
    assert author_avatars.main is avatars.main
    assert author_crawl.crawl_top_authors is authors.crawl_top_authors
    assert gr_quote.fetch_quotes is quotes.fetch_quotes
    assert load_complete_x_ticker_universe.main is complete_universe.main
    assert price_daily.main is short_window_prices.main
    assert reddit_ingest.ingest_once is realtime.ingest_once
    assert refresh.refresh_recent is reddit_refresh.refresh_recent
    assert sample_loader.load_sample is sample_data.load_sample
    assert sv_price_history.run is price_history.run
    assert toss.crawl is community.crawl
    assert twitter_match.run is ticker_match.run
    assert x_pull.main is cloud_pull.main
    assert youtube_channels.main is channels.main
    assert youtube_crawl.crawl is discovery.crawl


def test_legacy_analyze_wrappers_still_delegate_to_domains():
    from pipeline.analyze import (
        brief,
        global_retail_rollup,
        global_retail_tag,
        item_analyze,
        kol_argument,
        kol_judgment,
        kol_newcomers,
        kol_quality,
        kol_refine,
        kol_relevance,
        kol_sentiment,
        kol_translate,
        kol_viewpoint,
        kol_volume,
        market_mood,
        narrative_rotation,
        narratives,
        overall_signals,
        retail_newcomers,
        retail_sentiment,
        retail_volume,
        rollups,
        sv_v0,
        translate,
        trending,
        tweet_sentiment,
        youtube_analyze,
        youtube_creator_view,
        youtube_digest,
        youtube_judgment,
    )
    from pipeline.domain.authors import youtube_creator_view as creator_view_domain
    from pipeline.domain.global_retail import rollup as global_retail_rollup_domain
    from pipeline.domain.global_retail import tag as global_retail_tag_domain
    from pipeline.domain.market import brief as brief_domain
    from pipeline.domain.market import mood, rollups as rollups_domain, trending as trending_domain
    from pipeline.domain.narratives import legacy, rotation
    from pipeline.domain.opinions import (
        item_analysis,
        kol_argument as kol_argument_domain,
        kol_quality as kol_quality_domain,
        kol_refine as kol_refine_domain,
        kol_relevance as kol_relevance_domain,
        kol_translate as kol_translate_domain,
        kol_viewpoint as kol_viewpoint_domain,
        youtube_analysis,
        youtube_digest as youtube_digest_domain,
    )
    from pipeline.domain.smart_voice import (
        kol_newcomers as kol_newcomers_domain,
        kol_sentiment as kol_sentiment_domain,
        kol_volume as kol_volume_domain,
        overall_signals as overall_signals_domain,
        retail_newcomers as retail_newcomers_domain,
        retail_sentiment as retail_sentiment_domain,
        retail_volume as retail_volume_domain,
        tweet_sentiment as tweet_sentiment_domain,
        v0_impl,
    )
    from pipeline.domain.target_prices import kol_judgment as kol_judgment_domain
    from pipeline.domain.target_prices import youtube_judgment as youtube_judgment_domain
    from pipeline.domain.translations import legacy as translations_legacy

    assert brief.run_brief is brief_domain.run_brief
    assert global_retail_rollup.rollup is global_retail_rollup_domain.rollup
    assert global_retail_tag.tag_all is global_retail_tag_domain.tag_all
    assert item_analyze.run_analyze is item_analysis.run_analyze
    assert kol_argument.synthesize is kol_argument_domain.synthesize
    assert kol_judgment.run is kol_judgment_domain.run
    assert kol_newcomers.rollup is kol_newcomers_domain.rollup
    assert kol_quality.score is kol_quality_domain.score
    assert kol_refine.refine is kol_refine_domain.refine
    assert kol_relevance.score is kol_relevance_domain.score
    assert kol_sentiment.rollup is kol_sentiment_domain.rollup
    assert kol_translate.translate is kol_translate_domain.translate
    assert kol_viewpoint.classify is kol_viewpoint_domain.classify
    assert kol_volume.rollup is kol_volume_domain.rollup
    assert market_mood.run_market_mood is mood.run_market_mood
    assert market_mood.mood_label is mood.mood_label
    assert narrative_rotation.build_rotation is rotation.build_rotation
    assert narratives.run_narratives is legacy.run_narratives
    assert overall_signals.run is overall_signals_domain.run
    assert retail_newcomers.rollup is retail_newcomers_domain.rollup
    assert retail_sentiment.rollup is retail_sentiment_domain.rollup
    assert retail_volume.rollup is retail_volume_domain.rollup
    assert rollups.run_rollups is rollups_domain.run_rollups
    assert sv_v0.run is v0_impl.run
    assert translate.run is translations_legacy.run
    assert trending.run_trending is trending_domain.run_trending
    assert tweet_sentiment.score is tweet_sentiment_domain.score
    assert youtube_analyze.tag is youtube_analysis.tag
    assert youtube_analyze.tag_text is youtube_analysis.tag_text
    assert youtube_analyze.gen_fulltext is youtube_analysis.gen_fulltext
    assert youtube_creator_view.run is creator_view_domain.run
    assert youtube_digest.run is youtube_digest_domain.run
    assert youtube_judgment.run is youtube_judgment_domain.run
