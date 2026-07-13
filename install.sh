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

set -euo pipefail

REPO_URL="https://github.com/kohagizpk/victoria-mangowm-dotfiles.git"
CONFIG_DIR="$HOME/.config/mango"

# ---------- palette (catppuccin mocha, same accents as the waybar theme) ----------
c_reset='\033[0m'; c_bold='\033[1m'; c_dim='\033[2m'
c_mauve='\033[38;2;203;166;247m'; c_pink='\033[38;2;243;139;168m'
c_green='\033[38;2;166;227;161m'; c_yellow='\033[38;2;249;226;175m'
c_red='\033[38;2;243;139;168m';   c_blue='\033[38;2;137;180;250m'
c_sub='\033[38;2;108;112;134m'

STEP_NUM=0
TOTAL_STEPS="$(grep -c '^step "' "${BASH_SOURCE[0]}" 2>/dev/null || echo '?')"

step()  { STEP_NUM=$((STEP_NUM + 1)); printf "\n${c_mauve}❯${c_reset} ${c_sub}[%s/%s]${c_reset} ${c_bold}%s${c_reset}\n" "$STEP_NUM" "$TOTAL_STEPS" "$1"; }
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
    read -rp "$(printf "${c_mauve}?${c_reset} %s " "$1")[y/N] " reply
    [[ "$reply" =~ ^[yY]$ ]]
}

ADAPTATIONS=()
log_adapt() { ADAPTATIONS+=("$1"); }

on_error() {
    local line="$1"
    printf "\n${c_red}✗ Something went wrong at line %s.${c_reset}\n" "$line"
    printf "  ${c_sub}Scroll up to see the actual error message right above this.${c_reset}\n"
    printf "  ${c_sub}Most steps are safe to re-run — you can just run ./install.sh again;${c_reset}\n"
    printf "  ${c_sub}already-installed packages and already-applied fixes are skipped automatically.${c_reset}\n"
}
trap 'on_error $LINENO' ERR

banner

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
if [[ "${EUID}" -eq 0 ]]; then
    err "Don't run this as root. Run it as your normal user (it will ask for sudo when needed)."
    exit 1
fi

if ! (echo > /dev/tcp/github.com/443) 2>/dev/null; then
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
elif [[ -f "$SCRIPT_DIR/config.conf" && -f "$SCRIPT_DIR/scripts/autostart.sh" ]]; then
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

box "victoria-mangowm-dotfiles installer"
info "Source: $SOURCE_DIR"
info "Target: $CONFIG_DIR"
info "Distro family: $DISTRO_FAMILY"
info "Init system: $INIT_SYSTEM"
if ! confirm "Start?"; then
    exit 0
fi

# ---------- systemd-libs dummy (Artix) ----------
# AUR packages (built for vanilla Arch) commonly depend on systemd/systemd-libs.
# On Artix with libelogind this causes a file conflict; the official fix is to
# install artix-archlinux-support, which provides dummy systemd/systemd-libs.
if [[ "$DISTRO_FAMILY" == "arch" && "$INIT_SYSTEM" != "systemd" ]] && pacman -Si artix-archlinux-support >/dev/null 2>&1; then
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
    waybar rofi fuzzel wmenu
    wl-clipboard cliphist wl-clip-persist

    # terminal, shell
    kitty foot fish fastfetch

    # file manager & misc GUI utilities
    nemo pavucontrol nwg-look

    # wallpaper, multi-monitor
    swaybg waypaper kanshi wlr-randr

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
    materia-gtk-theme

    # audio
    pipewire pipewire-pulse pipewire-alsa wireplumber

    # bundled apps used by keybinds/autostart
    discord spotify helium-browser-bin

    # GRUB theme (ultragrub)
    wget

    # waybar tags module (parses mmsg JSON output)
    jq
)

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
if confirm "Install everything now? (builds -git AUR packages, can take a while)"; then
    "$AUR_HELPER" -S --needed "${PACKAGES[@]}"
    ok "Packages installed"
else
    warn "Skipped. The rest of the script continues, but the environment won't fully work until these are installed manually."
fi

