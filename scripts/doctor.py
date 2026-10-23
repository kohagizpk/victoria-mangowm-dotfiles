#!/usr/bin/env python3
"""Read-only checks; never installs packages or changes the running session."""
from pathlib import Path
import os
import shutil
import sys


def main():
    home = Path.home()
    config = home / '.config'
    mango = config / 'mango'
    cache = Path(os.environ.get('XDG_CACHE_HOME') or home / '.cache') / 'wallust'
    failures = 0

    def check(ok, label, hint):
        nonlocal failures
        print(f'{"OK" if ok else "MISSING"}: {label}' + ('' if ok else f' — {hint}'))
        failures += not ok

    for command in ('mango', 'waybar', 'wallust', 'fish', 'awww', 'waypaper', 'kitty', 'rofi', 'fuzzel', 'wlogout'):
        check(shutil.which(command), command, f'Install {command} with your distribution package manager.')
    for name in ('config.conf', 'colors.conf', 'local/custom.conf', 'waybar/config.jsonc', 'waybar/colors.css',
                 'config/rofi/colors.rasi', 'config/fuzzel.ini'):
        path = mango / name
        check(path.is_file(), name, 'Run ./install.sh --config-only.')
    for name in ('victoria-generation', 'victoria-colors.fish', 'sequences'):
        check((cache / name).is_file(), f'Wallust {name}', 'Run bash ~/.config/mango/scripts/wallust-reload.sh; see ~/.cache/wallust/victoria.log (or your XDG cache directory).')
    for version in (3, 4):
        path = config / f'gtk-{version}.0/settings.ini'
        check(path.is_file() and 'Materia-dark-compact' in path.read_text(), f'GTK {version} dark theme', 'Run the full installer to configure Materia-dark-compact.')
    path = config / 'Kvantum/kvantum.kvconfig'
    check(path.is_file() and 'MateriaDark' in path.read_text(), 'Qt/Kvantum dark theme', 'Run the full installer and restart Ark/qBittorrent.')
    print('Diagnostic only: no files, services or packages were modified.')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
