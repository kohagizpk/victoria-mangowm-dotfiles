#!/usr/bin/env bash
# Waypaper passes the selected image; persist it for the next login.
# --install IMAGE generates colors without contacting a running session.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/theme.py" apply "$@"
