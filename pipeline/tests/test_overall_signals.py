import sqlite3

from pipeline.domain.smart_voice.overall_signals import _local_sv_divergence


def test_local_sv_divergence_uses_only_asof_top_decile_scores():
    con = sqlite3.connect(":memory:")
    con.executescript(
        """
        CREATE TABLE sv_call (
          investor_id TEXT, ticker TEXT, created_at TEXT, direction TEXT,
          call_weight REAL, is_actionable_call INTEGER
        );
        CREATE TABLE sv_investor_score_asof (
          asof_day TEXT, investor_id TEXT, percentile REAL, raw_z REAL, n_eff REAL
        );
        CREATE TABLE retail_sentiment_daily (ticker TEXT, day TEXT, net REAL);

        INSERT INTO sv_call VALUES ('top','MU','2026-07-10','bull',2,1);
        INSERT INTO sv_call VALUES ('bottom','MU','2026-07-10','bear',8,1);
        INSERT INTO sv_call VALUES ('future-top','MU','2026-07-10','bear',8,1);
        INSERT INTO sv_investor_score_asof VALUES ('2026-07-09','top',5,1.5,8);
        INSERT INTO sv_investor_score_asof VALUES ('2026-07-09','bottom',95,-1.5,8);
        INSERT INTO sv_investor_score_asof VALUES ('2026-07-11','future-top',1,2,8);
        INSERT INTO retail_sentiment_daily VALUES ('MU','2026-07-10',-2);
        INSERT INTO retail_sentiment_daily VALUES ('MU','2026-07-11',-1);
        """
    )

    result = _local_sv_divergence("MU", con, ["2026-07-10", "2026-07-11"])

    assert result["smartAuthors"] == 1
    assert result["series"][0]["smart"] == 1.0
    assert result["read"] == {"smart": "bull", "retail": "bear", "diverging": True}
