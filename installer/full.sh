#!/usr/bin/env bash
#
# install.sh — installer for victoria-mangowm-dotfiles
# Repo: https://github.com/kohagizpk/victoria-mangowm-dotfiles
#
# Installs the MangoWM compositor plus the full desktop stack (Waybar, kitty,
# fish, rofi, fuzzel, wlogout, swayosd, swaync, GTK theming, portals, etc.),
# deploys this repo's dotfiles, and patches the handful of things that don't
# work out of the box on a fresh machine. Every patch it makes is logged and
# printed in the summary at the end.
#
# Internal full installation flow, called by the repository entry point.

set -Eeuo pipefail

REPO_URL="https://github.com/kohagizpk/victoria-mangowm-dotfiles.git"
CONFIG_DIR="$HOME/.config/mango"

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help)
            echo "Usage: $0 [--dry-run]"
            echo "  --dry-run   Show a read-only installation plan (no system changes)."
            exit 0
            ;;
        *) printf "Unknown option: %s\n" "$arg" >&2; exit 2 ;;
    esac
done

# Deliberately separate the read-only plan from the execution path. Wrapping
# individual commands cannot protect shell redirections or nested installers.
if [[ "$DRY_RUN" -eq 1 ]]; then
    cat <<'PLAN'
Victoria installation plan (read-only; no commands are executed)
Primary targets: Arch Linux, Artix and CachyOS; Fedora/NixOS experimental.
1. Detect distribution/init and ask for keyboard layout.
2. Ask separately about Discord, Spotify and their automatic startup.
3. Choose Helium, Firefox, Brave or no browser; optionally start it at login.
4. Back up existing desktop configuration before deploying any files.
5. Upgrade Arch-family packages with pacman -Syu, then install dependencies.
6. Configure Ly; ask before hiding any other login sessions.
7. Deploy Mango, detect connected monitors, configure wallpaper hooks and app bindings.
8. Apply Materia-dark-compact (GTK) and MateriaDark via Kvantum (Qt 5/6).
9. Offer GRUB theme, fish default shell and brightness permissions.
10. Check installed commands and report missing components.
Run ./install.sh interactively to choose options and execute this plan.
PLAN
    exit 0
fi

# ---------- palette (catppuccin mocha, same accents as the waybar theme) ----------
c_reset='\033[0m'; c_bold='\033[1m'; c_dim='\033[2m'
c_mauve='\033[38;2;203;166;247m'; c_pink='\033[38;2;243;139;168m'
c_green='\033[38;2;166;227;161m'; c_yellow='\033[38;2;249;226;175m'
c_red='\033[38;2;243;139;168m';   c_blue='\033[38;2;137;180;250m'
c_sub='\033[38;2;108;112;134m'

STEP_NUM=0
WATERMARK_ACTIVE=0
WATERMARK_LINES=3

# Pins a compact version of the banner to the top of the terminal using a
# DECSTBM scroll region, so it stays put while everything else scrolls
# underneath it — like archinstall's persistent header. Degrades silently
# to plain output (no pinning) on anything that isn't a real, big-enough
# interactive terminal.
draw_watermark() {
    [[ "$WATERMARK_ACTIVE" -eq 1 ]] || return 0
    tput sc 2>/dev/null
    tput cup 0 0 2>/dev/null || { tput rc 2>/dev/null; return 0; }
    printf "${c_mauve}${c_bold}  VICTORIA${c_reset} ${c_sub}· mango window manager · victoria-mangowm-dotfiles${c_reset}"; tput el 2>/dev/null
    printf '\n'; tput el 2>/dev/null
    printf "${c_mauve}  ──────────────────────────────────────────────────────────────────${c_reset}"; tput el 2>/dev/null
    tput rc 2>/dev/null
}

setup_watermark() {
    [[ -t 1 && -t 0 ]] || return 0
    command -v tput >/dev/null 2>&1 || return 0
    local lines
    lines="$(tput lines 2>/dev/null)" || return 0
    [[ "$lines" =~ ^[0-9]+$ && "$lines" -gt $((WATERMARK_LINES + 10)) ]] || return 0
    printf '\033[%d;%dr' "$((WATERMARK_LINES + 1))" "$lines" 2>/dev/null || return 0
    tput cup "$WATERMARK_LINES" 0 2>/dev/null
    WATERMARK_ACTIVE=1
    draw_watermark
}

