#!/usr/bin/env bash
# Sourced by full.sh after distribution, init and choices have been validated.
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
    xdg-utils xorg-xrdb

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

# ---------- optional audio inhibitor ----------
# The AUR package has a -git suffix; the executable does not. Install this
# convenience feature separately so its availability cannot block the desktop.
install_audio_inhibitor() {
    if command -v sway-audio-idle-inhibit >/dev/null 2>&1; then
        info "Audio idle inhibitor already installed"
    elif run "$AUR_HELPER" -S --needed --noconfirm sway-audio-idle-inhibit-git; then
        ok "Optional audio idle inhibitor installed"
    else
        warn "Could not install optional sway-audio-idle-inhibit-git; continuing without audio-based idle inhibition."
        log_adapt "Optional audio idle inhibitor skipped. Retry later: $AUR_HELPER -S --needed sway-audio-idle-inhibit-git"
    fi
}

step "Packages (${#PACKAGES[@]})"
info "${PACKAGES[*]}"
info "Using --noconfirm so this doesn't sit waiting on an easy-to-miss prompt (e.g. picking between multiple providers for the same package)."
if confirm "Install everything now? (builds -git AUR packages, can take a while)"; then
    run "$AUR_HELPER" -S --needed --noconfirm "${PACKAGES[@]}"
    ok "Packages installed"
    install_audio_inhibitor
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
