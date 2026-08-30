# bSmart MVP Privacy Data Map

> Scope: iOS-first anonymous MVP before account login or broker connection.

## Collected data

| Data | Purpose | Storage | Default retention |
|---|---|---|---|
| Random installation UUID and opaque session token | Authenticate one app installation | UUID on device and server; token in iOS Keychain, hash on server | Session 90 days unless refreshed |
| Manually entered ticker, position/watchlist type, optional shares, cost and weight | Portfolio relevance and position context | Device first; installation-scoped server state | Until user deletes or installation cleanup runs |
| Read, saved, ignored and enumerated feedback state | Restore feed state and improve relevance evaluation | Device first; installation-scoped server state | Until user deletes or installation cleanup runs |
| APNs device token, app version, locale and timezone | Deliver alerts, quiet hours and local-time digest | Installation-scoped server state | Until APNs invalidates it or installation cleanup runs |
| Enumerated telemetry event, event time, signal/evidence IDs, ticker, source and screen context | Measure whether alerts and evidence help research | Installation-scoped server state | 90 days by default, configurable downward |

## Explicitly excluded from telemetry

- social post, transcript, summary or evidence text;
- source URLs and search queries;
- shares, cost basis, position weight or portfolio value;
- names, email, phone number, advertising ID or cross-app identifier;
- arbitrary properties or free-form user text.

## Engineering rules

1. Anonymous installation IDs are first-party product identifiers, not identity claims.
2. Client mutations and telemetry use the same durable outbox, but separate typed contracts.
3. New telemetry fields require an OpenAPI update, privacy review and retention decision before code changes.
4. APNs signing keys and raw session tokens never enter logs or committed configuration.
5. The app privacy manifest declares Other Financial Info, User ID, Device ID and Product Interaction; the matching App Store Connect answers must be reviewed whenever collection changes.
6. Users can reset device-local positions, watchlist, follows, event activity, cached read models, alert preferences and pending sync operations from Settings. The anonymous installation identity remains because local reset is not server-account deletion.
7. Before public TestFlight, add installation-scoped server deletion and publish matching Privacy Policy and Privacy Choices URLs.
