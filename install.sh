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
# Usage: run it from inside a checkout of this repo (./install.sh), or drop
# it anywhere and it will clone the repo itself.

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
7. Deploy Mango, Waybar, wallpaper hooks and selected application bindings.
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

# ---------- where are the dotfiles, and where should they end up? ----------
# Three scenarios are supported:
#   1) The script is run from a checkout that already IS ~/.config/mango
#      (this is what the README recommends: clone the repo directly as
#      ~/.config/mango). Nothing needs to be copied.
#   2) The script is run from some other local checkout of the repo.
#      That checkout gets copied into ~/.config/mango (backing up anything
#      already there).
#   3) The script was grabbed on its own (e.g. curled) with no local
#      checkout at all. It clones the repo directly into ~/.config/mango.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IN_PLACE=0

if [[ "$SCRIPT_DIR" == "$CONFIG_DIR" ]]; then
    SOURCE_DIR="$SCRIPT_DIR"
    IN_PLACE=1
elif [[ -f "$SCRIPT_DIR/config.conf" && -f "$SCRIPT_DIR/autostart.sh" ]]; then
    SOURCE_DIR="$SCRIPT_DIR"
else
    step "No local checkout found next to this script"
    if [[ -d "$CONFIG_DIR" ]]; then
        if confirm "$CONFIG_DIR already exists. Back it up and clone fresh into it?"; then
            backup="$CONFIG_DIR.bak.$(date +%Y%m%d%H%M%S)"
            mv "$CONFIG_DIR" "$backup"
            ok "Backed up to $backup"
        else
            err "Can't continue without clearing $CONFIG_DIR. Aborting."
            exit 1
        fi
    fi
    git clone "$REPO_URL" "$CONFIG_DIR"
    SOURCE_DIR="$CONFIG_DIR"
    IN_PLACE=1
fi

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

# ---------- Arch's own repos, on Arch-based (non-Arch) distros ----------
# CachyOS, EndeavourOS etc. already ship Arch's [extra] repos, so this
# is a no-op there — this only ever actually does something on distros like
# Artix that deliberately don't include them by default.
if [[ "$DISTRO_FAMILY" == "arch" && "$(. /etc/os-release; printf '%s' "$ID")" == artix ]] && ! grep -qE '^\[extra\]' /etc/pacman.conf 2>/dev/null; then
    step "Arch's official repos"
    DISTRO_PRETTY="$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-your distro}")"
    info "$DISTRO_PRETTY doesn't have Arch's own [extra] repos enabled."
    info "Some AUR packages depend on things only published there (this is the standard artix-archlinux-support approach)."
    if confirm "Add them now, with a mirrorlist matched to your region?"; then
        sudo pacman -S --needed artix-archlinux-support
        sudo pacman-key --populate archlinux

        # Try to reuse whatever region your existing mirrors are already in,
        # by reading the "## CountryName" comment above them (the same
        # convention Arch's, Artix's, and reflector-generated mirrorlists
        # all use) — fall back to a quick IP geolocation lookup.
        REGION=""
        for ml in /etc/pacman.d/mirrorlist /etc/pacman.d/*mirrorlist*; do
            [[ -f "$ml" ]] || continue
            REGION="$(grep -m1 -oE '^## +[A-Za-z ]+$' "$ml" 2>/dev/null | sed 's/^## *//')"
            [[ -n "$REGION" ]] && break
        done
        if [[ -z "$REGION" ]]; then
            REGION="$(curl -fsSL --max-time 3 https://ipapi.co/country_name/ 2>/dev/null || true)"
        fi

        if command -v reflector >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm reflector 2>/dev/null; then
            if [[ -n "$REGION" ]]; then
                if sudo reflector --country "$REGION" --protocol https --latest 10 --sort rate --save /etc/pacman.d/mirrorlist-arch 2>/dev/null; then
                    ok "Arch mirrorlist generated for: $REGION"
                else
                    warn "No Arch mirrors found for '$REGION' specifically — grabbing the fastest ones worldwide instead."
                    sudo reflector --latest 15 --protocol https --sort rate --save /etc/pacman.d/mirrorlist-arch 2>/dev/null || true
                fi
            else
                sudo reflector --latest 15 --protocol https --sort rate --save /etc/pacman.d/mirrorlist-arch 2>/dev/null || true
                ok "Arch mirrorlist generated (fastest available; couldn't work out a region)"
            fi
        else
            warn "reflector isn't available — using the default mirrorlist-arch from artix-archlinux-support as-is (still works, just not latency-sorted)."
        fi

        if [[ -f /etc/pacman.d/mirrorlist-arch ]] && ! grep -q 'mirrorlist-arch' /etc/pacman.conf; then
            sudo tee -a /etc/pacman.conf >/dev/null <<'PACMANEOF'

[extra]
Include = /etc/pacman.d/mirrorlist-arch
PACMANEOF
            sudo pacman -Syu
            ok "Arch's [extra] repository added to /etc/pacman.conf"
            log_adapt "Added Arch's official [extra] repos as extra pacman sources (via artix-archlinux-support), with a mirrorlist matched to $([[ -n "$REGION" ]] && echo "$REGION" || echo "the fastest available mirrors") — some AUR/community packages depend on things only published there"
        else
            warn "Couldn't confirm mirrorlist-arch was created — skipping the pacman.conf edit. Packages needing Arch's repos may still fail; check https://wiki.artixlinux.org manually."
        fi
    fi
fi

# ---------- systemd-libs dummy (Artix) ----------
# AUR packages (built for vanilla Arch) commonly depend on systemd/systemd-libs.
# On Artix with libelogind this causes a file conflict; the official fix is to
# install artix-archlinux-support, which provides dummy systemd/systemd-libs.
if [[ "$DISTRO_FAMILY" == "arch" && "$(. /etc/os-release; printf '%s' "$ID")" == artix ]] && pacman -Si artix-archlinux-support >/dev/null 2>&1; then
    step "systemd-libs dummy (Artix)"
    sudo pacman -S --needed --noconfirm artix-archlinux-support
    ok "artix-archlinux-support installed"
    log_adapt "Installed artix-archlinux-support before anything else -> avoids the libelogind vs systemd-libs conflict when installing AUR packages built for vanilla Arch (mango, discord, etc.)"
fi

# ---------- AUR helper (Arch family only) ----------
if [[ "$DISTRO_FAMILY" == "arch" ]]; then
if command -v yay >/dev/null 2>&1; then
    AUR_HELPER="yay"
elif command -v paru >/dev/null 2>&1; then
    AUR_HELPER="paru"