# ---------- seat management (elogind) ----------
if [[ "$INIT_SYSTEM" != "systemd" ]]; then
    step "Enabling elogind ($INIT_SYSTEM)"
    case "$INIT_SYSTEM" in
        openrc)
            sudo rc-update add elogind boot || true
            sudo rc-service elogind start || true
            log_adapt "Enabled elogind in the boot runlevel via rc-update (OpenRC) — needed for mango to access DRM/input through libseat"
            ;;
        dinit)
            sudo dinitctl enable elogind || true
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
strip_other_sessions

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

            sudo sed -i "s|^ACTIVE_CONSOLES=.*|ACTIVE_CONSOLES=\"${new_active}\"|" "$CONSOLE_CONF"
            ok "Freed ${dinit_console} (dinit's own console) from ACTIVE_CONSOLES so ly can use it without fighting a getty"
            log_adapt "dinit: removed ${dinit_console} from $CONSOLE_CONF's ACTIVE_CONSOLES — without this, ly crash-loops with 'panic: reached unreachable code' because it and the getty on that tty fight over VT control. Requires a reboot to take effect."
            REBOOT_NEEDED_FOR_LY=1
        else
            warn "$CONSOLE_CONF not found or not in the expected format — skipping the console fix, check it by hand if ly crash-loops."
        fi

        sudo dinitctl enable ly || true
        if [[ "${REBOOT_NEEDED_FOR_LY:-0}" -eq 1 ]]; then
            ok "ly enabled (will start after your next reboot, needed for the console change above to take effect)"
        else
            sudo dinitctl start ly || true
            ok "ly enabled and started"
        fi
        log_adapt "Installed ly + ly-dinit and enabled it as the display manager"
        ;;

    openrc)
        sudo rc-update add ly default || true
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
        swaybg waypaper kanshi wlr-randr
        grim slurp
        dunst swaync libnotify
        swayosd brightnessctl pamixer swayidle
        wlogout wlsunset
        xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk
        xorg-x11-server-Xwayland
        jetbrains-mono-fonts google-noto-emoji-color-fonts
        pipewire pipewire-pulseaudio wireplumber
        discord
        wget jq
    )

    step "Packages (${#FEDORA_PACKAGES[@]})"
    info "${FEDORA_PACKAGES[*]}"
    warn "This list is best-effort: most of these are the same name in Fedora's repos as in Arch's, but it isn't as thoroughly verified as the Arch package list. Anything that fails to install is reported at the end instead of stopping the script."
    FEDORA_FAILED=()
    if confirm "Install everything now?"; then
        for pkg in "${FEDORA_PACKAGES[@]}"; do
            if ! sudo dnf install -y "$pkg"; then
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

    step "swaylock-effects (needs a COPR repo on Fedora)"
    if confirm "Enable the eddsalkield/swaylock-effects COPR and install it?"; then
        sudo dnf copr enable -y eddsalkield/swaylock-effects || true
        sudo dnf install -y swaylock-effects || warn "swaylock-effects install failed; falling back to plain swaylock."
        sudo dnf install -y swaylock || true
    fi

    step "materia-gtk-theme"
    sudo dnf install -y materia-gtk-theme 2>/dev/null || warn "materia-gtk-theme isn't in Fedora's repos on this release; the GTK settings below will still point to it, install it manually (e.g. from a COPR) if it doesn't show up."

    step "cliphist, wl-clipboard, wl-clip-persist, xfce-polkit, wmenu"
    for pkg in cliphist wl-clipboard wl-clip-persist xfce4-polkit wmenu; do
        sudo dnf install -y "$pkg" || warn "$pkg not found under that name in your Fedora repos — search 'dnf search $pkg' and adjust by hand."
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
        strip_other_sessions
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

    step "Discord & Spotify (Flatpak)"
    info "Fedora's repos don't carry Discord/Spotify; the repo's autostart.sh and keybinds expect the 'discord' and 'spotify' commands."
    if command -v flatpak >/dev/null 2>&1 || confirm "Install Flatpak, then Discord and Spotify through it?"; then
        command -v flatpak >/dev/null 2>&1 || sudo dnf install -y flatpak
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        flatpak install -y flathub com.discordapp.Discord com.spotify.Client || true
        mkdir -p "$HOME/.local/bin"
        printf '#!/bin/sh\nexec flatpak run com.discordapp.Discord "$@"\n' | sudo tee /usr/local/bin/discord >/dev/null
        printf '#!/bin/sh\nexec flatpak run com.spotify.Client "$@"\n' | sudo tee /usr/local/bin/spotify >/dev/null
        sudo chmod +x /usr/local/bin/discord /usr/local/bin/spotify
        log_adapt "Discord and Spotify installed via Flatpak, with /usr/local/bin/discord and /usr/local/bin/spotify wrapper scripts so the repo's existing 'discord'/'spotify' commands keep working unchanged"
    else
        warn "Skipped. Install Discord/Spotify yourself and make sure 'discord' and 'spotify' resolve to something, or edit config.conf/autostart.sh."
    fi

    warn "helium-browser has no Fedora package; the repo's helium-browser keybind/autostart line will do nothing until you install it manually or swap it for another browser."
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
    swaybg waypaper kanshi wlr-randr
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
    discord spotify
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
    ok "Copied"
