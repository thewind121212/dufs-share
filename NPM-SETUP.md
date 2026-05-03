# NPM setup

## Files

| File                     | Where it goes                                       | Why                                    |
|--------------------------|-----------------------------------------------------|----------------------------------------|
| `npm-http-custom.conf`   | NPM container: `/data/nginx/custom/http_top.conf`   | http-context: zones, maps, CORS rules  |
| `npm-advanced.conf`      | NPM dashboard: Proxy Host → Advanced tab            | location-context: headers, limits, CORS |

## Install

```bash
NPM_CONTAINER="$(docker ps --filter ancestor=jc21/nginx-proxy-manager --format '{{.Names}}' | head -1)"

# 1. http-level config
docker cp npm-http-custom.conf "$NPM_CONTAINER":/data/nginx/custom/http_top.conf
docker exec "$NPM_CONTAINER" nginx -t && docker exec "$NPM_CONTAINER" nginx -s reload

# 2. NPM dashboard
#    Hosts → Add Proxy Host
#    Domain:  files.yourdomain.com
#    Forward: host.docker.internal  port 5001  (NEVER 5002)
#    SSL: Let's Encrypt + Force SSL + HSTS + HTTP/2
#    Advanced: paste npm-advanced.conf

# 3. Verify
./pentest.sh https://files.yourdomain.com
```

## Limits — what they mean

### Default user (untrusted)

| Limit                    | Value      | What it stops                              |
|--------------------------|------------|--------------------------------------------|
| Request rate             | 60 r/s     | scraper hammering URLs                     |
| Burst                    | 200        | one page load (HTML+CSS+JS+10 imgs) OK     |
| Concurrent connections   | 20 per IP  | someone opening 1000 sockets               |
| Bandwidth per connection | 5 MB/s     | one IP saturating uplink                   |
| First 2 MB               | unthrottled| small files (icons, thumbnails) full speed |

Effective max bandwidth per IP: 5 MB/s × 20 conn = 100 MB/s burst.

### Trusted user (Origin-whitelisted or IP-allowlisted)

| Limit                    | Value      |
|--------------------------|------------|
| Request rate             | 600 r/s    |
| Burst                    | 200        |
| Concurrent connections   | 100 per IP |
| Bandwidth per connection | 50 MB/s    |

Effective: 50 × 100 = 5 GB/s burst. Effectively unlimited for legit apps.

## Edit allowlists

Open `npm-http-custom.conf`, find `=== EDIT BELOW ===` blocks:

### CORS allowed origins
```nginx
map $http_origin $cors_origin {
    default                              "";
    "https://app.example.com"            $http_origin;   # add yours
}
```

### Trusted Origins (rate-limit bypass via Origin header)
```nginx
map $http_origin $rate_limit_zone {
    default                              "dufs_default";
    "https://app.example.com"            "dufs_trusted";
}
```

### Trusted IPs (stronger than Origin — server-side check)
```nginx
geo $rate_limit_skip {
    default                              0;
    203.0.113.0/24                       1;
    198.51.100.42                        1;
}
```

After any edit:
```bash
docker cp npm-http-custom.conf "$NPM_CONTAINER":/data/nginx/custom/http_top.conf
docker exec "$NPM_CONTAINER" nginx -t && docker exec "$NPM_CONTAINER" nginx -s reload
```

## Tune rate values

| Want                                    | Edit                                         |
|-----------------------------------------|----------------------------------------------|
| More aggressive rate limit              | `rate=60r/s` → `rate=20r/s`                  |
| Allow bigger page-load spikes           | `burst=200` → `burst=500`                    |
| Throttle bandwidth from byte 0          | remove `limit_rate_after 2m;`                |
| Per-IP bandwidth cap                    | `5m` → `1m` (default), `50m` → `100m` (trusted) |
| More concurrent conns                   | `default 20` → `default 50`                  |

## When to skip rate limit

- Cloudflare/CDN in front (CF handles DDoS)
- Personal-only use
- Tiny audience

To skip: comment out `limit_req` and `limit_conn` lines in `npm-advanced.conf`.

## Architecture

```
Internet
   │
   ▼
NPM (TLS, headers, CORS, rate+conn+bw limit, verb whitelist)
   │  only GET/HEAD/OPTIONS pass
   ▼
dufs:5001 (loopback) — public read, stub blocks listing
dufs:5002 (loopback) — admin UI (NEVER routed via NPM)
   │
   ▼
data/public/share-* — share dirs with stubs
```
