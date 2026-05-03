# dufs-share

Self-hosted public file sharing on top of [dufs](https://github.com/sigoden/dufs), behind Nginx Proxy Manager. Public read via random unguessable share URLs; admin upload via separate loopback-only UI; WebDAV verb whitelist + CORS + rate limit at the proxy.

## Architecture

```
                Internet
                    │
                    ▼
              NPM (TLS, CORS, rate limit, verb whitelist)
                    │  GET / HEAD / OPTIONS only
                    ▼
            dufs:5001 (loopback) — public read, stub blocks listing
            dufs:5002 (loopback) — admin UI (NEVER routed via NPM)
                    │
                    ▼
              data/public/share-<random>/
```

## Quick start

```bash
git clone https://github.com/thewind121212/dufs-share.git
cd dufs-share

# 1. fill in env
cp .env.example .env
chmod 600 .env

#    generate password hash
openssl passwd -6 'your-strong-password'    # paste into ADMIN_PASS_HASH
#    set ADMIN_PASS to the same plaintext (used by share.sh)
#    set HOST_UID / HOST_GID — run `id -u` and `id -g`

# 2. render configs from templates
./setup.sh

# 3. start
docker compose up -d
docker compose logs -f
```

## Use

```bash
# upload a file → public URL printed
DUFS_PASS=$(grep ^ADMIN_PASS= .env | cut -d= -f2-) ./share.sh ~/photo.png
# → http://localhost:5001/share-<random32hex>/photo.png

# admin browser UI (auth required, loopback only)
open http://localhost:5002
```

## Public exposure (NPM)

See `NPM-SETUP.md`. Two files install:

```bash
NPM=$(docker ps --filter ancestor=jc21/nginx-proxy-manager --format '{{.Names}}' | head -1)
docker cp npm-http-custom.conf "$NPM":/data/nginx/custom/http_top.conf
docker exec "$NPM" nginx -t && docker exec "$NPM" nginx -s reload
```

Then in NPM dashboard add Proxy Host pointing at `127.0.0.1:5001` (or `host.docker.internal:5001`), and paste `npm-advanced.conf` into the Advanced tab.

**Never** expose port 5002 publicly — that's the admin UI.

## Tests

```bash
DUFS_PASS=... ./test.sh        # 35 functional tests
./pentest.sh                   # 65 adversarial attacks against :5001
./pentest.sh https://files.yourdomain.com   # after public, must show 0 vuln 0 warn
```

## Files

| File                          | Purpose                                              |
|-------------------------------|------------------------------------------------------|
| `docker-compose.yml`          | 2 dufs containers (public + admin loopback)          |
| `.env.example`                | Template for `.env` (gitignored)                     |
| `config.example.yaml`         | Public dufs template                                 |
| `config-admin.example.yaml`   | Admin dufs template                                  |
| `setup.sh`                    | Renders configs from templates + .env                |
| `share.sh`                    | CLI uploader (env-based auth, URL-encode, 128-bit)   |
| `test.sh`                     | Functional test suite (35 cases)                     |
| `pentest.sh`                  | Adversarial pentest (65 attacks, no creds)           |
| `npm-http-custom.conf`        | NPM `http {}` config (zones, CORS, allowlists)       |
| `npm-advanced.conf`           | NPM Advanced-tab paste (verb gate, headers, limits)  |
| `NPM-SETUP.md`                | Detailed NPM install + tuning                        |

## Security model

- Public port (`:5001`) is anon-read-only; writes always 401.
- All listings hidden via stub `index.html` + `render-try-index: true`.
- Random share dirs have 128 bits entropy (`openssl rand -hex 16`).
- Admin port (`:5002`) bound to loopback only, requires HTTP Basic Auth.
- Containers run non-root, read-only rootfs, all caps dropped, no-new-privileges.
- WebDAV verbs (PROPFIND, COPY, MOVE, etc.) blocked at NPM verb whitelist.
- CORS via Origin allowlist (no wildcard).
- Rate limit: 60r/s default, 600r/s for trusted Origin/IP, plus per-IP connection + bandwidth caps.

See `pentest.sh` for the full attack matrix.

## License

MIT.
