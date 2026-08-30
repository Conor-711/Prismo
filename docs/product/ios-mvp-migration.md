# iOS-first MVP Migration

## Decision

The native iOS app is the primary product for the first MVP. The current web
application remains available during migration, but new portfolio-aware product
work starts on iOS unless it is a public web page or an internal research tool.

## Keep, simplify, remove

### Keep as shared infrastructure

- Python platform adapters and AI analysis jobs.
- `data/dev.db` during the current backend transition.
- Smart Account Score and Hyperliquid Smart Money algorithms.
- Cross-platform Opinion, Author, Judgment, Ticker, and Narrative contracts.
- Evidence links and source attribution.

### Keep on Web with limited scope

- Public Smart Account ranking and public share pages.
- Internal data-quality and algorithm research screens.
- A small marketing/support surface when required for App Store distribution.
- Existing pages as migration regression references until iOS reaches parity.

### Stop expanding

- Generic high-density dashboards that are not connected to a position or an
  actionable research flow.
- Web-only implementations of features intended for the iOS MVP.
- Static pages that serialize large opinion collections into HTML.

### Remove only after replacement

A web route, query, or export may be deleted only when all of the following are
true:

1. Its user value is present in iOS or explicitly outside MVP scope.
2. Its data is available through a shared contract/API or has no remaining
   consumer.
3. Public links, SEO, experiments, and internal operations do not depend on it.
4. A database and deployment snapshot has been verified before deletion.

## Delivery phases

1. Native foundation: SwiftUI shell, shared tokens, `/v1` contract, fixtures.
2. Portfolio MVP: manual positions, event inbox, event detail, research, Smart.
3. Runtime API: authenticated portfolio/event endpoints and push event payloads.
4. Notifications: APNs registration, event priority, deep links, daily report.
5. Web reduction: classify routes as public, internal, retained, or removable.
6. Release: privacy disclosures, App Store assets, TestFlight, monitoring.

This order avoids deleting working evidence and pipeline paths before the native
client has a verified replacement.
