# Desktop controls

| Entry point | Function |
| --- | --- |
| Gear before the Waybar microphone / Super+, | Victoria Settings |
| Sliders beside the power button / Super+C | Control center |
| Right-click microphone | Select microphone and adjust input volume |
| Right-click speaker/headphones | Select output, master volume and application volumes |
| Right-click clock | Calendar, notifications, DND and visual performance |
| Super+V | Clipboard history: search, thumbnails, scrolling and older copies |
| Super+Shift+S | Capture a region to the clipboard |
| Super+L | Lock with Hyprlock |
| Super+Shift+P | Toggle visual performance |
| Super+/ | Shortcut guide |
| Super+Shift+F | Focus mode |

## Settings

Settings always floats. Personalize includes Appearance, Bar & clock, Notifications,
Mouse & touchpad, and Lock & idle. Changes apply with **Apply**. Setup covers keyboard,
displays and application choices; a timed confirmation protects monitor changes.
Diagnostics checks desktop dependencies and provides targeted repair actions.

**Open Settings automatically at login: ON/OFF** saves immediately. Turn it off to
stop the first-run panel. Settings remains available from the bar and launcher.
Pointer resizing creates a private scaled copy of the selected cursor theme, preserving
animation frames and hotspots, and updates Mango, GTK and session environment settings.
Reopen applications that cache their cursor/theme.

## Control center and audio

The menu offers Wi-Fi, Bluetooth, output/input selection, hardware power profiles,
turning screens off and suspend. Wi-Fi passwords use a small GTK dialog and pass to
nmcli through stdin, never command-line arguments. Enterprise networks may need
NetworkManager configuration. No VPN, lock, settings or visual-performance duplicate
buttons are included in this menu.

The audio panels open at the clicked bar icon using Gtk4LayerShell. Both have **Close**
and Escape. Device selection moves active audio streams where supported.

## Clipboard

The 480×450 history window has thumbnails, search, a visible scrollbar, and batches
of 50 older entries. Close with X or Escape; cancelling never changes the clipboard.
Images and text have separate capture processes. Old HTML fragments are explicitly
labeled: an image cannot be recovered if only its HTML was saved.

The window uses accessible input/caret coordinates when available, otherwise the mouse.
It stays within the monitor and opens above fields near the bottom. It does not read
input-field contents or automatically paste into another application.

## Lock, idle and performance

Hyprlock uses a blurred wallpaper, palette colors and a visible password field.
Enter the existing login password and press Enter. Swaylock is a fallback when
Hyprlock is unavailable. Screen-off and suspend wait for lock confirmation.

Automatic idle is disabled by default. Configure lock, screen-off and suspend minutes
in Settings; zero disables automatic suspend. A managed swayidle still locks before
system sleep. Screen-off arms a wake listener before switching off outputs; a 60-second
recovery timer turns displays back on if needed, without unlocking the session.

**Visual performance** disables Mango animations, blur and shadows with a reversible
`local/performance.conf` overlay. The calendar switch follows the real state, including
hotkey changes. **Hardware power profiles** (power-saver, balanced, performance) control
hardware energy policy; they are independent and can be combined.

## Wallpaper colors

One Waypaper hook updates Mango borders, Waybar, Rofi/Fuzzel, SwayNC, wlogout (including
icons), Fish, Kitty, GTK3/GTK4 and existing Vencord/Vesktop QuickCSS installations.
Qt5/Qt6 use a generated **VictoriaWallustDark** Kvantum theme based on installed
MateriaDark. Original package files are never edited; author/license files are retained.
GTK and Qt keep dark surfaces and readable text. Some applications need reopening;
Flatpak and applications with their own styles may require separate setup.

Waybar starts once, after wallpaper/palette restoration, and detects the CPU temperature
sensor by identity. Startup services run without fixed sleeps or unnecessary portal
restarts. Put extra startup commands in `~/.config/mango/local/autostart.sh`.

## Screen sharing compatibility

Blur is temporarily disabled in the compositor defaults, all Settings profiles and
the Settings switch. Installation also migrates existing blur overrides. Animations,
shadows and the Hyprlock wallpaper blur remain available. This prevents older saved
settings or the Effects profile from silently restoring the failing configuration.

SceneFX issue [#198](https://github.com/wlrfx/scenefx/issues/198) documents invalid
capture damage with blur and multiple outputs. The matching local failure was
`Invalid buffer damage coordinates`, followed by the portal disconnecting. Disabling
blur restored capture in the reported setup, including Settings on the DP output.
This is a workaround, not a replacement for an upstream SceneFX fix. Re-enable the
control only after verifying the fixed library and cross-output capture together.

Brazil ABNT2 uses XKB layout `br`, variant `abnt2`, and model `abnt2`.
The console keymap is `br-abnt2`. When clearing a variant in Mango,
write `xkb_rules_variant=""`: a bare empty assignment is not parsed correctly
and can leave an earlier variant (such as `intl`) active.
