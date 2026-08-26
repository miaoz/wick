#!/usr/bin/env bash
# View iOS wishlist demand stats and registered emails from Cloudflare R2 (Remote or Local)
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="remote"
if [[ "${1:-}" == "--local" || "${1:-}" == "-l" ]]; then
    MODE="local"
fi

if [[ "$MODE" == "local" ]]; then
    python3 - <<PY
import glob, json, sys

blobs = glob.glob("$ROOT_DIR/.wrangler/state/v3/r2/**/blobs/*", recursive=True)
latest_data = None

for path in blobs:
    try:
        with open(path, "rb") as fp:
            parsed = json.loads(fp.read().decode("utf-8"))
            if isinstance(parsed, dict) and ("emails" in parsed or "votes" in parsed):
                latest_data = parsed
    except Exception:
        pass

if not latest_data:
    print("==========================================")
    print("  📱 Wick iOS 愿望清单 (本地测试环境)")
    print("==========================================")
    print("（本地暂无测试登记记录）")
    print("==========================================")
    sys.exit(0)

votes = latest_data.get("votes", 0)
emails = latest_data.get("emails", [])
total = votes + len(emails)
print("==========================================")
print("  📱 Wick iOS 愿望清单 (本地测试环境)")
print("==========================================")
print(f"• 需求总人数:    {total} 位")
print(f"• 匿名 +1 投票:  {votes} 票")
print(f"• 邮箱订阅人数:  {len(emails)} 位")
print(f"• 最后更新时间:  {latest_data.get('updatedAt', 'N/A')}")
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
PY
    exit 0
fi

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

R2_BUCKET="${R2_BUCKET:-application-releases}"
OBJECT_KEY="wick/ios_wishlist.json"

HTTP_STATUS=$(curl -s -w "%{http_code}" -o "$TMP_FILE" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/r2/buckets/$R2_BUCKET/objects/$OBJECT_KEY")

if [[ "$HTTP_STATUS" -ne 200 ]]; then
    FETCHED=false
    if command -v wrangler >/dev/null 2>&1; then
        wrangler r2 object get "$R2_BUCKET/$OBJECT_KEY" --file="$TMP_FILE" --remote >/dev/null 2>&1 && FETCHED=true || true
    elif command -v npx >/dev/null 2>&1; then
        npx -y wrangler r2 object get "$R2_BUCKET/$OBJECT_KEY" --file="$TMP_FILE" --remote >/dev/null 2>&1 && FETCHED=true || true
    fi

    if [[ "$FETCHED" != "true" ]]; then
        echo "No remote wishlist data found (HTTP $HTTP_STATUS). Checking local state..."
        "$0" --local
        exit 0
    fi
fi


python3 - <<PY
import json
try:
    with open("$TMP_FILE") as f:
        data = json.load(f)
    votes = data.get("votes", 0)
    emails = data.get("emails", [])
    total = votes + len(emails)
    print("==========================================")
    print("  📱 Wick iOS 愿望清单 (线上正式环境)")
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