reset_watermark() {
    [[ "$WATERMARK_ACTIVE" -eq 1 ]] || return 0
    printf '\033[r'
    tput cup "$(tput lines 2>/dev/null || echo 24)" 0 2>/dev/null
    WATERMARK_ACTIVE=0
}

step()  { STEP_NUM=$((STEP_NUM + 1)); draw_watermark; printf "\n${c_mauve}❯${c_reset} ${c_sub}[%s]${c_reset} ${c_bold}%s${c_reset}\n" "$STEP_NUM" "$1"; }
info()  { printf "  ${c_sub}·${c_reset} %s\n" "$1"; }
ok()    { printf "  ${c_green}✓${c_reset} %s\n" "$1"; }
warn()  { printf "  ${c_yellow}!${c_reset} %s\n" "$1"; }
err()   { printf "  ${c_red}✗${c_reset} %s\n" "$1"; }

box() {
    local text="$1" color="${2:-$c_mauve}" len border
    len=${#text}
    border="$(printf '─%.0s' $(seq 1 $((len + 2))))"
    printf "${color}╭%s╮${c_reset}\n" "$border"
    printf "${color}│${c_reset} ${c_bold}%s${c_reset} ${color}│${c_reset}\n" "$text"
    printf "${color}╰%s╯${c_reset}\n" "$border"
}

banner() {
    local lines=(
'   :::     ::: ::::::::::: :::::::: ::::::::::: ::::::::  :::::::::  :::::::::::     :::  '
'  :+:     :+:     :+:    :+:    :+:    :+:    :+:    :+: :+:    :+:     :+:       :+: :+: '
' +:+     +:+     +:+    +:+           +:+    +:+    +:+ +:+    +:+     +:+      +:+   +:+ '
'+#+     +:+     +#+    +#+           +#+    +#+    +:+ +#++:++#:      +#+     +#++:++#++: '
'+#+   +#+      +#+    +#+           +#+    +#+    +#+ +#+    +#+     +#+     +#+     +#+  '
'#+#+#+#       #+#    #+#    #+#    #+#    #+#    #+# #+#    #+#     #+#     #+#     #+#   '
' ###     ########### ########     ###     ########  ###    ### ########### ###     ###    '
    )
    local n=${#lines[@]}
    # gradient: mauve (#cba6f7) -> pink (#f38ba8), matching the waybar accent colors
    local r1=203 g1=166 b1=247 r2=243 g2=139 b2=168
    local i r g b
    echo
    for i in "${!lines[@]}"; do
        r=$(( r1 + (r2 - r1) * i / (n - 1) ))
        g=$(( g1 + (g2 - g1) * i / (n - 1) ))
        b=$(( b1 + (b2 - b1) * i / (n - 1) ))
        printf "\033[1m\033[38;2;%d;%d;%dm%s\033[0m\n" "$r" "$g" "$b" "${lines[$i]}"
    done
    printf "\n${c_sub}  mango window manager · victoria-mangowm-dotfiles installer${c_reset}\n\n"
}

confirm() {
    local reply
    read -rp "$(printf "${c_mauve}?${c_reset} %s " "$1")[y/N] " reply || return 1
    [[ "$reply" =~ ^[yY]$ ]]
}

# Runs a command for real, or — in --dry-run — just prints it and returns
# success so the rest of the script's if/else logic still flows naturally.
run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf "  ${c_dim}would run:${c_reset} %s\n" "$*"
        return 0
    fi
    "$@"
}

# Same idea for anything that writes/edits a file. Use write_to/sudo_write_to
# in place of `cat >`/`sudo tee` in front of a heredoc — in --dry-run it just
# announces the write and discards the content instead of touching the file.
write_to() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf "  ${c_dim}would write:${c_reset} %s\n" "$1"
        cat >/dev/null
    else
        cat > "$1"
    fi
}
write_to_append() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf "  ${c_dim}would append to:${c_reset} %s\n" "$1"
        cat >/dev/null
    else
        cat >> "$1"
    fi
}
sudo_write_to() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf "  ${c_dim}would write (as root):${c_reset} %s\n" "$1"
        cat >/dev/null
    else
        sudo tee "$1" >/dev/null
    fi
}
sudo_write_to_append() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf "  ${c_dim}would append to (as root):${c_reset} %s\n" "$1"
        cat >/dev/null
    else
        sudo tee -a "$1" >/dev/null
    fi
}
# sed -i, wrapped the same way — announces the edit instead of making it.
run_sed() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf "  ${c_dim}would edit:${c_reset} %s\n" "${*: -1}"
        return 0
    fi
    sed "$@"
}

