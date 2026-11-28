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
sys.dont_write_bytecode = True
import tempfile
import time
import tomllib

HOME = Path.home()
CONFIG = HOME / '.config'
MANGO = CONFIG / 'mango'
CACHE = Path(os.environ.get('XDG_CACHE_HOME') or HOME / '.cache') / 'wallust'
LAST_WALLPAPER = Path(os.environ.get('XDG_STATE_HOME') or HOME / '.local/state') / 'victoria/last-wallpaper'
# The user's wallpaper folder; hyprquickpaper browses it (hyprquickpaper/config.json).
WALLPAPERS = HOME / 'Pictures/Wallpapers'
PICKER_CONFIG = MANGO / 'hyprquickpaper/config.json'
IMAGE_SUFFIXES = {'.jpg', '.jpeg', '.png', '.webp'}


def wallust_render_config(config):
    """Adapt the bundled v4 extraction options for stable Wallust v3."""
    version = subprocess.run(['wallust', '--version'], capture_output=True, text=True,
                             check=True, timeout=5).stdout
    match = re.search(r'wallust\s+(\d+)\.', version)
    if not match:
        raise RuntimeError('Could not determine the installed Wallust version.')
    config = dict(config)
    if int(match[1]) == 3 and 'style' in config:
        # v3 puts kmeans in backend and dark/light in palette; v4 splits them.
        if config.get('palette') == 'kmeans':
            config['backend'] = 'kmeans'
        config['palette'] = config.pop('style')
    return config


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


def ensure_wallpaper_folder():
    """Create ~/Pictures/Wallpapers and seed it with the bundled wallpapers once."""
    WALLPAPERS.mkdir(parents=True, exist_ok=True)
    if not any(p.suffix.lower() in IMAGE_SUFFIXES for p in WALLPAPERS.iterdir()):
        for image in sorted((MANGO / 'wallpaper').glob('*')):
            if image.suffix.lower() in IMAGE_SUFFIXES:
                shutil.copy2(image, WALLPAPERS / image.name)
    return WALLPAPERS


def saved_wallpaper():
    """Last applied wallpaper, then an older Waypaper choice, then ~/Pictures/Wallpapers,
    then the bundled wallpapers."""
    if LAST_WALLPAPER.is_file() and (path := expand_image(LAST_WALLPAPER.read_text())):
        return path
    if path := waypaper_wallpaper():
        return path
    folders = (WALLPAPERS, MANGO / 'wallpaper')
    fallback = MANGO / 'wallpaper/wallpaper.jpg'
    for folder in folders:
        images = [p for p in sorted(folder.glob('*')) if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES] if folder.is_dir() else []
        if folder != WALLPAPERS and fallback in images:
            return fallback
        if images:
            return images[0]
    raise RuntimeError('No readable wallpaper in ~/Pictures/Wallpapers, Waypaper or the bundled wallpaper directory.')


def waypaper_wallpaper():
    """Selection saved by Waypaper (used before hyprquickpaper), preferring the color monitor."""
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
    return None


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
            if line.lstrip(': ').split(':', 1)[0] == preferred:
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
    notifications = MANGO / 'config/swaync'
    if notifications.is_dir():
        for name in ('config.json', 'style.css', 'performance-label.svg', 'performance-on.svg', 'performance-off.svg'):
            atomic_write(CONFIG / 'swaync' / name, (notifications / name).read_text())
        subprocess.run([sys.executable, str(MANGO / 'scripts/notification-calendar.py'), 'prepare'], check=True)
    # TOML targets point at the actual cache location, including custom XDG paths.
    config = (source / 'wallust.toml').read_text()
    config = config.replace("'~/.cache/wallust/victoria-palette.json'", json.dumps(str(CACHE / 'victoria-palette.json')))
    atomic_write(target / 'wallust.toml', config)
    ensure_wallpaper_folder()
    fish = CONFIG / 'fish/conf.d/victoria-wallust.fish'
    atomic_write(fish, (MANGO / 'config/fish/conf.d/victoria-wallust.fish').read_text())
    # Select before rewriting Waypaper, so multi-monitor choices are preserved.
    image = saved_wallpaper()
    path = CONFIG / 'waypaper/config.ini'
    ini = read_ini(path)
    settings = ini['Settings']
    hook = 'bash ' + shlex.quote(str(MANGO / 'scripts/wallust-reload.sh')) + ' $wallpaper'
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
    controls = MANGO / 'scripts/install-controls.py'
    if controls.is_file():
        subprocess.run([sys.executable, str(controls)], check=True)
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


