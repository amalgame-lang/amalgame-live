#!/bin/bash
# Push the built app to the server and (re)start the systemd service.
# Run this FROM the dev VM (where SSH to the server works).
#
#   ./deploy/push.sh [ssh-target]
#
# ssh-target defaults to root@212.227.28.96 — override with whatever
# host/alias/port your working SSH session uses, e.g.
#   ./deploy/push.sh root@demo.amalgame.me
#   ./deploy/push.sh myalias                 # from ~/.ssh/config
set -euo pipefail

TARGET="${1:-root@212.227.28.96}"
DEST="/var/mosaic/demo"
cd "$(dirname "$0")/.."

echo "→ building (mosaic build)"
mosaic build >/dev/null
echo "→ pushing to $TARGET:$DEST"
ssh "$TARGET" "mkdir -p $DEST"
scp server "$TARGET:$DEST/server"
scp -r public "$TARGET:$DEST/"
scp deploy/amalgame-live.service "$TARGET:/etc/systemd/system/amalgame-live.service"

echo "→ (re)starting service"
ssh "$TARGET" "systemctl daemon-reload && systemctl enable --now amalgame-live && systemctl restart amalgame-live && sleep 1 && systemctl --no-pager status amalgame-live | head -6 && curl -s localhost:8080/api/state | head -c 120"

echo
echo "✓ app is up on :8080 — public via the host reverse proxy at https://demo.amalgame.me"
