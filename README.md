# Victoria's MangoWM Dotfiles

Personal dotfiles for a [mango](https://github.com/mangowm/mango) (dwl-based Wayland compositor) desktop — Waybar, a full Wayland utility stack, GRUB theming, and an installer that adapts itself to your distro, your init system, and your hardware.

https://github.com/user-attachments/assets/cb902017-0d69-4222-970d-5467773197c4

## Features

- **Window manager:** [mango](https://github.com/mangowm/mango) — a dwl-based Wayland compositor
- **Status bar:** Waybar, with a CPU temperature sensor auto-detected on install, a live tags module read straight from mango's own IPC, MPRIS media controls, and a calendar popup
- **App launcher:** rofi, plus fuzzel for the clipboard picker
- **Clipboard manager:** cliphist
- **Notifications & OSD:** swaync for notifications, swayosd for on-screen volume/brightness feedback
- **Screenshots:** grim + slurp
- **Logout menu:** wlogout, themed
- **Wallpaper:** waypaper (SUPER+F), with a bundled fallback wallpaper for the first boot
- **Multi-monitor:** native `monitor_rule=` lines in `monitor.conf` (mango doesn't implement `wlr-output-management`, so kanshi/wlr-randr can't be used). The file ships with the author's monitors (DP-1 @165 Hz + HDMI-A-1) — edit the output names/modes for your own setup
- **Wallpaper-driven colors:** wallust regenerates `colors.conf` (mango borders) and `waybar/colors.css` every time waypaper changes the wallpaper; mango hot-reloads on its own (`auto_reload_config`)
- **Keyboard layout:** picked from a short menu during install and applied both to mango (`xkb_rules_layout`/`xkb_rules_variant`) and to the raw console (`/etc/vconsole.conf`), so it's consistent whether you're at a bare TTY or inside the graphical session
- **GTK theming:** Materia-dark applied the same way `nwg-look` would (gtk-3.0/gtk-4.0 `settings.ini`, `~/.gtkrc-2.0`, `GTK_THEME` env var)
- **Shell:** fish, with the greeting disabled and fastfetch shown on every new terminal
- **Terminal:** kitty
- **Cursor theme:** whatever `cursor_theme=` says in `config.conf` (currently `Samuel-Noticias-Cursor`). If a folder with that name exists in `config/`, the installer copies it to `~/.local/share/icons`; otherwise it only checks that the theme is installed
- **Bootloader theming (optional):** UltraGrub GRUB theme, plus a patch that cleans up boot entries (e.g. tidies the Windows entry for dual-boot)
- **Display manager (optional):** [ly](https://github.com/fairyglade/ly), set up so Mango is the only session in the list
- **Discord screen sharing** wired up correctly (`--ozone-platform=wayland` + PipeWire capturer) wherever Discord gets launched from

### The installer

- **Multi-distro:** Arch/Artix/CachyOS/EndeavourOS (pacman), Fedora (dnf, best-effort), and NixOS (writes a config snippet instead of installing anything imperatively, since that's not how NixOS works)
- **Init-system aware:** detects systemd / OpenRC / dinit and sets up `elogind` for seat management automatically when you're not on systemd
- **Adds Arch's own repos when it makes sense:** on an Arch-based distro that doesn't already ship Arch's `[core]`/`[extra]` (e.g. Artix — CachyOS/EndeavourOS already have them, so this is a no-op there), offers to add them with a mirrorlist matched to your existing region
- **`--dry-run`:** shows every command and file change it would make without touching your system
- **Doesn't nag for your password 20 times:** asks once up front and keeps the sudo session alive for the rest of the run
- **Safe to re-run:** already-installed packages and already-applied fixes are skipped, not repeated

## Config layout

The config follows the layout of the current mango docs (0.16): `config.conf` pulls in `env.conf`, `bind.conf`, `rule.conf`, `monitor.conf`, `tag.conf` and `colors.conf` with `source=`. Validate any change without leaving your session with:

```
mango -c ~/.config/mango/config.conf -p
```

## Keybindings

| Keybind            | Action                                 |
| ------------------- | --------------------------------------- |
| SUPER + D           | App launcher (rofi)                    |
| SUPER + 1...9       | Change tag/workspace                   |
| ALT + 1...9         | Move program to tag/workspace          |
| SUPER + V           | Clipboard history (cliphist + fuzzel)  |
| SUPER + Shift + S   | Screenshot                             |
| SUPER + Enter       | Terminal (kitty)                       |
| SUPER + E           | File manager (nemo)                    |
| SUPER + W           | Browser (Helium)                       |
| SUPER + A           | Discord                                |
| SUPER + S           | Spotify                                |
| SUPER + F           | Wallpaper selector (waypaper)          |
| SUPER + Q           | Close active window                    |
| ALT + F             | Toggle fullscreen                      |
| ALT + M             | Quit window manager                    |
| ALT + Tab           | Toggle overview                        |

## Requirements

Pick whichever matches your system — the installer detects it automatically:

- **Arch-based:** Arch, Artix, CachyOS, EndeavourOS, or any other pacman-based distro, plus `git`. An AUR helper (`yay` or `paru`) is offered automatically if neither is found.
- **Fedora:** a recent release with `dnf` and `git`. Package coverage here is best-effort — anything that fails to install is reported at the end instead of silently breaking the run.
- **NixOS:** any recent generation. The installer writes a config snippet instead of installing packages; you add it to your flake/configuration.nix and rebuild yourself.

## How to install?

```bash
git clone https://github.com/kohagizpk/victoria-mangowm-dotfiles.git
cd victoria-mangowm-dotfiles
chmod +x install.sh
./install.sh
```

Want to see what it would do first, without changing anything?

```bash
./install.sh --dry-run
```

The script is interactive: it walks you through a few quick choices up front (keyboard layout, and an AUR helper if you don't have one), shows a summary of everything it's about to do, and only then asks you to confirm and starts working. Here's the gist of what happens, in order:

1. Checks you have an internet connection and aren't running as root.
2. Detects your distro family and, on Arch-based systems, your init system — asking only if it can't tell.
3. Asks for your keyboard layout once, up front.
4. Asks for your sudo password once, and keeps the session alive for the rest of the run instead of prompting repeatedly.
5. On an Arch-based distro without Arch's own `[core]`/`[extra]` repos (Artix, mainly), offers to add them with a mirrorlist matched to your region.
6. Installs everything: the compositor, Waybar, launchers, portals, the PipeWire audio stack, GTK theming, fonts (including real Nerd Font icon glyphs, even on Fedora where the packaged font doesn't have them), and bundled apps.
7. Deploys the dotfiles to `~/.config/mango` and adapts the few things that depend on your machine (elogind instead of systemd, a first-run wallpaper fallback, portals, your keyboard layout...). Every adaptation is logged and printed in the summary at the end.
8. Auto-detects your CPU temperature sensor and wires it into the Waybar config. (Monitors are **not** auto-detected: edit `monitor.conf`.)
9. Sets up the display manager (`ly`), the cursor theme, and — optionally — the GRUB theme, your default shell, and the `video` group permission brightness control needs.
10. Runs a health check at the end and tells you plainly if anything's missing.

## Repository structure

```
.
├── assets/        # Media used in this README
├── config/        # Terminal config, cursor theme, rofi/fuzzel theme, wlogout, wallust, GRUB theme
├── scripts/       # Helper scripts (volume/brightness OSD, print, waybar launcher, wallust hook, calendar, cava)
├── wallpaper/     # Bundled wallpapers
├── waybar/        # Waybar config, stylesheet and wallust color files
├── config.conf    # Main mango config (visuals, animations, input) — sources the files below
├── env.conf       # Environment variables
├── bind.conf      # Keybindings, mouse and axis bindings
├── rule.conf      # Window rules and layer rules
├── monitor.conf   # Monitor rules (edit for your own outputs)
├── tag.conf       # Per-tag layouts
├── colors.conf    # Generated by wallust (fallback palette until its first run)
├── autostart.sh   # Everything started with the session
└── install.sh     # Automated installer
```

## Known issues

- `config/Animated-Mew-Cursor/index.theme` and `cursor.theme` are currently saved as rich-text documents instead of plain text (probably edited in a word processor by accident). The actual cursor files still work, but GTK apps may not list the theme correctly until these two are re-saved as plain text.
- `monitor.conf` is tuned for the author's two monitors; on any other machine edit the output names/modes (`wlr-randr` lists them) or mango falls back to each output's preferred mode.
- `cursor_theme=Samuel-Noticias-Cursor` isn't bundled in the repo (only the old `config/Animated-Mew-Cursor` is). Drop the theme folder into `config/Samuel-Noticias-Cursor/` and the installer will install it, or install it yourself under `~/.local/share/icons/`.
- `install.sh` may still not behave perfectly on every machine — read its output carefully, it logs every adaptation it makes, and it's always safe to run again.

## Credits

- [mango](https://github.com/mangowm/mango) by DreamMaoMao and contributors
- [UltraGrub](https://github.com/YouStones/ultrakill-grub-theme) GRUB theme
- [Nerd Fonts](https://www.nerdfonts.com/) for the icon glyphs
- [Animated Mew Cursor](https://www.gnome-look.org/c/2326996) cursor theme