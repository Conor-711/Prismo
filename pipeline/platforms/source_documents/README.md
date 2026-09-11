# Public Supporting Documents

`web.py` fetches public HTML and returns `Document`: canonical fetched URL, title,
extracted body, publication/revision metadata, links and SHA-256 of fetched bytes.
It does not decide which opinion a source supports or change Smart Account Score.

The local job defaults to 30 requests, 2 MB per response, a 24-hour cache and at
least one second between requests to the same host. robots restrictions, long
crawl delays, HTTP errors, unsupported formats and unsafe destinations stop that
candidate. TLS remains verified with the original hostname while connections are
pinned to validated public addresses. It does not execute JavaScript or bypass
authentication, subscription access or anti-bot challenges.

No platform credentials or database schema are needed. Cached article text is
local runtime material, not an App asset; only short reviewed excerpts and
attributable metadata reach the client. Source redistribution rights require
separate review before expanding production coverage.

From repository root:

```sh
pipeline/.venv/bin/python -m pipeline.jobs.opinion_source_crawl
```

This checks only the explicit local sample manifest. Add `--apply` to export its
verified attachments into the current local fixture collections. The job does
not create a scheduler or deploy to the API. See the product document for sample
IDs, matching rules and limitations.
