#!/bin/bash
# ─────────────────────────────────────────────────────────────────
#  tools/mosaic-routes.sh — generate _routes.am from app/ tree
#
#  Scans the app/ directory for .am route files and emits a single
#  _routes.am module that:
#    1. Inlines every file's body (rewriting `class Page` to a
#       path-derived `<Prefix>_Page` to avoid collisions)
#    2. Generates a `class Routes` with `Register(Router r)` that
#       wires every file × HTTP verb on the router
#
#  Convention (Next.js-style):
#    app/index.am          → GET /
#    app/about.am          → GET /about
#    app/users/[id].am     → GET /users/:id
#    app/api/info.am       → GET /api/info  (+ POST/PUT/... if declared)
#    app/blog/[...slug].am → GET /blog/*slug
#
#  Each route file declares `public class Page` with one static
#  method per HTTP verb (GET/POST/PUT/PATCH/DELETE). No namespace
#  declaration needed — the generator puts everything into `App`.
#  Imports (`import Amalgame.Web`, etc.) are deduped automatically.
#
#  Example route file:
#
#    // app/users/[id].am
#    import Amalgame.Web
#
#    public class Page {
#        public static HttpResponse GET(WebContext ctx) {
#            return HttpResponse.New().Text("user " + ctx.Param("id"))
#        }
#    }
#
#  Usage:
#    tools/mosaic-routes.sh [app-dir] [out-file]
#
#  Defaults: app-dir=app, out-file=_routes.am
#
#  v0.6.0 — Static / `public/` pairing.
#  In addition to the `Routes.Register(Router r)` method (existing,
#  works against a bare Router), the generator now also emits
#  `Routes.Bind(WebApp app) → WebApp` for code using the v0.13.0+
#  amalgame-web `WebApp` orchestrator:
#
#      let app = WebApp.New()
#      Routes.Bind(app)
#      app.Serve(3000)
#
#  Bind:
#    - registers each route file via `app.<Verb>(path, handler)`
#      (typed wrapper around `app.Routes.Add(...)`, picks up the
#      pipeline middlewares if any are configured upstream).
#    - if a `public/` directory exists next to `app-dir` at
#      generation time (Next.js convention), adds
#      `app.WithStatic(Static.New("/", "./public"))` so
#      `/favicon.ico`, `/robots.txt`, `/assets/*.css` etc. are
#      served straight from disk with the v0.13.0 binary-safe
#      pipeline + strong ETag + 304 conditional GET.
#
#  Override the public-dir detection with `MOSAIC_PUBLIC=/path`.
#  Set `MOSAIC_PUBLIC=` (empty) to disable static auto-pairing.
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

APP_DIR="${1:-app}"
OUT_FILE="${2:-_routes.am}"

if [ ! -d "$APP_DIR" ]; then
    echo "error: app dir '$APP_DIR' not found" >&2
    exit 2
fi

# ── Public-dir auto-detection (v0.6.0) ───────────────────────────
#
# Convention: `public/` sibling of the app dir. Override via
# `MOSAIC_PUBLIC=`. Stored as a path RELATIVE to where `server.am`
# runs from, so it survives `cd` into a build subdir at runtime.
PUBLIC_DIR_LITERAL=""           # empty = no static mount emitted
if [ -n "${MOSAIC_PUBLIC+x}" ]; then
    # explicit env: empty disables, non-empty uses verbatim
    if [ -n "$MOSAIC_PUBLIC" ]; then
        PUBLIC_DIR_LITERAL="$MOSAIC_PUBLIC"
    fi
else
    # auto-detect: sibling of app-dir
    APP_PARENT="$(dirname "$APP_DIR")"
    if [ -d "$APP_PARENT/public" ]; then
        if [ "$APP_PARENT" = "." ]; then
            PUBLIC_DIR_LITERAL="./public"
        else
            PUBLIC_DIR_LITERAL="$APP_PARENT/public"
        fi
    fi
fi

# ── Path → (route segment, prefix segment) helpers ───────────────

