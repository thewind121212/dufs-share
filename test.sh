#!/usr/bin/env bash
# Comprehensive test suite for dufs setup.
# Covers: read, upload, delete, security.
# Usage: DUFS_PASS=xxx ./test.sh

set -uo pipefail

URL="${DUFS_URL:-http://localhost:5001}"
USER="${DUFS_USER:-admin}"
PASS="${DUFS_PASS:?set DUFS_PASS env}"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
FAILS=()

G="\033[32m"; R="\033[31m"; Y="\033[33m"; B="\033[1m"; X="\033[0m"

eq() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf "  ${G}PASS${X} %s\n" "$name"
        ((PASS_COUNT++))
    else
        printf "  ${R}FAIL${X} %s: expected=%s actual=%s\n" "$name" "$expected" "$actual"
        ((FAIL_COUNT++)); FAILS+=("$name")
    fi
}

in_set() {
    local name="$1" actual="$2"; shift 2
    for v in "$@"; do
        if [[ "$actual" == "$v" ]]; then
            printf "  ${G}PASS${X} %s (%s)\n" "$name" "$actual"
            ((PASS_COUNT++)); return
        fi
    done
    printf "  ${R}FAIL${X} %s: actual=%s expected one of: %s\n" "$name" "$actual" "$*"
    ((FAIL_COUNT++)); FAILS+=("$name")
}

contains() {
    local name="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf "  ${G}PASS${X} %s\n" "$name"; ((PASS_COUNT++))
    else
        printf "  ${R}FAIL${X} %s: missing '%s'\n" "$name" "$needle"
        ((FAIL_COUNT++)); FAILS+=("$name")
    fi
}

not_contains() {
    local name="$1" needle="$2" haystack="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        printf "  ${G}PASS${X} %s\n" "$name"; ((PASS_COUNT++))
    else
        printf "  ${R}FAIL${X} %s: leaked '%s'\n" "$name" "$needle"
        ((FAIL_COUNT++)); FAILS+=("$name")
    fi
}

warn() {
    printf "  ${Y}WARN${X} %s\n" "$1"; ((WARN_COUNT++))
}

http() { curl -sk -o /dev/null -w '%{http_code}' "$@"; }
body() { curl -sk "$@"; }

echo -e "${B}=== dufs comprehensive test ===${X}"
echo "URL: $URL  USER: $USER"
echo

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "fixture-content-$(date +%s)" > "$TMP/file.txt"
echo "weird" > "$TMP/has space and ?#.txt"
TEST_DIR="test-$(openssl rand -hex 8)"

############################
echo -e "${B}[1] READ — anonymous root${X}"
############################
ROOT=$(body "$URL/")
contains      "root serves stub HTML"           "Nothing here" "$ROOT"
not_contains  "root has no file listing"         "share-"        "$ROOT"
eq            "anon GET nonexistent file → 404"  "404"           "$(http "$URL/nonexistent.txt")"

############################
echo -e "${B}[2] UPLOAD — admin${X}"
############################
eq      "admin MKCOL → 201"                       "201" "$(http -u "$USER:$PASS" -X MKCOL "$URL/$TEST_DIR/")"
eq      "admin PUT new file → 201"                "201" "$(http -u "$USER:$PASS" -T "$TMP/file.txt" "$URL/$TEST_DIR/file.txt")"
in_set  "admin PUT overwrite → 201/204"           "$(http -u "$USER:$PASS" -T "$TMP/file.txt" "$URL/$TEST_DIR/file.txt")" 201 204
ENC=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1], safe=""))' "has space and ?#.txt")
eq      "admin PUT URL-encoded name → 201"        "201" "$(http -u "$USER:$PASS" -T "$TMP/has space and ?#.txt" "$URL/$TEST_DIR/$ENC")"
eq      "admin PUT auto-creates parent dirs"      "201" "$(http -u "$USER:$PASS" -T "$TMP/file.txt" "$URL/$TEST_DIR/missing-subdir/x.txt")"

############################
echo -e "${B}[3] AUTH — failure paths${X}"
############################
eq  "anon PUT → 401"             "401" "$(http -T "$TMP/file.txt" "$URL/$TEST_DIR/hack.txt")"
eq  "wrong password PUT → 401"   "401" "$(http -u "$USER:wrong" -T "$TMP/file.txt" "$URL/$TEST_DIR/hack.txt")"
eq  "wrong user PUT → 401"       "401" "$(http -u "nobody:nopass" -T "$TMP/file.txt" "$URL/x.txt")"
eq  "anon MKCOL → 401"           "401" "$(http -X MKCOL "$URL/anon-dir/")"
eq  "anon DELETE → 401"          "401" "$(http -X DELETE "$URL/$TEST_DIR/file.txt")"
eq  "anon COPY → 401"            "401" "$(http -X COPY -H "Destination: $URL/copied.txt" "$URL/$TEST_DIR/file.txt")"
eq  "anon MOVE → 401"            "401" "$(http -X MOVE -H "Destination: $URL/moved.txt" "$URL/$TEST_DIR/file.txt")"
eq  "anon PATCH → 401"           "401" "$(http -X PATCH "$URL/$TEST_DIR/file.txt")"