ADAPTATIONS=()
log_adapt() { ADAPTATIONS+=("$1"); }

on_error() {
    local line="$1"
    printf "\n${c_red}✗ Something went wrong at line %s.${c_reset}\n" "$line"
    printf "  ${c_sub}Scroll up to see the actual error message right above this.${c_reset}\n"
    printf "  ${c_sub}Review the error and configuration backups before running ./install.sh again;${c_reset}\n"
    printf "  ${c_sub}already-installed packages and already-applied fixes are skipped automatically.${c_reset}\n"
}
trap 'on_error $LINENO' ERR

SUDO_KEEPALIVE_PID=""
cleanup_on_exit() {
    [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
    reset_watermark
}
trap cleanup_on_exit EXIT

banner
setup_watermark

# Moves aside every session entry except mango.desktop, so display managers
# (ly) only ever list Mango. Reversible: nothing is deleted, just moved.
strip_other_sessions() {
    local sessions_backup="/etc/mango-removed-sessions-$(date +%Y%m%d%H%M%S)"
    local moved=0
    local dir f
    for dir in /usr/share/wayland-sessions /usr/share/xsessions; do
        [[ -d "$dir" ]] || continue
        for f in "$dir"/*.desktop; do
            [[ -f "$f" ]] || continue
            [[ "$(basename "$f")" == "mango.desktop" ]] && continue
            sudo mkdir -p "${sessions_backup}${dir}"
            sudo mv "$f" "${sessions_backup}${dir}/"
            moved=$((moved + 1))
        done
    done
    if [[ "$moved" -gt 0 ]]; then
        ok "Moved $moved other session entr(y/ies) out of the way (backed up in $sessions_backup)"
        log_adapt "Removed every login-screen session except Mango (dwl/river/GNOME/etc. were listed too) — moved, not deleted, to $sessions_backup"
    fi
}

# ---------- initial checks ----------
if [[ ! -t 0 ]]; then
    err "Run interactively in a terminal, or use --dry-run."
    exit 1
fi

if [[ "${EUID}" -eq 0 ]]; then
    err "Don't run this as root. Run it as your normal user (it will ask for sudo when needed)."
    exit 1
fi

if ! timeout 10 bash -c 'echo > /dev/tcp/github.com/443' 2>/dev/null; then
    err "Can't reach github.com — check your internet connection before running this (it downloads packages and dotfiles throughout)."
    exit 1
fi

# ---------- distro family ----------
# Package management, the AUR helper, the display manager service, and the
# GRUB theme are all handled very differently across these three families.
# Everything else (deploying and patching the dotfiles themselves) is plain
# file manipulation and works the same everywhere.
if [[ -f /etc/NIXOS || -n "${NIX_STORE:-}" ]] || command -v nixos-version >/dev/null 2>&1; then
    DISTRO_FAMILY="nixos"
elif command -v pacman >/dev/null 2>&1; then
    DISTRO_FAMILY="arch"
elif command -v dnf >/dev/null 2>&1; then
    DISTRO_FAMILY="fedora"
else
    err "Unsupported distro: no pacman, dnf, or NixOS detected."
    err "This script supports Arch/Artix/CachyOS, Fedora, and NixOS."
    exit 1
fi
if [[ "$DISTRO_FAMILY" != arch ]]; then
    warn "Fedora and NixOS support is experimental; Arch, Artix and CachyOS are the primary targets."
    confirm "Continue with experimental support?" || exit 0
fi

# Application choices are stored separately from autostart commands.
INSTALL_DISCORD=0; INSTALL_SPOTIFY=0
START_DISCORD=0; START_SPOTIFY=0; START_BROWSER=0
confirm "Install Discord?" && INSTALL_DISCORD=1
confirm "Install Spotify (and Spicetify)?" && INSTALL_SPOTIFY=1
BROWSER_COMMAND=""; BROWSER_PACKAGE=""; BROWSER_DESKTOP=""
PS3="Default browser [1-4]: "
select browser in Helium Firefox Brave None; do
    case "$REPLY" in
        1) BROWSER_COMMAND=helium-browser; BROWSER_PACKAGE=helium-browser-bin; BROWSER_DESKTOP=helium.desktop; break ;;
        2) BROWSER_COMMAND=firefox; BROWSER_PACKAGE=firefox; BROWSER_DESKTOP=firefox.desktop; break ;;
        3) BROWSER_COMMAND=brave; BROWSER_PACKAGE=brave-bin; BROWSER_DESKTOP=brave-browser.desktop; break ;;
        4) break ;;
        *) warn "Choose 1, 2, 3 or 4." ;;
    esac
done
[[ -n "${browser:-}" ]] || { err "Browser selection cancelled."; exit 1; }
if [[ "$INSTALL_DISCORD" -eq 1 ]] && confirm "Open Discord automatically at login?"; then START_DISCORD=1; fi
if [[ "$INSTALL_SPOTIFY" -eq 1 ]] && confirm "Open Spotify automatically at login?"; then START_SPOTIFY=1; fi
if [[ -n "$BROWSER_COMMAND" ]] && confirm "Open the browser automatically at login?"; then START_BROWSER=1; fi

# Back up every user configuration tree this installer can modify, including
# an in-place checkout. A failed copy stops installation before deployment.
BACKUP_DIR="$(mktemp -d "$HOME/victoria-backup.XXXXXXXX")"
for relative in .config/mango .config/wlogout .config/xdg-desktop-portal \
    .config/wallust .config/waypaper .config/gtk-3.0 .config/gtk-4.0 \
    .config/fastfetch .config/fish .config/kitty .config/Kvantum \
    .config/environment.d .config/mimeapps.list .local/share/applications/mimeapps.list \
    .local/share/icons .gtkrc-2.0 mango-nixos-snippet.nix; do
    if [[ -e "$HOME/$relative" || -L "$HOME/$relative" ]]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$relative")"
        cp -a "$HOME/$relative" "$BACKUP_DIR/$relative"
    fi
done
if [[ -d "${XDG_STATE_HOME:-$HOME/.local/state}/waypaper" ]]; then
    cp -a "${XDG_STATE_HOME:-$HOME/.local/state}/waypaper" "$BACKUP_DIR/waypaper-state"
fi
info "Configuration backup: $BACKUP_DIR"

# ---------- where are the dotfiles: staged from the organized source checkout ----------
SOURCE_DIR="${VICTORIA_SOURCE_DIR:?Run install.sh from the repository root}"
IN_PLACE=0

# ---------- init system ----------
detect_init() {
    if [[ -d /run/systemd/system ]]; then
        echo systemd
    elif command -v dinitctl >/dev/null 2>&1 && [[ -d /etc/dinit.d ]]; then
        echo dinit
    elif [[ -d /run/openrc ]] || command -v rc-service >/dev/null 2>&1; then
        echo openrc
    else
        echo unknown
    fi
}

if [[ "$DISTRO_FAMILY" != "arch" ]]; then
    # Fedora and NixOS are always systemd-based in practice; skip the prompt.
    INIT_SYSTEM="systemd"
else
    INIT_SYSTEM="$(detect_init)"
    if [[ "$INIT_SYSTEM" == "unknown" ]]; then
        warn "Couldn't auto-detect your init system."
        echo "    1) systemd"
        echo "    2) OpenRC"
        echo "    3) dinit"
        reply=""
        while [[ "$reply" != "1" && "$reply" != "2" && "$reply" != "3" ]]; do
            read -rp "Which one do you use? [1-3]: " reply
        done
        case "$reply" in
            1) INIT_SYSTEM="systemd" ;;
            2) INIT_SYSTEM="openrc" ;;
            3) INIT_SYSTEM="dinit" ;;
        esac
    fi
fi

# ---------- keyboard layout (asked here, applied later once config.conf exists) ----------
echo
echo "    1) us       — US"
echo "    2) br       — Brazil (ABNT2)"
echo "    3) us-intl  — US international (dead keys)"
echo "    4) de       — Germany"
echo "    5) fr       — France"
echo "    6) es       — Spain"
echo "    7) gb       — UK"
echo "    8) it       — Italy"
echo "    9) pt       — Portugal"
echo "    10) other (type the code yourself)"
kb_reply=""
while [[ ! "$kb_reply" =~ ^([1-9]|10)$ ]]; do
    read -rp "Keyboard layout [1-10]: " kb_reply
done
KB_VARIANT=""
case "$kb_reply" in
    1)  KB_LAYOUT="us"; KB_CONSOLE="us" ;;
    2)  KB_LAYOUT="br"; KB_CONSOLE="br-abnt2" ;;
    3)  KB_LAYOUT="us"; KB_VARIANT="intl"; KB_CONSOLE="us-acentos" ;;
    4)  KB_LAYOUT="de"; KB_CONSOLE="de" ;;
    5)  KB_LAYOUT="fr"; KB_CONSOLE="fr" ;;
    6)  KB_LAYOUT="es"; KB_CONSOLE="es" ;;
    7)  KB_LAYOUT="gb"; KB_CONSOLE="uk" ;;   # XKB calls it "gb", the console keymap is named "uk"
    8)  KB_LAYOUT="it"; KB_CONSOLE="it" ;;
    9)  KB_LAYOUT="pt"; KB_CONSOLE="pt-latin1" ;;
    10)
        read -rp "XKB layout code for config.conf (e.g. us, br, de — NOT 'br(intl)', see next question): " KB_LAYOUT
        read -rp "Variant, if any (e.g. intl, nodeadkeys — leave empty for none): " KB_VARIANT
        read -rp "Matching console keymap (e.g. us, br-abnt2 — leave empty to skip): " KB_CONSOLE
        ;;
esac

if [[ ! "$KB_LAYOUT" =~ ^[a-zA-Z0-9_-]+$ || ! "$KB_VARIANT" =~ ^[a-zA-Z0-9_-]*$ || ! "$KB_CONSOLE" =~ ^[a-zA-Z0-9_-]*$ ]]; then
    err "Invalid keyboard code; use letters, digits, underscores or hyphens."
    exit 1
fi

# ---------- summary, archinstall-style: every choice made, before anything runs ----------
box "victoria-mangowm-dotfiles installer"
info "Source:          $SOURCE_DIR"
info "Target:          $CONFIG_DIR"
info "Distro family:   $DISTRO_FAMILY"
info "Init system:     $INIT_SYSTEM"
info "Keyboard layout: ${KB_LAYOUT}${KB_VARIANT:+ ($KB_VARIANT)}"
[[ "$DRY_RUN" -eq 1 ]] && info "Mode:            dry run — nothing will actually be installed or changed"
if ! confirm "Everything above look right? Start?"; then
    exit 0
fi

# Ask for the sudo password once up front instead of ~20 separate times
# throughout the script. sudo caches it for a while (usually 15 min); a
# background loop keeps it refreshed for the rest of the run.
if [[ "$DRY_RUN" -eq 0 ]]; then
    info "This needs sudo for package installs and a few system files — asking once now."
    sudo -v
    SYSTEM_BACKUP="/var/backups/victoria-$(date +%Y%m%d-%H%M%S)-$$"
    sudo mkdir -p "$SYSTEM_BACKUP"
    for file in /etc/pacman.conf /etc/dinit.d/config/console.conf /etc/vconsole.conf /usr/share/wayland-sessions/mango.desktop; do
        if [[ -f "$file" ]]; then sudo cp --parents -a "$file" "$SYSTEM_BACKUP/"; fi
    done
    info "System configuration backup: $SYSTEM_BACKUP"
    if sudo -n true 2>/dev/null; then
        ( while true; do sleep 30; sudo -n true 2>/dev/null || exit; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
        SUDO_KEEPALIVE_PID=$!
    else
        warn "sudo isn't caching credentials on this system (some hardened setups disable that) — you'll be asked for your password a few more times as the script runs. That's normal, not a hang."
    fi
fi

if [[ "$DISTRO_FAMILY" == "arch" ]]; then
    step "Upgrading system packages (avoids partial upgrades)"
    sudo pacman -Syu
fi

source "$VICTORIA_PROJECT_ROOT/installer/packages.sh"

source "$VICTORIA_PROJECT_ROOT/installer/desktop.sh"
