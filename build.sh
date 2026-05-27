#!/bin/bash
# amalgame-live/build.sh
#
# Builds ./server from the .am sources. Mirrors the pollen-manager
# workaround: `amc package add` only compiles each package's facade.am
# into its archive, missing the classes in `sources = [...]` siblings
# (WebApp/Static/Session for amalgame-web, etc.). So we rebuild the
# multi-source amalgame-web archive locally and link the rest from the
# package cache.
#
# Prereqs: amc on PATH + the packages already fetched into
#   ~/.amalgame/packages/github.com/amalgame-lang/  (amc package add ...).
#
# Delete the rebuild_pkg dance once `amc package add` handles
# multi-source packages.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

PKG_BASE="$HOME/.amalgame/packages/github.com/amalgame-lang"
AMC_RT="$HOME/.local/share/amalgame/runtime"
AMC_LIB="$HOME/.local/share/amalgame/lib/libamalgame.a"

mkdir -p build

# Gather -I dirs for every cached package (their headers cross-#include).
PKG_INCS=()
for d in "$PKG_BASE"/*/; do
    latest=$(ls -1 "$d" 2>/dev/null | sort -V | tail -1)
    [ -d "$d$latest/runtime" ] && PKG_INCS+=(-I"$d$latest/runtime")
done

# Rebuild the amalgame-web archive locally with ALL sources (the
# upstream archive only contains facade.am).
rebuild_pkg() {
    local pkg_name=$1 cls=$2 ; shift 2
    local pkg_dir
    pkg_dir=$(ls -d "$PKG_BASE/amalgame-${pkg_name}/"*/ | grep -v '_clone/$' | sort -V | tail -1)
    pkg_dir=${pkg_dir%/}
    local stem="build/${cls}-multi"
    echo "→ rebuilding amalgame-${pkg_name} archive (${cls}) from $(basename "$pkg_dir")"
    (cd "$pkg_dir" && amc --lib --quiet "$@" -o "$ROOT/$stem" >/dev/null)
    gcc -O2 -I"$AMC_RT" "${PKG_INCS[@]}" -I"$pkg_dir/runtime" \
        -c "$stem.c" -o "$stem.o"
    ar rcs "build/libamalgame-pkg-${cls}.a" "$stem.o"
}

# amalgame-web — all 14 sources.
#
# amc 0.8.55's resolver has a multi-source `--lib` bug: imports in
# facade.am don't propagate to sibling files (web_app.am etc.), so
# rebuilding the web archive from source currently fails. We ship a
# known-good prebuilt archive (vendor/, web v0.13.3, same amc) and
# reuse it. Set FORCE_REBUILD_WEB=1 to attempt the from-source path
# (needs the resolver bug fixed first).
WEB_ARCHIVE="build/libamalgame-pkg-Router.a"
if [ "${FORCE_REBUILD_WEB:-0}" = "1" ]; then
    rebuild_pkg web Router \
        facade.am session.am web_context.am security_headers.am \
        cors.am rate_limit.am csrf.am log_config.am \
        signed_cookie_session.am redis_session.am acme_config.am \
        tls_binding_config.am static.am web_app.am
elif [ -f "$WEB_ARCHIVE" ]; then
    echo "→ reusing existing $WEB_ARCHIVE"
else
    echo "→ using vendored amalgame-web archive (vendor/)"
    cp vendor/libamalgame-pkg-Router.a "$WEB_ARCHIVE"
fi

# Upstream facade-only archives for the single-class deps.
get_pkg_archive() {
    local pkg=$1 cls=$2 d
    d=$(ls -d "$PKG_BASE/amalgame-${pkg}/"*/ | grep -v '_clone/$' | sort -V | tail -1)
    d=${d%/}
    echo "$d/build/linux-x86_64/libamalgame-pkg-${cls}.a"
}

echo "→ regenerating _routes.am"
"$ROOT/tools/mosaic-routes.sh" app _routes.am

echo "→ amc server.am lib/store.am _routes.am → server.c"
amc --quiet server.am lib/store.am _routes.am -o server >/dev/null

echo "→ link"
gcc -O2 -I"$AMC_RT" "${PKG_INCS[@]}" \
    -Wno-int-conversion -Wno-incompatible-pointer-types \
    server.c \
    -Wl,--start-group \
    build/libamalgame-pkg-Router.a \
    "$(get_pkg_archive crypto Sha256)" \
    "$(get_pkg_archive tls TlsConfig)" \
    "$(get_pkg_archive async Async)" \
    "$(get_pkg_archive net-http HttpRequest)" \
    "$(get_pkg_archive datetime DateTime)" \
    "$(get_pkg_archive random Random)" \
    "$(get_pkg_archive logging Log)" \
    "$(get_pkg_archive database-nosql-redis Redis)" \
    "$(get_pkg_archive threading Threading)" \
    "$AMC_LIB" \
    -Wl,--end-group \
    -lgc -lm -lz -lcrypto -lssl -lnghttp2 -lpthread \
    -o server

echo "✓ Built ./server"
