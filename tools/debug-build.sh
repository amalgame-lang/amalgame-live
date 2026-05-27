#!/bin/bash
# Debug build for F5 / amc dap: same as `mosaic build`, but the final
# gcc link uses -O0 -g so the binary carries DWARF and amc's #line
# directives map breakpoints back to the .am source.
#
# Mosaic has no -g flag yet, so we let `mosaic build` resolve + print
# the exact link command, then re-run it with -O2 swapped for -O0 -g.
set -euo pipefail
cd "$(dirname "$0")/.."

# Capture the full output first — piping `mosaic build` straight into
# `grep -m1` makes grep close the pipe early, which SIGPIPEs mosaic and
# (under `pipefail`) aborts this script before the relink.
OUT=$(mosaic build 2>&1)
LINK=$(printf '%s\n' "$OUT" | grep -m1 '→ link: gcc' | sed 's/^→ link: //')
if [ -z "$LINK" ]; then
    printf '%s\n' "$OUT" | tail -20 >&2
    echo "error: couldn't capture the link line from 'mosaic build'" >&2
    exit 1
fi
DBG=${LINK/-O2/-O0 -g}
echo "→ debug relink (-O0 -g)"
eval "$DBG"
echo "✓ built ./server (debug)"
