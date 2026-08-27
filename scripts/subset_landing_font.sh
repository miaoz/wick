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
# Pinned to a specific google/fonts commit (WEB-02) so the subset is
# reproducible — `main` moves and would silently change the printed font.
# Bump deliberately after checking in the new woff2. Resolve with:
#   curl -s "https://api.github.com/repos/google/fonts/commits?path=ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf&per_page=1"
FONT_COMMIT="2e61f4355afd22b801791b0df176065082423b87"
FONT_URL="https://github.com/google/fonts/raw/${FONT_COMMIT}/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf"
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
