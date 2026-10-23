#!/usr/bin/env bash
# Sourced after package installation.
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

# ---------- monitors: generated native Mango rules ----------
step "Detecting connected monitors"
python3 "$CONFIG_DIR/scripts/monitors.py" --output "$CONFIG_DIR/monitor.conf"
log_adapt "monitor.conf: detected DRM outputs, preferred resolution and highest advertised refresh at that resolution; personal rules take precedence."

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

# Apply the explicitly chosen keyboard over any previously migrated override.
sed -i '/^xkb_rules_layout[[:space:]]*=/d; /^xkb_rules_variant[[:space:]]*=/d' "$CONFIG_DIR/local/input.conf"
printf '\nxkb_rules_layout=%s\nxkb_rules_variant=%s\n' "$KB_LAYOUT" "$KB_VARIANT" >> "$CONFIG_DIR/local/input.conf"

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
CURSOR_NAME="${CURSOR_NAME:-Animated-Mew-Cursor}"

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
cp "$VICTORIA_PROJECT_ROOT/config/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
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
info "monitor.conf: generated for detected hardware; customize ~/.config/mango/local/monitor.conf (preserved on updates)."
info "The cursor theme name in config.conf (cursor_theme=) — see the warning above if that theme isn't installed"
info "Pick a wallpaper with SUPER+F (waypaper) any time you want to change it — wallust will regenerate colors automatically from then on"
# info "Spicetify: autostart.sh runs 'spicetify backup apply' every login, but that needs one manual first-time setup after logging into Spotify — run 'spicetify backup apply' yourself once, following spicetify's own setup guide, before it'll do anything on autostart"
echo
printf "${c_bold}${c_blue}To start:${c_reset} log in on a TTY and run '%bmango%b', or pick Mango from ly's session list.\n" "$c_mauve" "$c_reset"
echo