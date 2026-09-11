from pipeline.common.smart_account_titles import build_smart_account_activity_titles


def test_activity_titles_summarize_target_and_reason_without_author_boilerplate() -> None:
    titles = build_smart_account_activity_titles(
        ticker="NVDA",
        direction="bull",
        lifecycle="open_call",
        horizon="20D",
        target_price=200,
        thesis_zh="作者预计英伟达在 20 天内达到 200 美元，因为需求持续改善。",
        thesis_en="The author expects NVIDIA to reach $200 within 20 days as demand improves.",
    )

    assert titles["activityTitleZH"] == "NVDA：预计英伟达在 20 天内达到 200 美元，因为需求持续改善。"
    assert titles["activityTitleEN"] == "NVDA: Expects NVIDIA to reach $200 within 20 days as demand improves."
    assert "作者" not in titles["activityTitleZH"]
    assert "author" not in titles["activityTitleEN"].lower()


def test_activity_title_makes_reversal_explicit() -> None:
    titles = build_smart_account_activity_titles(
        ticker="MSTR",
        direction="bear",
        lifecycle="reverse_call",
        horizon="5D",
        target_price=None,
        thesis_zh="多头止损并反手做空。",
        thesis_en="Stopped out of the long and reversed short.",
    )

    assert titles["activityTitleZH"].startswith("MSTR 观点反转：")
    assert titles["activityTitleEN"].startswith("MSTR view reversed:")


def test_activity_title_preserves_later_sentence_and_long_term_qualification() -> None:
    zh = "作者预计短期价格回补缺口并反弹至240至260美元，已经部分平掉空头仓位。长期仍然看空，若回到阻力位会考虑再次增加空头仓位。"
    en = "Author expects a short-term rebound to $240-$260 and has covered part of the short. Still bearish longer term; may add short exposure again at resistance."
    titles = build_smart_account_activity_titles(
        ticker="NBIS", direction="bull", lifecycle="open_call", horizon="20D",
        target_price=260, thesis_zh=zh, thesis_en=en,
    )
    assert "长期仍然看空" in titles["activityTitleZH"]
    assert "若回到阻力位" in titles["activityTitleZH"]
    assert "Still bearish longer term" in titles["activityTitleEN"]
    assert "…" not in titles["activityTitleZH"]
    assert "…" not in titles["activityTitleEN"]
