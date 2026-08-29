#!/usr/bin/env python3
"""Check Binance funding history for `symbol#time` dedup collisions (TR-07).

The Wick exchange coordinator dedups funding events by the key `symbol#time`
(see ExchangePositionCoordinator.syncFromExchange). On a Binance HEDGE-MODE
account both lanes can be open on one symbol at a funding settlement, and the
two funding rows can share the same `time` (ms) with different amounts — the
current key would silently drop one, so the funding total would not match the
exchange bill.

Feed it one of:
  * a raw `GET /fapi/v1/income?incomeType=FUNDING_FEE` response (a JSON array),
  * the CSV exported from Binance's "Funds > Futures > Income History" page.

It reports every `symbol#time` collision and whether the colliding rows are
genuinely distinct (different amount / different tranId) — i.e. real funding
events the current dedup would drop — plus the total amount the current dedup
undercounts versus the true total.

Exit code 1 when any real-drop-risk collision is found (handy for scripting).
"""

from __future__ import annotations

import csv
import datetime
import json
import sys
from collections import defaultdict

REQUIRED = ("symbol", "income", "time")


def norm_key(s: str) -> str:
    return (s or "").strip().lower().replace("/", "")


def time_to_ms(value: str) -> int | None:
    """Epoch ms from either an integer ms string or 'YYYY-MM-DD HH:MM:SS' (UTC)."""
    v = (value or "").strip()
    if not v:
        return None
    try:
        return int(v)
    except ValueError:
        pass
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S", "%Y/%m/%d %H:%M:%S"):
        try:
            dt = datetime.datetime.strptime(v, fmt)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=datetime.timezone.utc)
            return int(dt.timestamp() * 1000)
        except ValueError:
            continue
    return None


def parse_csv(path: str) -> list[dict]:
    """Binance income-history CSV → normalized rows (symbol/income/time_ms/tranId).

    Handles both the website export ('UTC Time' at second resolution,
    'Transaction ID') and a raw column rename of the API shape.
    """
    rows: list[dict] = []
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for raw in reader:
            # Header casing varies between the zh/en exports; match case-insensitively.
            row = {k.strip().lower().replace(" ", "_"): v.strip() for k, v in raw.items()}
            income_type = row.get("income_type") or row.get("type") or ""
            if income_type and norm_key(income_type) != "funding_fee":
                continue
            symbol = row.get("symbol", "")
            if not symbol:
                continue
            time_val = row.get("time") or row.get("utc_time") or row.get("timestamp")
            if not time_val:
                continue
            rows.append({
                "symbol": symbol,
                "income": row.get("income", "0"),
                "time_ms": time_to_ms(time_val),
                "time_str": time_val,
                "asset": row.get("asset", ""),
                "tranId": row.get("tranid")
                           or row.get("transaction_id")
                           or row.get("tx_id")
                           or "",
            })
    return rows


def parse_json(path: str) -> list[dict]:
    with open(path, encoding="utf-8") as f:
        payload = json.load(f)
    if not isinstance(payload, list):
        sys.exit("expected a JSON array (GET /fapi/v1/income response)")
    rows = []
    for item in payload:
        income_type = str(item.get("incomeType", "")).lower()
        if income_type and income_type != "funding_fee":
            continue
        rows.append({
            "symbol": item.get("symbol", ""),
            "income": str(item.get("income", "0")),
            "time_ms": time_to_ms(str(item.get("time", "0"))),
            "time_str": str(item.get("time", "")),
            "asset": item.get("asset", ""),
            "tranId": str(item.get("tranId", "")),
        })
    return rows


def row_key(row: dict) -> str:
    t = row["time_ms"] if row["time_ms"] is not None else row["time_str"]
    return f"{norm_key(row['symbol'])}#{t}"


def analyze(rows: list[dict]) -> int:
    if not rows:
        print("no FUNDING_FEE rows found")
        return 0

    by_key: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        by_key[row_key(row)].append(row)

    collisions = {k: v for k, v in by_key.items() if len(v) > 1}
    true_total = sum(float(r["income"]) for r in rows)

    # The coordinator's current dedup keeps only the FIRST row per key.
    deduped_total = sum(float(v[0]["income"]) for v in by_key.values())

    print(f"rows={len(rows)}  unique symbol#time keys={len(by_key)}  "
          f"colliding keys={len(collisions)}")
    print(f"true funding total = {true_total:.8f}")
    print(f"deduped total      = {deduped_total:.8f}")
    print(f"undercount by current symbol#time dedup = {true_total - deduped_total:.8f}")

    real_drop = 0
    for key in sorted(collisions):
        rows_in_key = collisions[key]
        amounts = {float(r["income"]) for r in rows_in_key}
        tran_ids = {r["tranId"] for r in rows_in_key if r["tranId"]}
        distinct = len(amounts) > 1 or len(tran_ids) > 1
        if distinct:
            real_drop += 1
        flag = "REAL DROP RISK" if distinct else "benign duplicate"
        print(f"\n  [{flag}] {key}  ({len(rows_in_key)} rows, amounts={sorted(amounts)}, "
              f"tranIds={sorted(tran_ids) or ['<none>']})")
    return 1 if real_drop else 0


def selftest() -> int:
    """Synthetic hedge-mode data: same symbol+ms, two lanes, different amounts."""
    synthetic = [
        {"symbol": "BTCUSDT", "income": "-1.5", "time_ms": 1725000000000, "time_str": "1725000000000", "asset": "USDT", "tranId": "111"},
        {"symbol": "BTCUSDT", "income": "0.75", "time_ms": 1725000000000, "time_str": "1725000000000", "asset": "USDT", "tranId": "222"},
        {"symbol": "ETHUSDT", "income": "-0.3", "time_ms": 1725000000000, "time_str": "1725000000000", "asset": "USDT", "tranId": "333"},
        {"symbol": "ETHUSDT", "income": "-0.3", "time_ms": 1725000000000, "time_str": "1725000000000", "asset": "USDT", "tranId": "333"},
    ]
    print("== self-test (synthetic hedge-mode data) ==")
    return analyze(synthetic)


def main() -> int:
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if args[0] == "--selftest":
        return selftest()

    rows: list[dict] = []
    for path in args:
        with open(path, encoding="utf-8") as f:
            first = f.read(4096).lstrip()
        if first.startswith("["):
            rows.extend(parse_json(path))
        else:
            rows.extend(parse_csv(path))
    return analyze(rows)


if __name__ == "__main__":
    sys.exit(main())