else
    step "AUR helper"
    echo "    1) yay"
    echo "    2) paru"
    reply=""
    while [[ "$reply" != "1" && "$reply" != "2" ]]; do
        read -rp "Neither yay nor paru is installed. Which one do you want? [1-2]: " reply
    done
    case "$reply" in
        1) AUR_HELPER="yay" ;;
        2) AUR_HELPER="paru" ;;
    esac
    if confirm "Install $AUR_HELPER now? (needed for mango and other AUR packages)"; then
        sudo pacman -S --needed --noconfirm base-devel git
        TMP_AUR="$(mktemp -d)"
        git clone "https://aur.archlinux.org/${AUR_HELPER}.git" "$TMP_AUR/$AUR_HELPER"
        (cd "$TMP_AUR/$AUR_HELPER" && makepkg -si --noconfirm)
        rm -rf "$TMP_AUR"
    else
        err "Can't continue without an AUR helper. Aborting."
        exit 1
    fi
fi
ok "Using $AUR_HELPER"
fi

# ---------- packages: Arch family ----------
if [[ "$DISTRO_FAMILY" == "arch" ]]; then
PACKAGES=(
    # compositor
    mangowm-git

    # bar, launcher, menu, clipboard
    # waybar-git, not waybar: the native mango/workspaces + mango/window
    # modules are recent additions upstream, the stable release may not have
    # them yet
    waybar-git rofi fuzzel wmenu
    wl-clipboard cliphist wl-clip-persist

    # terminal, shell
    kitty foot fish fastfetch

    # file manager & misc GUI utilities
    nemo pavucontrol nwg-look

    # wallpaper (awww, formerly swww, is the actual backend waypaper/wallust
    # drive here — see scripts/wallust-reload.sh), multi-monitor
    awww waypaper

    # wallpaper-driven color scheme (wallust) + the two things it re-colors
    wallust cava python

    # Spotify theming (needs a one-time manual "spicetify backup apply"
    # after first login — see the summary at the end)

    # screenshots
    grim slurp

    # notifications, OSD, idle/lock, polkit
    # dunst is kept only for the dunstify binary (used by volume.sh); the
    # actual running notification daemon is swaync
    dunst swaync libnotify
    swayosd brightnessctl pamixer
    swaylock-effects swayidle
    xfce-polkit

    # session / logout, blue light filter
    wlogout wlsunset

    # portals (screen sharing, file picker)
    xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk

    # XWayland (legacy X11 app compatibility)
    xorg-xwayland

    # fonts
    ttf-jetbrains-mono-nerd noto-fonts-emoji

    # GTK theming (materia-dark, applied like nwg-look would)
    materia-gtk-theme kvantum kvantum-qt5 kvantum-theme-materia
    xdg-utils xorg-xrdb sway-audio-idle-inhibit

    # audio
    pipewire pipewire-pulse pipewire-alsa wireplumber

    # bundled apps used by keybinds/autostart

    # GRUB theme (ultragrub)
    wget

    # waybar tags module (parses mmsg JSON output)
    jq
)

[[ "$INSTALL_DISCORD" -eq 1 ]] && PACKAGES+=(discord)
[[ "$INSTALL_SPOTIFY" -eq 1 ]] && PACKAGES+=(spotify spicetify-cli)
[[ -n "$BROWSER_PACKAGE" ]] && PACKAGES+=("$BROWSER_PACKAGE")

# seat management: mango (via libseat) needs elogind outside of systemd.
# ly is the display manager on every init system; each one needs its own
# integration package.
case "$INIT_SYSTEM" in
    openrc)  PACKAGES+=(elogind-openrc ly ly-openrc) ;;
    dinit)   PACKAGES+=(elogind-dinit ly ly-dinit) ;;
    systemd) PACKAGES+=(ly) ;;
esac

step "Packages (${#PACKAGES[@]})"
info "${PACKAGES[*]}"
info "Using --noconfirm so this doesn't sit waiting on an easy-to-miss prompt (e.g. picking between multiple providers for the same package)."
if confirm "Install everything now? (builds -git AUR packages, can take a while)"; then
    run "$AUR_HELPER" -S --needed --noconfirm "${PACKAGES[@]}"
    ok "Packages installed"
else
    warn "Skipped. The rest of the script continues, but the environment won't fully work until these are installed manually."
fi

# ---------- seat management (elogind) ----------
if [[ "$INIT_SYSTEM" != "systemd" ]]; then
    step "Enabling elogind ($INIT_SYSTEM)"
    case "$INIT_SYSTEM" in
        openrc)
            sudo rc-update add elogind boot
            sudo rc-service elogind start
            log_adapt "Enabled elogind in the boot runlevel via rc-update (OpenRC) — needed for mango to access DRM/input through libseat"
            ;;
        dinit)
            sudo dinitctl enable elogind
            log_adapt "Enabled elogind via dinitctl (dinit) — needed for mango to access DRM/input through libseat"
            ;;
    esac
    ok "elogind configured (if it was already active, the commands above just confirmed that)"
fi

# ---------- display manager (ly) ----------
step "Display manager (ly)"

# Wayland session entry so ly (or any other display manager) can list
# Mango, in case the mangowm-git package doesn't ship one. dbus-run-session
# wraps mango in its own D-Bus session, which it needs when launched from a
# display manager instead of a TTY.
sudo mkdir -p /usr/share/wayland-sessions
sudo tee /usr/share/wayland-sessions/mango.desktop >/dev/null <<'LYEOF'
[Desktop Entry]
Name=Mango
Comment=MangoWM, a dwl-based Wayland compositor
Exec=dbus-run-session mango
Type=Application
LYEOF
log_adapt "Created/updated /usr/share/wayland-sessions/mango.desktop (dbus-run-session mango) so display managers can list Mango as a session"
if confirm "Hide all login sessions except Mango (with a backup)?"; then
    strip_other_sessions
fi

