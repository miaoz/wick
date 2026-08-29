#!/usr/bin/env python3
"""Fetch a Binance USDⓈ-M account's funding-fee income history using the app's
locally stored Keychain credential (service `com.miaoz.wick.exchange`), then
save it as a JSON array for `funding_dedup_check.py`.

The secret is read from the macOS Keychain at runtime and is never printed or
written to disk. Requests mirror the app's `BinanceFuturesClient` (7-day chunks,
limit 1000, cursor by last time+1ms, HMAC-SHA256 lowercase-hex signature).

Usage:
  python3 scripts/fetch_binance_income.py --journal 84E6D62B-... --start 2026-03-01 \
      --out /tmp/binance-funding.json
Then:
  python3 scripts/funding_dedup_check.py /tmp/binance-funding.json
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import hmac
import json
import subprocess
import sys
import time
import urllib.parse
import urllib.request

BASE = "https://fapi.binance.com"
CHUNK = 7 * 24 * 3600  # seconds
LIMIT = 1000


def load_blob(journal_id: str) -> dict:
    """Reads the app's Keychain item (service com.miaoz.wick.exchange)."""
    proc = subprocess.run(
        ["security", "find-generic-password", "-s", "com.miaoz.wick.exchange",
         "-a", journal_id, "-w"],
        capture_output=True, text=True, check=True,
    )
    return json.loads(proc.stdout.strip())


def signed_request(api_key: str, secret: str, path: str, params: list[tuple[str, str]]) -> dict:
    query = "&".join(f"{k}={urllib.parse.quote_plus(str(v))}" for k, v in params)
    signature = hmac.new(secret.encode(), query.encode(), hashlib.sha256).hexdigest()
    url = f"{BASE}{path}?{query}&signature={signature}"
    req = urllib.request.Request(url, headers={"X-MBX-APIKEY": api_key})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def income_page(api_key: str, secret: str, start_ms: int, end_ms: int) -> list[dict]:
    params = [
        ("incomeType", "FUNDING_FEE"),
        ("startTime", start_ms),
        ("endTime", end_ms),
        ("limit", LIMIT),
        ("recvWindow", "5000"),
        ("timestamp", int(time.time() * 1000)),
    ]
    return signed_request(api_key, secret, "/fapi/v1/income", params)


def fetch(api_key: str, secret: str, start: datetime.datetime, end: datetime.datetime) -> list[dict]:
    rows: list[dict] = []
    chunk_start = start
    while chunk_start < end:
        chunk_end = min(end, chunk_start + datetime.timedelta(seconds=CHUNK))
        cursor = chunk_start
        page_count = 0
        while cursor < chunk_end and page_count < 200:
            page_count += 1
            page = income_page(api_key, secret,
                               int(cursor.timestamp() * 1000),
                               int(chunk_end.timestamp() * 1000))
            rows.extend(page)
            if len(page) < LIMIT:
                break
            last_time = max(r["time"] for r in page)
            next_cursor = datetime.datetime.fromtimestamp((last_time + 1) / 1000,
                                                          tz=datetime.timezone.utc)
            cursor = max(next_cursor, cursor + datetime.timedelta(milliseconds=1))
            time.sleep(0.1)
        chunk_start = chunk_end + datetime.timedelta(milliseconds=1)
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--journal", required=True,
                        help="journal UUID bound to Binance (from ~/Library/Application Support/Wick/Journals/catalog.json)")
    parser.add_argument("--start", default="", help="ISO date to fetch from (default 180 days ago)")
    parser.add_argument("--out", default="/tmp/binance-funding.json")
    args = parser.parse_args()

    blob = load_blob(args.journal)
    if blob.get("venue") != "binance":
        sys.exit(f"journal {args.journal} is not a Binance binding (venue={blob.get('venue')})")
    api_key = blob["apiKey"].strip()
    secret = blob["secret"].strip()

    end = datetime.datetime.now(datetime.timezone.utc)
    if args.start:
        start = datetime.datetime.fromisoformat(args.start).replace(tzinfo=datetime.timezone.utc)
    else:
        start = end - datetime.timedelta(days=180)

    rows = fetch(api_key, secret, start, end)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)

    n = len(rows)
    if n:
        times = [r["time"] for r in rows]
        first = datetime.datetime.fromtimestamp(min(times) / 1000, tz=datetime.timezone.utc)
        last = datetime.datetime.fromtimestamp(max(times) / 1000, tz=datetime.timezone.utc)
        total = sum(float(r.get("income", 0)) for r in rows)
        print(f"fetched {n} FUNDING_FEE rows  {first:%Y-%m-%d}..{last:%Y-%m-%d}  total={total:.8f}")
    else:
        print("no FUNDING_FEE rows in the window")
    print(f"saved {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
