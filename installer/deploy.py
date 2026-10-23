#!/usr/bin/env python3
"""Explicit source-to-runtime mapping, with backups and preserved user overrides."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HOME = Path.home()
CONFIG = HOME / '.config'
MANGO = CONFIG / 'mango'
MAPPING = {
    'config/mango': '.', 'config/waybar': 'waybar', 'scripts': 'scripts',
    'wallpapers': 'wallpaper', 'config/wallust': 'config/wallust',
    'config/fish': 'config/fish', 'config/rofi': 'config/rofi',
    'config/fuzzel/fuzzel.ini': 'config/fuzzel.ini', 'config/wlogout': 'config/wlogout',
    'config/fastfetch': 'config/terminal_configs', 'themes': 'config',
}


def copy(source, target):
    if source.is_dir():
        for item in source.iterdir():
            copy(item, target / item.name)
    else:
        # Never follow a destination symlink into unrelated user files.
        for parent in [target.parent, *target.parents]:
            if parent == HOME.parent:
                break
            if parent.is_symlink():
                raise RuntimeError(f'Refusing to write through directory symlink: {parent}')
        target.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(dir=target.parent)
        os.close(fd)
        try:
            shutil.copy2(source, temporary)
            os.replace(temporary, target)
        finally:
            Path(temporary).unlink(missing_ok=True)


def stage(target, config_only=False):
    if ROOT == MANGO or MANGO in ROOT.parents:
        raise RuntimeError('Move the checkout outside ~/.config/mango before installing (for example ~/src/victoria-mangowm-dotfiles).')
    for source, destination in MAPPING.items():
        copy(ROOT / source, target / destination)
    for script in target.rglob('*.sh'):
        script.chmod(script.stat().st_mode | 0o111)
    local = target / 'local'
    if (MANGO / 'local').is_dir():
        copy(MANGO / 'local', local)
    local.mkdir(exist_ok=True)
    for name in ('input.conf', 'monitor.conf', 'custom.conf'):
        path = local / name
        if not path.exists():
            path.write_text('# Personal overrides; preserved by the installer.\n')
            if name == 'monitor.conf' and (MANGO / 'monitor.conf').is_file():
                copy(MANGO / 'monitor.conf', path)
            if name == 'input.conf' and config_only and (MANGO / 'config.conf').is_file():
                lines = (MANGO / 'config.conf').read_text().splitlines()
                path.write_text('\n'.join(line for line in lines if re.match(r'^\s*(xkb_rules_\w+|repeat_rate|repeat_delay|numlock_on)\s*=', line)) + '\n')
    if config_only:
        for name in ('apps.conf', 'bind.conf', 'env.conf', 'waybar/config.jsonc'):
            if (MANGO / name).is_file():
                copy(MANGO / name, target / name)

        bar = target / 'waybar/config.jsonc'
        bar.write_text(bar.read_text().replace('WaybarCava.sh', 'waybar-cava.sh'))


def install():
    with tempfile.TemporaryDirectory(prefix='victoria-deploy-') as temporary:
        staged = Path(temporary)
        stage(staged, config_only=True)
        backup = Path(tempfile.mkdtemp(prefix='victoria-backup.', dir=HOME))
        for name in ('mango', 'wallust', 'waypaper', 'fish', 'wlogout', 'kitty', 'fastfetch'):
            source = CONFIG / name
            if source.exists():
                shutil.copytree(source, backup / '.config' / name, symlinks=True)
        state = Path(os.environ.get('XDG_STATE_HOME') or HOME / '.local/state') / 'waypaper'
        if state.exists():
            shutil.copytree(state, backup / 'waypaper-state', symlinks=True)
        print(f'Backup: {backup}', flush=True)
        copy(staged, MANGO)
        # Existing app preferences stay untouched; only new installations get defaults.
        for source, destination in (
            ('config/kitty/kitty.conf', 'kitty/kitty.conf'),
            ('config/fastfetch/fastfetch.jsonc', 'fastfetch/config.jsonc'),
            ('config/wlogout/layout', 'wlogout/layout'),
        ):
            if not (CONFIG / destination).exists():
                copy(ROOT / source, CONFIG / destination)
        for name in ('style.css', 'colors.css'):
            copy(ROOT / 'config/wlogout' / name, CONFIG / 'wlogout' / name)
        subprocess.run([sys.executable, str(MANGO / 'scripts/theme.py'), 'setup'], check=True)
        if shutil.which('wallust'):
            subprocess.run([sys.executable, str(MANGO / 'scripts/theme.py'), 'apply', '--install'], check=True)
        else:
            print('Wallust is missing: fallback colors are installed. Install wallust, then run ~/.config/mango/scripts/wallust-reload.sh.')
        print('User configurations installed. Packages, login manager and system services were not changed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['stage', 'install'])
    parser.add_argument('destination', nargs='?', type=Path)
    args = parser.parse_args()
    if sys.version_info < (3, 11):
        parser.error('Python 3.11+ is required.')
    if args.command == 'stage':
        if args.destination is None:
            parser.error('stage needs a destination')
        stage(args.destination)
    else:
        install()


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(f'Installation failed: {error}')
