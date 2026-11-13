# Project layout

Keep the checkout outside `~/.config/mango` (for example `~/src/victoria-mangowm-dotfiles`).
`install.sh` is the single entry point: full interactive install, `--config-only`,
`--diagnose`, or `--dry-run`. Configuration-only mode never installs dependencies or
changes system services; use full installation on a fresh machine.

| Source | Installed runtime |
| --- | --- |
| `config/mango/` | `~/.config/mango/` |
| `config/waybar/` | `~/.config/mango/waybar/` |
| `config/hyprlock/hyprlock.conf` | `~/.config/mango/config/hyprlock/hyprlock.conf` |
| `config/{rofi,swaync,wlogout,wallust,...}/` | Mango templates; the installer/hooks activate app configurations |
| `scripts/` | `~/.config/mango/scripts/` |
| `themes/`, `wallpapers/` | Bundled assets, deployed by the installer |
| `installer/` | Package selection, deployment and desktop integration |
| `tests/`, `.github/workflows/` | Isolated regression tests and CI |
| `docs/` | User and maintenance documentation |

Executable entry points use hyphenated names; reusable Python helpers use underscores.
Settings helpers, clipboard helpers and theme renderers stay in `scripts/` so both source
and runtime use ordinary Python imports without a package-install step. Static templates
live under `config/`.

`~/.config/mango/local/` holds personal overrides, settings and startup commands.
State and generated caches live in the user's XDG state/cache/runtime directories.
They are not source assets and must not be committed. Installers back up affected
configuration before deployment in `$XDG_STATE_HOME/victoria/backups` (default
`~/.local/state/victoria/backups`). Tests use temporary directories under `/tmp`,
not the real home directory. Reinstalling preserves local overrides and existing
bindings; managed legacy clipboard bindings are migrated to the current browser.

Run `python3 -m unittest discover -s tests` and `git diff --check` before publishing.
Full package/login testing on each supported distribution still requires a real machine.
