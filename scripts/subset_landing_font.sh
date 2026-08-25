#!/bin/bash
# Regenerate landing/assets/fonts/wick-print.woff2 — the self-hosted serif subset
# (Noto Serif SC variable wght, OFL; renamed to "Wick Print").
#
# Why: iOS has no preinstalled Simplified-Chinese serif (Songti SC is an
# on-demand downloadable asset), so serif text falls back to the Japanese
# HiraMinProN and simplified-only glyphs (图/载/烛…) fall through again —
# mixed typefaces within one heading. The subset keeps print text identical
# on every platform.
#
# Charset = every char used in landing/index.html + landing/app.js (+ ASCII
# and CJK punctuation). Run this after changing landing copy, then commit
# the regenerated woff2.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=.build/landing-font
FONT_URL="https://github.com/google/fonts/raw/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf"
mkdir -p "$WORK"

if [ ! -f "$WORK/NotoSerifSC.ttf" ]; then
    curl -sL -o "$WORK/NotoSerifSC.ttf" "$FONT_URL"
fi

if [ ! -x "$WORK/venv/bin/python3" ]; then
    python3 -m venv "$WORK/venv"
    "$WORK/venv/bin/pip" install -q fonttools brotli
fi

"$WORK/venv/bin/python3" - <<'EOF'
chars = set()
for fn in ("landing/index.html", "landing/app.js"):
    with open(fn, encoding="utf-8") as f:
        chars |= set(f.read())
chars |= {chr(c) for c in range(0x20, 0x7F)}
chars |= set("　、。，；：？！…—～·「」『』（）《》【】％‰")
chars -= {"\n", "\r", "\t"}
with open(".build/landing-font/chars.txt", "w", encoding="utf-8") as f:
    f.write("".join(sorted(chars)))
print(f"charset: {len(chars)} chars")
EOF

"$WORK/venv/bin/pyftsubset" "$WORK/NotoSerifSC.ttf" \
    --text-file="$WORK/chars.txt" --flavor=woff2 \
    --output-file="$WORK/wick-print.woff2" \
    --layout-features='*' --no-hinting --desubroutinize

"$WORK/venv/bin/python3" - <<'EOF'
from fontTools.ttLib import TTFont
f = TTFont(".build/landing-font/wick-print.woff2")
for nid, val in ((1, "Wick Print"), (2, "Regular"), (4, "Wick Print"),
                 (6, "WickPrint-Regular"), (16, "Wick Print"), (17, "Regular")):
    f["name"].setName(val, nid, 3, 1, 0x409)
    f["name"].setName(val, nid, 1, 0, 0)
f.save("landing/assets/fonts/wick-print.woff2", reorderTables=None)
EOF

ls -lh landing/assets/fonts/wick-print.woff2
