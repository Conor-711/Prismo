# Congress Score Architecture

## Boundary

Congress Score is an offline research export. It does not write `data/dev.db`, reuse Smart Account author scoring, or enter the iOS investment-event contract by default.

```text
House Clerk + Senate eFD official filings
                |
                v
open normalized dataset ZIP (official PDF URL preserved)
                |
                v
pipeline/platforms/congress/disclosures.py
                |
                v
pipeline/domain/congress_score/scoring.py
                |
       local price_daily + Yahoo fallback
                |
                v
pipeline/jobs/congress_score/workflows.py
                |
                v
data/exports/congress_score/*
```

## Ownership

- `pipeline/platforms/congress`: source download and source-specific normalization only.
- `pipeline/domain/congress_score`: priceability policy, event collapse, settlement, qualification, scoring, and output schema.
- `pipeline/jobs/congress_score`: source/price orchestration and report generation.
- `pipeline/cli/commands/congress.py`: argument parsing only.
- `docs/contracts/congress_score.md`: product and field contract.

## Data policy

The normalized dataset is a parsing layer over public House Clerk and Senate eFD disclosures. Every exported evidence row retains its official document URL. The source ZIP and Yahoo price cache are reproducible local exports under `data/exports/` and remain outside Git.

No database migration is required. Promotion into a public web or iOS surface requires a separate product decision, API contract, and static export review.