fi
rm -rf "$CONFIG_DIR/.git" "$CONFIG_DIR/install.sh"

# ---------- corrections ----------
step "Applying corrections"

WAYBAR_JSONC="$CONFIG_DIR/waybar/config.jsonc"
AUTOSTART="$CONFIG_DIR/scripts/autostart.sh"
WLOGOUT_LAYOUT="$CONFIG_DIR/config/wlogout/layout"
WLOGOUT_THEME_SCRIPT="$CONFIG_DIR/scripts/wlogout-theme.sh"

# 1) waybar: systemctl -> loginctl (no systemd, running elogind)
if [[ -f "$WAYBAR_JSONC" ]]; then
    sed -i \
        -e 's/systemctl poweroff/loginctl poweroff/' \
        -e 's/systemctl reboot/loginctl reboot/' \
        "$WAYBAR_JSONC"
    log_adapt "waybar/config.jsonc: systemctl poweroff/reboot -> loginctl (no systemd here)"
fi

# 2) wlogout: hyprlock/hyprctl (Hyprland) don't exist here -> swaylock-effects/mmsg
#    (mango's IPC syntax >= 0.14.0)
if [[ -f "$WLOGOUT_LAYOUT" ]]; then
    sed -i \
        -e 's/"action" : "hyprlock"/"action" : "swaylock -f"/' \
        -e 's/"action" : "hyprctl dispatch exit"/"action" : "mmsg dispatch quit"/' \
        "$WLOGOUT_LAYOUT"
    log_adapt "config/wlogout/layout: hyprlock -> swaylock -f, hyprctl dispatch exit -> mmsg dispatch quit (those were Hyprland commands, not mango's; mmsg syntax updated for >= 0.14.0)"
fi

# 3) wlogout-theme.sh: BASE/TARGET have gone through several broken states
#    across repo edits (a quoted "~", which bash never expands; a hardcoded
#    /home/julia; and, most recently, still pointing at the old
#    kohagi_personal_configs/wlogout folder after it was renamed to
#    config/wlogout). Normalize both regardless of which state it's in.
if [[ -f "$WLOGOUT_THEME_SCRIPT" ]]; then
    sed -i -E \
        -e 's#^BASE=".*/\.config/mango/(kohagi_personal_configs|config)/wlogout"#BASE="'"${CONFIG_DIR}"'/config/wlogout"#' \
        -e 's#^TARGET=".*/\.config/wlogout"#TARGET="'"${HOME}"'/.config/wlogout"#' \
        "$WLOGOUT_THEME_SCRIPT"
    log_adapt "scripts/wlogout-theme.sh: BASE/TARGET normalized to \$CONFIG_DIR/config/wlogout and \$HOME/.config/wlogout (the file has pointed at a quoted ~, a hardcoded /home/julia, and the old kohagi_personal_configs path across different repo revisions)"
    # run it once now so ~/.config/wlogout is populated immediately
    bash "$WLOGOUT_THEME_SCRIPT" >/dev/null 2>&1 || true
fi

