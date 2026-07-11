# Victoria's MangoWM Dotfiles

Personal dotfiles for a [mango](https://github.com/DreamMaoMao/mango) (dwl-based Wayland compositor) desktop, tuned for Arch-based systems. Styled with Waybar, a full Wayland utility stack, and an installer that adapts itself to your init system.

https://github.com/user-attachments/assets/9dbbe4a3-2a75-49df-aee3-562ab775e16b

## Features

- **Window manager:** [mango](https://github.com/DreamMaoMao/mango) — a dwl-based Wayland compositor
- **Status bar:** Waybar, with a CPU temperature sensor that is auto-detected on install, MPRIS media controls, and a calendar popup
- **App launcher:** rofi
- **Clipboard manager:** cliphist, picked through fuzzel
- **Notifications & OSD:** swaync/dunst for notifications, swayosd for on-screen volume and brightness feedback
- **Screenshots:** grim + slurp
- **Logout menu:** wlogout
- **Multi-monitor:** kanshi, with a saved profile for two-monitor setups
- **Shell:** fish, showing fastfetch and a random image on every new terminal
- **Terminal:** kitty
- **Cursor theme:** Animated-Mew-Cursor
- **Bootloader theming (optional):** UltraGrub GRUB theme, plus a patch that cleans up boot entries (e.g. tidies the Windows entry)
- **Init-system aware installer:** detects and supports systemd, OpenRC, and dinit, and configures elogind for seat management automatically when you're not on systemd

## Keybindings

| Keybind            | Action                                |
| ------------------ | -------------------------------------- |
| SUPER + D          | App launcher (rofi)                    |
| SUPER + V          | Clipboard history (cliphist + fuzzel)  |
| SUPER + Shift + S   | Screenshot                             |
| SUPER + Enter      | Terminal (kitty)                       |
| SUPER + E          | File manager (nemo)                    |
| SUPER + W          | Browser (helium)                       |
| SUPER + A          | Discord                                |
| SUPER + S          | Spotify                                |
| SUPER + F          | Wallpaper selector (waypaper)          |
| SUPER + Q          | Close active window                    |
| ALT + F            | Toggle fullscreen                      |
| ALT + M            | Quit window manager                    |

## Requirements

- Arch, Artix, CachyOS, or any other pacman-based distro
- An AUR helper (`yay` or `paru`) — the installer will offer to install `yay` for you if neither is found
- `git`

## How to install?

```bash
cd
mkdir .config
cd .config
git clone https://github.com/kohagizpk/victoria-mangowm-dotfiles.git
mv victoria-mangowm-dotfiles mango
cd mango
chmod +x install.sh
./install.sh
```

The script is interactive and will ask for confirmation before any potentially destructive step. Here's what it does, in order:

1. Detects your init system (systemd / OpenRC / dinit) and, if you're not on systemd, sets up `elogind` so mango can access DRM/input through libseat.
2. Installs an AUR helper (`yay`) automatically if you don't already have one.
3. Installs every required package: the compositor, Waybar, launchers, portals, the PipeWire audio stack, fonts, and bundled apps (Discord, Spotify, Helium browser).
4. Patches a handful of paths and commands that were specific to the original machine (wallpaper paths, systemd-only power commands, a couple of missing binaries) so the config works out of the box on a fresh install.
5. Auto-detects your CPU temperature sensor and wires it into the Waybar config.
6. Sets up fastfetch, kanshi, and the terminal welcome script in their proper locations outside `~/.config/mango`.
7. Optionally installs the UltraGrub GRUB theme, adds your user to the `video` group (needed for brightness control via swayosd), and sets fish as your default shell.

## Repository structure

```
.
├── assets/                  # Media used in this README
├── kohagi_personal_configs/ # Wallpapers, terminal config, cursor theme, kanshi profile, GRUB theme
├── scripts/                 # Helper scripts (print, wlogout, calendar etc.)
├── waybar/                  # Waybar config and stylesheet
├── config.conf              # Main mango compositor config
└── install.sh               # Automated installer
```

## Known issues

- `install.sh` may still not work perfectly on every machine — read its output carefully, it logs every adaptation it makes.
- Monitor names used by kanshi/autostart (e.g. `DP-1`, `HDMI-A-1`) are hardware-specific. Run `wlr-randr` to confirm yours before relying on the two-monitor 