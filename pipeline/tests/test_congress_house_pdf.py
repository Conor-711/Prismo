from pipeline.jobs.congress_quiver_backfill.house_pdf import parse_page_words


def _word(text, x, top, page=1):
    return {"text": text, "x0": x, "top": top, "page": page}


def test_cross_page_house_transaction_excludes_header_amount() -> None:
    words = [
        _word("JT", 65, 700),
        _word("Devon", 104, 700), _word("Energy", 130, 700),
        _word("S", 261, 700), _word("(partial)", 270, 700),
        _word("09/02/2026", 326, 700), _word("09/15/2026", 382, 700),
        _word("$100,001", 446.7, 700), _word("-", 478, 700),
        _word("$200?", 480, 1030, page=2),
        _word("Stock", 104, 1080, page=2), _word("(DVN)", 130, 1080, page=2),
        _word("$250,000", 446.7, 1080, page=2),
    ]
    rows, errors = parse_page_words(words)
    assert errors == []
    assert len(rows) == 1
    assert rows[0]["amount_high"] == 250000
    assert rows[0]["notification_date"] == "2026-09-15"
    assert rows[0]["ticker"] == "DVN"


def test_unrecognized_house_row_is_visible_error() -> None:
    words = [_word("P", 261, 100), _word("09/02/2026", 326, 100)]
    rows, errors = parse_page_words(words)
    assert rows == []
    assert errors
