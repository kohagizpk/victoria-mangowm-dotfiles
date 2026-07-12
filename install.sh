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

# ---------- helpers ----------
c_reset='\033[0m'; c_bold='\033[1m'; c_green='\033[1;32m'; c_yellow='\033[1;33m'; c_red='\033[1;31m'; c_blue='\033[1;34m'

step()  { printf "\n${c_blue}==>${c_reset} ${c_bold}%s${c_reset}\n" "$1"; }
info()  { printf "    %s\n" "$1"; }
ok()    { printf "${c_green}[ok]${c_reset} %s\n" "$1"; }
warn()  { printf "${c_yellow}[warn]${c_reset} %s\n" "$1"; }
err()   { printf "${c_red}[error]${c_reset} %s\n" "$1"; }

confirm() {
    local reply
    read -rp "$1 [y/N] " reply
    [[ "$reply" =~ ^[yY]$ ]]
}

ADAPTATIONS=()
log_adapt() { ADAPTATIONS+=("$1"); }

# ---------- initial checks ----------
if [[ "${EUID}" -eq 0 ]]; then
    err "Don't run this as root. Run it as your normal user (it will ask for sudo when needed)."
    exit 1
fi

if ! command -v pacman >/dev/null 2>&1; then
    err "pacman not found. This script targets Arch/Artix/CachyOS and other pacman-based distros."
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

echo -e "${c_bold}victoria-mangowm-dotfiles installer${c_reset}"
info "Source: $SOURCE_DIR"
info "Target: $CONFIG_DIR"
info "Init system: $INIT_SYSTEM"
if ! confirm "Start?"; then
    exit 0
fi

# ---------- systemd-libs dummy (Artix) ----------
# AUR packages (built for vanilla Arch) commonly depend on systemd/systemd-libs.
# On Artix with libelogind this causes a file conflict; the official fix is to
# install artix-archlinux-support, which provides dummy systemd/systemd-libs.
if [[ "$INIT_SYSTEM" != "systemd" ]] && pacman -Si artix-archlinux-support >/dev/null 2>&1; then
    step "systemd-libs dummy (Artix)"
    sudo pacman -S --needed --noconfirm artix-archlinux-support
    ok "artix-archlinux-support installed"
    log_adapt "Installed artix-archlinux-support before anything else -> avoids the libelogind vs systemd-libs conflict when installing AUR packages built for vanilla Arch (mango, discord, etc.)"
fi

# ---------- AUR helper ----------
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

# ---------- packages ----------
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
    ttf-jetbrains-mono-nerd

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

# Create a Wayland session entry so ly (or any other display manager) can
# list Mango, in case the mangowm-git package doesn't ship one.
if [[ ! -f /usr/share/wayland-sessions/mango.desktop ]]; then
    sudo mkdir -p /usr/share/wayland-sessions
    sudo tee /usr/share/wayland-sessions/mango.desktop >/dev/null <<'LYEOF'
[Desktop Entry]
Name=Mango
Comment=MangoWM, a dwl-based Wayland compositor
Exec=mango
Type=Application
LYEOF
    log_adapt "Created /usr/share/wayland-sessions/mango.desktop so display managers can list Mango as a session"
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
            sudo systemctl enable ly.service
            ok "ly enabled as the display manager"
            log_adapt "Installed and enabled ly.service as the display manager — Mango now shows up as a selectable session on the login screen"
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

# 3) wlogout-theme.sh: BASE/TARGET used a quoted "~", which bash does NOT expand
#    inside double quotes -> the script was silently operating on a literal
#    "~/..." path that doesn't exist. Use $HOME instead, which does expand.
if [[ -f "$WLOGOUT_THEME_SCRIPT" ]]; then
    sed -i \
        -e 's#BASE="~/\.config/mango/config/wlogout"#BASE="$HOME/.config/mango/config/wlogout"#' \
        -e 's#TARGET="~/\.config/wlogout"#TARGET="$HOME/.config/wlogout"#' \
        -e 's#BASE="/home/julia/\.config/mango/config/wlogout"#BASE="$HOME/.config/mango/config/wlogout"#' \
        -e 's#TARGET="/home/julia/\.config/wlogout"#TARGET="$HOME/.config/wlogout"#' \
        "$WLOGOUT_THEME_SCRIPT"
    log_adapt "scripts/wlogout-theme.sh: BASE/TARGET now use \$HOME instead of a hardcoded /home/julia path or a quoted ~ (which bash never expands inside quotes)"
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

    if grep -qx 'waypaper --restore &' "$AUTOSTART" && ! grep -q 'swaybg -i' "$AUTOSTART"; then
        sed -i '/^waypaper --restore &$/c\
if [ -f "$HOME/.config/waypaper/config.ini" ]; then\
    waypaper --restore \&\
else\
    swaybg -i "'"${CONFIG_DIR}"'/config/wallpaper/wallpaper.png" \&\
fi' "$AUTOSTART"
        log_adapt "scripts/autostart.sh: waypaper --restore does nothing on a fresh install (no saved state yet) -> falls back to swaybg with the bundled wallpaper so you get one immediately"
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

