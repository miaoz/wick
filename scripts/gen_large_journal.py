#!/usr/bin/env python3
"""Generate a large multi-thousand-item journal archive for performance testing
(T4-5 Instruments / large-journal scenarios in the maintenance plan).

Produces a zip matching Wick's export format exactly:

    Wick-Journal/
      journal.json        # JournalSnapshot { version: 2, entries: [...] }
      images/             # optional <uuid>.png placeholders referenced by items

journal.json is pretty-printed with sorted keys and ISO-8601 (UTC) dates, the
same as `JournalSyncEncoding.encoder` (JournalSyncEncoding.swift), and item
keys match the custom `JournalItem.CodingKeys` (id/tag/body/imageFilenames/
review) — so the archive imports through `JournalStore.importArchive` unchanged.

Usage:
  python3 scripts/gen_large_journal.py --days 365 --items-per-day 8 \
      --images-per-day 1 --out ~/Desktop/LargeJournal.zip
"""

from __future__ import annotations

import argparse
import datetime
import io
import json
import os
import struct
import uuid
import zlib
import zipfile

VERSION = 2


# ISO-8601 (no fractional seconds) — matches JSONEncoder .iso8601.
def iso(dt: datetime.datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def make_item(index: int, day: datetime.date, images: list[str]) -> dict:
    tag = ["BTC", "ETH", "SOL", "复盘", "读书", "想法", "PEPE", "工作"][index % 8]
    # Body long enough to matter for keystroke re-evaluation / search cost.
    body = (f"第 {index + 1} 条。今天是 {day}，记录一下这一天的交易与思考。"
            "市场波动、仓位管理、情绪复盘，逐条写下来，便于日后回看。\n"
            "长一点的正文能让编辑器重估、全文搜索和侧栏统计都更有代表性。" * 6)
    item: dict = {
        "id": str(uuid.uuid4()),
        "tag": tag,
        "body": body,
        "imageFilenames": [],
    }
    if images:
        item["imageFilenames"] = [images[index % len(images)]]
    return item


def make_entry(day: datetime.date, item_count: int, images: list[str]) -> dict:
    day_dt = datetime.datetime(day.year, day.month, day.day, tzinfo=datetime.timezone.utc)
    return {
        "id": str(uuid.uuid4()),
        "date": iso(day_dt),
        "title": "",
        "items": [make_item(i, day, images) for i in range(item_count)],
        "createdAt": iso(day_dt),
        "updatedAt": iso(day_dt),
    }


def tiny_png(size: int = 32) -> bytes:
    """A minimal solid-color PNG (no PIL dependency)."""
    def chunk(tag: bytes, data: bytes) -> bytes:
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)  # 8-bit RGB
    raw = b"".join(b"\x00" + bytes([0xD8, 0xA0, 0x70]) * size for _ in range(size))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(raw))
            + chunk(b"IEND", b""))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--days", type=int, default=200, help="number of calendar days")
    parser.add_argument("--items-per-day", type=int, default=50, help="items per day")
    parser.add_argument("--images-per-day", type=int, default=0,
                        help="placeholder images per day (0 = none, keeps the zip small)")
    parser.add_argument("--out", default=os.path.expanduser("~/Desktop/Wick-LargeJournal.zip"))
    args = parser.parse_args()

    total_items = args.days * args.items_per_day
    print(f"generating {args.days} days × {args.items_per_day} items = {total_items} items "
          f"({args.images_per_day} images/day)")

    today = datetime.date.today()
    entries: list[dict] = []
    referenced_images: set[str] = set()
    for d in range(args.days):
        day = today - datetime.timedelta(days=d)
        day_images = [f"{uuid.uuid4()}.png" for _ in range(args.images_per_day)]
        referenced_images.update(day_images)
        entries.append(make_entry(day, args.items_per_day, day_images))

    payload = {"version": VERSION, "entries": entries}
    json_bytes = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True).encode("utf-8")

    png = tiny_png()
    with zipfile.ZipFile(args.out, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("Wick-Journal/journal.json", json_bytes)
        for name in sorted(referenced_images):
            zf.writestr(f"Wick-Journal/images/{name}", png)

    size_mb = os.path.getsize(args.out) / 1_048_576
    print(f"wrote {args.out} ({size_mb:.1f} MB, {len(referenced_images)} image files)")
    print("import: Wick 菜单栏 → 日记 → 导入，选择该 zip。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
