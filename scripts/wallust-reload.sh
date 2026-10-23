#!/usr/bin/env bash
# Waypaper post_command. Preference: HDMI-A-1, then another active output.
# --install IMAGE generates colors without contacting a running session.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/theme.py" apply "$@"
