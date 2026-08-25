#!/usr/bin/env bash
# View iOS wishlist demand stats and registered emails from Cloudflare R2
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$ROOT_DIR/.env" ]]; then
    set -a
    source "$ROOT_DIR/.env"
    set +a
fi

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" || -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
    echo "Error: CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID must be set in .env" >&2
    exit 1
fi

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

npx wrangler r2 object get application-releases/wick/ios_wishlist.json --file="$TMP_FILE" --remote >/dev/null 2>&1 || {
    echo "No wishlist data recorded yet."
    exit 0
}

python3 - <<PY
import json
try:
    with open("$TMP_FILE") as f:
        data = json.load(f)
    votes = data.get("votes", 0)
    emails = data.get("emails", [])
    total = votes + len(emails)
    print("==========================================")
    print("  📱 Wick iOS 愿望清单与需求统计")
    print("==========================================")
    print(f"• 需求总人数:    {total} 位")
    print(f"• 匿名 +1 投票:  {votes} 票")
    print(f"• 邮箱订阅人数:  {len(emails)} 位")
    print(f"• 最后更新时间:  {data.get('updatedAt', 'N/A')}")
    print("------------------------------------------")
    if emails:
        print("登记邮箱列表:")
        for idx, it in enumerate(emails, 1):
            if isinstance(it, dict):
                print(f"  {idx}. {it.get('email')}  ({it.get('createdAt', '')})")
            else:
                print(f"  {idx}. {it}")
    else:
        print("（暂无登记邮箱）")
    print("==========================================")
except Exception as e:
    print(f"Error reading wishlist data: {e}")
PY
