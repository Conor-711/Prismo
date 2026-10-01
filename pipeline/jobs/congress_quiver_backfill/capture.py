"""Licensed Quiver trade capture; never labels vendor rows as official filings.

Only normalized records are persisted. The member roster and House filing index are
refreshed on every run, while successful member fetches are checkpointed in SQLite.
"""
from __future__ import annotations

import datetime as dt
import io
import json
import re
import sqlite3
import subprocess
import time
import urllib.parse
import xml.etree.ElementTree as ET
import zipfile
from html.parser import HTMLParser
from pathlib import Path
from typing import Callable

import requests


BASE = "https://www.quiverquant.com"
HOUSE_BASE = "https://disclosures-clerk.house.gov/public_disc"
HEADERS = {"User-Agent": "bSmart Congress disclosure research/1.0 (licensed Quiver access)"}
MAX_HTML_BYTES = 32 * 1024 * 1024
MAX_INDEX_BYTES = 4 * 1024 * 1024


class CaptureError(RuntimeError):
    pass


def _read_limited(response: requests.Response, limit: int) -> str:
    chunks = []
    size = 0
    for chunk in response.iter_content(chunk_size=65536):
        size += len(chunk)
        if size > limit:
            raise CaptureError(f"response exceeds {limit} bytes")
        chunks.append(chunk)
    return b"".join(chunks).decode("utf-8")


def fetch_html(url: str, *, session: requests.Session | None = None) -> str:
    client = session or requests.Session()
    last_error: Exception | None = None
    for attempt in range(4):
        try:
            with client.get(url, headers=HEADERS, timeout=(15, 60), stream=True) as response:
                if response.status_code in {401, 403, 429}:
                    retry_after = response.headers.get("Retry-After")
                    detail = f"; Retry-After={retry_after}" if retry_after else ""
                    raise CaptureError(f"access refused (HTTP {response.status_code}{detail}): {url}")
                response.raise_for_status()
                return _read_limited(response, MAX_HTML_BYTES)
        except (requests.Timeout, requests.ConnectionError, requests.HTTPError) as exc:
            last_error = exc
            if attempt < 3:
                time.sleep(2 ** attempt)
    raise CaptureError(f"could not fetch {url}: {last_error}")


def fetch_house_index(year: int) -> bytes:
    url = f"{HOUSE_BASE}/financial-pdfs/{year}FD.ZIP"
    try:
        result = subprocess.run(
            ["curl", "--fail", "--location", "--silent", "--show-error",
             "--retry", "3", "--max-time", "60", url],
            check=True, capture_output=True, timeout=180,
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError) as exc:
        raise CaptureError(f"could not fetch official House index {url}: {exc}") from exc
    if len(result.stdout) > MAX_INDEX_BYTES:
        raise CaptureError(f"House index exceeds {MAX_INDEX_BYTES} bytes")
    return result.stdout


def _js_literal(html: str, assignment: str) -> object:
    match = re.search(r"\b(?:let|const|var)\s+" + re.escape(assignment) + r"\s*=\s*", html)
    if match is None:
        raise CaptureError(f"missing {assignment} payload")
    value, _ = json.JSONDecoder().raw_decode(html[match.end():].lstrip())
    return value


def parse_roster(html: str) -> list[dict]:
    marker = "const allCongressMembers = JSON.parse(`"
    start = html.find(marker)
    if start < 0:
        raise CaptureError("missing congressional roster")
    end = html.find("`);", start + len(marker))
    if end < 0:
        raise CaptureError("unterminated congressional roster")
    roster = json.loads(html[start + len(marker):end])
    if not isinstance(roster, list):
        raise CaptureError("invalid congressional roster")
    result = []
    for item in roster:
        if not isinstance(item, dict) or item.get("chamber") not in {"House", "Senate", "Inactive"}:
            continue
        name = str(item.get("name") or "").strip()
        member_id = str(item.get("bioguideID") or "").strip()
        if not name or not re.fullmatch(r"[A-Z][0-9]{6}", member_id):
            continue
        slug = urllib.parse.quote(f"{name}-{member_id}", safe="-")
        result.append({
            "member_id": member_id,
            "name": name,
            "chamber": item["chamber"],
            "party": item.get("party"),
            "profile_url": f"{BASE}/congresstrading/politician/{slug}",
        })
    return result


