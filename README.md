# Victoria's MangoWM Dotfiles

A wallpaper-colored Wayland desktop built around [Mango](https://github.com/mangowm/mango). One [Quickshell](https://quickshell.org) process draws the bar, Control Center, settings app, launcher, clipboard history, notifications, on-screen indicators and lock screen, and every piece follows the palette that [Wallust](https://codeberg.org/explosion-mental/wallust) extracts from your wallpaper.

https://github.com/user-attachments/assets/5ad00014-64fa-4ea0-8588-aad44244a558

> The video shows an earlier version of the desktop. The layout and colors are the same, but the Control Center, Settings, launcher, notifications and lock screen have since been rebuilt in Quickshell.

> **Screen sharing:** background blur is disabled to avoid a SceneFX capture crash. Animations and shadows remain available. See [screen-sharing compatibility](#screen-sharing-compatibility).

## Contents

- [Highlights](#highlights)
- [Before you install](#before-you-install)
- [Installation](#installation)
- [First login](#first-login)
- [The desktop](#the-desktop)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Wallpapers and colors](#wallpapers-and-colors)
- [Update an existing installation](#update-an-existing-installation)
- [Personal configuration](#personal-configuration)
- [Scripting the shell](#scripting-the-shell)
- [Troubleshooting](#troubleshooting)
- [Backups and recovery](#backups-and-recovery)
- [Project structure and development](#project-structure-and-development)

## Highlights

- **Everything themed by the wallpaper:** Mango borders, the Quickshell UI, Waybar, Rofi/Fuzzel, wlogout, Fish, Kitty, GTK, Qt (Kvantum) and Spotifast update together when you pick a wallpaper.
- **Control Center:** Wi-Fi and Bluetooth lists, Do Not Disturb, night light (always on or scheduled), keep awake, visual performance, power profile, focus mode, notification history, volume, media and capture tools.
- **Victoria Settings:** profile picture, appearance with a live preview, bar, notifications, keyboard and mouse, lock and idle timers, a setup wizard with 35 keyboard layouts plus a second layout to switch to, a searchable shortcut list and desktop health checks.
- **Launcher and clipboard:** fuzzy app search with a built-in calculator, and clipboard history with image thumbnails.
- **Per-monitor wallpapers:** the picker applies to the monitor it was opened on, with optional automatic rotation.
- **Light on resources:** the whole shell renders in software and idles around 110 MB; audio and notifications come from native services instead of polling.

## Before you install

### Supported systems

| Distribution | Support |
| --- | --- |
| Arch, Artix, CachyOS | Primary targets |
| EndeavourOS and other pacman-based distributions | Installer support; results depend on the distribution |
| Fedora | Experimental; package coverage is best-effort |
| NixOS | Experimental; generates a configuration snippet that you integrate and rebuild yourself |

Full installations have not been validated on every listed distribution. Automated tests cover configuration and installer behavior, not every package build, login manager or hardware combination.

### Requirements

- Git, Bash and **Python 3.11 or newer** available before running the installer.
- A normal user account with access to `sudo` for the full installation.
- An internet connection and an interactive terminal for the full installation.
- Quickshell **0.3.2 or newer**, built against the installed Qt version (the installer pulls it in).

The installer offers an AUR helper on Arch-based systems if neither `yay` nor `paru` is available.

### What installation changes

The full installer installs packages, deploys user configuration, sets up desktop services and offers login-manager and theme choices. On Arch-based systems it performs a full `pacman -Syu` upgrade. Artix may require enabling Arch's `extra` repository; the installer asks before adding it.

Backups are created before configuration deployment. Read the prompts, especially those for Ly, hiding other login sessions, GRUB, the default shell and optional applications.

**Run the installer as your normal user, not with `sudo ./install.sh`.** It requests elevated privileges when needed.

## Installation

### 1. Download the repository

Keep the checkout **outside `~/.config/mango`**. That directory is the installed desktop configuration, not the source checkout.

```bash
mkdir -p ~/src
cd ~/src
git clone https://github.com/kohagizpk/victoria-mangowm-dotfiles.git
cd victoria-mangowm-dotfiles
```

### 2. Preview the installation

```bash
./install.sh --dry-run
```

This prints the plan without installing packages or changing files.

### 3. Run the installer

```bash
./install.sh
```

Follow the prompts to choose your keyboard layout, optional applications, browser and startup preferences. The installer then:

1. Detects your distribution and init system.
2. Backs up affected configuration and installs the required packages.
3. Deploys the desktop to `~/.config/mango` and the relevant application directories.
4. Creates `~/Pictures/Wallpapers` (seeded with the bundled wallpapers), detects monitors and configures themes.
5. Offers optional login-manager, shell and bootloader setup.
6. Generates the initial color palette and reports missing components.

If a step fails, read the error and the backup path before rerunning the installer.

### Installation modes

Run these commands from the repository checkout:

| Command | Purpose |
| --- | --- |
| `./install.sh` | Full interactive installation, including packages and system integration |
| `./install.sh --config-only` | Back up and deploy dotfiles without installing packages or changing system services |
| `./install.sh --diagnose` | Read-only dependency and configuration checks |
| `./install.sh --dry-run` | Preview the full installation plan |
| `./install.sh --config-only --dry-run` | Preview configuration deployment |
| `./install.sh --help` | Show available options |

Use the full installer on a fresh machine. Configuration-only mode expects the desktop dependencies to be installed already.

## First login

Log out of your current desktop and select **Mango** in your login manager.

- **Victoria Settings** opens on the first login with the **Setup** page: keyboard, displays and default apps. Display changes have a 20-second confirmation, so an unusable layout reverts by itself. Turn off **Open Settings automatically at login** when you are done.
- Pick a wallpaper with **Super + F**. Colors update everywhere.
- Set a profile picture in **Settings → Profile**.
- Open the **Control Center** with **Super + C** or the sliders icon on the bar.

`Super` usually means the Windows key. Interface text uses English; keyboard layout and timezone are independent.

## The desktop

### Bar

Workspace tags, microphone and volume (live from PipeWire; scroll to change, right-click for the mixer), CPU/memory/temperature, the tray, the network, the keyboard layout (when you have two), weather (opt-in), now playing with an audio visualizer, a recording timer, notifications, the clock (right-click for the calendar) and the Control Center. Right-click the song for the media player. Esc closes any popup.

### Control Center — `Super + C`

| Section | What it does |
| --- | --- |
| **Wi-Fi, Bluetooth** | Toggle with a click; the arrow lists networks or devices. Connect, enter a Wi-Fi password, pair, see device battery |
| **Quick toggles** | Do Not Disturb, night light, keep awake (pauses idle actions), visual performance, power profile, focus mode |
| **Notifications** | History with actions; clear one or all |
| **Sound** | Output and microphone volume, shortcuts to the full mixers |
| **Media** | Compact player; long titles scroll |
| **Capture** | Region, window or screen screenshots, annotate with Swappy, record the screen with desktop audio |
| **Quick actions** | Wallpaper picker, random wallpaper, clipboard, apps, screens off, suspend, restart and shut down (both ask for a second click) |

### Victoria Settings — `Super + ,`

| Page | Contents |
| --- | --- |
| **Profile** | Display name and profile picture (from `~/Pictures/Avatars`, your Pictures, your wallpapers or any file). Saved as `~/.face` |
| **Appearance** | Profiles, palette source (wallpaper or a fixed accent), spacing, borders, corners, opacity, text size, animations, wallpaper rotation and night light, with a live preview |
| **Bar & clock** | Position, margin, modules, 24-hour clock, seconds, weather |
| **Notifications** | Corner, duration, width, images |
| **Keyboard & mouse** | Pointer size, focus follows mouse, touchpad, key repeat |
| **Lock & idle** | Lock, screens off and suspend timers |
| **Setup** | 35 keyboard layouts and an optional second layout with its switch shortcut, display arrangement and scale, default terminal and browser |
| **Shortcuts** | Searchable list of the bindings Mango actually loaded |
| **Health** | Dependency and configuration checks with one-click repairs |

Appearance, bar, notification, input and idle changes stay in a draft until you press **Apply**.

### Launcher, clipboard and capture

- **Launcher — `Super + D`:** fuzzy search over installed apps, most-used first. Type a calculation such as `12*4` and press Enter to copy the result.
- **Clipboard — `Super + V`:** cliphist history with image thumbnails; Enter copies, Delete removes an entry.
- **Screenshots:** `Super + Shift + S` captures a region. The Control Center adds window, screen and annotate. Files go to `~/Pictures/Screenshots` and are copied to the clipboard.
- **Recording:** from the Control Center, saved to `~/Videos/Recordings` (needs `wf-recorder`). Click the timer on the bar to stop.

### Notifications, indicators and lock screen

- **Notifications** appear in the corner chosen in Settings, with app icons, images and action buttons. Do Not Disturb holds normal notifications in the history; critical ones still show.
- **On-screen indicators** show volume, microphone mute, brightness and keyboard-layout changes.
- **Lock screen — `Super + L`:** clock, wallpaper, profile picture and media controls; enter your login password. Idle and suspend lock with it too.

### Idle, focus and performance

Automatic idle actions start disabled; configure them in **Settings → Lock & idle**. A managed swayidle instance still locks before system sleep, and screens turned off by idle wake on the first input. **Keep awake** in the Control Center pauses idle actions until you turn it off.

**Visual performance** (Control Center or **Super + Shift + P**) disables desktop effects without changing your saved appearance. **Power profile** changes the hardware's energy policy when power-profiles-daemon supports it. **Focus mode** (**Super + Shift + F**) enables Do Not Disturb and hides secondary bar modules; leaving it restores the previous notification state.

See the [desktop controls guide](docs/desktop-controls.md) for more detail.

### Resource usage

The shell runs with Qt's software scene graph, which uses far less memory than OpenGL for a mostly static UI. Audio comes from Quickshell's PipeWire service and notifications from its own notification server, so nothing polls `pactl` or `swaync-client`; the system sampler spawns at most one short command every 15 seconds. Cava runs only while something is playing. When the bar is Quickshell, SwayNC and SwayOSD are not started.

XWayland persistence is disabled: after the next login, it can exit when the last X11 client closes. Local overrides can restore `xwayland_persistence=1`.

### Waybar fallback

Waybar, Rofi, SwayNC, SwayOSD and Hyprlock remain installed as the fallback desktop:

```sh
bash ~/.config/mango/scripts/bar-switch.sh waybar
bash ~/.config/mango/scripts/bar-switch.sh quickshell
```

Keybindings keep working on both: `scripts/victoria-open.sh` opens the Quickshell panel, or the GTK/Rofi tool when the bar is Waybar.

## Keyboard shortcuts

These are the defaults. Existing custom bindings are preserved during configuration-only updates; use **Super + /** to see the bindings actually loaded on your machine.

| Shortcut | Action |
| --- | --- |
| Super + D | App launcher |
| Super + C | Control Center |
| Super + comma | Victoria Settings |
| Super + / | Shortcut guide |
| Super + V | Clipboard history |
| Super + F | Wallpaper picker (on the focused monitor) |
| Super + Shift + S | Region screenshot |
| Super + L | Lock screen |
| Super + Shift + P | Toggle visual performance |
| Super + Shift + F | Toggle focus mode |
| Super + Enter | Terminal |
| Super + E | File manager |
| Super + W | Selected browser, if enabled |
| Super + A / Super + S | Discord / Spotify, if enabled |
| Super + 1–9 | Switch workspace/tag |
| Alt + 1–9 | Move the focused window to a tag |
| Super + Q | Close the focused window |
| Alt + F | Toggle fullscreen |
| Alt + A | Toggle floating |
| Alt + Tab | Window overview |
| Super + left/right mouse drag | Move / resize a window |
| Alt + R | Reload Mango configuration |
| Alt + M | Leave the Mango session |

With two keyboard layouts, the switch shortcut chosen in Setup (Alt + Shift by default) changes layout; the bar shows the active one.

## Wallpapers and colors

**Your wallpapers live in `~/Pictures/Wallpapers`.** Drop images there and they appear in the picker.

[hyprquickpaper](https://github.com/ujjalsigdel/hyprquickpaper) (vendored in `config/hyprquickpaper/`, MIT) is the picker. It opens on the focused monitor and applies the wallpaper **only to that monitor**, so each screen can have its own image. Every pick runs `scripts/wallust-reload.sh`, which generates the palette and updates Mango borders, the Quickshell UI, Waybar, Rofi, Fuzzel, wlogout, Fish, Kitty, GTK3/GTK4, Spotifast and supported Qt themes. The palette follows the most recent pick. **Settings → Appearance → Change automatically** rotates a random wallpaper on every monitor at the interval you choose.

For native Linux Spotifast, select **Victoria Wallust** under **Settings → Appearance → Theme** once. The generated file is `~/.config/spotifast/themes/Victoria Wallust.json`; later wallpaper changes update it automatically. Run `spotifast reload-themes` if it does not appear immediately, and disable **Colour from album art** to keep pages in the Wallust palette. See the [Spotifast custom themes documentation](https://spotifast.rocks/settings-and-files/#custom-themes).

The bundled configuration uses **Wallust 4.x syntax**. The theme helper detects **Wallust 3.x** and translates its rendering options without rewriting the source configuration.

GTK uses **Materia-dark-compact**. Qt applications use **Kvantum** with a generated **VictoriaWallustDark** theme based on MateriaDark. Some applications need reopening after a theme change; Flatpak applications and Libadwaita may not follow the host theme exactly.

## Update an existing installation

Update the source checkout, then deploy the configuration:

```bash
cd ~/src/victoria-mangowm-dotfiles
git pull --ff-only
./install.sh --config-only --dry-run
./install.sh --config-only
./install.sh --diagnose
```

If Git reports local changes or diverged history, resolve them before updating; do not discard your work just to force the pull.

Configuration-only updates preserve personal overrides and existing bindings while applying managed migrations (for example, moving the old Rofi, clipboard and settings bindings to the Quickshell panels). They **do not install newly required packages**; check `./install.sh --diagnose` and use the full installer when something is missing. This version needs `quickshell`, `qt6-5compat`, `imagemagick`, `jq`, `zenity`, `swappy` and `wf-recorder`.

## Personal configuration

Keep custom changes in `~/.config/mango/local/`:

| File | Purpose |
| --- | --- |
| `input.conf` | Keyboard layouts and repeat settings (Setup writes a marked block here) |
| `monitor.conf` | Monitor positions, resolution, rotation and scale |
| `custom.conf` | Personal compositor options; Settings maintains a marked block here |
| `settings.json` | Saved preferences managed by Victoria Settings |
| `autostart.sh` | Extra personal startup commands |
| `performance.conf` | Generated visual-performance override; do not use for permanent preferences |

Other personal data: wallpapers in `~/Pictures/Wallpapers`, avatar candidates in `~/Pictures/Avatars`, the profile picture in `~/.face`, quick settings (night light, weather, rotation) in `~/.local/state/victoria/quick.json`.

Monitor detection uses available driver modes and does not invent refresh rates. It cannot infer your physical monitor arrangement; use Setup or personal monitor rules for your layout.

Avoid editing generated color files. Change templates under `config/wallust/templates/` in the source checkout instead.

**Weather is opt-in** (Settings → Bar & clock). It queries [wttr.in](https://wttr.in) every 30 minutes; that service sees your IP address and the city you enter.

## Scripting the shell

Everything in the Control Center can be driven from scripts and keybindings:

```bash
quickshell ipc -p ~/.config/mango/quickshell call bar <function> [arguments]
```

| Function | Effect |
| --- | --- |
| `controlCenter`, `launcher`, `clipboard`, `settings <page>` | Open a panel |
| `volume <mic:true/false> <delta>`, `mute <mic>` | Change or mute output/microphone |
| `dnd <on>`, `nightLight <on>`, `caffeine <on>` | Quick toggles |
| `set <key> <json>`, `get <key>` | Quick settings, e.g. `set nightMode '"schedule"'` |
| `lock`, `lockStatus` | Lock the session, check the lock state |
| `quick` | Current state as JSON |

## Troubleshooting

Start with the read-only diagnostic:

```bash
./install.sh --diagnose
```

| Symptom | What to check |
| --- | --- |
| Missing program or control | Read the diagnostic output; configuration-only mode does not install dependencies |
| Colors do not update | Settings → Health → Refresh colors, or run the command below and inspect the Wallust log |
| Bar shows nothing or crashes | Rebuild Quickshell after a Qt upgrade; it warns in `quickshell log -p ~/.config/mango/quickshell` |
| Screen recording does nothing | Install `wf-recorder` |
| Qt apps remain light | Confirm Kvantum and MateriaDark are installed, reopen the app and check its custom theme settings |
| Settings opens on every login | Disable **Open Settings automatically at login** in Settings → Setup |
| Incorrect monitor arrangement | Review Setup and `local/monitor.conf` |
| Screen sharing freezes | See the compatibility note below; do not re-enable background blur on affected setups |

Refresh the current wallpaper colors:

```bash
bash ~/.config/mango/scripts/wallust-reload.sh
```

Wallust logs are in `~/.cache/wallust/victoria.log`, or `$XDG_CACHE_HOME/wallust/victoria.log` when configured.

Check Mango configuration syntax before restarting your session:

```bash
mango -c ~/.config/mango/config.conf -p
```

### Stuck on the lock screen

If the shell ever stops while the session is locked, Mango keeps the screen locked on purpose. Switch to a text console (**Ctrl + Alt + F3**), log in and run:

```bash
WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/$(id -u) quickshell ipc -p ~/.config/mango/quickshell call bar unlock
```

If the shell is not running at all, start it with the same two variables (`bash ~/.config/mango/scripts/bar-launch.sh`) and unlock normally. Then return to the graphical session (usually **Ctrl + Alt + F1** or **F2**).

### Screen-sharing compatibility

[SceneFX issue #198](https://github.com/wlrfx/scenefx/issues/198) documents a capture failure with blur enabled. The portal can exit with `Invalid buffer damage coordinates`, interrupting sharing across applications.

For compatibility, Victoria disables compositor background blur in new installations, saved profiles and migrated overrides. The Settings switch explains this restriction. Animations and shadows remain available. This is a **workaround**, not an upstream repair; re-enabling blur requires verifying a fixed SceneFX version with your setup.

## Backups and recovery

User configuration backups are stored under:

```text
~/.local/state/victoria/backups/install-*
```

If `XDG_STATE_HOME` is set, the location is `$XDG_STATE_HOME/victoria/backups`. The installer prints the exact path. Relevant system changes have separate backup locations reported during installation.

To recover a configuration, close the affected application, inspect the backup and restore the specific files you need. Backups do not undo package upgrades, service changes, group membership or a changed login shell. There is no automatic update-and-rollback feature.

## Project structure and development

| Directory | Contents |
| --- | --- |
| `installer/` | Package selection, deployment (`deploy.py` maps source to runtime) and system integration |
| `config/quickshell/` | The desktop shell: bar, Control Center, Settings, launcher, clipboard, notifications, OSD, lock screen |
| `config/hyprquickpaper/` | Vendored wallpaper picker (MIT); Victoria's changes are listed in its `VICTORIA.md` |
| `config/` | Mango and application configuration templates |
| `scripts/` | Settings backend (`victoria_settings.py`, `victoria-cli.py`), themes, session controls, capture and launchers |
| `themes/`, `wallpapers/` | Bundled desktop assets |
| `tests/` | Isolated regression tests |
| `docs/` | Detailed desktop and maintenance guides |

Run checks from the source checkout:

```bash
python3 -m unittest discover -s tests -v
bash -n install.sh
./install.sh --dry-run
git diff --check
```

Tests use temporary directories rather than the real home configuration. GitHub Actions runs the suite on pushes and pull requests. The Quickshell UI and full installations still need testing on real hardware.

Further reading: [Desktop controls](docs/desktop-controls.md) · [Project layout](docs/project-layout.md) · [Maintenance guide, in Portuguese](docs/maintenance.md).

## Credits

Built with [Mango](https://github.com/mangowm/mango) and the work of its contributors, alongside [Quickshell](https://quickshell.org), [hyprquickpaper](https://github.com/ujjalsigdel/hyprquickpaper) by Ujjal Sigdel, Wallust, awww, Waybar, Rofi/Fuzzel, SwayNC, Hyprlock, PipeWire and the Wayland desktop ecosystem.

Bundled themes and assets include [UltraGrub](https://github.com/YouStones/ultrakill-grub-theme), [Nerd Fonts](https://www.nerdfonts.com/), [Animated Mew Cursor](https://www.gnome-look.org/c/2326996), [Materia GTK](https://github.com/nana-4/materia-theme) and [Materia KDE](https://github.com/PapirusDevelopmentTeam/materia-kde), used with [Kvantum](https://github.com/tsujan/Kvantum).
