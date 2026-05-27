# Amalgame Live

A real-time audience-participation board, written in **Amalgame** and served by
the pure-Amalgame **Mosaic** web stack — compiled to a single native binary.

The room scans a QR code, votes on a poll and fires emoji/messages from their
phones; the big screen updates live.

```
  phones ──▶ /join ──┐
                     ├──▶  ./server  (Amalgame, HTTP :8080)
  projector ◀── /  ──┘         │
                               └──▶ state.json  (file-backed shared state)
```

## Why it's a good demo

- **The language.** ~250 lines of Amalgame across a handful of small files —
  classes, `List<T>`, lambdas, string interpolation, JSON parsing. Readable
  enough to put on a slide.
- **The web stack is 100% Amalgame.** Routing, request/response, JSON, and
  static-file serving all come from `amalgame-web` + `amalgame-net-http`. No C
  framework underneath — it compiles *to* C.
- **It's live.** Real audience interaction beats any screenshot.

## Layout

| Path | What |
|------|------|
| `server.am` | entry point — reads `$PORT`, builds the `WebApp`, serves |
| `lib/store.am` | the data model (`LiveState`, `PollOption`, `Reaction`) + a tiny file-backed JSON store |
| `app/index.am` | `GET /` — the projector view |
| `app/join.am` | `GET /join` — the phone view |
| `app/api/state.am` | `GET /api/state` — the whole board as JSON (polled once a second) |
| `app/api/vote.am` | `POST /api/vote` — `{"i": <option>}` |
| `app/api/react.am` | `POST /api/react` — `{"emoji": "🔥", "text": "…"}` |
| `app/api/reset.am` | `POST /api/reset` — presenter wipe (gated by `RESET_KEY`) |
| `public/` | `style.css` + `app.js` (vanilla, zero deps) — auto-served at `/` |

Routing is filesystem-based: `tools/mosaic-routes.sh` scans `app/` and generates
`_routes.am` at build time (Next.js style — `app/api/vote.am` → `POST /api/vote`).

## Run it locally

```bash
./run.sh
# ▶ http://localhost:8080/       projector
# ▶ http://localhost:8080/join   phone
```

## Configuration (env vars)

| Var | Default | Meaning |
|-----|---------|---------|
| `PORT` | `8080` | HTTP listen port |
| `STATE_FILE` | `/tmp/amalgame-live-state.json` | where the board is persisted |
| `RESET_KEY` | *(empty)* | when set, `/api/reset` requires `{"key": "…"}` |

## Deploy

See [deploy/DEPLOY.md](deploy/DEPLOY.md) for the general recipe. The push script
builds, copies the binary + `public/` to the server, and (re)starts the systemd
service:

```bash
./deploy/push.sh neitsab@sites.neitsab.fr   # add `-p 55` via ~/.ssh/config
```

### Live deployment (as shipped)

- **URL:** http://demo.amalgame.me:8080  (`/` projector, `/join` phones)
- **Host:** Debian 12, runs as the `amalgame-live` systemd service from
  `/var/mosaic/demo` (enabled at boot, `Restart=on-failure`).
- **Runtime dep:** `libgc1` (Boehm GC) — `apt-get install -y libgc1`.
- **Firewall:** the IONOS cloud firewall must allow the chosen port(s);
  8080 is open. Ports 80/443 are taken by another service on this host.
- **QR:** generated server-side with `qrencode` into `public/qr.png` for the
  current join URL — no external service, no mixed content.
- **Reset key:** `RESET_KEY` is set via a systemd drop-in
  (`/etc/systemd/system/amalgame-live.service.d/override.conf`), so `/api/reset`
  needs `{"key":"…"}`.

### HTTPS

Not enabled. Standard Let's Encrypt (HTTP-01/TLS-ALPN) can't be used because
ports 80/443 are occupied by another service. Options: a DNS-01 cert on a TLS
listener at `:8443`, or fronting the app with the host's existing reverse proxy
on `:443`. Plain HTTP on `:8080` is what the demo ships with.

## Build notes

`build.sh` reuses a vendored, prebuilt `amalgame-web` archive
(`vendor/libamalgame-pkg-Router.a`) because amc 0.8.55's `--lib` resolver can't
yet rebuild that multi-source package from source. Set `FORCE_REBUILD_WEB=1`
once that's fixed. Everything else links straight from the package cache.