case "$INIT_SYSTEM" in
    systemd)
        enable_ly=1
        other_dm=""
        for dm in gdm sddm lightdm lxdm; do
            if systemctl is-enabled "${dm}.service" >/dev/null 2>&1; then
                other_dm="$dm"
                break
            fi
        done

        if [[ -n "$other_dm" ]]; then
            warn "${other_dm}.service is already enabled as your display manager."
            if confirm "Disable ${other_dm} and switch to ly?"; then
                sudo systemctl disable "${other_dm}.service" || true
            else
                enable_ly=0
                warn "Leaving ${other_dm} in place; not enabling ly."
            fi
        fi

        if [[ "$enable_ly" -eq 1 ]]; then
            sudo systemctl enable ly@tty2.service
            ok "ly enabled as the display manager (ly@tty2.service)"
            log_adapt "Installed and enabled ly@tty2.service as the display manager — Mango now shows up as a selectable session on the login screen"
        fi
        ;;

    dinit)
        # Known ly-dinit packaging issue on Artix: its service file uses
        # shares-console instead of pinning ly to its own tty, so it fights
        # the getty on the console dinit itself uses (whatever tty PID 1's
        # stdout points to — tty1 unless the kernel cmdline says otherwise)
        # for control of the VT and crashes in a restart loop ("panic:
        # reached unreachable code"). Fix: free that tty from ACTIVE_CONSOLES.
        CONSOLE_CONF=/etc/dinit.d/config/console.conf
        if [[ -f "$CONSOLE_CONF" ]] && grep -q '^ACTIVE_CONSOLES=' "$CONSOLE_CONF"; then
            dinit_console="$(readlink -f /proc/1/fd/1 2>/dev/null || echo /dev/tty1)"
            if [[ "$dinit_console" != /dev/tty* ]]; then
                cmdline_tty="$(grep -oE 'console=tty[0-9]+' /proc/cmdline 2>/dev/null | head -1 | grep -oE '[0-9]+')"
                dinit_console="/dev/tty${cmdline_tty:-1}"
            fi
            dinit_tty_num="${dinit_console##*tty}"

            consoles=()
            for n in 1 2 3 4 5 6; do
                [[ "$n" == "$dinit_tty_num" ]] && continue
                consoles+=("/dev/tty${n}")
            done
            new_active="${consoles[*]}"

            run sudo sed -i "s|^ACTIVE_CONSOLES=.*|ACTIVE_CONSOLES=\"${new_active}\"|" "$CONSOLE_CONF"
            ok "Freed ${dinit_console} (dinit's own console) from ACTIVE_CONSOLES so ly can use it without fighting a getty"
            log_adapt "dinit: removed ${dinit_console} from $CONSOLE_CONF's ACTIVE_CONSOLES — without this, ly crash-loops with 'panic: reached unreachable code' because it and the getty on that tty fight over VT control. Requires a reboot to take effect."
            REBOOT_NEEDED_FOR_LY=1
        else
            warn "$CONSOLE_CONF not found or not in the expected format — skipping the console fix, check it by hand if ly crash-loops."
        fi

        sudo dinitctl enable ly
        if [[ "${REBOOT_NEEDED_FOR_LY:-0}" -eq 1 ]]; then
            ok "ly enabled (will start after your next reboot, needed for the console change above to take effect)"
        else
            ok "ly enabled; log out or reboot when ready to use it"
        fi
        log_adapt "Installed ly + ly-dinit and enabled it as the display manager"
        ;;

    openrc)
        sudo rc-update add ly default
        ok "ly enabled as the display manager (OpenRC)"
        log_adapt "Installed ly + ly-openrc and enabled it as the display manager"
        info "If ly crash-loops with a VT/console error, it's likely the same kind of getty-vs-ly console conflict as on dinit — check what's running on the tty ly wants (usually tty2) with 'rc-status' and free it up in your getty config."
        ;;
esac
fi

# ---------- packages: Fedora ----------
if [[ "$DISTRO_FAMILY" == "fedora" ]]; then
    step "Terra repository (mango's package lives here)"
    if ! dnf repolist 2>/dev/null | grep -qi terra; then
        sudo dnf install -y --nogpgcheck --repofrompath \
            'terra,https://repos.fyralabs.com/terra$releasever' terra-release
        ok "Terra repo added"
    else
        ok "Terra repo already enabled"
    fi

    # Best-effort package list: most Wayland-ecosystem tools use the same
    # name in Fedora's repos as in Arch's. A few things are Arch/AUR-only
    # (helium-browser, the AUR "spotify" build, ttf-jetbrains-mono-nerd's
    # Arch-specific bundling) and have no dnf equivalent — those are handled
    # separately below (Flatpak, or a manual note) instead of guessed at.
    FEDORA_PACKAGES=(
        mangowm
        waybar rofi fuzzel foot kitty fish fastfetch
        nemo pavucontrol nwg-look
        awww waypaper cava python3
        grim slurp
        dunst swaync libnotify
        swayosd brightnessctl pamixer swayidle
        wlogout wlsunset
        xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk
        xorg-x11-server-Xwayland
        jetbrains-mono-fonts google-noto-emoji-color-fonts
        pipewire pipewire-pulseaudio wireplumber
        kvantum materia-kde-kvantum
        wget jq unzip
    )

    step "Packages (${#FEDORA_PACKAGES[@]})"
    info "${FEDORA_PACKAGES[*]}"
    warn "This list is best-effort: most of these are the same name in Fedora's repos as in Arch's, but it isn't as thoroughly verified as the Arch package list. Anything that fails to install is reported at the end instead of stopping the script."
    FEDORA_FAILED=()
    if confirm "Install everything now?"; then
        for pkg in "${FEDORA_PACKAGES[@]}"; do
            if ! run sudo dnf install -y "$pkg"; then
                FEDORA_FAILED+=("$pkg")
            fi
        done
        if [[ "${#FEDORA_FAILED[@]}" -gt 0 ]]; then
            warn "Couldn't install: ${FEDORA_FAILED[*]} — check the exact package name for your Fedora version and install those by hand."
        else
            ok "All packages installed"
        fi
    else
        warn "Skipped. The rest of the script continues, but the environment won't fully work until these are installed manually."
    fi

    # Fedora's jetbrains-mono-fonts package is the PLAIN font, not the Nerd
    # Font build — it doesn't have the icon glyphs waybar/wlogout/rofi use,
    # so they'd all render as blank boxes. There's no official dnf/COPR
    # package worth depending on here, so grab the real thing straight from
    # the upstream Nerd Fonts releases instead.
    step "Nerd Font icons (waybar/wlogout glyphs)"
    mkdir -p "$HOME/.local/share/fonts"
    NF_ZIP="$(mktemp -u --suffix=.zip)"
    if run curl -fsSL -o "$NF_ZIP" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"; then
        mkdir -p "$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
        run unzip -o -q "$NF_ZIP" -d "$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
        run fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1
        rm -f "$NF_ZIP"
        ok "JetBrainsMono Nerd Font installed to ~/.local/share/fonts"
        log_adapt "Fedora's jetbrains-mono-fonts package doesn't include the Nerd Font icon glyphs waybar/wlogout use -> downloaded the real Nerd Font build from the upstream GitHub releases instead of guessing at a COPR"
    else
        warn "Couldn't download the Nerd Font — waybar/wlogout icons will show as blank boxes until you install one from https://www.nerdfonts.com"
    fi


    step "swaylock-effects (needs a COPR repo on Fedora)"
    if confirm "Enable the eddsalkield/swaylock-effects COPR and install it?"; then
        run sudo dnf copr enable -y eddsalkield/swaylock-effects || true
        run sudo dnf install -y swaylock-effects || warn "swaylock-effects install failed; falling back to plain swaylock."
        run sudo dnf install -y swaylock || true
    fi

    step "materia-gtk-theme"
    run sudo dnf install -y materia-gtk-theme 2>/dev/null || warn "materia-gtk-theme isn't in Fedora's repos on this release; the GTK settings below will still point to it, install it manually (e.g. from a COPR) if it doesn't show up."

    step "cliphist, wl-clipboard, wl-clip-persist, xfce-polkit, wmenu"
    for pkg in cliphist wl-clipboard wl-clip-persist xfce4-polkit wmenu; do
        run sudo dnf install -y "$pkg" || warn "$pkg not found under that name in your Fedora repos — search 'dnf search $pkg' and adjust by hand."
    done

    step "ly (display manager)"
    if sudo dnf install -y ly; then
        sudo mkdir -p /usr/share/wayland-sessions
        sudo tee /usr/share/wayland-sessions/mango.desktop >/dev/null <<'LYEOF'