# 4) autostart.sh: swayosd-server and the polkit agent don't start on their own
#    without systemd --user; wire up a wallpaper fallback for waypaper's first run
if [[ -f "$AUTOSTART" ]]; then
    if ! grep -q "swayosd-server" "$AUTOSTART"; then
        printf '\npgrep -x swayosd-server >/dev/null || swayosd-server &\n' >> "$AUTOSTART"
        log_adapt "scripts/autostart.sh: added swayosd-server startup (used by volume.sh/brightness.sh but was never started)"
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
        log_adapt "scripts/autostart.sh: added a polkit agent startup (xfce-polkit) — nothing was providing GUI privilege prompts before"
    fi

    WALLPAPER_FALLBACK="$(find "$CONFIG_DIR/config" "$CONFIG_DIR/wallpaper" -maxdepth 2 \( -iname 'wallpaper*.png' -o -iname 'wallpaper*.jpg' \) 2>/dev/null | head -1)"
    if grep -qx 'waypaper --restore &' "$AUTOSTART" && ! grep -q 'swaybg -i' "$AUTOSTART" && [[ -n "$WALLPAPER_FALLBACK" ]]; then
        sed -i '/^waypaper --restore &$/c\
if [ -f "$HOME/.config/waypaper/config.ini" ]; then\
    waypaper --restore \&\
else\
    swaybg -i "'"${WALLPAPER_FALLBACK}"'" \&\
fi' "$AUTOSTART"
        log_adapt "scripts/autostart.sh: waypaper --restore does nothing on a fresh install (no saved state yet) -> falls back to swaybg with a bundled wallpaper so you get one immediately"
    elif [[ -z "$WALLPAPER_FALLBACK" ]]; then
        info "No wallpaper image bundled in the repo right now, so no swaybg fallback was set up — the desktop will have no wallpaper until you pick one with SUPER+F (waypaper)."
    fi

    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        sed -i 's/^dbus-update-activation-environment \\$/dbus-update-activation-environment --systemd \\/' "$AUTOSTART"
        log_adapt "scripts/autostart.sh: added --systemd to dbus-update-activation-environment (you're on systemd, this also propagates the env vars to systemd --user)"
    fi
fi

# 5) volume.sh: the mute notification pointed at an icon that doesn't exist anywhere in the repo
if [[ -f "$CONFIG_DIR/scripts/volume.sh" ]]; then
    sed -i 's#\${HOME}/\.config/rice_assets/Icons/mute\.png#/usr/share/icons/Adwaita/96x96/status/audio-volume-muted-symbolic.symbolic.png#' "$CONFIG_DIR/scripts/volume.sh"
    log_adapt "scripts/volume.sh: fixed the mute icon path (the old one doesn't exist anywhere in the repo)"
fi

# 6) waybar tags/workspaces module: only patch this if the repo still uses the
#    deprecated dwl/tags module. If it has already moved to ext/workspaces or
#    custom/tags, leave it alone.
if [[ -f "$WAYBAR_JSONC" ]] && grep -q '"dwl/tags"' "$WAYBAR_JSONC"; then
    mkdir -p "$CONFIG_DIR/scripts"
    cat > "$CONFIG_DIR/scripts/waybar-tags.sh" <<'TAGSEOF'
#!/bin/bash
# custom/tags module for waybar, reads mmsg directly (mango >= 0.14.0).
# Format of "mmsg get all-tags" / "mmsg watch all-tags":
# {"all_tags":[{"monitor":"eDP-1","tags":[{"index":1,"is_active":bool,"is_urgent":bool,"client_count":n}, ...]}]}

# MANGO_INSTANCE_SIGNATURE sometimes isn't inherited from the parent process
# (seen on -git builds). If it's missing, find the socket ourselves.
if [[ -z "${MANGO_INSTANCE_SIGNATURE:-}" ]]; then
    sig="$(find "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" /tmp -maxdepth 2 -type s -iname '*mango*' 2>/dev/null | head -1)"
    [[ -n "$sig" ]] && export MANGO_INSTANCE_SIGNATURE="$sig"
fi

render() {
    jq -c '
        .all_tags[0].tags as $tags
        | ($tags | map(
            if .is_urgent then
                "<span foreground=\"#f38ba8\"><b>" + (.index|tostring) + "</b></span>"
            elif .is_active then
                "<span foreground=\"#cba6f7\"><b>[" + (.index|tostring) + "]</b></span>"
            elif .client_count > 0 then
                (.index|tostring)
            else
                empty
            end
          ) | join(" ")) as $out
        | {text: $out, tooltip: "mango tags"}
    '
}