def picker_accent(colors):
    """Tint hyprquickpaper's selection border with the same accent the bar uses."""
    if not PICKER_CONFIG.is_file():
        return
    import colorsys
    r, g, b = (int(colors['color5'][i:i + 2], 16) / 255 for i in (1, 3, 5))
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    # Same as Qt.lighter(color5, 1.6) in quickshell/shell.qml.
    r, g, b = colorsys.hsv_to_rgb(h, s if v * 1.6 <= 1 else s / (v * 1.6), min(1, v * 1.6))
    accent = '#%02X%02X%02X' % tuple(round(c * 255) for c in (r, g, b))
    try:
        config = json.loads(PICKER_CONFIG.read_text())
    except ValueError:
        return
    if config.get('border_color') != accent:
        config['border_color'] = accent
        atomic_write(PICKER_CONFIG, json.dumps(config, indent=2) + '\n')


def apply(image=None, install=False):
    CACHE.mkdir(parents=True, exist_ok=True)
    with (CACHE / 'victoria.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        last = expand_image(LAST_WALLPAPER.read_text()) if LAST_WALLPAPER.is_file() else None
        if image:
            selected = expand_image(image)
        else:
            selected = last or (None if install else active_wallpaper()) or saved_wallpaper()
        if selected is None:
            raise RuntimeError('The selected wallpaper does not exist.')
        settings_path = MANGO / 'local/settings.json'
        settings = json.loads(settings_path.read_text()) if settings_path.exists() else {}
        fixed = settings.get('color_mode') == 'fixed'
        if not fixed and not shutil.which('wallust'):
            raise RuntimeError('wallust is missing; install it and run scripts/wallust-reload.sh again.')
        # Skip Wallust's global PTY writes: Fish applies cached OSC sequences itself.
        # Explicit paths avoid an unrelated XDG_CONFIG_HOME selecting another config.
        destinations = {
            'waybar': MANGO / 'waybar/colors.css',
            'mango': MANGO / 'colors.conf',
            'terminal': CACHE / 'victoria-palette.json',
            'rofi': MANGO / 'config/rofi/colors.rasi',
            'fuzzel': MANGO / 'config/fuzzel.ini',
            'wlogout': CONFIG / 'wlogout/colors.css',
            'spotifast': CONFIG / 'spotifast/themes/Victoria Wallust.json',
        }
        # Render into staging: an invalid/missing template must not replace the
        # working desktop palette or publish a new Fish generation.
        config = tomllib.loads((CONFIG / 'wallust/wallust.toml').read_text())
        if not fixed:
            config = wallust_render_config(config)
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
                if fixed:
                    accent = settings.get('accent', '#B9413E')
                    if not re.fullmatch(r'#[0-9a-fA-F]{6}', accent):
                        raise ValueError('Invalid fixed accent color.')
                    colors = dict(background='#141218', foreground='#EEEAF2')
                    base = ['#201D25', '#E58181', '#A6C98D', '#E5C890', '#9EB6E8', accent, '#92C7C5', '#D6D1DD',
                            '#726B7D', '#F29A9A', '#B7DB9C', '#F0D5A1', '#B3C7F2', accent, '#A8DBD8', '#EEEAF2']
                    colors.update({f'color{i}': value for i, value in enumerate(base)})
                    def render(match):
                        name, _, transform = match[1].strip().partition('|')
                        value = colors[name.strip()]
                        return value.lstrip('#') if transform.strip() == 'strip' else value
                    for name in destinations:
                        template = CONFIG / 'wallust/templates' / config['templates'][name]['template']
                        (staging / name).write_text(re.sub(r'{{(.*?)}}', render, template.read_text()))
                else:
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
        from theme_extras import apply as apply_extras
        apply_extras(colors)
        atomic_write(LAST_WALLPAPER, str(selected.resolve()) + '\n')
        picker_accent(colors)
        if not install and os.environ.get('WAYLAND_DISPLAY'):
            # Mango watches colors.conf; only refresh an already-running Waybar.
            if shutil.which('pkill'):
                subprocess.run(['pkill', '-USR2', '-u', str(os.getuid()), '-x', 'waybar'], check=False)
        # SwayNC imports Waybar's palette; refresh it after each successful render.
        if shutil.which('swaync-client') and os.environ.get('WAYLAND_DISPLAY'):
            try:
                subprocess.run(['swaync-client', '-sw', '-rs'], check=False,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
            except (OSError, subprocess.TimeoutExpired):
                pass
        print(f'Wallust: Waybar, Mango, Fish, Rofi, Fuzzel, wlogout and Spotifast colors generated from {selected.name}')


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
