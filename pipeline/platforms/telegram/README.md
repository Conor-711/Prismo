# Telegram public channel adapter

This adapter is intentionally limited to public broadcast-channel preview pages:

- it does not log in, join private groups, bypass access controls, or use user credentials;
- it paginates the public `t.me/s/<handle>` history and preserves each message's
  source HTML in `telegram_public_message.raw`;
- forwarded posts are retained in the raw layer but marked so Private Smart
  Voice attribution can exclude them;
- platform code stops at raw/normalized storage. Call extraction and scoring
  live under `pipeline/domain/smart_voice`.

The first MVP uses a separate SQLite database and does not feed Telegram
messages into Prismo's public Smart Voice JSON export.
