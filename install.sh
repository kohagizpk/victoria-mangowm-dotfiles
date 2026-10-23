#!/usr/bin/env bash
# Entry point; run from a complete checkout outside ~/.config/mango.
set -Eeuo pipefail
mode=full
dry_run=0
for arg in "$@"; do
    case "$arg" in
        --config-only) mode=config ;;
        --diagnose) mode=doctor ;;
        --dry-run) dry_run=1 ;;
        -h|--help)
            printf '%s\n' 'Usage: ./install.sh [--config-only | --diagnose] [--dry-run]' \
                '  --config-only  Back up and deploy user dotfiles; no packages, sudo or services.' \
                '  --diagnose     Read-only dependency and configuration checks.' \
                '  --dry-run      Print the selected plan without changing files.'
            exit 0 ;;
        *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
    esac
done
VICTORIA_PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export VICTORIA_PROJECT_ROOT
if ((dry_run)); then
    if [[ $mode == full ]]; then
        exec bash "$VICTORIA_PROJECT_ROOT/installer/full.sh" --dry-run
    fi
    printf 'Read-only plan (%s): no files or system settings will change.\n' "$mode"
    [[ $mode != config ]] || printf '%s\n' 'Back up user configurations; deploy managed files; preserve local overrides; configure Wallust hooks and render if available.'
    exit 0
fi
command -v python3 >/dev/null || { echo 'Python 3.11+ is required.' >&2; exit 1; }
if [[ $mode == doctor ]]; then
    exec python3 "$VICTORIA_PROJECT_ROOT/scripts/doctor.py"
elif [[ $mode == config ]]; then
    exec python3 "$VICTORIA_PROJECT_ROOT/installer/deploy.py" install
fi
# Stage before full installation so only runtime assets enter ~/.config/mango.
VICTORIA_SOURCE_DIR="$(mktemp -d)"
export VICTORIA_SOURCE_DIR
trap 'rm -rf -- "$VICTORIA_SOURCE_DIR"' EXIT
python3 "$VICTORIA_PROJECT_ROOT/installer/deploy.py" stage "$VICTORIA_SOURCE_DIR"
bash "$VICTORIA_PROJECT_ROOT/installer/full.sh"