# 8) config.conf: the SUPER+A keybind launches plain "discord", without the
#    Wayland/PipeWire flags that autostart.sh already uses. Screen sharing
#    only works with those flags, so any Discord window opened via this bind
#    (instead of the one autostart launched) would have broken screen share.
if [[ -f "$CONFIG_DIR/config.conf" ]] && grep -qx 'bind=SUPER,a,spawn,discord' "$CONFIG_DIR/config.conf"; then
    sed -i 's/^bind=SUPER,a,spawn,discord$/bind=SUPER,a,spawn,discord --enable-features=UseOzonePlatform,WebRTCPipeWireCapturer --ozone-platform=wayland/' "$CONFIG_DIR/config.conf"
    log_adapt "config.conf: SUPER+A now launches Discord with the same --ozone-platform=wayland/PipeWire flags as autostart.sh, so screen sharing works no matter how you opened it"
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

# ---------- GTK theme (Materia-dark, the same files nwg-look would write) ----------
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
    # the referenced ascii.txt doesn't exist in the repo; without this fix
    # fastfetch's logo would break. Removing the line falls back to the
    # distro's own auto-detected logo, which just works.
    sed -i '\#"source": "~/.config/fastfetch/ascii.txt"#d' "$HOME/.config/fastfetch/config.jsonc"
    ok "~/.config/fastfetch/config.jsonc"
    log_adapt "fastfetch: the custom logo (ascii.txt) doesn't exist in the repo -> removed, falls back to the distro's automatic logo"
fi

# ---------- terminal welcome image ----------
step "Terminal image"
mkdir -p "$HOME/img_terminal"
EXAMPLE_IMG="$CONFIG_DIR/config/terminal_configs/img_terminal/example.png"
if [[ -f "$EXAMPLE_IMG" && -z "$(ls -A "$HOME/img_terminal" 2>/dev/null)" ]]; then
    cp "$EXAMPLE_IMG" "$HOME/img_terminal/"
    ok "Example image copied to ~/img_terminal/"
    log_adapt "~/img_terminal/ was empty -> seeded with the repo's bundled example.png so random_image.sh has something to show immediately"
else
    ok "~/img_terminal/ ready (add your own images any time)"
fi

# ---------- random_image.sh + fish ----------
step "Configuring the terminal welcome script"
RANDIMG_SRC="$CONFIG_DIR/config/terminal_configs/random_image.sh"
if [[ -f "$RANDIMG_SRC" ]]; then
    cp "$RANDIMG_SRC" "$HOME/random_image.sh"
    chmod +x "$HOME/random_image.sh"
    ok "~/random_image.sh"

    FISH_CONFIG="$HOME/.config/fish/config.fish"
    mkdir -p "$HOME/.config/fish"
    touch "$FISH_CONFIG"
    if ! grep -q "random_image.sh" "$FISH_CONFIG"; then
        cat >> "$FISH_CONFIG" <<'EOF'

# victoria-mangowm-dotfiles: random image + fastfetch on every new terminal
if status is-interactive
    and test -f "$HOME/random_image.sh"
    bash "$HOME/random_image.sh"
end
EOF
        ok "Hooked into ~/.config/fish/config.fish"
        log_adapt "fish: random_image.sh was never actually called by anything -> now runs automatically in every interactive shell"
    else
        info "~/.config/fish/config.fish already calls random_image.sh"
    fi
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
if [[ -d "$ULTRAGRUB_DIR" ]]; then
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

# ---------- summary ----------
step "Done"
info "Init system: $INIT_SYSTEM"
if [[ "${#ADAPTATIONS[@]}" -gt 0 ]]; then
    echo -e "${c_bold}Adaptations made (the original repo had these broken or incomplete):${c_reset}"
    for a in "${ADAPTATIONS[@]}"; do
        printf "  - %s\n" "$a"
    done
fi
echo
echo -e "${c_bold}Worth double-checking by hand:${c_reset}"
info "Monitor output names picked for kanshi: ${OUTPUTS[*]:-none} — run 'wlr-randr' once mango is running to confirm they match"
info "The Animated-Mew-Cursor theme, if it wasn't already installed (see the warning above)"
info "Pick a wallpaper with SUPER+F (waypaper) any time you want to change it"
echo
info "To start: log in on a TTY and run 'mango'"