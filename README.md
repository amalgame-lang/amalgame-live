# Amalgame Live

A real-time audience-participation board, written in **Amalgame** and built with
**Mosaic** — the CLI/build tool for the pure-Amalgame web stack. Compiled to a
single native binary.

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
| `server.am` | entry point — builds the `WebApp` + the data model (`LiveState`, `PollOption`, `Reaction`) and a tiny file-backed JSON `Store` |
| `app/index.am` | `GET /` — the projector view |
| `app/join.am` | `GET /join` — the phone view |
| `app/api/state.am` | `GET /api/state` — the whole board as JSON (polled once a second) |
| `app/api/vote.am` | `POST /api/vote` — `{"i": <option>}` |
| `app/api/react.am` | `POST /api/react` — `{"emoji": "🔥", "text": "…"}` |
| `app/api/reset.am` | `POST /api/reset` — presenter wipe (gated by `RESET_KEY`) |
| `public/` | `style.css` + `app.js` (vanilla, zero deps) — auto-served at `/` |

Routing is filesystem-based: Mosaic scans `app/` and generates `_routes.am` at
build time (Next.js style — `app/api/vote.am` → `POST /api/vote`), and
auto-serves `public/` at `/`.

## Run it locally — with Mosaic

First clone only: install the locked deps into the amc package cache, then build.

```bash
./tools/install-deps.sh        # once, populates ~/.amalgame/packages from amalgame.lock

mosaic dev                     # watch + rebuild + livereload on save
# ▶ http://localhost:8080/       projector
# ▶ http://localhost:8080/join   phone

# or a one-shot production build:
mosaic build && ./server
```

Needs the Mosaic CLI (`mosaic`) ≥ v0.6 on PATH — see
https://github.com/amalgame-lang/mosaic.

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

- **URL:** https://demo.amalgame.me  (`/` projector, `/join` phones)
- **Host:** Debian 12, runs as the `amalgame-live` systemd service from
  `/var/mosaic/demo` (enabled at boot, `Restart=on-failure`), listening on
  plain HTTP `127.0.0.1:8080`.
- **TLS / public URL:** the host's existing greenlock-express + Node server owns
  ports 80/443 and auto-issues Let's Encrypt certs. `demo.amalgame.me` was added
  to its `greenlock.d/config.json` sites list, and a one-line `req.hostname`
  passthrough in its `app.js` reverse-proxies `demo.amalgame.me` → `127.0.0.1:8080`.
  So the demo gets a real cert and a clean URL with no extra port and no Caddy.
- **Runtime dep:** `libgc1` (Boehm GC) — `apt-get install -y libgc1`.
- **Firewall:** the IONOS cloud firewall only opens 80/443/55 by default
  (8080/8443 were opened too, but the public path is 443 via the proxy).
- **QR:** generated server-side with `qrencode` into `public/qr.png` for
  `https://demo.amalgame.me/join` — no external service, no mixed content.
- **Reset key:** `RESET_KEY` is set via a systemd drop-in
  (`/etc/systemd/system/amalgame-live.service.d/override.conf`), so `/api/reset`
  needs `{"key":"…"}`.

### HTTPS — note

The Amalgame web stack can't terminate TLS itself yet in a way the Mosaic router
can use (`amalgame-net-http` v0.9.6's `Https.Serve` is HTTP/2-only and not wired
to the HTTP/1.1 `WebApp` handler). Standard Let's Encrypt (HTTP-01/TLS-ALPN) was
also blocked here because 80/443 are held by the host's Node server. The pragmatic
fix was to front the app with that existing reverse proxy. Native TLS termination
in `amalgame-web` is the proper long-term fix.

## Build notes

Built with **Mosaic** (`mosaic build` / `mosaic dev`) ≥ v0.6 — it regenerates
`_routes.am` from `app/`, drives `amc` + `gcc`, and links the package archives
from the amc cache (resolved via `amalgame.lock`). The data model lives in
`server.am` (not a separate file) so it's compiled together with the generated
routes. Needs the dependencies present in the cache first — run
`./tools/install-deps.sh` on a fresh clone.