[Desktop Entry]
Name=Mango
Comment=MangoWM, a dwl-based Wayland compositor
Exec=dbus-run-session mango
Type=Application
LYEOF
        log_adapt "Created/updated /usr/share/wayland-sessions/mango.desktop (dbus-run-session mango) so display managers can list Mango as a session"
        if confirm "Hide all login sessions except Mango (with a backup)?"; then
    strip_other_sessions
fi
        other_dm=""
        for dm in gdm sddm lightdm lxdm; do
            if systemctl is-enabled "${dm}.service" >/dev/null 2>&1; then
                other_dm="$dm"
                break
            fi
        done
        enable_ly=1
        if [[ -n "$other_dm" ]]; then
            warn "${other_dm}.service is already enabled as your display manager."
            if confirm "Disable ${other_dm} and switch to ly?"; then
                sudo systemctl disable "${other_dm}.service" || true
            else
                enable_ly=0
            fi
        fi
        if [[ "$enable_ly" -eq 1 ]]; then
            sudo systemctl enable ly@tty2.service
            ok "ly enabled as the display manager (ly@tty2.service)"
            log_adapt "Installed and enabled ly@tty2.service as the display manager — Mango now shows up as a selectable session on the login screen"
        fi
    else
        warn "ly isn't available in your Fedora repos; use GDM/SDDM with the Mango session entry created above, or install ly from source."
    fi

    if [[ "$INSTALL_DISCORD" -eq 1 || "$INSTALL_SPOTIFY" -eq 1 ]]; then
        command -v flatpak >/dev/null 2>&1 || sudo dnf install -y flatpak
        flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        for app in discord spotify; do
            [[ "$app" == discord && "$INSTALL_DISCORD" -eq 0 ]] && continue
            [[ "$app" == spotify && "$INSTALL_SPOTIFY" -eq 0 ]] && continue
            case "$app" in discord) appid=com.discordapp.Discord ;; spotify) appid=com.spotify.Client ;; esac
            flatpak install --user -y flathub "$appid"
            printf '#!/bin/sh\nexec flatpak run %s "$@"\n' "$appid" | sudo tee "/usr/local/bin/$app" >/dev/null
            sudo chmod +x "/usr/local/bin/$app"
        done
    fi
    if [[ "$BROWSER_COMMAND" == firefox ]]; then
        sudo dnf install -y firefox
    elif [[ -n "$BROWSER_COMMAND" ]]; then
        warn "Install $BROWSER_COMMAND manually on Fedora; automatic browser installation is supported on Arch/Artix/CachyOS."
    fi
fi

# ---------- packages: NixOS ----------
if [[ "$DISTRO_FAMILY" == "nixos" ]]; then
    step "NixOS: generating a config snippet instead of installing packages"
    info "NixOS manages packages and services declaratively — this script won't run 'nix-env -i' or 'systemctl enable' behind your back."
    info "It writes a snippet with everything this setup needs; add it to your flake/configuration.nix and rebuild."

    NIX_SNIPPET="$HOME/mango-nixos-snippet.nix"
    cat > "$NIX_SNIPPET" <<'NIXEOF'
# Generated by victoria-mangowm-dotfiles install.sh
# Merge this into your flake.nix / configuration.nix and run nixos-rebuild switch.
#
# 1) flake.nix inputs:
#      mangowm = {
#        url = "github:mangowm/mango";
#        inputs.nixpkgs.follows = "nixpkgs";
#      };
#
# 2) In your NixOS module imports:
#      imports = [ inputs.mangowm.nixosModules.mango ];
#      programs.mango.enable = true;
#
# 3) Login (pick ONE from https://mangowm.github.io/docs/installation#nixos):
#      services.greetd.enable = true;               # TUI greeter, or
#      services.displayManager.defaultSession = "mango";  # with an existing DM (ly/gdm/sddm), or
#      services.getty.autologinUser = "your-username"; environment.loginShellInit = ''[ "$(tty)" = /dev/tty1 ] && exec mango'';
#
# 4) Packages (best-effort names; check `nix search nixpkgs <name>` for anything missing):
{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    waybar rofi fuzzel foot kitty fish fastfetch
    nemo pavucontrol nwg-look
    awww waypaper
    wallust cava python3
    grim slurp
    dunst swaync libnotify
    swayosd brightnessctl pamixer swayidle swaylock-effects
    xfce-polkit wlogout wlsunset
    xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk
    xwayland
    jetbrains-mono
    noto-fonts-emoji
    materia-theme
    pipewire wireplumber
    # Add optional Discord/Spotify/browser packages yourself on NixOS.
    wget jq
  ];
}
NIXEOF
    ok "Wrote $NIX_SNIPPET"
    log_adapt "NixOS: package installation and display-manager setup were NOT done imperatively — a config snippet was written to $NIX_SNIPPET instead. Add it to your flake/configuration.nix and run nixos-rebuild switch."
    warn "The GRUB theme step (ultragrub) is skipped below too — NixOS manages the bootloader declaratively via boot.loader.grub.* and would just overwrite anything ultragrub does to /etc/grub.d on the next rebuild."
    if ! confirm "Continue and deploy the dotfiles to $CONFIG_DIR now? (This part is just files, it's independent of the Nix config above.)"; then
        exit 0
    fi
fi

# ---------- copy dotfiles (only if we're not already operating in place) ----------
if [[ "$IN_PLACE" -eq 1 ]]; then
    step "Using $CONFIG_DIR in place"
    info "No copy needed, the checkout at $SOURCE_DIR already is $CONFIG_DIR."
    info "Leaving .git and install.sh alone here — this IS your actual clone, not a throwaway copy."
else
    step "Copying dotfiles to $CONFIG_DIR"
    if [[ -d "$CONFIG_DIR" ]]; then
        if confirm "$CONFIG_DIR already exists. Back it up and overwrite?"; then
            backup="$CONFIG_DIR.bak.$(date +%Y%m%d%H%M%S)"
            mv "$CONFIG_DIR" "$backup"
            ok "Backed up to $backup"
        else
            err "Can't continue without overwriting $CONFIG_DIR. Aborting."
            exit 1
        fi
    fi
    mkdir -p "$CONFIG_DIR"
    cp -a "$SOURCE_DIR/." "$CONFIG_DIR/"
    rm -rf "$CONFIG_DIR/.git" "$CONFIG_DIR/install.sh"
    ok "Copied"