title_case() {
    local s="$1"
    local first="${s:0:1}"
    local rest="${s:1}"
    printf '%s%s' "$(printf '%s' "$first" | tr '[:lower:]' '[:upper:]')" "$rest"
}

seg_to_route() {
    local s="$1"
    if [[ "$s" == \[...* ]]; then printf '*%s' "${s:4:-1}"
    elif [[ "$s" == \[*\] ]]; then printf ':%s' "${s:1:-1}"
    else printf '%s' "$s"; fi
}

seg_to_prefix() {
    local s="$1"
    if [[ "$s" == \[...* ]]; then title_case "${s:4:-1}"
    elif [[ "$s" == \[*\] ]]; then title_case "${s:1:-1}"
    else title_case "$s"; fi
}

path_to_route() {
    local rel="$1"
    rel="${rel%.am}"
    if [ "$rel" = "index" ]; then printf '/'; return; fi
    local out=""
    IFS='/' read -ra segs <<< "$rel"
    for s in "${segs[@]}"; do
        if [ "$s" = "index" ] && [ -n "$out" ]; then continue; fi
        out="$out/$(seg_to_route "$s")"
    done
    printf '%s' "$out"
}

path_to_prefix() {
    local rel="$1"
    rel="${rel%.am}"
    local out=""
    IFS='/' read -ra segs <<< "$rel"
    for s in "${segs[@]}"; do
        local p
        p="$(seg_to_prefix "$s")"
        if [ -z "$out" ]; then out="$p"
        else out="${out}_${p}"
        fi
    done
    printf '%s' "$out"
}

# ── Discover route files ─────────────────────────────────────────

mapfile -t FILES < <(cd "$APP_DIR" && find . -name '*.am' -type f | sed 's|^\./||' | sort)

if [ "${#FILES[@]}" -eq 0 ]; then
    echo "warning: no .am files in '$APP_DIR' — emitting empty router" >&2
fi

# ── Detect HTTP verbs ────────────────────────────────────────────

verbs_in_file() {
    local f="$1"
    local verbs=""
    for verb in GET POST PUT PATCH DELETE; do
        if grep -Eq "^[[:space:]]*public[[:space:]]+static[[:space:]]+HttpResponse[[:space:]]+${verb}[[:space:]]*\(" "$f"; then
            verbs="$verbs $verb"
        fi
    done
    printf '%s' "$verbs"
}

# ── Pass 1 — collect imports (deduped) ───────────────────────────

declare -A SEEN_IMPORTS
IMPORTS=()
for f in "${FILES[@]}"; do
    while IFS= read -r line; do
        if [ -z "${SEEN_IMPORTS[$line]:-}" ]; then
            SEEN_IMPORTS[$line]=1
            IMPORTS+=("$line")
        fi
    done < <(grep -E '^[[:space:]]*import[[:space:]]+' "$APP_DIR/$f" || true)
done

# ── Pass 2 — emit _routes.am ─────────────────────────────────────

{
    echo "// Generated by mosaic-routes.sh — DO NOT EDIT BY HAND"
    echo "// Source: $APP_DIR/"
    echo "// Regenerate: tools/mosaic-routes.sh $APP_DIR $OUT_FILE"
    echo ""
    echo "namespace App"
    echo ""
    # Ensure the framework imports are present even if no user file
    # mentions them.
    if [ -z "${SEEN_IMPORTS[import Amalgame.Collections]:-}" ]; then
        echo "import Amalgame.Collections"
    fi
    if [ -z "${SEEN_IMPORTS[import Amalgame.Web]:-}" ]; then
        echo "import Amalgame.Web"
    fi
    for imp in "${IMPORTS[@]}"; do
        echo "$imp"
    done
    echo ""

    # Inline each file's class body, renaming `class Page` →
    # `<Prefix>_Page`. Drop namespace + import lines (already
    # collected). The sed pattern also handles whitespace variants.
    for f in "${FILES[@]}"; do
        prefix=$(path_to_prefix "$f")
        full_path="$APP_DIR/$f"
        echo "// ── from $APP_DIR/$f (Page → ${prefix}_Page) ─────────────"
        sed -E \
            -e '/^[[:space:]]*namespace[[:space:]]/d' \
            -e '/^[[:space:]]*import[[:space:]]/d' \
            -e "s/(public[[:space:]]+class[[:space:]]+)Page([[:space:]]*\\{|[[:space:]]+|\$)/\\1${prefix}_Page\\2/" \
            "$full_path"
        echo ""
    done

    # Map an HTTP verb to its WebApp builder method.
    # WebApp exposes typed .Get / .Post / .Put / .Patch / .Delete
    # builders; we route through them so any pipeline middleware
    # (RateLimit, CSRF, etc.) gets exercised. Falls back to the
    # raw `.Routes.Add(verb, ...)` path for verbs WebApp doesn't
    # surface as a builder (none today, but future-proof).
    verb_to_webapp_method() {
        case "$1" in
            GET)    echo "Get" ;;
            POST)   echo "Post" ;;
            PUT)    echo "Put" ;;
            PATCH)  echo "Patch" ;;
            DELETE) echo "Delete" ;;
            *)      echo "" ;;
        esac
    }

    # Registration class.
    echo "public class Routes {"
    echo "    // Register every filesystem-mapped route on \`r\`."
    echo "    // Use this when wiring against a bare Router (legacy"
    echo "    // pre-WebApp pattern); Bind(WebApp) is the modern path."
    echo "    public static void Register(Router r) {"
    for f in "${FILES[@]}"; do
        route=$(path_to_route "$f")
        prefix=$(path_to_prefix "$f")
        full_path="$APP_DIR/$f"
        v=$(verbs_in_file "$full_path")
        if [ -z "$v" ]; then
            echo "        // $f → $route: no HTTP verb methods found — skipped"
            continue
        fi
        echo "        // $f → $route"
        for verb in $v; do
            echo "        r.Add(\"$verb\", \"$route\", ctx => ${prefix}_Page.${verb}(ctx))"
        done
    done
    echo "    }"
    echo ""
    # v0.6.0 — Bind to a WebApp (the modern, full-pipeline path).
    echo "    // v0.6.0 — Register routes + (if present) the public/"
    echo "    // static mount on a WebApp. Returns the same WebApp for"
    echo "    // fluent chaining: \`Routes.Bind(WebApp.New()).Serve(3000)\`."
    echo "    public static WebApp Bind(WebApp app) {"
    for f in "${FILES[@]}"; do
        route=$(path_to_route "$f")
        prefix=$(path_to_prefix "$f")
        full_path="$APP_DIR/$f"
        v=$(verbs_in_file "$full_path")
        if [ -z "$v" ]; then
            echo "        // $f → $route: no HTTP verb methods found — skipped"
            continue
        fi
        echo "        // $f → $route"
        for verb in $v; do
            wm=$(verb_to_webapp_method "$verb")
            if [ -n "$wm" ]; then
                echo "        app.${wm}(\"$route\", ctx => ${prefix}_Page.${verb}(ctx))"
            else
                echo "        app.Routes.Add(\"$verb\", \"$route\", ctx => ${prefix}_Page.${verb}(ctx))"
            fi
        done
    done
    if [ -n "$PUBLIC_DIR_LITERAL" ]; then
        echo ""
        echo "        // Static — auto-detected ${PUBLIC_DIR_LITERAL}/ at generation time"
        echo "        app.WithStatic(Static.New(\"/\", \"${PUBLIC_DIR_LITERAL}\"))"
    fi
    echo "        return app"
    echo "    }"
    echo "}"
} > "$OUT_FILE"

if [ -n "$PUBLIC_DIR_LITERAL" ]; then
    echo "✓ wrote $OUT_FILE ($(wc -l < "$OUT_FILE") lines, ${#FILES[@]} route files, static: ${PUBLIC_DIR_LITERAL})"
else
    echo "✓ wrote $OUT_FILE ($(wc -l < "$OUT_FILE") lines, ${#FILES[@]} route files, no public/)"
fi
