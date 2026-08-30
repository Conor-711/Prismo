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