fi

# ---------- corrections ----------
step "Applying corrections"

WAYBAR_JSONC="$CONFIG_DIR/waybar/config.jsonc"
AUTOSTART="$CONFIG_DIR/autostart.sh"
WLOGOUT_LAYOUT="$CONFIG_DIR/config/wlogout/layout"
WLOGOUT_THEME_SCRIPT="$CONFIG_DIR/scripts/wlogout-theme.sh"

# 1) waybar: systemctl -> loginctl (no systemd, running elogind)
if [[ "$INIT_SYSTEM" != systemd && -f "$WAYBAR_JSONC" ]]; then
    run_sed -i \
        -e 's/systemctl poweroff/loginctl poweroff/' \
        -e 's/systemctl reboot/loginctl reboot/' \
        "$WAYBAR_JSONC"
    log_adapt "waybar/config.jsonc: systemctl poweroff/reboot -> loginctl (no systemd here)"
fi

if [[ -d "$CONFIG_DIR/config/wlogout" ]]; then
    mkdir -p "$HOME/.config/wlogout"
    cp "$CONFIG_DIR/config/wlogout/"* "$HOME/.config/wlogout/" 2>/dev/null || true
    if [[ "$INIT_SYSTEM" == systemd ]]; then
        sed -i -E 's/loginctl (poweroff|reboot|suspend|hibernate)/systemctl \1/g' "$HOME/.config/wlogout/layout"
        sed -i -E 's/loginctl (poweroff|reboot|suspend|hibernate)/systemctl \1/g' "$WAYBAR_JSONC"
    fi
    ok "~/.config/wlogout populated directly from the repo"
fi

# 4) autostart.sh: swayosd-server and the polkit agent don't start on their own
#    without systemd --user; wire up a wallpaper fallback for waypaper's first run
if [[ -f "$AUTOSTART" ]]; then
    if ! grep -q "swayosd-server" "$AUTOSTART"; then
        printf '\npgrep -x swayosd-server >/dev/null || swayosd-server &\n' >> "$AUTOSTART"
        log_adapt "autostart.sh: added swayosd-server startup (used by volume.sh/brightness.sh but was never started)"
    fi

    if ! grep -q "xfce-polkit" "$AUTOSTART"; then
        cat >> "$AUTOSTART" <<'POLKITEOF'

# polkit agent (needed for GUI privilege prompts, e.g. mounting drives in nemo)
if command -v xfce-polkit >/dev/null 2>&1; then
    pgrep -x xfce-polkit >/dev/null || xfce-polkit &
elif [ -x /usr/lib/xfce-polkit/xfce-polkit ]; then
    pgrep -f xfce-polkit >/dev/null || /usr/lib/xfce-polkit/xfce-polkit &
fi
POLKITEOF
        log_adapt "autostart.sh: added a polkit agent startup (xfce-polkit) — nothing was providing GUI privilege prompts before"
    fi

    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        run_sed -i 's/^dbus-update-activation-environment \\$/dbus-update-activation-environment --systemd \\/' "$AUTOSTART"
        log_adapt "autostart.sh: added --systemd to dbus-update-activation-environment (you're on systemd, this also propagates the env vars to systemd --user)"
    fi
fi

# 9) xdg-desktop-portal: with both -wlr and -gtk backends installed, explicitly
#    pin ScreenCast/Screenshot to wlr so Discord's share picker reliably talks
#    to the backend that actually implements it, instead of depending on
#    whichever portal happened to register first at boot.
mkdir -p "$HOME/.config/xdg-desktop-portal"
cat > "$HOME/.config/xdg-desktop-portal/portals.conf" <<'PORTALSEOF'
[preferred]
default=gtk
org.freedesktop.impl.portal.ScreenCast=wlr
org.freedesktop.impl.portal.Screenshot=wlr
PORTALSEOF
log_adapt "Added ~/.config/xdg-desktop-portal/portals.conf pinning ScreenCast/Screenshot to xdg-desktop-portal-wlr (the gtk portal doesn't implement screen sharing at all) — makes Discord screen share reliable regardless of portal startup order"

ok "Corrections applied"


# ---------- CPU temperature sensor (waybar) ----------
step "Detecting the CPU sensor for waybar"
hwmon_path=""
for d in /sys/class/hwmon/hwmon*; do
    [ -r "$d/name" ] || continue
    name="$(cat "$d/name" 2>/dev/null || true)"
    case "$name" in
        k10temp|coretemp|zenpower|cpu_thermal|acpitz)
            hwmon_path="$d/temp1_input"
            break
            ;;
    esac
done
if [[ -n "$hwmon_path" && -f "$WAYBAR_JSONC" ]]; then
    run_sed -i "s#/sys/class/hwmon/hwmon[0-9]*/temp1_input#${hwmon_path}#" "$WAYBAR_JSONC"
    ok "Sensor: $hwmon_path"
    log_adapt "waybar/config.jsonc: hwmon-path was hardcoded (hwmon4) -> auto-detected as $hwmon_path"
else
    warn "Couldn't auto-detect the sensor. Set 'hwmon-path' in $WAYBAR_JSONC by hand (run 'sensors' or check /sys/class/hwmon/*/name)."
fi

# ---------- wallust: Waybar, Mango borders and Fish ----------
step "Wallpaper colors (Wallust)"
if ! command -v python3 >/dev/null 2>&1; then
    err "python3 is required to configure Wallust and Waypaper. Install it and rerun."
    exit 1
fi
# Existing user configuration was backed up before deployment.
WALLPAPER_FALLBACK="$(python3 "$CONFIG_DIR/scripts/theme.py" setup)"
if command -v wallust >/dev/null 2>&1; then
    if ! bash "$CONFIG_DIR/scripts/wallust-reload.sh" --install "$WALLPAPER_FALLBACK"; then
        err "Initial palette generation failed. See ${XDG_CACHE_HOME:-$HOME/.cache}/wallust/victoria.log."
        exit 1
    fi
    ok "Wallpaper palette generated for Waybar, Mango borders and Fish"
else
    warn "Wallust is not installed yet. Configurations are ready; generate the palette after installing it."
fi
log_adapt "Installed Wallust templates, Waypaper's awww hook and Fish palette loader; first palette uses the saved wallpaper or a bundled image."