class _ActiveLinks(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.in_table = False
        self.depth = 0
        self.links: set[str] = set()

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag == "table" and values.get("id") == "mostActiveTradersTable":
            self.in_table = True
        if self.in_table and tag == "table":
            self.depth += 1
        if self.in_table and tag == "a":
            href = values.get("href") or ""
            if "/congresstrading/politician/" in href:
                url = urllib.parse.urljoin(BASE + "/", href)
                parts = urllib.parse.urlsplit(url)
                encoded_path = urllib.parse.quote(urllib.parse.unquote(parts.path), safe="/-")
                self.links.add(urllib.parse.urlunsplit(parts._replace(path=encoded_path)))

    def handle_endtag(self, tag: str) -> None:
        if self.in_table and tag == "table":
            self.depth -= 1
            if self.depth == 0:
                self.in_table = False


def active_profile_urls(html: str) -> set[str]:
    parser = _ActiveLinks()
    parser.feed(html)
    return parser.links


def _parse_date(value: object) -> dt.date | None:
    try:
        return dt.date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def _amount(value: object) -> tuple[int | None, int | None]:
    numbers = [int(part.replace(",", "")) for part in re.findall(r"\$([\d,]+)", str(value or ""))]
    return (numbers[0], numbers[1]) if len(numbers) == 2 else (None, None)


def parse_trades(html: str, member: dict, since: dt.date, until: dt.date) -> list[dict]:
    payload = _js_literal(html, "tradeData")
    if not isinstance(payload, list):
        raise CaptureError("invalid Quiver trade payload")
    trades: dict[str, dict] = {}
    for row in payload:
        if not isinstance(row, list) or len(row) < 15:
            raise CaptureError("Quiver trade schema changed")
        trade_date = _parse_date(row[3])
        if trade_date is None or not since <= trade_date <= until:
            continue
        source_id = str(row[7] or "").strip()
        if not re.fullmatch(r"(?:House|Senate)-(?:[A-Z]\d{6}|\d+)-\d+", source_id):
            raise CaptureError(f"unexpected trade ID: {source_id}")
        if str(row[11] or "") != source_id.split("-")[0]:
            raise CaptureError(f"trade chamber disagrees with ID: {source_id}")
        if _surname(str(row[6] or "")) != _surname(member["name"]):
            raise CaptureError(f"trade belongs to another member: {source_id}")
        amount_low, amount_high = _amount(row[10])
        trades[source_id] = {
            "source_id": source_id,
            "member_id": member["member_id"],
            "transaction_date": trade_date.isoformat(),
            "filing_date": (_parse_date(row[2]) or "").__str__(),
            "ticker": str(row[0]).strip().upper() if row[0] else None,
            "action": str(row[1] or "").strip(),
            "asset_name": str(row[8] or "").strip(),
            "asset_type": str(row[9] or "").strip(),
            "amount_low": amount_low,
            "amount_high": amount_high,
            "note": str(row[4] or "").strip(),
            "source_url": member["profile_url"],
            "verification": "vendor_only",
        }
    return list(trades.values())


def parse_house_index(data: bytes, year: int, since: dt.date, until: dt.date) -> list[dict]:
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        root = ET.fromstring(archive.read(f"{year}FD.xml"))
    filings = []
    for item in root.findall("Member"):
        if item.findtext("FilingType") != "P":
            continue
        try:
            filing_date = dt.datetime.strptime(item.findtext("FilingDate") or "", "%m/%d/%Y").date()
        except ValueError:
            continue
        if not since <= filing_date <= until:
            continue
        doc_id = item.findtext("DocID") or ""
        if not re.fullmatch(r"\d+", doc_id):
            continue
        filings.append({
            "doc_id": doc_id,
            "first": (item.findtext("First") or "").strip(),
            "last": (item.findtext("Last") or "").strip(),
            "state_district": (item.findtext("StateDst") or "").strip(),
            "filing_date": filing_date.isoformat(),
            "pdf_url": f"{HOUSE_BASE}/ptr-pdfs/{year}/{doc_id}.pdf",
        })
    return filings


_SUFFIXES = {"jr", "sr", "ii", "iii", "iv", "v"}
_HOUSE_NAME_ALIASES = {
    ("Elizabeth Fletcher", "F000468"),
    ("James D Jordan", "J000289"),
    ("James French Hill", "H001072"),
    ("Michael A. Collins", "C001129"),
    ("Richard W. Allen", "A000372"),
    ("William R. Keating", "K000375"),
}
_ALIAS_IDS = dict(_HOUSE_NAME_ALIASES)


def _name_parts(value: str) -> list[str]:
    return re.findall(r"[a-z]+", value.lower())


def _surname(value: str) -> str:
    parts = _name_parts(value)
    while parts and parts[-1] in _SUFFIXES:
        parts.pop()
    return parts[-1] if parts else ""


def select_members(roster: list[dict], active_urls: set[str], filings: list[dict]) -> tuple[list[dict], list[str]]:
    """Select House filers and Senate members, leaving ambiguous matches visible."""
    by_last: dict[str, list[dict]] = {}
    for member in roster:
        by_last.setdefault(_surname(member["name"]), []).append(member)
    selected = {m["member_id"]: m for m in roster if m["chamber"] == "Senate"}
    selected.update({m["member_id"]: m for m in roster if m["profile_url"] in active_urls})
    unmatched = []
    seen_filers = {(f["first"], f["last"]) for f in filings}
    for first, last in sorted(seen_filers):
        filer_name = f"{first} {last}".strip()
        alias_id = _ALIAS_IDS.get(filer_name)
        if alias_id is not None:
            member = next((m for m in roster if m["member_id"] == alias_id), None)
            if member is not None:
                selected[alias_id] = member
                continue
        candidates = [m for m in by_last.get(_surname(last), []) if m["chamber"] in {"House", "Inactive"}]
        if len(candidates) > 1:
            given = _name_parts(first)
            first_name = given[0] if given else ""
            matches = []
            for member in candidates:
                member_parts = _name_parts(member["name"])
                member_first = member_parts[0] if member_parts else ""
                if member_first == first_name or (
                    min(len(member_first), len(first_name)) >= 2
                    and (member_first.startswith(first_name) or first_name.startswith(member_first))
                ):
                    matches.append(member)
            candidates = matches
        if len(candidates) == 1:
            selected[candidates[0]["member_id"]] = candidates[0]
        else:
            unmatched.append(filer_name)
    return list(selected.values()), unmatched


def _schema(db: sqlite3.Connection) -> None:
    db.executescript("""
        CREATE TABLE IF NOT EXISTS capture_window (
            singleton INTEGER PRIMARY KEY CHECK(singleton=1),
            since TEXT NOT NULL, until TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS members (
            member_id TEXT PRIMARY KEY, name TEXT NOT NULL, chamber TEXT NOT NULL,
            party TEXT, profile_url TEXT NOT NULL, fetched_at TEXT, error TEXT,
            trade_count INTEGER
        );
        CREATE TABLE IF NOT EXISTS trades (
            source_id TEXT PRIMARY KEY, member_id TEXT NOT NULL,
            transaction_date TEXT NOT NULL, filing_date TEXT, ticker TEXT,
            action TEXT NOT NULL, asset_name TEXT, asset_type TEXT,
            amount_low INTEGER, amount_high INTEGER, note TEXT,
            source_url TEXT NOT NULL, verification TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS trades_date ON trades(transaction_date);
        CREATE TABLE IF NOT EXISTS house_filings (
            doc_id TEXT PRIMARY KEY, first TEXT, last TEXT,
            state_district TEXT, filing_date TEXT NOT NULL, pdf_url TEXT NOT NULL
        );
    """)


def capture(
    *, since: dt.date, until: dt.date, db_path: Path, report_path: Path,
    max_members: int | None = None, delay: float = 0.75,
    refresh: bool = False,
    get_html: Callable[[str], str] = fetch_html,
    get_house_index: Callable[[int], bytes] = fetch_house_index,
) -> dict:
    if since > until or delay < 0:
        raise ValueError("invalid date window or delay")
    db_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    dashboard = get_html(f"{BASE}/congresstrading/")
    roster = parse_roster(dashboard)
    active_urls = active_profile_urls(dashboard)
    if not roster or not active_urls:
        raise CaptureError("Quiver roster or active traders table is empty")
    active_ids = {url.rsplit("-", 1)[-1] for url in active_urls}
    house_filings: list[dict] = []
    house_index_errors: list[str] = []
    for year in range(since.year, until.year + 1):
        try:
            house_filings.extend(parse_house_index(get_house_index(year), year, since, until))
        except (CaptureError, OSError, ValueError, zipfile.BadZipFile, ET.ParseError, KeyError) as exc:
            house_index_errors.append(f"{year}: {exc}")

    selected, unmatched_filers = select_members(roster, active_urls, house_filings)
    selected.sort(key=lambda member: (member["member_id"] not in active_ids, member["chamber"] != "House", member["name"]))
    selected_count = len(selected)
    if max_members is not None:
        selected = selected[:max_members]

    db = sqlite3.connect(db_path)
    try:
        _schema(db)
        prior_window = db.execute("SELECT since,until FROM capture_window WHERE singleton=1").fetchone()
        if prior_window and prior_window != (since.isoformat(), until.isoformat()):
            raise CaptureError("existing database belongs to a different date window")
        with db:
            db.execute(
                "INSERT OR IGNORE INTO capture_window VALUES (1,?,?)",
                (since.isoformat(), until.isoformat()),
            )
            db.executemany(
                "INSERT OR REPLACE INTO house_filings VALUES (:doc_id,:first,:last,:state_district,:filing_date,:pdf_url)",
                house_filings,
            )
            db.executemany("""
                INSERT INTO members(member_id,name,chamber,party,profile_url)
                VALUES (:member_id,:name,:chamber,:party,:profile_url)
                ON CONFLICT(member_id) DO UPDATE SET name=excluded.name,
                    chamber=excluded.chamber,party=excluded.party,profile_url=excluded.profile_url
            """, selected)
        failures = []
        for index, member in enumerate(selected, start=1):
            prior = db.execute("SELECT fetched_at FROM members WHERE member_id=?", (member["member_id"],)).fetchone()
            if prior and prior[0] and not refresh:
                continue
            try:
                trades = parse_trades(get_html(member["profile_url"]), member, since, until)
                with db:
                    db.execute("DELETE FROM trades WHERE member_id=?", (member["member_id"],))
                    db.executemany("""
                        INSERT INTO trades VALUES (:source_id,:member_id,:transaction_date,
                            :filing_date,:ticker,:action,:asset_name,:asset_type,
                            :amount_low,:amount_high,:note,:source_url,:verification)
                    """, trades)
                    db.execute(
                        "UPDATE members SET fetched_at=?,error=NULL,trade_count=? WHERE member_id=?",
                        (dt.datetime.now(dt.timezone.utc).isoformat(), len(trades), member["member_id"]),
                    )
            except (CaptureError, requests.RequestException, ValueError) as exc:
                failures.append(f"{member['member_id']}: {exc}")
                with db:
                    db.execute("UPDATE members SET error=? WHERE member_id=?", (str(exc), member["member_id"]))
                if "access refused" in str(exc):
                    break
            if index % 25 == 0:
                print(f"processed {index}/{len(selected)} members", flush=True)
            time.sleep(delay)
        total_trades = db.execute("SELECT COUNT(*) FROM trades").fetchone()[0]
        fetched_members = sum(
            db.execute("SELECT fetched_at FROM members WHERE member_id=?", (member["member_id"],)).fetchone()[0] is not None
            for member in selected
        )
        chamber_counts = dict(db.execute(
            "SELECT CASE WHEN source_id LIKE 'House-%' THEN 'House' ELSE 'Senate' END,COUNT(*) "
            "FROM trades GROUP BY 1"
        ))
        report = {
            "source": "quiver_licensed_public_pages",
            "since": since.isoformat(), "until": until.isoformat(),
            "roster_members": len(roster), "selected_members": len(selected),
            "full_run_members": selected_count,
            "fetched_members": fetched_members, "trade_count": total_trades,
            "trade_count_by_chamber": chamber_counts,
            "house_ptr_filings_in_filing_window": len(house_filings),
            "unmatched_house_filers": unmatched_filers,
            "house_index_errors": house_index_errors, "member_errors": failures,
            "verification": "vendor_only; official House index is filing-level coverage, not trade-level verification",
            "capture_complete": (
                not failures and not house_index_errors and not unmatched_filers
                and fetched_members >= len(selected) and max_members is None
            ),
            "database": str(db_path),
        }
        tmp = report_path.with_suffix(report_path.suffix + ".tmp")
        tmp.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        tmp.replace(report_path)
        return report
    finally:
        db.close()