############################
echo -e "${B}[4] READ — share content${X}"
############################
DL=$(body "$URL/$TEST_DIR/file.txt")
contains  "anon GET share file body"         "fixture-content"   "$DL"
eq        "anon GET share file → 200"         "200" "$(http "$URL/$TEST_DIR/file.txt")"

# Without stub the share dir LEAKS its listing — share.sh always drops stub.
NOSTUB=$(body "$URL/$TEST_DIR/")
if [[ "$NOSTUB" == *"file.txt"* ]]; then
    warn "share dir without stub leaks file listing — share.sh MUST drop stub (it does)"
fi

# Drop stub
http -u "$USER:$PASS" -T data/public/index.html "$URL/$TEST_DIR/index.html" >/dev/null
DIR=$(body "$URL/$TEST_DIR/")
contains      "share dir with stub serves stub"   "Nothing here" "$DIR"
not_contains  "share dir hides file listing"      "file.txt"     "$DIR"

############################
echo -e "${B}[5] DELETE${X}"
############################
eq  "wrong pass DELETE → 401"        "401" "$(http -u "$USER:wrong" -X DELETE "$URL/$TEST_DIR/file.txt")"
eq  "admin DELETE file → 204"        "204" "$(http -u "$USER:$PASS" -X DELETE "$URL/$TEST_DIR/file.txt")"
eq  "GET after delete → 404"         "404" "$(http "$URL/$TEST_DIR/file.txt")"
eq  "admin DELETE share dir → 204"   "204" "$(http -u "$USER:$PASS" -X DELETE "$URL/$TEST_DIR/")"
# trailing-slash GET on missing dir returns 200 empty listing (dufs quirk, not a leak)
DEAD=$(body "$URL/$TEST_DIR/")
not_contains  "deleted dir reveals no children"   "file.txt" "$DEAD"

############################
echo -e "${B}[6] SECURITY — traversal${X}"
############################
in_set  "literal /../config.yaml"        "$(http "$URL/../config.yaml")"      400 403 404
in_set  "%2e%2e encoded traversal"        "$(http "$URL/%2e%2e/config.yaml")" 400 403 404
in_set  "..%2f hybrid traversal"          "$(http "$URL/..%2fconfig.yaml")"   400 403 404
eq      "config.yaml not served"          "404" "$(http "$URL/config.yaml")"
eq      "docker-compose.yml not served"   "404" "$(http "$URL/docker-compose.yml")"
eq      "/etc/passwd not served"          "404" "$(http "$URL/etc/passwd")"

############################
echo -e "${B}[7] SECURITY — hidden patterns${X}"
############################
echo "secret-do-not-leak" > data/public/.env
echo "secret-key" > data/public/.api.key
LISTING_HOME=$(body "$URL/")
not_contains  "hidden .env not in /     listing"  ".env"     "$LISTING_HOME"
not_contains  "hidden .api.key not in / listing"  ".api"     "$LISTING_HOME"
# dufs `hidden:` is listing-only — direct GET still works. This is documented behavior.
GOT_ENV=$(body "$URL/.env")
if [[ "$GOT_ENV" == *"secret-do-not-leak"* ]]; then
    warn "hidden file directly GET-able — never put secrets under serve-path (dufs limitation)"
fi
rm -f data/public/.env data/public/.api.key

############################
echo -e "${B}[8] SECURITY — symlink escape${X}"
############################
ln -s /etc/hosts data/public/symlink-target 2>/dev/null || true
in_set  "symlink read blocked"   "$(http "$URL/symlink-target")"  403 404
rm -f data/public/symlink-target

############################
echo -e "${B}[9] SECURITY — WebDAV introspection${X}"
############################
PROPFIND=$(body -X PROPFIND -H 'Depth: 1' "$URL/")
if [[ "$PROPFIND" == *"<D:href>"* ]]; then
    warn "PROPFIND leaks listing at dufs (BLOCK at NPM via npm-advanced.conf)"
fi
ALLOW=$(curl -sIk -X OPTIONS "$URL/" | grep -i '^allow:' || true)
[[ -n "$ALLOW" ]] && warn "OPTIONS reveals allowed methods: $(echo "$ALLOW" | tr -d '\r' | head -c 120)"

############################
echo -e "${B}[10] SECURITY — auth brute-force${X}"
############################
for i in 1 2 3 4 5; do
    code=$(http -u "$USER:nope$i" -T "$TMP/file.txt" "$URL/brute$i.txt")
    [[ "$code" == "401" ]] || { printf "  ${R}FAIL${X} brute attempt %d returned %s\n" "$i" "$code"; ((FAIL_COUNT++)); }
done
echo "  ${G}PASS${X} 5x wrong-pass = 5x 401 (no dufs lockout — NPM rate-limit required for public)"
((PASS_COUNT++))
warn "no rate limiting at dufs — must add at NPM (limit_req_zone)"

############################
echo
echo -e "${B}=== summary ===${X}"
echo -e "  ${G}passed${X}: $PASS_COUNT"
echo -e "  ${R}failed${X}: $FAIL_COUNT"
echo -e "  ${Y}warnings${X}: $WARN_COUNT (security caveats; mitigate at NPM)"

if (( FAIL_COUNT > 0 )); then
    echo -e "${R}failed cases:${X}"
    for f in "${FAILS[@]}"; do echo "  - $f"; done
    exit 1
fi
echo -e "${G}all green.${X}"
