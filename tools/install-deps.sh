#!/bin/bash
# Install every dependency pinned in amalgame.lock into the local amc
# package cache (~/.amalgame/packages). Run this once after cloning, on
# any machine where the deps aren't cached yet — otherwise amc can't
# resolve `WebApp`/`HttpResponse`/etc. and the build fails with
# "Unknown symbol".
#
#   ./tools/install-deps.sh        # then ./build.sh
#
# Needs network + git access to github.com/amalgame-lang/*.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f amalgame.lock ] || { echo "error: no amalgame.lock here"; exit 1; }

# Pull "<git-url>@<tag>" pairs straight from the lockfile. Order in the
# lock is dependency-first (web last), which is the right install order.
awk -F'"' '/git[[:space:]]*=/{g=$2} /tag[[:space:]]*=/{print g"@"$2}' amalgame.lock \
| while read -r spec; do
    echo "→ amc package add $spec"
    amc package add "$spec"
done

echo
echo "✓ deps installed — verify with: amc package check"
echo "  then build with:            ./build.sh"
