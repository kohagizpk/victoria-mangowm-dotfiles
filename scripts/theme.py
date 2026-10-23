#!/usr/bin/env python3
"""Install and refresh Victoria's wallpaper palette. Python standard library only."""
import argparse
import configparser
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib

HOME = Path.home()
CONFIG = HOME / '.config'
MANGO = CONFIG / 'mango'
CACHE = Path(os.environ.get('XDG_CACHE_HOME') or HOME / '.cache') / 'wallust'


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(text)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def read_ini(path, section="Settings"):
    config = configparser.ConfigParser(interpolation=None, strict=False)
    if path.exists():
        with path.open() as stream:
            config.read_file(stream)
    if not config.has_section(section):
        config.add_section(section)
    return config


def expand_image(value):
    path = Path(os.path.expanduser(value.strip()))
    return path if path.is_file() else None


def saved_wallpaper():
    ini = read_ini(CONFIG / 'waypaper/config.ini')
    settings = ini['Settings']
    if settings.getboolean('use_xdg_state', fallback=False):
        state = Path(os.environ.get('XDG_STATE_HOME') or HOME / '.local/state')
        settings = read_ini(state / 'waypaper/state.ini', 'State')['State']
    images = settings.get('wallpaper', '').splitlines()
    monitors = settings.get('monitors', '').splitlines()
    preferred = os.environ.get('VICTORIA_COLOR_MONITOR', 'HDMI-A-1')
    for monitor, image in zip(monitors, images):
        if monitor.strip() == preferred and (path := expand_image(image)):
            return path
    for image in images:
        if path := expand_image(image):
            return path
    fallback = MANGO / 'wallpaper/wallpaper.jpg'
    if fallback.is_file():
        return fallback
    for path in sorted((MANGO / 'wallpaper').glob('*')):
        if path.is_file() and path.suffix.lower() in {'.jpg', '.jpeg', '.png', '.webp'}:
            return path
    raise RuntimeError('No readable wallpaper in Waypaper or the bundled wallpaper directory.')


