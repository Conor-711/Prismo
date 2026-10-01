"""Match congressional research rows to the app's verified subject identities."""

from __future__ import annotations

from pipeline.jobs.congress_capture.refresh_cycle import congress_rows
from pipeline.jobs.congress_capture.research_feed import (
    build_research_feed,
    portrait_for,
)


def app_politician_ids(members: list, disclosures: list) -> dict[str, str]:
    feed, _ = build_research_feed(congress_rows(disclosures), members)
    visible = {subject["id"] for subject in feed["subjects"]}
    identities = {}
    for member in members:
        portrait = portrait_for(member)
        if portrait and f"politician:{portrait[0]}" in visible:
            identities[member.member_id] = portrait[0]
    return identities