# ---------- monitors: monitor.conf (fixed rules) ----------
# monitor.conf ships with the repo author's two monitors (DP-1 @165Hz + HDMI-A-1).
# mango has no way to auto-detect outputs before the session starts, and
# kanshi / wlr-randr don't work here (mango doesn't implement
# wlr-output-management), so on any other machine the rules just need the
# right output names. Outputs with no matching rule still work (mango picks
# their preferred mode), they just aren't positioned.
step "Monitor layout (monitor.conf)"
if [[ -f "$CONFIG_DIR/monitor.conf" ]]; then
    warn "monitor.conf is tuned for DP-1 @165Hz + HDMI-A-1 (the author's setup)."
    info "Check Mango output information inside your session and edit $CONFIG_DIR/monitor.conf."
    log_adapt "monitor.conf: kept as shipped (DP-1 @165Hz + HDMI-A-1) — edit the output names/modes for your own monitors"
else
    warn "monitor.conf not found in this checkout — outputs will use mango's defaults. See mango's docs, Configuration > Monitors (monitor_rule=)."
fi

# ---------- keyboard layout (asked earlier, applied now) ----------

if [[ "$KB_LAYOUT" =~ ^([a-zA-Z0-9_-]+)\(([a-zA-Z0-9_-]+)\)$ ]]; then
    KB_VARIANT="${BASH_REMATCH[2]}"
    KB_LAYOUT="${BASH_REMATCH[1]}"
fi

if [[ -n "$KB_LAYOUT" && -f "$CONFIG_DIR/config.conf" ]]; then
    if grep -q '^xkb_rules_layout=' "$CONFIG_DIR/config.conf"; then
        run_sed -i "s/^xkb_rules_layout=.*/xkb_rules_layout=${KB_LAYOUT}/" "$CONFIG_DIR/config.conf"
    else
        printf '\n# keyboard layout (set by install.sh)\nxkb_rules_layout=%s\n' "$KB_LAYOUT" | write_to_append "$CONFIG_DIR/config.conf"
    fi
    if grep -q '^xkb_rules_variant=' "$CONFIG_DIR/config.conf"; then
        run_sed -i "s/^xkb_rules_variant=.*/xkb_rules_variant=${KB_VARIANT}/" "$CONFIG_DIR/config.conf"
    elif [[ -n "$KB_VARIANT" ]]; then
        run_sed -i "/^xkb_rules_layout=${KB_LAYOUT}$/a xkb_rules_variant=${KB_VARIANT}" "$CONFIG_DIR/config.conf"
    fi
    ok "config.conf: xkb_rules_layout=$KB_LAYOUT${KB_VARIANT:+, xkb_rules_variant=$KB_VARIANT}"
    log_adapt "config.conf: keyboard layout set to '$KB_LAYOUT'${KB_VARIANT:+ (variant: $KB_VARIANT)}"
fi

if [[ -n "${KB_CONSOLE:-}" ]]; then
    if [[ "$DISTRO_FAMILY" == "nixos" ]]; then
        info "NixOS manages the console keymap declaratively — add console.keyMap = \"$KB_CONSOLE\"; to your configuration.nix instead (it's in the snippet written earlier)."
    else
        if [[ -f /etc/vconsole.conf ]] && grep -q '^KEYMAP=' /etc/vconsole.conf; then
            run sudo sed -i "s/^KEYMAP=.*/KEYMAP=${KB_CONSOLE}/" /etc/vconsole.conf || true
        else
            printf 'KEYMAP=%s\n' "$KB_CONSOLE" | sudo tee -a /etc/vconsole.conf >/dev/null || true
        fi
        if [[ "$INIT_SYSTEM" == "systemd" ]]; then
            sudo localectl set-keymap "$KB_CONSOLE" 2>/dev/null || true
        else
            sudo loadkeys "$KB_CONSOLE" 2>/dev/null || true
        fi
        ok "Console/TTY keymap: $KB_CONSOLE (/etc/vconsole.conf)"
        log_adapt "Console keymap set to $KB_CONSOLE, matching the $KB_LAYOUT layout in config.conf — so a bare TTY and the shell before mango even starts use the same layout, not just the graphical session"
    fi
fi


CURSOR_NAME="$(grep -m1 '^cursor_theme=' "$CONFIG_DIR/config.conf" 2>/dev/null | cut -d= -f2 || true)"
CURSOR_NAME="${CURSOR_NAME:-Samuel-Noticias-Cursor}"

step "GTK theme (Materia-dark-compact)"
mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
for gtk_ini in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
    cat > "$gtk_ini" <<GTKEOF
[Settings]
gtk-theme-name=Materia-dark-compact
gtk-icon-theme-name=Adwaita
gtk-cursor-theme-name=${CURSOR_NAME}
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=1
GTKEOF
done
cat > "$HOME/.gtkrc-2.0" <<GTK2EOF
gtk-theme-name="Materia-dark-compact"
gtk-cursor-theme-name="${CURSOR_NAME}"
gtk-cursor-theme-size=24
GTK2EOF
if [[ -f "$AUTOSTART" ]] && ! grep -q "GTK_THEME" "$AUTOSTART"; then
    run_sed -i '/^export XCURSOR_THEME=/i export GTK_THEME=Materia-dark-compact' "$AUTOSTART"
fi
ok "gtk-3.0/gtk-4.0 settings.ini and ~/.gtkrc-2.0 written"
log_adapt "GTK theme: applied Materia-dark-compact the same way nwg-look would (gtk-3.0/gtk-4.0 settings.ini + ~/.gtkrc-2.0 + GTK_THEME env var), together with the $CURSOR_NAME cursor"

# Qt widgets (Ark, qBittorrent) need a Qt style, not just a GTK setting.
mkdir -p "$HOME/.config/Kvantum"
printf '[General]\ntheme=MateriaDark\n' > "$HOME/.config/Kvantum/kvantum.kvconfig"
if [[ ! -f /usr/share/Kvantum/MateriaDark/MateriaDark.kvconfig ]]; then
    warn "MateriaDark for Kvantum is missing. Install kvantum, kvantum-qt5 and kvantum-theme-materia on Arch/Artix/CachyOS."
fi
if command -v gsettings >/dev/null 2>&1; then
    gsettings get org.gnome.desktop.interface gtk-theme > "$BACKUP_DIR/gtk-theme.gsettings" 2>/dev/null || true
    gsettings get org.gnome.desktop.interface color-scheme > "$BACKUP_DIR/color-scheme.gsettings" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme Materia-dark-compact || warn "Could not set GTK theme through GSettings."
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark || warn "Could not set dark preference through GSettings."
fi
if [[ -f "$CONFIG_DIR/env.conf" ]]; then
    sed -i '/^env=GTK_THEME,/d; /^env=QT_STYLE_OVERRIDE,/d' "$CONFIG_DIR/env.conf"
    printf '\nenv=GTK_THEME,Materia-dark-compact\nenv=QT_STYLE_OVERRIDE,kvantum\n' >> "$CONFIG_DIR/env.conf"
