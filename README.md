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
- **Multi-monitor:** installation detects connected Linux DRM outputs and writes native `monitor_rule=` lines to `monitor.conf`, including from a TTY. Uses the preferred resolution and highest advertised refresh at that resolution when DRM access is available; otherwise lets Mango choose the mode. Personal rules in `local/monitor.conf` take precedence.
- **Wallpaper-driven colors:** wallust regenerates `colors.conf` (mango borders), `waybar/colors.css` and Fish/terminal colors every time waypaper changes the wallpaper; mango hot-reloads on its own (`auto_reload_config`)
- **Keyboard layout:** picked from a short menu during install and applied both to mango (`xkb_rules_layout`/`xkb_rules_variant`) and to the raw console (`/etc/vconsole.conf`), so it's consistent whether you're at a bare TTY or inside the graphical session
- **GTK theming:** Materia-dark-compact applied the same way `nwg-look` would (gtk-3.0/gtk-4.0 `settings.ini`, `~/.gtkrc-2.0`, `GTK_THEME` env var)
- **Shell:** fish, with the greeting disabled and fastfetch shown on every new terminal
- **Terminal:** kitty
- **Cursor theme:** bundled **Animated-Mew-Cursor**, installed in `~/.local/share/icons` in both installation modes. An existing selection is preserved when its theme is available; missing themes fall back to the bundled cursor. Mango and its session environment use the same selection.
- **Bootloader theming (optional):** UltraGrub GRUB theme, plus a patch that cleans up boot entries (e.g. tidies the Windows entry for dual-boot)
- **Display manager (optional):** [ly](https://github.com/fairyglade/ly), the default DM; hiding other sessions is an explicit opt-in with a backup
- **Discord screen sharing** wired up correctly (`--ozone-platform=wayland` + PipeWire capturer) wherever Discord gets launched from

### The installer

- **Primary targets: Arch, Artix and CachyOS.** Fedora and NixOS remain experimental; neither has been validated by a full installation in this change.
- **Multi-distro:** Arch/Artix/CachyOS/EndeavourOS (pacman), Fedora (dnf, best-effort), and NixOS (writes a config snippet instead of installing anything imperatively, since that's not how NixOS works)
- **Init-system aware:** detects systemd / OpenRC / dinit and sets up `elogind` for seat management automatically when you're not on systemd
- **Adds Arch's own repos when it makes sense:** on an Arch-based distro that doesn't already ship Arch's `[extra]` (e.g. Artix — CachyOS/EndeavourOS already have them, so this is a no-op there), offers to add them with a mirrorlist matched to your existing region
- **`--dry-run`:** prints a read-only high-level plan and exits before privilege checks, network access, prompts or filesystem writes. It is not a command-by-command simulation.
- **Doesn't nag for your password 20 times:** asks once up front and keeps the sudo session alive for the rest of the run
- **Backups:** existing user configuration is copied to `~/victoria-backup.XXXXXXXX` before deployment, including an in-place Mango checkout. Relevant system files are backed up under `/var/backups/victoria-*`. Re-running can overwrite customizations; inspect and keep the backup.
- **Application choices:** Discord and Spotify each have a yes/no prompt. Choose Helium, Firefox, Brave or no browser. Automatic startup is separately optional; shortcuts are generated for selected apps. “None” leaves the system browser default alone and removes SUPER+W from the deployed bindings.
- **Qt theming:** installs Kvantum for Qt 5 and Qt 6 plus MateriaDark, alongside Materia-dark-compact for GTK.

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
| SUPER + W           | Selected browser (if enabled)                       |
| SUPER + A           | Discord (if enabled)                                |
| SUPER + S           | Spotify (if enabled)                                |
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

The script is interactive: it walks you through a few quick choices up front (keyboard layout, and an AUR helper if you don't have one), shows a summary of everything it's about to do, and asks for confirmation before package installation. Configuration backups are created early, before deployment. Here's the gist of what happens, in order:

1. Requires an interactive terminal and a normal user, and checks connectivity with a timeout. `--dry-run` bypasses all execution steps.
2. Detects your distro family and, on Arch-based systems, your init system — asking only if it can't tell.
3. Asks for optional apps, browser, autostart and keyboard layout. Creates backups of existing user configuration.
4. Asks for your sudo password once, and keeps the session alive for the rest of the run instead of prompting repeatedly.
5. Performs a full `pacman -Syu` upgrade, avoiding partial upgrades. On an Arch-based distro without Arch's own `[extra]` repos (Artix, mainly), offers to add them with a mirrorlist matched to your region.
6. Installs everything: the compositor, Waybar, launchers, portals, the PipeWire audio stack, GTK theming, fonts (including real Nerd Font icon glyphs, even on Fedora where the packaged font doesn't have them), and bundled apps.
7. Deploys the dotfiles to `~/.config/mango` and adapts the few things that depend on your machine (elogind instead of systemd, a first-run wallpaper fallback, portals, your keyboard layout...). Every adaptation is logged and printed in the summary at the end.
8. Auto-detects your CPU temperature sensor for Waybar and connected monitors for `monitor.conf`. Places screens side by side from `0,0`, with the laptop panel first when present; preserves personal monitor rules.
9. Sets up the default display manager (`ly`), asks whether to hide other sessions, the cursor theme, and — optionally — the GRUB theme, your default shell, and the `video` group permission brightness control needs.
10. Runs a health check at the end and tells you plainly if anything's missing.

## Repository structure

| Path | Purpose |
| --- | --- |
| `install.sh` | Entry point, installation modes and read-only plans |
| `installer/` | Interactive flow, packages, desktop setup and explicit deployment mapping |
| `config/mango/` | Compositor, bindings, monitors and autostart |
| `config/waybar/`, `config/rofi/`, `config/fuzzel/`, `config/wlogout/` | Bar and menus |
| `config/fish/`, `config/kitty/`, `config/fastfetch/` | Shell and terminal defaults |
| `config/wallust/` | One source of truth for generated color templates |
| `themes/` | Bundled cursor and UltraGrub, with upstream licenses |
| `wallpapers/`, `assets/` | Wallpapers and README media |
| `scripts/` | Session helpers and read-only diagnostics |
| `docs/`, `tests/` | Maintenance guide and isolated regression tests |

The checkout must live **outside `~/.config/mango`**, for example in `~/src/victoria-mangowm-dotfiles`.
The installer maps organized source files to the existing runtime paths; session scripts do not need a migration.
Only runtime files are deployed, not Git history, tests or installer modules.

```bash
./install.sh --config-only --dry-run  # preview without writes
./install.sh --config-only            # back up and update dotfiles only
./install.sh --diagnose               # report missing components, without changes
```

Configuration-only mode does not install packages, configure Ly, modify services or apply system themes.
It preserves existing app preferences, bindings, environment, Kitty/Fastfetch configuration and personal overrides.
Use the full interactive installer for GTK/Kvantum setup and package choices.
Wallust refreshes Waybar, borders, Fish, Rofi, Fuzzel and wlogout; missing Wallust leaves fallback colors and an actionable warning.
See [maintenance and personal overrides](docs/maintenance.md).

## Known issues and validation limits

The concrete configuration issues from the previous list are addressed:

- Monitor rules are generated for detected hardware, instead of shipping the author's two outputs. Legacy untouched defaults are migrated; edited personal layouts are preserved and loaded first because Mango uses the first matching monitor rule.
- The cursor default now refers to the bundled Animated Mew theme. Its `index.theme` and `cursor.theme` were already plain-text INI files; regression tests now verify this and the stale warning has been removed.
- App rules no longer require DP-1/HDMI-A-1, and XWayland's default DPI now matches the generated scale of 1.

Remaining limits:

- Without permission to read DRM modes or without `libdrm.so.2`, sysfs supplies connector names and preferred sizes for placement; the compositor selects the mode/refresh. No fabricated timings or overclocking are applied. With no readable connected outputs, no monitor rules are forced.
- Duplicate connector names across GPUs are skipped rather than guessed; configure those setups manually. Physical left/right order, rotation and desired scaling cannot be inferred from connector names: use `local/monitor.conf`. Detection runs during installation/update, not continuously when a monitor is plugged in.
- Full package installation, Ly login and the resulting Mango session still need testing on real Arch/Artix/CachyOS hardware. Fedora/NixOS remain experimental. Automated tests do not replace this validation.

See [monitor setup and maintenance](docs/maintenance.md) for preview and regeneration commands.

## Credits

- [mango](https://github.com/mangowm/mango) by DreamMaoMao and contributors
- [UltraGrub](https://github.com/YouStones/ultrakill-grub-theme) GRUB theme
- [Nerd Fonts](https://www.nerdfonts.com/) for the icon glyphs
- [Animated Mew Cursor](https://www.gnome-look.org/c/2326996) cursor theme

## Dark theme: GTK and Qt

The installer selects **Materia-dark-compact** for GTK 2/3/4 and **MateriaDark**
for Qt widgets through Kvantum. Qt has a separate theme engine; MateriaDark is
not an identical compact port. The Arch-family dependencies are `materia-gtk-theme`,
`kvantum`, `kvantum-qt5` and `kvantum-theme-materia`.

The style environment is set in `env.conf` for programs launched by Mango and
exported by `autostart.sh` for its children and D-Bus activation. GSettings also
receives `prefer-dark` when available. Log out and back in after installing;
already-running apps keep their old environment.

For **Ark and qBittorrent**, use the native package and disable any custom
application theme/style override if it prevents Kvantum from taking effect.
GTK theme settings alone cannot style these Qt apps. Flatpak applications need
matching themes/plugins inside their runtime; host Kvantum does not automatically
style them. Libadwaita apps normally follow the dark preference, but do not promise
the exact Materia widget appearance. No custom qBittorrent settings are erased.

Upstream references: [Materia GTK](https://github.com/nana-4/materia-theme),
[Materia KDE](https://github.com/PapirusDevelopmentTeam/materia-kde),
[Kvantum installation](https://github.com/tsujan/Kvantum/blob/master/Kvantum/INSTALL.md).

## Verification and recovery

Run the isolated regression suite without installing anything:

```bash
python3 -m unittest discover -s tests -v
bash -n install.sh
./install.sh --dry-run
```

The suite checks all 16 browser/Discord/Spotify combinations, backup preservation,
repeated app configuration, Qt settings, dry-run side effects, shell syntax and
Waybar retry/cleanup behavior with mocked applications. GitHub Actions runs it on
pushes and pull requests. These tests do **not** replace booting a real Arch/Artix/
CachyOS machine, building AUR packages, testing Ly or visually checking Qt apps.

The installer prints its backup locations. To recover, close the affected apps,
inspect the backup and copy back the individual configuration directories you want
to restore (for example `.config/kitty`). GSettings values are recorded separately
in `gtk-theme.gsettings` and `color-scheme.gsettings`; restoring files does not
restore those settings. Backups do not roll back package upgrades, service enablement,
group membership or shell changes. Hidden sessions retain their full paths below
`/etc/mango-removed-sessions-*` and can be moved back individually.

Wallust prefers HDMI-A-1 as before, but falls back to another active wallpaper if
that output is absent. Set `VICTORIA_COLOR_MONITOR` to choose another preferred output.
Spicetify is now applied manually after Spotify updates, rather than restoring and
patching Spotify on every login.


## Wallpaper palette and visual refresh

Waybar uses three floating groups with consistent padding, a subtle outline and
readable foreground text. Active workspaces and controls inherit the wallpaper
accent. Mango keeps its layouts and animations with 12px corners, 10px outer gaps
and 96% inactive-window opacity. Kitty uses 88% opacity and 10px padding.

The installer copies all Wallust templates into `~/.config/wallust/templates`,
sets Waypaper to `awww`, and generates the initial palette **during installation**.
It uses the saved wallpaper (preferring HDMI-A-1), including Waypaper's XDG state
file, or `wallpaper/wallpaper.jpg` on a fresh setup. No running compositor is needed
for that first generation. The managed config targets Wallust **3.x**, validated
in CI with 3.5.1: `backend = "kmeans"`, `palette = "dark"`, `check_contrast = true`.

The Fish loader lives in `~/.config/fish/conf.d/victoria-wallust.fish`; your prompt,
PATH and `config.fish` are preserved. Terminal background/foreground/ANSI colors
and Fish syntax/prompt variables follow the wallpaper. New terminals load the
palette immediately; open Fish sessions refresh **at the next prompt**. Prompts
with their own hardcoded RGB colors may override the Fish color variables.

At login, `scripts/wallpaper-start.sh` waits for awww, restores Waypaper and
synchronizes the palette. On wallpaper changes, the post-command uses
`scripts/wallust-reload.sh`. It serializes updates, renders into staging, checks
all outputs, and only then publishes the generated files and Fish cache. A failed
or incomplete Wallust render keeps the last complete palette. Existing unrelated
Waypaper post-commands are retained; an empty or old Victoria hook is repaired.

To regenerate manually (after configuration has been installed):

```bash
bash ~/.config/mango/scripts/wallust-reload.sh
```

Diagnostics: `${XDG_CACHE_HOME:-$HOME/.cache}/wallust/victoria.log`.
The automated tests cover setup, saved/active/missing monitors, XDG state, repeated
installation, custom hooks, failed rendering and native GTK CSS parsing. CI also
runs the real Wallust renderer and Fish loader. Full compositor/DM installation
and screenshot-level validation still require a real desktop session.
