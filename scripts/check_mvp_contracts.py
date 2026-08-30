#!/usr/bin/env python3
"""Validate cross-file invariants for the Smart Intelligence MVP fixtures."""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from uuid import UUID


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "contracts" / "fixtures"


def load(name: str) -> list[dict]:
    with (FIXTURES / name).open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, list):
        raise AssertionError(f"{name} must contain a JSON array")
    return value


def parse_id(value: str, label: str) -> str:
    UUID(value)
    return value


def parse_time(value: str, label: str) -> datetime:
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise AssertionError(f"{label} must be ISO-8601: {value}") from error


def unique_ids(rows: list[dict], label: str) -> set[str]:
    values = [parse_id(row["id"], f"{label}.id") for row in rows]
    if len(values) != len(set(values)):
        raise AssertionError(f"{label} contains duplicate ids")
    return set(values)


def unique_string_ids(rows: list[dict], label: str) -> set[str]:
    values = [str(row["id"]).strip() for row in rows]
    if not all(values):
        raise AssertionError(f"{label} contains an empty id")
    if len(values) != len(set(values)):
        raise AssertionError(f"{label} contains duplicate ids")
    return set(values)


def main() -> None:
    portfolio = load("portfolio.json")
    account_updates = load("smart-account-updates.json")
    money_movements = load("smart-money-movements.json")
    signals = load("portfolio-signals.json")
    intelligence = load("ticker-intelligence.json")
    smart_accounts = load("smart-accounts.json")
    smart_money_accounts = load("smart-money.json")
    smart_money_evidence = load("smart-money-evidence.json")

    account_ids = unique_ids(account_updates, "SmartAccountUpdate")
    money_ids = unique_ids(money_movements, "SmartMoneyMovement")
    signal_ids = unique_ids(signals, "PortfolioSignal")
    signal_by_id = {row["id"]: row for row in signals}
    smart_account_ids = unique_string_ids(smart_accounts, "SmartAccountProfile")
    smart_money_ids = unique_string_ids(smart_money_accounts, "SmartMoneySignal")
    unique_ids(smart_money_evidence, "SmartMoneyRepresentativeEvidence")
    smart_money_identity_by_id: dict[str, tuple[str, int]] = {}

    unique_ids(portfolio, "PortfolioPosition")
    for profile in smart_accounts:
        rank = profile.get("rank")
        platform_rank = profile.get("platformRank")
        percentile = profile.get("platformPercentile")
        if not isinstance(rank, int) or rank < 1:
            raise AssertionError(f"SmartAccountProfile {profile['id']} has invalid rank")
        if not isinstance(platform_rank, int) or platform_rank < 1:
            raise AssertionError(f"SmartAccountProfile {profile['id']} has invalid platformRank")
        if not isinstance(percentile, (int, float)) or not 0 <= percentile <= 1:
            raise AssertionError(f"SmartAccountProfile {profile['id']} has invalid platformPercentile")
        if profile.get("confidence") not in {"observing", "low", "medium", "high"}:
            raise AssertionError(f"SmartAccountProfile {profile['id']} has invalid confidence")
        if profile.get("effectiveSamples", -1) < 0 or profile.get("settledCalls", -1) < 0:
            raise AssertionError(f"SmartAccountProfile {profile['id']} has invalid evidence counts")
        if not profile.get("topTickers"):
            raise AssertionError(f"SmartAccountProfile {profile['id']} must expose ranked ticker evidence")

    for account in smart_money_accounts:
        display_name = account.get("displayName")
        avatar_variant = account.get("avatarVariant")
        if not isinstance(display_name, str) or not display_name.strip():
            raise AssertionError(f"SmartMoneySignal {account['id']} must expose a stable displayName")
        if len(display_name.split()) != 1:
            raise AssertionError(f"SmartMoneySignal {account['id']} must use a single display name")
        if not isinstance(avatar_variant, int) or not 1 <= avatar_variant <= 54:
            raise AssertionError(f"SmartMoneySignal {account['id']} has invalid avatarVariant")
        smart_money_identity_by_id[account["id"]] = (display_name, avatar_variant)
    display_names = [identity[0] for identity in smart_money_identity_by_id.values()]
    if len(display_names) != len(set(display_names)):
        raise AssertionError("SmartMoneySignal contains duplicate consumer display names")
    avatar_variants = [identity[1] for identity in smart_money_identity_by_id.values()]
    if len(avatar_variants) != len(set(avatar_variants)):
        raise AssertionError("SmartMoneySignal contains duplicate consumer avatar variants")

    for entry in portfolio:
        kind = entry["entryKind"]
        if kind not in {"position", "watchlist"}:
            raise AssertionError(f"PortfolioPosition {entry['id']} has invalid entryKind")
        weight = entry.get("portfolioWeight")
        if weight is not None and not 0 <= weight <= 1:
            raise AssertionError(f"PortfolioPosition {entry['id']} has invalid portfolioWeight")
        if kind == "watchlist" and (entry["shares"] != 0 or weight is not None):
            raise AssertionError(f"Watchlist entry {entry['id']} contains synthetic holding values")

    for update in account_updates:
        if update["authorId"] not in smart_account_ids:
            raise AssertionError(
                f"SmartAccountUpdate {update['id']} references missing profile {update['authorId']}"
            )
        percentile = update["platformPercentile"]
        if not 0 <= percentile <= 1:
            raise AssertionError(f"SmartAccountUpdate {update['id']} has invalid platformPercentile")
        parse_time(update["publishedAt"], "SmartAccountUpdate.publishedAt")

    for movement in money_movements:
        if movement["accountId"] not in smart_money_ids:
            raise AssertionError(
                f"SmartMoneyMovement {movement['id']} references missing account {movement['accountId']}"
            )
        parse_time(movement["observedAt"], "SmartMoneyMovement.observedAt")
        expected_change = movement["notionalAfter"] - movement["notionalBefore"]
        if abs(expected_change - movement["notionalChange"]) > 0.01:
            raise AssertionError(f"SmartMoneyMovement {movement['id']} has inconsistent notionals")
        movement_identity = (movement.get("accountDisplayName"), movement.get("avatarVariant"))
        if movement_identity != smart_money_identity_by_id[movement["accountId"]]:
            raise AssertionError(f"SmartMoneyMovement {movement['id']} has inconsistent public identity")

    evidence_counts: dict[str, int] = {}
    for item in smart_money_evidence:
        account_id = item["accountId"]
        if account_id not in smart_money_ids:
            raise AssertionError(
                f"SmartMoneyRepresentativeEvidence {item['id']} references missing account {account_id}"
            )
        evidence_counts[account_id] = evidence_counts.get(account_id, 0) + 1
        if evidence_counts[account_id] > 3:
            raise AssertionError(f"Smart Money account {account_id} has more than three representative markets")
        if item["representativeRank"] != evidence_counts[account_id]:
            raise AssertionError(f"Smart Money account {account_id} has non-contiguous representative ranks")
        price_evidence = item["priceEvidence"]
        if price_evidence["market"] != item["market"] or not price_evidence["candles"]:
            raise AssertionError(f"SmartMoneyRepresentativeEvidence {item['id']} has invalid market candles")
        markers = price_evidence["entryMarkers"]
        if not 1 <= len(markers) <= 10:
            raise AssertionError(f"SmartMoneyRepresentativeEvidence {item['id']} has invalid marker count")
        for marker in markers:
            if marker["action"] not in {"opened", "increased", "flipped"}:
                raise AssertionError(f"SmartMoneyRepresentativeEvidence {item['id']} contains an exit marker")
            if marker["price"] <= 0 or marker["entryNotional"] <= 0:
                raise AssertionError(f"SmartMoneyRepresentativeEvidence {item['id']} has invalid marker economics")
            if marker["priceBasis"] not in {"reported", "nearest_4h_close"}:
                raise AssertionError(f"SmartMoneyRepresentativeEvidence {item['id']} has invalid price basis")

    for signal in signals:
        occurred_at = parse_time(signal["occurredAt"], "PortfolioSignal.occurredAt")
        data_as_of = parse_time(signal["dataAsOf"], "PortfolioSignal.dataAsOf")
        if data_as_of < occurred_at:
            raise AssertionError(f"PortfolioSignal {signal['id']} has dataAsOf before occurredAt")
        if signal["dataStatus"] not in {"current", "delayed"}:
            raise AssertionError(f"PortfolioSignal {signal['id']} has invalid dataStatus")
        limitations = signal["limitations"]
        if not limitations or not all(isinstance(item, str) and item.strip() for item in limitations):
            raise AssertionError(f"PortfolioSignal {signal['id']} must disclose its limitations")
        if signal["dataStatus"] == "delayed" and not any("delay" in item.lower() for item in limitations):
            raise AssertionError(f"Delayed signal {signal['id']} must explain the delayed source")

        sources: set[str] = set()
        for evidence in signal["evidence"]:
            source = evidence["source"]
            sources.add(source)
            reference_id = parse_id(evidence["referenceId"], "PortfolioSignalEvidence.referenceId")
            if source == "smart_account" and reference_id not in account_ids:
                raise AssertionError(f"Signal {signal['id']} references a missing Smart Account update")
            if source == "smart_money" and reference_id not in money_ids:
                raise AssertionError(f"Signal {signal['id']} references a missing Smart Money movement")
            if source == "smart_money":
                identity = (evidence.get("actorName"), evidence.get("avatarVariant"))
                movement = next(row for row in money_movements if row["id"] == reference_id)
                expected_identity = (
                    movement["accountDisplayName"],
                    movement["avatarVariant"],
                )
                if identity != expected_identity:
                    raise AssertionError(
                        f"Signal {signal['id']} has inconsistent Smart Money public identity"
                    )
            if source not in {"smart_account", "smart_money"}:
                raise AssertionError(f"Signal {signal['id']} uses unsupported evidence source {source}")
            parse_time(evidence["observedAt"], "PortfolioSignalEvidence.observedAt")

        kind = signal["kind"]
        if kind in {"confirmation", "divergence"} and sources != {"smart_account", "smart_money"}:
            raise AssertionError(f"{kind} signal {signal['id']} requires both evidence sources")
        if kind == "account_leads" and "smart_account" not in sources:
            raise AssertionError(f"account_leads signal {signal['id']} requires Smart Account evidence")
        if kind == "money_leads" and "smart_money" not in sources:
            raise AssertionError(f"money_leads signal {signal['id']} requires Smart Money evidence")
        if signal["smartMoneyCoverage"] == "unavailable" and "smart_money" in sources:
            raise AssertionError(f"Signal {signal['id']} cannot have money evidence with unavailable coverage")

    intelligence_tickers = [row["ticker"] for row in intelligence]
    if len(intelligence_tickers) != len(set(intelligence_tickers)):
        raise AssertionError("TickerIntelligence contains duplicate tickers")

    for snapshot in intelligence:
        ticker = snapshot["ticker"]
        parse_time(snapshot["dataAsOf"], "TickerIntelligence.dataAsOf")
        latest_signal_id = snapshot.get("latestSignalId")
        if latest_signal_id is not None:
            parse_id(latest_signal_id, "TickerIntelligence.latestSignalId")
            if latest_signal_id not in signal_ids:
                raise AssertionError(f"TickerIntelligence {ticker} references a missing signal")
            if signal_by_id[latest_signal_id]["ticker"] != ticker:
                raise AssertionError(f"TickerIntelligence {ticker} references a signal for another ticker")

        expected_authors = sum(update["ticker"] == ticker for update in account_updates)
        expected_accounts = len(
            {
                movement["accountId"]
                for movement in money_movements
                if movement["ticker"] == ticker
            }
        )
        account_snapshot = snapshot["smartAccount"]
        money_snapshot = snapshot["smartMoney"]
        if account_snapshot["qualifiedAuthorCount"] != expected_authors:
            raise AssertionError(f"TickerIntelligence {ticker} has an inconsistent author count")
        if money_snapshot["qualifiedAccountCount"] != expected_accounts:
            raise AssertionError(f"TickerIntelligence {ticker} has an inconsistent account count")
        if expected_authors == 0 and account_snapshot.get("latestUpdateAt") is not None:
            raise AssertionError(f"TickerIntelligence {ticker} has a timestamp without an account update")
        if expected_accounts == 0 and money_snapshot.get("latestMovementAt") is not None:
            raise AssertionError(f"TickerIntelligence {ticker} has a timestamp without a money movement")
        if money_snapshot["coverage"] == "unavailable" and expected_accounts != 0:
            raise AssertionError(f"TickerIntelligence {ticker} exposes movements with unavailable coverage")

    print(
        "MVP contract fixtures passed: "
        f"{len(portfolio)} portfolio entries, {len(account_updates)} account updates, "
        f"{len(money_movements)} money movements, {len(signals)} portfolio signals, "
        f"{len(intelligence)} ticker snapshots, {len(smart_accounts)} Smart Account profiles, "
        f"{len(smart_money_accounts)} Smart Money accounts, "
        f"{len(smart_money_evidence)} representative entry charts."
    )


if __name__ == "__main__":
    main()
