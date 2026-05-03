#!/usr/bin/env bash
# Generates config.yaml + config-admin.yaml from templates using .env values.
# Run once after cloning + filling .env.
set -euo pipefail

cd "$(dirname "$0")"

[[ ! -f .env ]] && { echo "no .env — copy .env.example to .env and edit"; exit 1; }

# shellcheck disable=SC1091
set -a; source .env; set +a

: "${ADMIN_USER:?missing in .env}"
: "${ADMIN_PASS_HASH:?missing in .env}"

[[ "$ADMIN_PASS_HASH" == '$6$REPLACE_WITH_OPENSSL_PASSWD_6_OUTPUT' ]] && {
    echo "ADMIN_PASS_HASH still placeholder. Generate with:"
    echo "  openssl passwd -6 'your-strong-password'"
    exit 1
}

[[ "$ADMIN_PASS_HASH" != \$6\$* ]] && {
    echo "ADMIN_PASS_HASH must start with \$6\$ (SHA-512 crypt). Got: ${ADMIN_PASS_HASH:0:6}..."
    exit 1
}

render() {
    local src="$1" dst="$2"
    sed -e "s|__ADMIN_USER__|${ADMIN_USER}|g" \
        -e "s|__ADMIN_HASH__|${ADMIN_PASS_HASH}|g" \
        "$src" > "$dst"
    chmod 600 "$dst"
    echo "  wrote $dst"
}

render config.example.yaml       config.yaml
render config-admin.example.yaml config-admin.yaml

mkdir -p data/public
[[ ! -f data/public/index.html ]] && cat > data/public/index.html <<'EOF'
<!doctype html>
<html><head><meta charset="utf-8"><title>404</title></head>
<body style="font-family:monospace;text-align:center;padding:4rem">
<h1>Nothing here</h1>
</body></html>
EOF
chmod 700 data data/public

echo
echo "ready. start with:"
echo "  docker compose up -d"
echo "  docker compose logs -f"