mmsg get all-tags | render
mmsg watch all-tags | while IFS= read -r line; do
    [[ -n "$line" ]] && printf '%s\n' "$line" | render
done
TAGSEOF
    chmod +x "$CONFIG_DIR/scripts/waybar-tags.sh"

    sed -i 's/"dwl\/tags",/"custom\/tags",/' "$WAYBAR_JSONC"
    sed -i '/"dwl\/tags": {/,/^    },/c\
    "custom/tags": {\
        "exec": "'"${CONFIG_DIR}"'/scripts/waybar-tags.sh",\
        "return-type": "json",\
        "restart-interval": 0\
    },' "$WAYBAR_JSONC"
    log_adapt "waybar/config.jsonc: dwl/tags -> custom/tags reading mmsg directly (dwl-ipc is deprecated in mango, and wlr/workspaces isn't compiled into the Arch/Artix waybar package; exec uses an absolute path because ~ doesn't reliably expand in waybar's exec)"
fi

# 7) config.conf: tag 1's tagrule is missing the "tagrule" prefix (a broken
#    line that has no effect and could confuse the parser)
if [[ -f "$CONFIG_DIR/config.conf" ]] && grep -qx '=id:1,layout_name:scroller' "$CONFIG_DIR/config.conf"; then
    sed -i 's/^=id:1,layout_name:scroller$/#&  # broken line (missing the "tagrule" prefix) - commented out by install.sh/' "$CONFIG_DIR/config.conf"
    log_adapt "config.conf: commented out the line '=id:1,layout_name:scroller' (missing the 'tagrule=' prefix, had no effect and could confuse the parser). If you actually wanted tag 1 on the scroller layout instead of tile, let me know and I'll fix it properly."
fi

# 8) Discord screen sharing needs --ozone-platform=wayland and the PipeWire
#    capturer feature flag. Both scripts.sh/autostart.sh's "discord &" and
#    config.conf's SUPER+A bind have gone back and forth between having these
#    flags and not across repo edits — force them on in both places.
if [[ -f "$AUTOSTART" ]] && grep -qx 'discord &' "$AUTOSTART"; then
    sed -i 's/^discord &$/discord --enable-features=UseOzonePlatform,WebRTCPipeWireCapturer --ozone-platform=wayland \&/' "$AUTOSTART"
    log_adapt "scripts/autostart.sh: discord now launches with --ozone-platform=wayland + WebRTCPipeWireCapturer (screen sharing silently breaks without these)"
fi
if [[ -f "$CONFIG_DIR/config.conf" ]] && grep -qx 'bind=SUPER,a,spawn,discord' "$CONFIG_DIR/config.conf"; then
    sed -i 's/^bind=SUPER,a,spawn,discord$/bind=SUPER,a,spawn,discord --enable-features=UseOzonePlatform,WebRTCPipeWireCapturer --ozone-platform=wayland/' "$CONFIG_DIR/config.conf"
    log_adapt "config.conf: SUPER+A now launches Discord with the same --ozone-platform=wayland/PipeWire flags, so screen sharing works no matter how you opened it"
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

# 10) mango can't bind btn_left/btn_right with modifier NONE (this is a known
#     engine limitation, not a config mistake — upstream's own example config
#     has the exact same comment). It logs an error and just skips the bind,
#     but toggleoverview/killclient already have working keybinds elsewhere
#     (ALT+Tab, SUPER+q), so these two lines are pure noise on every start.
if [[ -f "$CONFIG_DIR/config.conf" ]] && grep -q '^mousebind=NONE,btn_\(left\|right\),' "$CONFIG_DIR/config.conf"; then
    sed -i -E 's/^(mousebind=NONE,btn_(left|right),.*)$/# \1  # mango can'"'"'t bind btn_left\/btn_right with NONE - already bound to ALT+Tab \/ SUPER+q/' "$CONFIG_DIR/config.conf"
    log_adapt "config.conf: commented out mousebind=NONE,btn_left/btn_right (mango rejects NONE as a modifier for those two buttons — it's a known engine limitation, and both actions already have working keybinds: ALT+Tab and SUPER+q)"
fi

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
    sed -i "s#/sys/class/hwmon/hwmon[0-9]*/temp1_input#${hwmon_path}#" "$WAYBAR_JSONC"
    ok "Sensor: $hwmon_path"
    log_adapt "waybar/config.jsonc: hwmon-path was hardcoded (hwmon4) -> auto-detected as $hwmon_path"
