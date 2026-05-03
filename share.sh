#!/usr/bin/env bash
# Usage: DUFS_PASS=xxx ./share.sh <local-file>
# Or set DUFS_PASS / DUFS_USER / DUFS_URL in .env and source it.
set -euo pipefail

# auto-load .env if present
if [[ -f "$(dirname "$0")/.env" ]]; then
    set -a; source "$(dirname "$0")/.env"; set +a
fi

DUFS_URL="${DUFS_URL:-http://localhost:${PUBLIC_PORT:-5001}}"
DUFS_USER="${DUFS_USER:-${ADMIN_USER:-admin}}"
DUFS_PASS="${DUFS_PASS:-${ADMIN_PASS:-}}"
[[ -z "$DUFS_PASS" ]] && { echo "set DUFS_PASS or ADMIN_PASS (env or .env)"; exit 1; }

STUB="$(dirname "$0")/data/public/index.html"
[[ ! -f "$STUB" ]] && { echo "stub missing — run ./setup.sh first"; exit 1; }

[[ $# -lt 1 ]] && { echo "usage: $0 <file>"; exit 1; }
FILE="$1"
[[ ! -f "$FILE" ]] && { echo "no file: $FILE"; exit 1; }

NAME="$(basename "$FILE")"
[[ "$NAME" == "." || "$NAME" == ".." || -z "$NAME" ]] && { echo "bad name"; exit 1; }
ENC_NAME="$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1], safe=""))' "$NAME")"

DIR="share-$(openssl rand -hex 16)"

curl -fsS -u "$DUFS_USER:$DUFS_PASS" -X MKCOL "$DUFS_URL/$DIR/" >/dev/null
curl -fsS -u "$DUFS_USER:$DUFS_PASS" -T "$STUB" "$DUFS_URL/$DIR/index.html" >/dev/null
curl -fsS -u "$DUFS_USER:$DUFS_PASS" -T "$FILE" "$DUFS_URL/$DIR/$ENC_NAME" >/dev/null

echo "$DUFS_URL/$DIR/$ENC_NAME"
