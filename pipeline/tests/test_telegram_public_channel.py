from pipeline.platforms.telegram.public_channel import (
    parse_compact_number,
    parse_preview_page,
)


def test_compact_counts_are_non_negative():
    assert parse_compact_number("8.49K") == 8_490
    assert parse_compact_number("1.2M subscribers") == 1_200_000
    assert parse_compact_number("-30") == 0
    assert parse_compact_number("") == 0


def test_parse_public_preview_message():
    html = """
    <div class="js-widget_message" data-post="samplechannel/42">
      <a class="tgme_widget_message_author">Sample Channel</a>
      <div class="js-message_text">I bought $NVDA for the long term.</div>
      <span class="tgme_widget_message_views">2.5K</span>
      <div class="js-message_reactions">
        <span class="tgme_reaction">Like 12</span>
      </div>
      <time datetime="2025-01-02T03:04:05+00:00"></time>
    </div>
    <a class="tme_messages_more" data-before="42"></a>
    """
    messages, before, _ = parse_preview_page(html, "samplechannel")

    assert before == "42"
    assert len(messages) == 1
    message = messages[0]
    assert message.message_id == 42
    assert message.author_name == "Sample Channel"
    assert message.view_count == 2_500
    assert message.reaction_count == 12
    assert message.url == "https://t.me/samplechannel/42"