else
    warn "Couldn't auto-detect the sensor. Set 'hwmon-path' in $WAYBAR_JSONC by hand (run 'sensors' or check /sys/class/hwmon/*/name)."
fi

# ---------- monitor detection (kanshi profile, native/max resolution+refresh) ----------
step "Monitor detection"
DETECTED_OUTPUTS=()
DETECTED_WIDTHS=()
for status_file in /sys/class/drm/card*-*/status; do
    [[ -r "$status_file" ]] || continue
    [[ "$(cat "$status_file" 2>/dev/null)" == "connected" ]] || continue
    conn_dir="$(dirname "$status_file")"
    raw_name="$(basename "$conn_dir")"
    out_name="${raw_name#card*-}"
    out_width=1920
    if [[ -r "$conn_dir/modes" ]]; then
        first_mode="$(head -1 "$conn_dir/modes" 2>/dev/null || true)"
        [[ "$first_mode" == *x* ]] && out_width="${first_mode%%x*}"
    fi
    DETECTED_OUTPUTS+=("$out_name")
    DETECTED_WIDTHS+=("$out_width")
done

OUTPUTS=()
WIDTHS=()
if [[ "${#DETECTED_OUTPUTS[@]}" -gt 0 ]]; then
    info "Detected connected output(s): ${DETECTED_OUTPUTS[*]}"
    if confirm "Use these for the kanshi profile?"; then
        OUTPUTS=("${DETECTED_OUTPUTS[@]}")
        WIDTHS=("${DETECTED_WIDTHS[@]}")
    fi
else
    warn "No connected output found automatically (checked /sys/class/drm/*/status)."
fi

if [[ "${#OUTPUTS[@]}" -eq 0 ]]; then
    read -rp "Enter your monitor output name(s), space-separated (e.g. DP-1 HDMI-A-1), or leave empty to skip: " -a OUTPUTS
    for _ in "${OUTPUTS[@]}"; do WIDTHS+=(1920); done
fi

if [[ "${#OUTPUTS[@]}" -gt 0 ]]; then
    mkdir -p "$HOME/.config/kanshi"
    {
        echo "profile auto {"
        x=0
        for i in "${!OUTPUTS[@]}"; do
            echo "    output ${OUTPUTS[$i]} enable position $x,0"
            x=$((x + WIDTHS[i]))
        done
        echo "}"
    } > "$HOME/.config/kanshi/config"
    ok "kanshi profile written for: ${OUTPUTS[*]}"
    info "No explicit mode was set on purpose: the compositor will use each display's native/preferred mode, which is normally its maximum resolution and refresh rate."
    log_adapt "kanshi: auto-generated a profile for the detected output(s) (${OUTPUTS[*]}) instead of the repo's hardcoded DP-1/HDMI-A-1 profile, using each display's native mode (max resolution+Hz) rather than a fixed one"
else
    warn "No monitor configured for kanshi. Falling back to the repo's bundled two-monitor profile (DP-1 + HDMI-A-1) as a starting point — edit ~/.config/kanshi/config if your outputs are named differently."
    KANSHI_SRC="$CONFIG_DIR/config/kanshi (if_u_have_2_monitors)/config"
    if [[ -f "$KANSHI_SRC" ]]; then
        mkdir -p "$HOME/.config/kanshi"
        cp "$KANSHI_SRC" "$HOME/.config/kanshi/config"
    fi
fi

# ---------- keyboard layout ----------
step "Keyboard layout"
echo "    1) us       — US"
echo "    2) br       — Brazil (ABNT2)"
echo "    3) br-intl  — Brazil (ABNT2, international/dead-key variant)"
echo "    4) de       — Germany"
echo "    5) fr       — France"
echo "    6) es       — Spain"
echo "    7) gb       — UK"
echo "    8) it       — Italy"
echo "    9) pt       — Portugal"
echo "    10) other (type the code yourself)"
kb_reply=""
while [[ ! "$kb_reply" =~ ^([1-9]|10)$ ]]; do
    read -rp "Pick your keyboard layout [1-10]: " kb_reply