def active_wallpaper():
    if not shutil.which('awww'):
        return None
    try:
        result = subprocess.run(['awww', 'query'], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None
    preferred = os.environ.get('VICTORIA_COLOR_MONITOR', 'HDMI-A-1')
    found = []
    for line in result.stdout.splitlines():
        if 'currently displaying: image: ' not in line:
            continue
        image = line.split('currently displaying: image: ', 1)[1]
        path = expand_image(image)
        if path:
            if line.split(':', 1)[0] == preferred:
                return path
            found.append(path)
    return found[0] if found else None


def setup():
    """Called after install.sh has backed up user configuration."""
    source = MANGO / 'config/wallust'
    target = CONFIG / 'wallust'
    (target / 'templates').mkdir(parents=True, exist_ok=True)
    for template in (source / 'templates').iterdir():
        if template.is_file():
            shutil.copy2(template, target / 'templates' / template.name)
    # TOML targets point at the actual cache location, including custom XDG paths.
    config = (source / 'wallust.toml').read_text()
    config = config.replace("'~/.cache/wallust/victoria-palette.json'", json.dumps(str(CACHE / 'victoria-palette.json')))
    atomic_write(target / 'wallust.toml', config)
    fish = CONFIG / 'fish/conf.d/victoria-wallust.fish'
    atomic_write(fish, (MANGO / 'config/fish/conf.d/victoria-wallust.fish').read_text())
    # Select before rewriting Waypaper, so multi-monitor choices are preserved.
    image = saved_wallpaper()
    path = CONFIG / 'waypaper/config.ini'
    ini = read_ini(path)
    settings = ini['Settings']
    hook = 'bash ' + shlex.quote(str(MANGO / 'scripts/wallust-reload.sh'))
    previous = settings.get('post_command', '').strip()
    # Preserve an unrelated user's hook, but do not duplicate our own on reruns.
    if previous and 'wallust-reload.sh' not in previous:
        hook = previous + '; ' + hook
    elif previous and 'wallust-reload.sh' in previous and '; ' in previous:
        hook = previous
    settings['backend'] = 'awww'
    settings['post_command'] = hook
    settings.setdefault('folder', str(MANGO / 'wallpaper'))
    settings.setdefault('fill', 'fill')
    # Existing multi-monitor and state-file selections stay intact.
    if not settings.get('wallpaper', '').strip() and not settings.getboolean('use_xdg_state', fallback=False):
        settings['wallpaper'] = str(image)
        settings['monitors'] = 'All'
    import io
    stream = io.StringIO()
    ini.write(stream)
    atomic_write(path, stream.getvalue())
    if settings.getboolean('use_xdg_state', fallback=False):
        state_path = Path(os.environ.get('XDG_STATE_HOME') or HOME / '.local/state') / 'waypaper/state.ini'
        state = read_ini(state_path, 'State')
        state['State']['backend'] = 'awww'
        if not state['State'].get('wallpaper', '').strip():
            state['State']['wallpaper'] = str(image)
            state['State']['monitors'] = 'All'
        stream = io.StringIO()
        state.write(stream)
        atomic_write(state_path, stream.getvalue())
    return image


def terminal_colors():
    colors = json.loads((CACHE / 'victoria-palette.json').read_text())
    names = ['background', 'foreground', *[f'color{i}' for i in range(16)]]
    for name in names:
        if not re.fullmatch(r'#[0-9A-Fa-f]{6}', colors.get(name, '')):
            raise RuntimeError(f'Invalid Wallust color: {name}')
    sequence = ''.join(f'\033]4;{i};{colors[f"color{i}"]}\033\\' for i in range(16))
    sequence += ''.join(f'\033]{code};{colors[name]}\033\\' for code, name in ((10, 'foreground'), (11, 'background'), (12, 'color5')))
    atomic_write(CACHE / 'sequences', sequence)
    mapping = {
        'fish_color_normal': 'foreground', 'fish_color_command': 'color5',
        'fish_color_keyword': 'color5', 'fish_color_quote': 'color2',
        'fish_color_redirection': 'color6', 'fish_color_end': 'color6',
        'fish_color_error': 'color1', 'fish_color_param': 'foreground',
        'fish_color_comment': 'color8', 'fish_color_autosuggestion': 'color8',
        'fish_color_operator': 'color4', 'fish_color_escape': 'color6',
        'fish_color_cwd': 'color5', 'fish_color_user': 'color4',
        'fish_color_host': 'color6', 'fish_color_status': 'color1',
        'fish_pager_color_prefix': 'color5', 'fish_pager_color_completion': 'foreground',
        'fish_pager_color_description': 'color7', 'fish_pager_color_progress': 'color6',
    }
    fish = '# Generated by Victoria Wallust; do not edit.\n'
    fish += ''.join(f'set -g {name} {colors[color][1:]}\n' for name, color in mapping.items())
    fish += f'set -g fish_color_search_match --background={colors["color8"][1:]} {colors["foreground"][1:]}\n'
    atomic_write(CACHE / 'victoria-colors.fish', fish)
    # Publish last: open Fish sessions load the complete generation at next prompt.
    atomic_write(CACHE / 'victoria-generation', str(time.time_ns()) + '\n')


def apply(image=None, install=False):
    CACHE.mkdir(parents=True, exist_ok=True)
    with (CACHE / 'victoria.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if install:
            selected = expand_image(image) if image else saved_wallpaper()
        else:
            selected = active_wallpaper() or (expand_image(image) if image else None) or saved_wallpaper()
        if selected is None:
            raise RuntimeError('The selected wallpaper does not exist.')
        if not shutil.which('wallust'):
            raise RuntimeError('wallust is missing; install it and run scripts/wallust-reload.sh again.')
        # Skip Wallust's global PTY writes: Fish applies cached OSC sequences itself.
        # Explicit paths avoid an unrelated XDG_CONFIG_HOME selecting another config.
        destinations = {
            'waybar': MANGO / 'waybar/colors.css',
            'mango': MANGO / 'colors.conf',
            'terminal': CACHE / 'victoria-palette.json',
        }
        # Render into staging: an invalid/missing template must not replace the
        # working desktop palette or publish a new Fish generation.
        config = tomllib.loads((CONFIG / 'wallust/wallust.toml').read_text())
        with tempfile.TemporaryDirectory(prefix='victoria-render-', dir=CACHE) as folder:
            staging = Path(folder)
            staged_config = ''.join(f'{key} = {json.dumps(value)}\n' for key, value in config.items() if not isinstance(value, dict))
            staged_config += '\n[templates]\n'
            for name in destinations:
                template = config['templates'][name]['template']
                staged_config += f'{name} = {{ template = {json.dumps(template)}, target = {json.dumps(str(staging / name))} }}\n'
            (staging / 'wallust.toml').write_text(staged_config)
            command = ['wallust', '--skip-sequences', '--no-hooks', '--config-file', str(staging / 'wallust.toml'),
                       '--templates-dir', str(CONFIG / 'wallust/templates'), 'run', str(selected)]
            with (CACHE / 'victoria.log').open('a') as log:
                log.write(f'\nWallpaper: {selected}\n'); log.flush()
                subprocess.run(command, stdout=log, stderr=log, check=True)
            for name in destinations:
                path = staging / name
                if not path.is_file() or not path.stat().st_size or '{{' in path.read_text():
                    raise RuntimeError(f'Wallust did not render the {name} template')
            colors = json.loads((staging / 'terminal').read_text())
            for name in ['background', 'foreground', *[f'color{i}' for i in range(16)]]:
                if not re.fullmatch(r'#[0-9A-Fa-f]{6}', colors.get(name, '')):
                    raise RuntimeError(f'Invalid rendered color: {name}')
            for name, destination in destinations.items():
                atomic_write(destination, (staging / name).read_text())
        terminal_colors()
        if not install and os.environ.get('WAYLAND_DISPLAY'):
            # Mango watches colors.conf; only refresh an already-running Waybar.
            if shutil.which('pkill'):
                subprocess.run(['pkill', '-USR2', '-u', str(os.getuid()), '-x', 'waybar'], check=False)
        print(f'Wallust: Waybar, Mango and Fish colors generated from {selected.name}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('setup')
    sub.add_parser('wallpaper')
    sub.add_parser('active-wallpaper')
    refresh = sub.add_parser('apply')
    refresh.add_argument('--install', action='store_true')
    refresh.add_argument('image', nargs='?')
    args = parser.parse_args()
    try:
        if args.command == 'setup':
            print(setup())
        elif args.command == 'active-wallpaper':
            selected = active_wallpaper()
            if selected is None:
                return 1
            print(selected)
        elif args.command == 'wallpaper':
            print(saved_wallpaper())
        else:
            apply(args.image, args.install)
    except (OSError, ValueError, RuntimeError, configparser.Error, KeyError, subprocess.SubprocessError) as error:
        print(f'Victoria theme: {error}. Details: {CACHE / "victoria.log"}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
