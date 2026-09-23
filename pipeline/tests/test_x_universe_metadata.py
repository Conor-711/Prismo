import sqlite3

from pipeline.platforms.x import complete_universe


def test_ticker_meta_refresh_preserves_explicit_inactive_status(monkeypatch):
    connection = sqlite3.connect(':memory:')
    connection.execute('''CREATE TABLE ticker_meta (
        ticker TEXT PRIMARY KEY, company_name TEXT, cik TEXT, exchange TEXT,
        sector TEXT, market TEXT, is_active INTEGER, aliases TEXT)''')
    connection.execute("INSERT INTO ticker_meta VALUES ('ATAI', 'AtaiBeckley', NULL, '', '', 'us', 0, '[]')")
    monkeypatch.setattr(complete_universe, 'fetch_sec_names', lambda: {})

    complete_universe.upsert_ticker_meta(connection, {'ATAI', 'NVDA'})

    assert dict(connection.execute('SELECT ticker, is_active FROM ticker_meta')) == {'ATAI': 0, 'NVDA': 1}