done
KB_VARIANT=""
case "$kb_reply" in
    1)  KB_LAYOUT="us"; KB_CONSOLE="us" ;;
    2)  KB_LAYOUT="br"; KB_CONSOLE="br-abnt2" ;;
    3)  KB_LAYOUT="br"; KB_VARIANT="intl"; KB_CONSOLE="br-abnt2" ;;
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

# Defensive: if someone typed setxkbmap-style "layout(variant)" in a custom
# entry (e.g. "br(intl)"), split it instead of writing that literal string
# into xkb_rules_layout — mango expects layout and variant as separate
# fields, and xkbcommon fails to compile the keymap otherwise.
if [[ "$KB_LAYOUT" =~ ^([a-zA-Z0-9_-]+)\(([a-zA-Z0-9_-]+)\)$ ]]; then
    KB_VARIANT="${BASH_REMATCH[2]}"
    KB_LAYOUT="${BASH_REMATCH[1]}"
fi

if [[ -n "$KB_LAYOUT" && -f "$CONFIG_DIR/config.conf" ]]; then
    if grep -q '^xkb_rules_layout=' "$CONFIG_DIR/config.conf"; then
        sed -i "s/^xkb_rules_layout=.*/xkb_rules_layout=${KB_LAYOUT}/" "$CONFIG_DIR/config.conf"
    else
        printf '\n# keyboard layout (set by install.sh)\nxkb_rules_layout=%s\n' "$KB_LAYOUT" >> "$CONFIG_DIR/config.conf"
    fi
    if grep -q '^xkb_rules_variant=' "$CONFIG_DIR/config.conf"; then
        sed -i "s/^xkb_rules_variant=.*/xkb_rules_variant=${KB_VARIANT}/" "$CONFIG_DIR/config.conf"
    elif [[ -n "$KB_VARIANT" ]]; then
        sed -i "/^xkb_rules_layout=${KB_LAYOUT}$/a xkb_rules_variant=${KB_VARIANT}" "$CONFIG_DIR/config.conf"
    fi
    ok "config.conf: xkb_rules_layout=$KB_LAYOUT${KB_VARIANT:+, xkb_rules_variant=$KB_VARIANT}"
    log_adapt "config.conf: keyboard layout set to '$KB_LAYOUT'${KB_VARIANT:+ (variant: $KB_VARIANT)}"
fi

if [[ -n "${KB_CONSOLE:-}" ]]; then
    if [[ -f /etc/vconsole.conf ]] && grep -q '^KEYMAP=' /etc/vconsole.conf; then
        sudo sed -i "s/^KEYMAP=.*/KEYMAP=${KB_CONSOLE}/" /etc/vconsole.conf
    else
        printf 'KEYMAP=%s\n' "$KB_CONSOLE" | sudo tee -a /etc/vconsole.conf >/dev/null
    fi
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        sudo localectl set-keymap "$KB_CONSOLE" 2>/dev/null || true
    else
        sudo loadkeys "$KB_CONSOLE" 2>/dev/null || true
    fi
    ok "Console/TTY keymap: $KB_CONSOLE (/etc/vconsole.conf)"
    log_adapt "Console keymap set to $KB_CONSOLE, matching the $KB_LAYOUT layout in config.conf — so a bare TTY and the shell before mango even starts use the same layout, not just the graphical session"
fi


step "GTK theme (Materia-dark)"
mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
for gtk_ini in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
    cat > "$gtk_ini" <<GTKEOF
[Settings]
gtk-theme-name=Materia-dark
gtk-icon-theme-name=Adwaita
gtk-cursor-theme-name=Animated-Mew-Cursor
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=1
GTKEOF
done
cat > "$HOME/.gtkrc-2.0" <<GTK2EOF
gtk-theme-name="Materia-dark"
gtk-cursor-theme-name="Animated-Mew-Cursor"
gtk-cursor-theme-size=24
GTK2EOF
if [[ -f "$AUTOSTART" ]] && ! grep -q "GTK_THEME" "$AUTOSTART"; then
    sed -i '/^export XCURSOR_THEME=/i export GTK_THEME=Materia-dark:dark' "$AUTOSTART"
