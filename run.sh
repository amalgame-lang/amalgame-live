#!/bin/bash
# Local rehearsal: build then run on http://localhost:8080
# (open / for the projector view, /join for a phone).
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
export PORT="${PORT:-8080}"
export STATE_FILE="${STATE_FILE:-/tmp/amalgame-live-state.json}"
echo
echo "▶ open  http://localhost:$PORT/        (projector)"
echo "▶ open  http://localhost:$PORT/join    (phone)"
echo
exec ./server