fi
sed -i '/^export QT_QPA_PLATFORMTHEME=gtk3$/d' "$AUTOSTART"
if ! grep -q '^export QT_STYLE_OVERRIDE=' "$AUTOSTART"; then
    sed -i '/^export XCURSOR_THEME=/i export QT_STYLE_OVERRIDE=kvantum' "$AUTOSTART"
fi
# Always rewrite managed app choices, so rerunning can turn apps off again.
cat > "$CONFIG_DIR/apps.conf" <<APPS
INSTALL_DISCORD=$INSTALL_DISCORD
INSTALL_SPOTIFY=$INSTALL_SPOTIFY
START_DISCORD=$START_DISCORD
START_SPOTIFY=$START_SPOTIFY
START_BROWSER=$START_BROWSER
BROWSER_COMMAND=$BROWSER_COMMAND
APPS
sed -i '/^bind=SUPER,w,spawn,/d; /^bind=SUPER,a,spawn,/d; /^bind=SUPER,s,spawn,/d' "$CONFIG_DIR/bind.conf"
[[ -n "$BROWSER_COMMAND" ]] && printf 'bind=SUPER,w,spawn,%s\n' "$BROWSER_COMMAND" >> "$CONFIG_DIR/bind.conf"
[[ "$INSTALL_DISCORD" -eq 1 ]] && printf 'bind=SUPER,a,spawn,discord --ozone-platform=wayland\n' >> "$CONFIG_DIR/bind.conf"
[[ "$INSTALL_SPOTIFY" -eq 1 ]] && printf 'bind=SUPER,s,spawn,spotify\n' >> "$CONFIG_DIR/bind.conf"
if [[ -n "$BROWSER_DESKTOP" ]] && command -v xdg-settings >/dev/null 2>&1; then
    if [[ -f "/usr/share/applications/$BROWSER_DESKTOP" ]]; then
        xdg-settings set default-web-browser "$BROWSER_DESKTOP" || warn "Set your default browser manually with xdg-settings."
    else
        warn "Browser desktop entry $BROWSER_DESKTOP not found; SUPER+W is configured, but the system browser default was not changed."
    fi
fi
info "Log out and back in to apply GTK/Qt settings to the whole Mango session."

# ---------- fastfetch (outside ~/.config/mango) ----------
step "Configuring fastfetch"
FASTFETCH_SRC="$CONFIG_DIR/config/terminal_configs/fastfetch.jsonc"
if [[ -f "$FASTFETCH_SRC" ]]; then
    mkdir -p "$HOME/.config/fastfetch"
    cp "$FASTFETCH_SRC" "$HOME/.config/fastfetch/config.jsonc"
    ok "~/.config/fastfetch/config.jsonc"
    # fastfetch's logo now points at config/terminal_configs/img_terminal
    # (deployed automatically as part of the repo copy) instead of the old
    # broken ascii.txt reference. Just a sanity check in case that ever
    # changes again — don't mutate the file, just warn.
    logo_src="$(grep -o '"source": *"[^"]*"' "$HOME/.config/fastfetch/config.jsonc" | head -1 | sed -E 's/.*"source": *"([^"]*)"/\1/')"
    logo_src_expanded="${logo_src/#\~/$HOME}"
    logo_src_expanded="${logo_src_expanded%\*}"
    if [[ -n "$logo_src_expanded" && ! -e "$logo_src_expanded" ]]; then
        warn "fastfetch's logo source ($logo_src) doesn't exist -> it'll fall back to the distro's automatic logo instead."
    fi

    # Nothing in the repo calls fastfetch automatically anymore (the old
    # random_image.sh wrapper that used to do this was removed once
    # fastfetch's own kitty logo took over showing the image). Wire it into
    # fish directly so new terminals still get the welcome screen.
    FISH_CONFIG="$HOME/.config/fish/config.fish"
    mkdir -p "$HOME/.config/fish"
    touch "$FISH_CONFIG"
    if ! grep -q "fastfetch" "$FISH_CONFIG"; then
        cat >> "$FISH_CONFIG" <<'EOF'

# victoria-mangowm-dotfiles: fastfetch on every new terminal
if status is-interactive
    fastfetch
end
EOF
        ok "Hooked fastfetch into ~/.config/fish/config.fish"
        log_adapt "fish: nothing called fastfetch automatically anymore after random_image.sh was removed from the repo -> now runs on every interactive shell directly"
    else
        info "~/.config/fish/config.fish already calls fastfetch"
    fi
fi

if command -v fish >/dev/null 2>&1; then
    fish -c 'set -U fish_greeting' 2>/dev/null || true
    ok "Disabled fish's startup greeting"
fi

# ---------- kitty ----------
step "Configuring kitty"
mkdir -p "$HOME/.config/kitty"
cat > "$HOME/.config/kitty/kitty.conf" <<'KITTYEOF'
shell fish
background_opacity 0.88
window_padding_width 10
font_size 13
font_family JetBrainsMono Nerd Font
KITTYEOF
ok "~/.config/kitty/kitty.conf"

# ---------- permissions ----------
step "Fixing permissions"
find "$CONFIG_DIR" -name '*.sh' -exec chmod +x {} \;
ok "Scripts marked executable"

# ---------- cursor ----------
# The theme name comes from cursor_theme= in config.conf (CURSOR_NAME, set above).
# If a folder with that name exists in config/ it is installed from the repo,
# otherwise we only check whether the theme is already installed on the system.
step "Cursor ($CURSOR_NAME)"
CURSOR_SRC="$CONFIG_DIR/config/$CURSOR_NAME"
CURSOR_DST="$HOME/.local/share/icons/$CURSOR_NAME"
if [[ -d "$CURSOR_SRC" ]]; then
    mkdir -p "$HOME/.local/share/icons"
    rm -rf "$CURSOR_DST"
    cp -a "$CURSOR_SRC" "$CURSOR_DST"
    find "$CURSOR_DST" -maxdepth 1 -name '.~lock.*#' -delete 2>/dev/null
    ok "Cursor copied from the repo to $CURSOR_DST"
    log_adapt "Cursor: the $CURSOR_NAME theme ships in the repo (config/$CURSOR_NAME) -> copied to ~/.local/share/icons/"

    # index.theme should be plain text ([Icon Theme]...)
    if [[ -f "$CURSOR_DST/index.theme" ]] && ! head -c 200 "$CURSOR_DST/index.theme" 2>/dev/null | grep -q '\[Icon Theme\]'; then
        warn "$CURSOR_DST/index.theme isn't a valid theme file (looks like 'OpenDocument Text', not plain text)."
        info "The files under cursors/ are real X11 cursors and should still work via XCURSOR_THEME,"
        info "but index.theme/cursor.theme need to be re-saved as plain text."
    fi