fi
ok "gtk-3.0/gtk-4.0 settings.ini and ~/.gtkrc-2.0 written"
log_adapt "GTK theme: applied Materia-dark the same way nwg-look would (gtk-3.0/gtk-4.0 settings.ini + ~/.gtkrc-2.0 + GTK_THEME env var), together with the Animated-Mew-Cursor cursor"

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
background_opacity 0.6
font_size 13
font_family JetBrainsMono Nerd Font
KITTYEOF
ok "~/.config/kitty/kitty.conf"

# ---------- permissions ----------
step "Fixing permissions"
find "$CONFIG_DIR" -name '*.sh' -exec chmod +x {} \;
ok "Scripts marked executable"

# ---------- cursor ----------
step "Cursor (Animated-Mew-Cursor)"
CURSOR_SRC="$CONFIG_DIR/config/Animated-Mew-Cursor"
CURSOR_DST="$HOME/.local/share/icons/Animated-Mew-Cursor"
if [[ -d "$CURSOR_SRC" ]]; then
    mkdir -p "$HOME/.local/share/icons"
    rm -rf "$CURSOR_DST"
    cp -a "$CURSOR_SRC" "$CURSOR_DST"
    find "$CURSOR_DST" -maxdepth 1 -name '.~lock.*#' -delete 2>/dev/null
    ok "Cursor copied from the repo to $CURSOR_DST"
    log_adapt "Cursor: the Animated-Mew-Cursor theme now ships in the repo -> copied to ~/.local/share/icons/"

    # index.theme should be plain text ([Icon Theme]...); in the repo right
    # now it's saved as OpenDocument Text, not the actual theme file.
    if [[ -f "$CURSOR_DST/index.theme" ]] && ! head -c 200 "$CURSOR_DST/index.theme" 2>/dev/null | grep -q '\[Icon Theme\]'; then
        warn "$CURSOR_DST/index.theme isn't a valid theme file (looks like 'OpenDocument Text', not plain text)."
        info "The files under cursors/ are real X11 cursors and should still work via XCURSOR_THEME,"
        info "but index.theme/cursor.theme need to be fixed in the repo (looks like a .odt got committed in the wrong place)."
    fi
elif [[ -d "$HOME/.local/share/icons/Animated-Mew-Cursor" || -d "$HOME/.icons/Animated-Mew-Cursor" || -d "/usr/share/icons/Animated-Mew-Cursor" ]]; then
    ok "Cursor theme already present"
else
    warn "The 'Animated-Mew-Cursor' theme wasn't found in the repo or already installed. Grab it manually:"
    info "https://www.gnome-look.org/c/2326996"
    info "Extract it to ~/.local/share/icons/Animated-Mew-Cursor"
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
check_cmd mango
check_cmd waybar
check_cmd kitty
check_cmd fish
check_cmd mmsg
check_file "$CONFIG_DIR/config.conf" "config.conf deployed"
check_file "$HOME/.config/wlogout/layout" "wlogout theme deployed"
check_file "$HOME/.local/share/icons/Animated-Mew-Cursor" "cursor theme installed"
if [[ "$HEALTH_OK" -eq 1 ]]; then
    ok "Everything checks out"
else
    warn "Some things above are missing — scroll up for what failed, or just re-run the script; it's safe to run more than once."
fi

# ---------- summary ----------
echo
box "Done — welcome to Mango" "$c_green"
info "Init system: $INIT_SYSTEM"
if [[ "${#ADAPTATIONS[@]}" -gt 0 ]]; then
    printf "\n${c_bold}${c_mauve}Adaptations made${c_reset} ${c_sub}(the original repo had these broken or incomplete)${c_reset}\n"
    for a in "${ADAPTATIONS[@]}"; do
        printf "  ${c_mauve}›${c_reset} %s\n" "$a"
    done
fi
printf "\n${c_bold}${c_yellow}Worth double-checking by hand${c_reset}\n"
info "Monitor output names picked for kanshi: ${OUTPUTS[*]:-none} — run 'wlr-randr' once mango is running to confirm they match"
info "The Animated-Mew-Cursor theme, if it wasn't already installed (see the warning above)"
info "Pick a wallpaper with SUPER+F (waypaper) any time you want to change it"
echo
printf "${c_bold}${c_blue}To start:${c_reset} log in on a TTY and run '%bmango%b', or pick Mango from ly's session list.\n" "$c_mauve" "$c_reset"
echo