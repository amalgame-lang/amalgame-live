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

See [deploy/DEPLOY.md](deploy/DEPLOY.md) — plain HTTP on `:8080` behind Caddy,
which terminates TLS on `:8443` with an automatic Let's Encrypt certificate for
`demo.amalgame.me`.

## Build notes

`build.sh` reuses a vendored, prebuilt `amalgame-web` archive
(`vendor/libamalgame-pkg-Router.a`) because amc 0.8.55's `--lib` resolver can't
yet rebuild that multi-source package from source. Set `FORCE_REBUILD_WEB=1`
once that's fixed. Everything else links straight from the package cache.