elif [[ -d "$HOME/.local/share/icons/$CURSOR_NAME" || -d "$HOME/.icons/$CURSOR_NAME" || -d "/usr/share/icons/$CURSOR_NAME" ]]; then
    ok "Cursor theme already present"
else
    warn "cursor_theme=$CURSOR_NAME (config.conf) isn't in the repo (config/$CURSOR_NAME) and isn't installed — cursors fall back to a default theme until it is."
    info "Put the theme folder in ~/.local/share/icons/$CURSOR_NAME (or in config/$CURSOR_NAME in the repo, so this step installs it for you)."
fi

# ---------- GRUB (ultragrub: theme + boot entry patch) ----------
ULTRAGRUB_DIR="$CONFIG_DIR/config/ultragrub"
if [[ "$DISTRO_FAMILY" == "nixos" ]]; then
    : # already explained above: skipped, NixOS owns /etc/grub.d
elif [[ -d "$ULTRAGRUB_DIR" ]]; then
    step "GRUB theme (UltraGrub)"
    warn "This step touches /etc/default/grub and the scripts in /etc/grub.d (your bootloader)."
    if confirm "Install the GRUB theme and patch the boot entries (cleans up the Windows entry, etc.)?"; then
        GRUB_BACKUP="/etc/grub-backup-$(date +%Y%m%d%H%M%S)"
        sudo mkdir -p "$GRUB_BACKUP"
        for f in /etc/default/grub /etc/grub.d/30_os-prober /etc/grub.d/10_linux /etc/grub.d/30_uefi-firmware; do
            [[ -f "$f" ]] && sudo cp -a "$f" "$GRUB_BACKUP/" 2>/dev/null
        done
        ok "Backed up the GRUB files to $GRUB_BACKUP"

        grub_install_ok=1
        info "Running the theme's install.sh (downloads UltraGrub from GitHub, --lang English)..."
        if ! bash "$ULTRAGRUB_DIR/install.sh" --lang English; then
            err "The theme's install.sh failed (see the output above). Skipping patch_entries.sh."
            grub_install_ok=0
        fi

        if [[ "$grub_install_ok" -eq 1 ]]; then
            info "Running patch_entries.sh..."
            if bash "$ULTRAGRUB_DIR/patch_entries.sh"; then
                ok "GRUB boot entries patched"
                log_adapt "GRUB: installed the UltraGrub theme and applied patch_entries.sh (backup at $GRUB_BACKUP)"
            else
                err "patch_entries.sh failed. The original files are backed up at $GRUB_BACKUP."
            fi
        fi
    else
        info "Skipped. To run it later:"
        info "  bash '$ULTRAGRUB_DIR/install.sh' --lang English && bash '$ULTRAGRUB_DIR/patch_entries.sh'"
    fi
fi

# ---------- video group (swayosd writing to /sys/class/backlight) ----------
step "Brightness permission"
if ! groups "$USER" | grep -qw video; then
    if confirm "Add your user to the 'video' group (needed for swayosd to control brightness)?"; then
        sudo usermod -aG video "$USER"
        ok "Added. You'll need to log out and back in for it to take effect."
        log_adapt "Added the user to the 'video' group (without this, brightness control via swayosd fails with a permission error)"
    fi
else
    ok "Already in the video group"
fi

# ---------- default shell ----------
step "Default shell"
FISH_BIN="$(command -v fish || true)"
if [[ -n "$FISH_BIN" && "$SHELL" != "$FISH_BIN" ]]; then
    if confirm "Set fish as your default shell?"; then
        grep -qxF "$FISH_BIN" /etc/shells || echo "$FISH_BIN" | sudo tee -a /etc/shells >/dev/null
        chsh -s "$FISH_BIN"
        ok "Shell changed (takes effect on your next login)"
    fi
else
    info "Already fish, or fish isn't installed"
fi

# ---------- health check ----------
step "Health check"
HEALTH_OK=1
check_cmd() {
    if command -v "$1" >/dev/null 2>&1; then
        ok "$1 found"
    else
        warn "$1 not found"
        HEALTH_OK=0
    fi
}
check_file() {
    if [[ -e "$1" ]]; then
        ok "$2"
    else
        warn "$2 — missing ($1)"
        HEALTH_OK=0
    fi
}
if [[ "$DISTRO_FAMILY" == "nixos" ]]; then
    info "Skipping the command checks — on NixOS nothing gets installed until you rebuild with the snippet from earlier, so 'not found' here would just be expected, not a real problem."
    check_file "$CONFIG_DIR/config.conf" "config.conf deployed"
    check_file "$HOME/.config/wlogout/layout" "wlogout theme deployed"
else
    check_cmd mango
    check_cmd waybar
    check_cmd kitty
    check_cmd fish
    check_cmd mmsg
    check_cmd wallust
    check_file "${XDG_CACHE_HOME:-$HOME/.cache}/wallust/victoria-generation" "Wallust palette generated"
    check_file "$CONFIG_DIR/config.conf" "config.conf deployed"
    check_file "$HOME/.config/wlogout/layout" "wlogout theme deployed"
    check_file "$HOME/.local/share/icons/$CURSOR_NAME" "cursor theme installed"
fi
if [[ "$HEALTH_OK" -eq 1 ]]; then
    ok "Everything checks out"
else
    warn "Some things above are missing — scroll up for what failed, review the errors and your backups before re-running."
fi

# ---------- summary ----------
echo
box "Done — welcome to Mango" "$c_green"
info "Init system: $INIT_SYSTEM"
info "Configuration backup: $BACKUP_DIR"
if [[ "${#ADAPTATIONS[@]}" -gt 0 ]]; then
    printf "\n${c_bold}${c_mauve}Adaptations made${c_reset} ${c_sub}(the original repo had these broken or incomplete)${c_reset}\n"
    for a in "${ADAPTATIONS[@]}"; do
        printf "  ${c_mauve}›${c_reset} %s\n" "$a"
    done
fi
printf "\n${c_bold}${c_yellow}Worth double-checking by hand${c_reset}\n"
info "monitor.conf: shipped with DP-1 @165Hz + HDMI-A-1 — edit the output names/modes there for your own monitors (check Mango output information inside your session)"
info "The cursor theme name in config.conf (cursor_theme=) — see the warning above if that theme isn't installed"
info "Pick a wallpaper with SUPER+F (waypaper) any time you want to change it — wallust will regenerate colors automatically from then on"
# info "Spicetify: autostart.sh runs 'spicetify backup apply' every login, but that needs one manual first-time setup after logging into Spotify — run 'spicetify backup apply' yourself once, following spicetify's own setup guide, before it'll do anything on autostart"
echo
printf "${c_bold}${c_blue}To start:${c_reset} log in on a TTY and run '%bmango%b', or pick Mango from ly's session list.\n" "$c_mauve" "$c_reset"
echo