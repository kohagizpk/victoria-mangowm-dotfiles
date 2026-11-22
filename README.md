# Victoria's MangoWM Dotfiles

A wallpaper-colored Wayland desktop built around [Mango](https://github.com/mangowm/mango), with a floating settings app, a control center, notifications, audio mixers and a guided installer.

Use the desktop controls for everyday changes. Keep your personal overrides separate from the files managed by the installer.

https://github.com/user-attachments/assets/cb902017-0d69-4222-970d-5467773197c4

> **Screen sharing:** background blur is temporarily disabled to avoid a SceneFX capture crash. Animations and shadows remain available. See [screen-sharing compatibility](#screen-sharing-compatibility).

## Contents

- [Before you install](#before-you-install)
- [Installation](#installation)
- [First login](#first-login)
- [Everyday controls](#everyday-controls)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Wallpaper colors and themes](#wallpaper-colors-and-themes)
- [Update an existing installation](#update-an-existing-installation)
- [Personal configuration](#personal-configuration)
- [Troubleshooting](#troubleshooting)
- [Backups and recovery](#backups-and-recovery)
- [Project structure and development](#project-structure-and-development)

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

This prints a high-level plan without installing packages or changing files. It is not a simulation of every command.

### 3. Run the installer

```bash
./install.sh
```

Follow the prompts to choose your keyboard layout, optional applications, browser and startup preferences. The installer then:

1. Detects your distribution and init system.
2. Backs up affected configuration and installs the required packages.
3. Deploys desktop files to `~/.config/mango` and the relevant application directories.
4. Detects monitors and configures the desktop, themes and wallpaper hook.
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

Log out of your current desktop and select **Mango** in your login manager. A new login allows applications to receive the updated theme and session environment.

- Open **Victoria Settings** with **Super + comma**, the launcher or the gear before the microphone.
- Review keyboard, display and application choices in **Setup**. Display changes have a timed confirmation so an unusable layout can revert.
- Choose a wallpaper with **Super + F**. Colors update automatically.
- Turn off **Open Settings automatically at login** if you do not want the setup window to appear at startup.

`Super` usually means the Windows key. Interface text uses English; keyboard layout and timezone are independent.

## Everyday controls

| Component | What it does |
| --- | --- |
| **Victoria Settings** | Appearance, profiles, Waybar modules, clock, notifications, cursor size, input preferences and lock/idle timers |
| **Control center** | Wi-Fi, Bluetooth, audio devices, hardware power profiles, screen off and suspend |
| **Quickshell bar** | Default bar with workspace tags, media, system tray, CPU temperature and native audio/calendar popups. Waybar remains available as a fallback. |
| **Media player** | Right-click the Waybar song to toggle a compact horizontal player: rotating album record, previous/play/pause/next, progress and player selection. Esc closes it; colors follow Wallust live. Uses the existing GTK4 dependencies. |
| **Audio mixers** | Right-click the speaker for output/application volumes; right-click the microphone for input selection and volume |
| **SwayNC** | Notifications and Do Not Disturb. Right-click the Quickshell clock for the native calendar, DND and performance controls; Waybar uses the SwayNC calendar. |
| **Clipboard history** | Search, image thumbnails, scrolling and older entries; opens near the input field when available, otherwise near the pointer |
| **Screenshots** | Select a region with Super + Shift + S |
| **Lock screen** | Hyprlock with a blurred wallpaper, clock and password field; enter your existing login password |
| **Power menu** | Wallpaper-colored lock, logout, suspend and power actions |

The Control center opens from the sliders beside the power button or **Super + C**. Wi-Fi authentication uses a graphical password dialog. Bluetooth pairing is available through Blueman. Set `VICTORIA_MENU=fuzzel` to use Fuzzel instead of Rofi for the menu.

### Victoria Quickshell bar

The default bar uses Quickshell 0.3.2+, with native QML media, audio and calendar popups.
It reads the existing Wallust `waybar/colors.css` palette live; no second palette generator is needed.
Mango tags use `mmsg watch all-tags`; media and tray use Quickshell services.
Settings (visibility, clock, position, margin and focus mode) remain in Victoria Settings.
Right-click audio/microphone, music or clock for the respective popup; Esc closes it.
The original Waybar remains available:

```sh
bash ~/.config/mango/scripts/bar-switch.sh waybar
bash ~/.config/mango/scripts/bar-switch.sh quickshell
```

Quickshell must be built against the installed Qt version. The bar keeps SwayNC and
the existing control center, settings and power actions.

### Idle, focus and performance

Automatic idle actions start disabled. Configure their timeouts in **Settings → Personalize → Lock & idle**. A managed swayidle instance still handles locking before system sleep. Screen-off uses a wake listener and a recovery timer.

**Visual performance** disables desktop effects without changing your saved appearance preferences. Toggle it in the calendar panel or with **Super + Shift + P**. Turning it off restores permitted effects; background blur remains disabled by the compatibility workaround.

**Hardware power profiles** in the Control center are separate: they change the hardware's energy policy and only appear when supported by the service and hardware.

**Focus mode**, toggled with **Super + Shift + F**, enables Do Not Disturb and hides secondary bar modules. Leaving it restores the previous notification state.

See the [desktop controls guide](docs/desktop-controls.md) for more detail.

### Idle resource usage

Quickshell caches audio queries for up to 30 seconds and invalidates them on
PulseAudio/PipeWire events (volume and device changes still update on the next
2-second sample). Network discovery runs at most once every 15 seconds; traffic
counters still update every sample. Cava runs only while an unmuted playback
stream is active, including players without MPRIS. The clock uses minute precision
when seconds are disabled. Bar launchers prevent duplicate Quickshell instances.

XWayland persistence is disabled: after the next login, it can exit when the last
X11 client closes. Starting an X11 application may consequently take a little
longer. Local overrides can restore `xwayland_persistence=1`.

For this Artix/dinit installation, `maintenance/disable-unused-services.sh`
removes Waydroid, libvirt and SSH from boot and stops them without uninstalling
packages. It is an explicit maintenance action, not part of the installer.
Restore a needed service with `sudo dinitctl --system enable SERVICE`.
Google Drive can be mounted on demand with
`rclone mount gdrive: ~/Drive --vfs-cache-mode full --daemon`.

## Keyboard shortcuts

These are the defaults. Existing custom bindings are preserved during configuration-only updates; use **Super + /** to inspect the bindings actually loaded on your machine.

| Shortcut | Action |
| --- | --- |
| Super + D | Application launcher |
| Super + comma | Victoria Settings |
| Super + C | Control center |
| Super + / | Shortcut guide |
| Super + Enter | Terminal |
| Super + E | File manager |
| Super + W | Selected browser, if enabled |
| Super + A / Super + S | Discord / Spotify, if enabled |
| Super + F | Wallpaper selector |
| Super + V | Clipboard history |
| Super + Shift + S | Region screenshot |
| Super + L | Lock screen |
| Super + Shift + P | Toggle visual performance |
| Super + Shift + F | Toggle focus mode |
| Super + 1–9 | Switch workspace/tag |
| Alt + 1–9 | Move the focused window to a tag |
| Super + Q | Close the focused window |
| Alt + F | Toggle fullscreen |
| Alt + A | Toggle floating |
| Alt + Tab | Window overview |
| Super + left/right mouse drag | Move / resize a window |
| Alt + R | Reload Mango configuration |
| Alt + M | Leave the Mango session |

## Wallpaper colors and themes

Waypaper selects the wallpaper; Wallust generates the palette. One hook updates Waybar, Mango borders, Rofi, Fuzzel, SwayNC, wlogout icons, Fish, Kitty, GTK3/GTK4, Spotifast and supported Qt themes. Existing Vencord/Vesktop installations can receive matching QuickCSS; enable QuickCSS in the client.

For native Linux Spotifast, select **Victoria Wallust** under **Settings → Appearance → Theme** once. The generated regular file is `~/.config/spotifast/themes/Victoria Wallust.json`; later wallpaper changes update it automatically, including while music plays. Run `spotifast reload-themes` if it does not appear immediately. Disable **Colour from album art** to keep pages in the Wallust palette. This themes the main window; Winamp skins are separate. See the [Spotifast custom themes documentation](https://spotifast.rocks/settings-and-files/#custom-themes).

The bundled configuration uses **Wallust 4.x syntax**. The theme helper detects **Wallust 3.x** and translates its rendering options without rewriting the source configuration. CI tests the real Wallust 3.5.1 renderer; local validation also covers 4.1.0-alpha.

GTK uses **Materia-dark-compact**. Qt applications such as Ark and qBittorrent use **Kvantum**, with a generated **VictoriaWallustDark** theme based on MateriaDark. The installer includes Qt 5 and Qt 6 integration on the primary distributions.

Some applications need reopening after a theme change. Flatpak applications, custom application themes and Libadwaita may not reproduce the host theme exactly. GTK theme settings alone do not configure Qt applications.

Wallpaper restoration runs before the selected bar starts. Repeated launcher calls avoid starting a second bar. Generated palettes are validated before replacing the previous working colors.

## Update an existing installation

Update the source checkout, then deploy the configuration:

```bash
cd ~/src/victoria-mangowm-dotfiles
git pull --ff-only
./install.sh --config-only --dry-run
./install.sh --config-only
./install.sh --diagnose
```

If Git reports local changes or diverged history, resolve those changes before updating; do not discard your work just to force the pull.

Configuration-only updates preserve personal overrides and existing bindings, while applying managed migrations such as the clipboard command and screen-sharing blur workaround. They also update managed styles and theme integration. They **do not install newly required packages**; review diagnostics and use the full installer when dependency or system setup is needed.

## Personal configuration

Keep custom changes in `~/.config/mango/local/`:

| File | Purpose |
| --- | --- |
| `input.conf` | Keyboard layout and repeat settings |
| `monitor.conf` | Monitor positions, resolution, rotation and scale |
| `custom.conf` | Personal compositor options; Settings maintains a marked block here |
| `settings.json` | Saved preferences managed by Victoria Settings |
| `autostart.sh` | Extra personal startup commands |
| `performance.conf` | Generated visual-performance override; do not use for permanent preferences |

Monitor detection uses available driver modes and does not invent refresh rates. It cannot infer your physical monitor arrangement. Detection runs during installation, not continuously; use Setup or personal monitor rules for your layout. Ambiguous connector names across multiple GPUs may need manual configuration.

Avoid editing generated color files. Change templates under `config/wallust/templates/` in the source checkout instead.

## Troubleshooting

Start with the read-only diagnostic:

```bash
./install.sh --diagnose
```

| Symptom | What to check |
| --- | --- |
| Missing program or control | Read the diagnostic output; configuration-only mode does not install dependencies |
| Colors do not update | Run the refresh command below and inspect the Wallust log |
| Qt apps remain light | Confirm Kvantum and MateriaDark are installed, reopen the app and check its custom theme settings |
| Settings opens on every login | Disable **Open Settings automatically at login** in Settings |
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

### Screen-sharing compatibility

[SceneFX issue #198](https://github.com/wlrfx/scenefx/issues/198) documents a capture failure with blur enabled. The portal can exit with `Invalid buffer damage coordinates`, interrupting sharing across applications. The reported Victoria setup also froze when Settings appeared on the captured DP monitor; disabling blur restored sharing.

For compatibility, Victoria disables compositor background blur in new installations, saved profiles and migrated overrides. The Settings switch explains this restriction. Animations, shadows and Hyprlock's wallpaper blur remain available.

This is a **workaround**, not an upstream repair or a guarantee against every capture failure. Re-enabling blur requires verifying a fixed SceneFX version with your compositor and monitor setup.

## Backups and recovery

User configuration backups are stored under:

```text
~/.local/state/victoria/backups/install-*
```

If `XDG_STATE_HOME` is set, the location is `$XDG_STATE_HOME/victoria/backups`. The installer prints the exact path. Relevant system changes have separate backup locations reported during installation.

To recover a configuration, close the affected application, inspect the backup and restore the specific files you need. Backups do not undo package upgrades, service changes, group membership or a changed login shell. GSettings values require separate restoration; copying configuration files alone does not restore them.

There is no automatic update-and-rollback feature.

## Project structure and development

| Directory | Contents |
| --- | --- |
| `installer/` | Package selection, deployment and system integration |
| `config/` | Compositor and application configuration templates |
| `scripts/` | Settings, session controls, themes and desktop helpers |
| `themes/`, `wallpapers/` | Bundled desktop assets |
| `assets/` | Preview media |
| `tests/` | Isolated regression tests |
| `docs/` | Detailed desktop and maintenance guides |

Run checks from the source checkout:

```bash
python3 -m unittest discover -s tests -v
bash -n install.sh
./install.sh --dry-run
git diff --check
```

Tests use temporary directories rather than the real home configuration. Pillow is needed for cursor tests; the Fish and Wallust integration checks use those binaries when installed. GitHub Actions installs these test dependencies and runs the suite on pushes and pull requests. Full installation and graphical behavior still require testing on real hardware.

Further reading: [Desktop controls](docs/desktop-controls.md) · [Project layout](docs/project-layout.md) · [Maintenance guide, in Portuguese](docs/maintenance.md).

## Credits

Built with [Mango](https://github.com/mangowm/mango) and the work of its contributors, alongside Quickshell, Waybar, Rofi/Fuzzel, SwayNC, Wallust, Waypaper, Hyprlock, PipeWire and the Wayland desktop ecosystem.

Bundled themes and assets include [UltraGrub](https://github.com/YouStones/ultrakill-grub-theme), [Nerd Fonts](https://www.nerdfonts.com/), [Animated Mew Cursor](https://www.gnome-look.org/c/2326996), [Materia GTK](https://github.com/nana-4/materia-theme) and [Materia KDE](https://github.com/PapirusDevelopmentTeam/materia-kde), used with [Kvantum](https://github.com/tsujan/Kvantum).
