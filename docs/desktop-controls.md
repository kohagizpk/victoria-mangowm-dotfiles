# Desktop controls

| Entry point | Function |
| --- | --- |
| Sliders beside the power button / Super+C | Control Center |
| Super+, (or the gear in the Control Center) | Victoria Settings |
| Super+D | App launcher with calculator |
| Super+V | Clipboard history with image thumbnails |
| Super+F | Wallpaper picker (applies to the focused monitor) |
| Right-click microphone | Select microphone, adjust input and recording apps |
| Right-click speaker/headphones | Select output, master volume and application volumes |
| Right-click clock | Calendar (and weather, when enabled) |
| Right-click music | MPRIS player: album art, progress, shuffle/loop, player switch; long names scroll |
| Bell on the bar | Notification history; right-click toggles Do Not Disturb |
| Super+Shift+S | Capture a region (saved and copied) |
| Super+L | Lock screen |
| Super+Shift+P | Toggle visual performance |
| Super+/ | Shortcut guide |
| Super+Shift+F | Focus mode |

## Settings

Victoria Settings is a centered Quickshell panel. **Profile** sets the display name and
the profile picture (`~/.face`, also shown on the lock screen). **Appearance**, **Bar &
clock**, **Notifications**, **Keyboard & mouse** and **Lock & idle** edit a draft with a
live preview; changes apply with **Apply** and **Discard** reverts them. Wallpaper
rotation, night light and weather apply immediately. **Setup** covers keyboard layouts
(35 layouts, an optional second layout and its switch shortcut), displays and default
apps; a 20-second confirmation protects monitor changes. **Health** checks desktop
dependencies and offers targeted repairs.

**Open Settings automatically at login** (Setup) saves immediately. Turn it off to stop
the first-run panel. Pointer resizing creates a private scaled copy of the selected
cursor theme, preserving animation frames and hotspots, and updates Mango, GTK and the
session environment. Reopen applications that cache their cursor/theme.

## Control Center and audio

Wi-Fi and Bluetooth use Quickshell's native services: click a tile to toggle it, click
its arrow to list networks or devices. Known and open networks connect directly; new
protected networks ask for the passphrase inline. Bluetooth devices pair, connect and
show their battery when they report it; **Advanced…** opens Blueman.

Quick toggles: Do Not Disturb, night light (always on or scheduled, with a warmth
slider), keep awake (an idle inhibitor), visual performance, power profile and focus
mode. Below them: notification history, output and microphone volume, a compact media
player, capture tools (region, window, screen, annotate, record) and session actions.
Restart and shut down ask for a second click.

Audio is read and written through PipeWire directly, so sliders follow external changes
immediately and dragging never starts processes. Choosing a device also moves streams
that are already playing or recording. Waybar keeps the GTK4 audio and media panels.

## Clipboard

The Quickshell panel lists up to 300 cliphist entries with search and thumbnails for
images (rendered once into `~/.cache/victoria/clipboard-thumbs`). Enter copies, Delete or
middle-click removes an entry, and the bin button erases the history after confirmation.
Escape closes without changing the clipboard.

## Notifications and indicators

Quickshell owns the notification service while it is the bar; SwayNC only runs with
Waybar (and D-Bus starts it if the shell stops). Popups appear in the corner chosen in
Settings, pause while hovered and respect each app's timeout. Do Not Disturb keeps normal
notifications in the history and still shows critical ones. On-screen indicators show
volume, microphone mute, brightness and keyboard-layout changes.

## Lock, idle and performance

The lock screen shows the time, the wallpaper, your profile picture and media controls.
Enter your login password (checked through PAM, the `login` service) and press Enter.
Hyprlock or Swaylock lock instead when the bar is Waybar. Screen-off and suspend wait for
the compositor to confirm the lock.

Automatic idle is disabled by default. Configure lock, screen-off and suspend minutes in
Settings; zero disables automatic suspend. A managed swayidle still locks before system
sleep. Screen-off arms a wake listener before switching outputs off; the screens stay off
until there is input. **Keep awake** pauses all idle actions until turned off.

**Visual performance** disables Mango animations, blur and shadows with a reversible
`local/performance.conf` overlay. **Hardware power profiles** (power-saver, balanced,
performance) control hardware energy policy; they are independent and can be combined.

## Wallpaper colors

Wallpapers live in `~/Pictures/Wallpapers`. The hyprquickpaper picker applies a wallpaper
with awww to the monitor it was opened on, then one hook updates Mango borders, the
Quickshell UI, Waybar, Rofi/Fuzzel, wlogout (including icons), Fish, Kitty, GTK3/GTK4 and
existing Vencord/Vesktop QuickCSS installations. Qt5/Qt6 use a generated
**VictoriaWallustDark** Kvantum theme based on installed MateriaDark. Original package
files are never edited; author/license files are retained.

The selected bar starts once, after wallpaper/palette restoration, and detects the CPU
temperature sensor by identity. Put extra startup commands in
`~/.config/mango/local/autostart.sh`.

## Screen sharing compatibility

Blur is temporarily disabled in the compositor defaults, all Settings profiles and the
Settings switch. Installation also migrates existing blur overrides. Animations and
shadows remain available. This prevents older saved settings or the Effects profile from
silently restoring the failing configuration.

SceneFX issue [#198](https://github.com/wlrfx/scenefx/issues/198) documents invalid
capture damage with blur and multiple outputs. The matching local failure was
`Invalid buffer damage coordinates`, followed by the portal disconnecting. Disabling
blur restored capture in the reported setup. This is a workaround, not a replacement for
an upstream SceneFX fix. Re-enable the control only after verifying the fixed library and
cross-output capture together.
