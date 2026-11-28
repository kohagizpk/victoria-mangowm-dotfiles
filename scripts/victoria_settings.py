#!/usr/bin/env python3
"""Victoria desktop controls. Standard-library backend, independent of GTK."""
import configparser
import io
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

HOME = Path.home()
MANGO = HOME / '.config/mango'
LOCAL = MANGO / 'local'
STATE = Path(os.environ.get('XDG_STATE_HOME') or HOME / '.local/state') / 'victoria'
DEFAULTS = dict(font_size=12, gaps=8, border=2, radius=12, opacity=0.96,
                animations=True, blur=False, bar_position='top', color_mode='wallpaper', accent='#B9413E',
                shadows=True, animation_speed='normal', cursor_size=36, focus_follows_mouse=True,
                natural_scroll=False, tap_to_click=True, bar_margin=0,
                show_stats=True, show_media=True, show_visualizer=True, show_tray=True,
                clock_seconds=True, clock_24h=True, notification_position='top-right',
                notification_timeout=8, notification_width=400, notification_images=True, idle_enabled=False, idle_lock_minutes=10, idle_screen_minutes=15, idle_suspend_minutes=0,
                repeat_rate=25, repeat_delay=600)
PROFILES = {
    'Minimal': dict(font_size=12, gaps=4, border=1, radius=6, opacity=1.0, animations=False, blur=False),
    'Comfort': dict(font_size=14, gaps=10, border=2, radius=12, opacity=0.98, animations=True, blur=False),
    'Effects': dict(font_size=12, gaps=8, border=2, radius=16, opacity=0.94, animations=True, blur=False),
}
# Display name -> (xkb layout, xkb variant). Every pair is checked against evdev.lst.
KEYBOARDS = {
    'English (US)': ('us', ''), 'English (US, international)': ('us', 'intl'),
    'English (US, AltGr international)': ('us', 'altgr-intl'), 'English (UK)': ('gb', ''),
    'English (Dvorak)': ('us', 'dvorak'), 'English (Colemak)': ('us', 'colemak'),
    'English (Colemak-DH)': ('us', 'colemak_dh'),
    'Portuguese (Brazil, ABNT2)': ('br', ''), 'Portuguese (Brazil, ThinkPad)': ('br', 'thinkpad'),
    'Portuguese (Portugal)': ('pt', ''), 'Spanish (Spain)': ('es', ''), 'Spanish (Latin America)': ('latam', ''),
    'French (AZERTY)': ('fr', ''), 'French (Canada)': ('ca', ''), 'French (Belgium)': ('be', ''),
    'German': ('de', ''), 'German (Switzerland)': ('ch', ''), 'Italian': ('it', ''), 'Dutch': ('nl', ''),
    'Polish': ('pl', ''), 'Czech': ('cz', ''), 'Hungarian': ('hu', ''), 'Romanian': ('ro', ''),
    'Swedish': ('se', ''), 'Norwegian': ('no', ''), 'Danish': ('dk', ''), 'Finnish': ('fi', ''),
    'Turkish': ('tr', ''), 'Greek': ('gr', ''), 'Russian': ('ru', ''), 'Ukrainian': ('ua', ''),
    'Hebrew': ('il', ''), 'Arabic': ('ara', ''), 'Japanese': ('jp', ''), 'Korean': ('kr', ''),
}
# Names used by older versions of the setup wizard.
KEYBOARD_ALIASES = {'US': 'English (US)', 'US international': 'English (US, international)',
                    'Brazil ABNT2': 'Portuguese (Brazil, ABNT2)'}
LAYOUT_SWITCH = {'Alt + Shift': 'grp:alt_shift_toggle', 'Super + Space': 'grp:win_space_toggle',
                 'Ctrl + Shift': 'grp:ctrl_shift_toggle', 'Caps Lock': 'grp:caps_toggle'}
TERMINALS = ('kitty', 'foot', 'alacritty', 'wezterm', 'ghostty')
BROWSERS = ('firefox', 'helium-browser', 'brave', 'chromium', 'zen-browser', 'librewolf')
BEGIN = '# BEGIN VICTORIA SETTINGS'
END = '# END VICTORIA SETTINGS'


def atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(text)
        os.replace(tmp, path)
    finally:
        Path(tmp).unlink(missing_ok=True)


def read_settings():
    data = dict(DEFAULTS)
    # Read existing compositor choices before a user has saved a profile.
    for p in (MANGO / 'config.conf', LOCAL / 'custom.conf'):
        if not p.exists():
            continue
        mapping = {'gap_inner_horizontal': 'gaps', 'border_px': 'border', 'border_radius': 'radius',
                   'unfocused_opacity': 'opacity', 'animations': 'animations', 'blur': 'blur',
                   'shadows': 'shadows', 'cursor_size': 'cursor_size', 'sloppy_focus': 'focus_follows_mouse',
                   'trackpad_natural_scrolling': 'natural_scroll', 'tap_to_click': 'tap_to_click',
                   'repeat_rate': 'repeat_rate', 'repeat_delay': 'repeat_delay'}
        for key, value in re.findall(r'^\s*(\w+)\s*=\s*([^#\n]+)', p.read_text(), re.M):
            if key in mapping:
                try:
                    dest = mapping[key]
                    data[dest] = bool(int(value)) if type(DEFAULTS[dest]) is bool else float(value) if dest == 'opacity' else int(value)
                except ValueError:
                    pass
    # New controls inherit the current desktop instead of imposing defaults.
    bar = MANGO / 'waybar/config.jsonc'
    if bar.exists():
        import bar_config
        configs = bar_config.parse(bar.read_text())
        config = configs[0] if isinstance(configs, list) else configs
        modules = sum((config.get('modules-' + side, []) for side in ('left','center','right')), [])
        for key, names in bar_config.VISIBILITY.items():
            data[key] = any(name in modules for name in names)
        fmt = config.get('clock', {}).get('format', '')
        data['clock_seconds'] = '%S' in fmt
        data['clock_24h'] = '%I' not in fmt
        data['bar_position'] = config.get('position', 'top')
        margin = config.get('margin-top', 0)
        if isinstance(margin, int): data['bar_margin'] = min(16, max(0, margin))
    notifications = HOME / '.config/swaync/config.json'
    if notifications.exists():
        config = json.loads(notifications.read_text())
        position = config.get('positionY', 'top') + '-' + config.get('positionX', 'right')
        if position in ('top-right','top-left','bottom-right','bottom-left'): data['notification_position'] = position
        data['notification_timeout'] = max(3, min(20, config.get('timeout', 8)))
        data['notification_width'] = max(300, min(600, config.get('notification-window-width', 400)))
        data['notification_images'] = config.get('image-visibility') != 'never'
    p = LOCAL / 'settings.json'
    if p.exists():
        data.update(json.loads(p.read_text()))
    return validate_settings(data)


def validate_settings(data):
    result = {key: data.get(key, val) for key, val in DEFAULTS.items()}
    for key, lo, hi in [('font_size', 10, 20), ('gaps', 0, 30), ('border', 0, 8), ('radius', 0, 30), ('cursor_size', 16, 64), ('bar_margin', 0, 16), ('notification_timeout', 3, 20), ('notification_width', 300, 600), ('idle_lock_minutes', 1, 120), ('idle_screen_minutes', 1, 180), ('idle_suspend_minutes', 0, 240), ('repeat_rate', 10, 80), ('repeat_delay', 150, 1000)]:
        if type(result[key]) is not int or not lo <= result[key] <= hi:
            raise ValueError(f'{key} must be between {lo} and {hi}.')
    if isinstance(result['opacity'], bool) or not isinstance(result['opacity'], (float, int)) or not 0.7 <= result['opacity'] <= 1:
        raise ValueError('Opacity must be between 0.70 and 1.00.')
    for key in (key for key, value in DEFAULTS.items() if type(value) is bool):
        if type(result[key]) is not bool:
            raise ValueError(f'{key} must be true or false.')
    if result['bar_position'] not in ('top', 'bottom') or result['color_mode'] not in ('wallpaper', 'fixed'):
        raise ValueError('Invalid bar position or color mode.')
    if result['idle_enabled'] and (result['idle_screen_minutes'] < result['idle_lock_minutes'] or (result['idle_suspend_minutes'] and result['idle_suspend_minutes'] < result['idle_screen_minutes'])):
        raise ValueError('Idle times must follow lock ≤ screen off ≤ suspend. Set suspend to 0 to disable it.')
    if result['animation_speed'] not in ('fast', 'normal', 'relaxed'):
        raise ValueError('Invalid animation speed.')
    if result['notification_position'] not in ('top-right', 'top-left', 'bottom-right', 'bottom-left'):
        raise ValueError('Invalid notification position.')
    if not isinstance(result['accent'], str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', result['accent']):
        raise ValueError('Use a color such as #B9413E.')
    # SceneFX #198: keep legacy saved settings from restoring unsafe blur.
    result['blur'] = False
    return result


def managed(text, body):
    text = re.sub(re.escape(BEGIN) + r'.*?' + re.escape(END) + r'\n?', '', text, flags=re.S)
    return text.rstrip() + '\n\n' + BEGIN + '\n' + body.rstrip() + '\n' + END + '\n'


def command(args, timeout=8, required=True):
    result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if required and result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or f'{args[0]} failed.')
    return result


def snapshot(paths):
    return {p: p.read_bytes() if p.exists() else None for p in paths}


def restore(saved):
    for p, content in saved.items():
        if content is None:
            p.unlink(missing_ok=True)
        else:
            atomic(p, content.decode())


def check_mango():
    command(['mango', '-c', str(MANGO / 'config.conf'), '-p'])


def refresh_bar_config():
    import bar_config
    runtime = Path(os.environ.get('XDG_RUNTIME_DIR') or os.environ.get('XDG_CACHE_HOME') or HOME / '.cache') / 'victoria-waybar'
    content = bar_config.current()
    for p in runtime.glob('config.*.jsonc'):
        atomic(p, content)


def reload_ui():
    refresh_bar_config()
    if not os.environ.get('WAYLAND_DISPLAY'):
        return
    for args in (['pkill', '-USR2', '-u', str(os.getuid()), '-x', 'waybar'], ['swaync-client', '-sw', '-rs']):
        if shutil.which(args[0]):
            try:
                command(args, timeout=4, required=False)
            except (OSError, subprocess.TimeoutExpired):
                pass


def save_appearance(values):
    values = validate_settings(values)
    paths = [LOCAL / 'custom.conf', LOCAL / 'settings.json', LOCAL / 'appearance.css', MANGO / 'env.conf', MANGO / 'autostart.sh',
             MANGO / 'waybar/config.jsonc', MANGO / 'waybar/style.css',
             HOME / '.config/swaync/style.css', HOME / '.config/swaync/config.json', MANGO / 'config/rofi/theme.rasi']
    paths += [HOME/f'.config/gtk-{v}.0/settings.ini' for v in (3,4)]
    before = snapshot(paths)
    try:
        v = values
        from cursor_theme import prepare
        cursor_theme = prepare(HOME,MANGO,v['cursor_size'])
        body = '\n'.join(f'{key}={value}' for key, value in {
            'gap_inner_horizontal': v['gaps'], 'gap_inner_vertical': v['gaps'],
            'gap_outer_horizontal': v['gaps'], 'gap_outer_vertical': v['gaps'],
            'border_px': v['border'], 'border_radius': v['radius'], 'unfocused_opacity': v['opacity'],
            'animations': int(v['animations']), 'layer_animations': int(v['animations']),
            'blur': int(v['blur']), 'blur_layer': int(v['blur']),
            'shadows': int(v['shadows']), 'layer_shadows': int(v['shadows']),
            'cursor_theme': cursor_theme, 'cursor_size': v['cursor_size'], 'sloppy_focus': int(v['focus_follows_mouse']),
            'trackpad_natural_scrolling': int(v['natural_scroll']), 'tap_to_click': int(v['tap_to_click']),
            'repeat_rate': v['repeat_rate'], 'repeat_delay': v['repeat_delay']}.items())
        speed = {'fast': 0.75, 'normal': 1, 'relaxed': 1.4}[v['animation_speed']]
        body += '\n' + '\n'.join(f'animation_duration_{key}={round(value * speed)}' for key, value in
                                   {'move':350, 'open':280, 'tag':250, 'close':350, 'focus':100}.items())
        p = LOCAL / 'custom.conf'
        atomic(p, managed(p.read_text() if p.exists() else '', body))
        p = MANGO / 'env.conf'
        if p.exists():
            text = re.sub(r'^env=XCURSOR_SIZE,.*$', f'env=XCURSOR_SIZE,{v["cursor_size"]}', p.read_text(), flags=re.M)
            if 'env=XCURSOR_SIZE,' not in text: text += f'\nenv=XCURSOR_SIZE,{v["cursor_size"]}\n'
            text = re.sub(r'^env=XCURSOR_THEME,.*$', 'env=XCURSOR_THEME,'+cursor_theme, text, flags=re.M)
            if 'env=XCURSOR_THEME,' not in text:text+='\nenv=XCURSOR_THEME,'+cursor_theme+'\n'
            atomic(p, text)
        p = MANGO / 'autostart.sh'
        if p.exists():
            atomic(p, re.sub(r'^export XCURSOR_SIZE=.*$', f'export XCURSOR_SIZE={v["cursor_size"]}', p.read_text(), flags=re.M))
        for version in (3,4):
            p=HOME/f'.config/gtk-{version}.0/settings.ini'
            ini=configparser.ConfigParser(interpolation=None,strict=False);ini.optionxform=str
            if p.exists():ini.read(p)
            if not ini.has_section('Settings'):ini.add_section('Settings')
            ini['Settings']['gtk-cursor-theme-name']=cursor_theme
            ini['Settings']['gtk-cursor-theme-size']=str(v['cursor_size'])
            stream=io.StringIO();ini.write(stream,space_around_delimiters=False);atomic(p,stream.getvalue())
        p=MANGO/'autostart.sh'
        if p.exists():atomic(p,re.sub(r'^export XCURSOR_THEME=.*$', 'export XCURSOR_THEME='+cursor_theme,p.read_text(),flags=re.M))
        check_mango()
        css = f'* {{ font-size: {v["font_size"]}px; }}\n#workspaces button:not(.empty):not(.active) {{ font-size: {v["font_size"] + 2}px; }}\n'
        atomic(LOCAL / 'appearance.css', css)
        for p, relative in [(MANGO / 'waybar/style.css', '../local/appearance.css'),
                            (HOME / '.config/swaync/style.css', '../mango/local/appearance.css')]:
            if p.exists():
                text = re.sub(r'/\* VICTORIA APPEARANCE \*/.*?/\* END APPEARANCE \*/', '', p.read_text(), flags=re.S)
                atomic(p, text.rstrip() + f'\n/* VICTORIA APPEARANCE */\n@import "{relative}";\n/* END APPEARANCE */\n')
        p = MANGO / 'config/rofi/theme.rasi'
        if p.exists():
            text = re.sub(r'/\* VICTORIA FONT \*/.*?/\* END FONT \*/', '', p.read_text(), flags=re.S)
            atomic(p, text.rstrip() + f'\n/* VICTORIA FONT */\n* {{ font: "JetBrainsMono Nerd Font {v["font_size"]}"; }}\n/* END FONT */\n')
        p = MANGO / 'waybar/config.jsonc'
        text, count = re.subn(r'("position"\s*:\s*")[^"]+("\s*[,}])', lambda m: m[1] + v['bar_position'] + m[2], p.read_text())
        if not count:
            raise ValueError('Waybar has no position field to change.')
        atomic(p, text)
        p = HOME / '.config/swaync/config.json'
        if p.exists():
            notifications = json.loads(p.read_text())
            y, x = v['notification_position'].split('-')
            notifications.update({'positionX': x, 'positionY': y, 'timeout': v['notification_timeout'],
                                  'notification-window-width': v['notification_width'],
                                  'image-visibility': 'when-available' if v['notification_images'] else 'never'})
            atomic(p, json.dumps(notifications, ensure_ascii=False, indent=2) + '\n')
        atomic(LOCAL / 'settings.json', json.dumps(values, indent=2) + '\n')
        # Refresh the palette only when the color selection changes.
        previous = json.loads(before[LOCAL / 'settings.json']) if before[LOCAL / 'settings.json'] else DEFAULTS
        if any(previous.get(k) != values[k] for k in ('accent', 'color_mode')):
            command(['python3', str(MANGO / 'scripts/theme.py'), 'apply', '--install'], timeout=60)
        if any(previous.get(k, DEFAULTS[k]) != values[k] for k in ('idle_enabled','idle_lock_minutes','idle_screen_minutes','idle_suspend_minutes')):
            command(['python3', str(MANGO / 'scripts/session-controls.py'), 'idle-restart'])
        if os.environ.get('WAYLAND_DISPLAY'):
            for args in (['mmsg','dispatch','reload_config'],['gsettings','set','org.gnome.desktop.interface','cursor-size',str(v['cursor_size'])],['gsettings','set','org.gnome.desktop.interface','cursor-theme',cursor_theme],['dbus-update-activation-environment','XCURSOR_SIZE='+str(v['cursor_size']),'XCURSOR_THEME='+cursor_theme]):
                if shutil.which(args[0]):command(args,required=False)
        reload_ui()
        if os.environ.get('WAYLAND_DISPLAY') and shutil.which('swaync-client'):
            try:
                command(['swaync-client', '-sw', '-R'], timeout=4, required=False)
            except (OSError, subprocess.TimeoutExpired):
                pass
    except Exception:
        restore(before)
        reload_ui()
        raise


def shortcuts():
    rows, seen = [], set()
    def visit(path):
        path = path.resolve()
        if path in seen or not path.is_file():
            return
        seen.add(path)
        for raw in path.read_text().splitlines():
            line = raw.strip()
            if line.startswith('source='):
                item = os.path.expandvars(os.path.expanduser(line.split('=', 1)[1].strip()))
                visit(Path(item) if Path(item).is_absolute() else path.parent / item)
            match = re.match(r'(bind|mousebind|axisbind)\s*=\s*([^,]+),([^,]+),([^,]+),?(.*)', line)
            if match:
                kind, mods, key, action, args = match.groups()
                combo = (mods.upper() + ' + ' if mods.lower() != 'none' else '') + key
                desc = args.strip() if action.startswith('spawn') else action.replace('_', ' ').title() + (' · ' + args.rstrip(',') if args.strip(',') else '')
                friendly = {
                    'killclient': 'Close window', 'quit': 'Sign out of Mango', 'focusdir': 'Focus window',
                    'togglefloating': 'Toggle floating window', 'togglefullscreen': 'Toggle fullscreen',
                    'toggleoverview': 'Overview', 'reload_config': 'Reload desktop configuration',
                    'view': 'Switch to tag', 'tag': 'Move window to tag', 'exchange_client': 'Swap window',
                    'movewin': 'Move window', 'resizewin': 'Resize window', 'focusmon': 'Focus monitor',
                    'moveresize': 'Move window' if 'curmove' in args else 'Resize window',
                }
                if action in friendly:
                    desc = friendly[action] + (' · ' + args.split(',')[0] if args.strip(',') and action not in ('moveresize',) else '')
                elif action.startswith('spawn'):
                    for token, label in [('cliphist', 'Clipboard history'), ('clipboard-picker', 'Clipboard history'),
                        ('rofi', 'App launcher'), ('victoria-open.sh settings', 'Victoria Settings'),
                        ('victoria-open.sh control', 'Control center'), ('victoria-open.sh launcher', 'App launcher'), ('victoria-open.sh clipboard', 'Clipboard history'), ('wallpaper-picker', 'Wallpaper picker'), ('victoria-open.sh shortcuts', 'Shortcut guide'),
                        ('control-center.py', 'Control center'), ('session-controls.py lock', 'Lock screen'),
                        ('session-controls.py performance', 'Performance mode'), ('wallpaper-picker', 'Wallpaper picker'),
                        ('kitty', 'Terminal'), ('foot', 'Terminal'), ('nemo', 'File manager'), ('helium', 'Browser'),
                        ('firefox', 'Browser'), ('discord', 'Discord'), ('spotify', 'Spotify'),
                        ('--shortcuts', 'Shortcut guide'), ('--focus', 'Toggle focus mode'),
                        ('victoria-controls.py', 'Victoria Settings'), ('print.sh', 'Capture screen region'),
                        ('volume.sh', 'Volume · ' + args.split()[-1]), ('brightness.sh', 'Brightness · ' + args.split()[-1])]:
                        if token in args:
                            desc = label; break
                rows.append((combo, desc, kind))
    visit(MANGO / 'config.conf')
    return rows


def _quickshell(*args):
    return command(['quickshell', 'ipc', '-p', str(MANGO / 'quickshell'), 'call', 'bar', *args], timeout=5, required=False)


def dnd_get():
    """Do-not-disturb from whichever daemon owns notifications (Quickshell bar or swaync)."""
    if shutil.which('quickshell'):
        result = _quickshell('dndStatus')
        if result.returncode == 0 and result.stdout.strip() in ('true', 'false'):
            return result.stdout.strip() == 'true'
    response = command(['swaync-client', '-sw', '-D'], required=False).stdout.strip().lower()
    if response not in ('true', 'false'):
        raise RuntimeError('Could not read notification state. Focus mode was not changed.')
    return response == 'true'


def dnd_set(on):
    if shutil.which('quickshell') and _quickshell('dnd', 'true' if on else 'false').returncode == 0:
        return
    command(['swaync-client', '-sw', '-dn' if on else '-df'])


def focus(enabled=None):
    STATE.mkdir(parents=True, exist_ok=True)
    p = STATE / 'focus.json'
    with (STATE / 'focus.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        active = p.exists()
        enabled = not active if enabled is None else enabled
        if enabled == active:
            return active
        if enabled:
            previous = dnd_get()
            dnd_set(True)
            atomic(p, json.dumps({'previous_dnd': previous}))
        else:
            previous = json.loads(p.read_text())
            dnd_set(previous['previous_dnd'])
            p.unlink()
        refresh_bar_config()
        command(['pkill', '-USR2', '-u', str(os.getuid()), '-x', 'waybar'], required=False)
        return enabled


def display_rules(scale, outputs=None):
    import monitors
    if scale not in (1, 1.25, 1.5, 2):
        raise ValueError('Unsupported scale.')
    outputs = monitors.detect() if outputs is None else outputs
    if not outputs:
        raise RuntimeError('No connected monitors detected. Keep the existing layout.')
    lines, x = ['# Configured by Victoria Setup; only driver-advertised modes.'], 0
    for name, mode in outputs:
        line = f'monitor_rule=name:^{name}$'
        if mode.refresh:
            line += f',width:{mode.width},height:{mode.height},refresh:{mode.refresh:.6f}'
        line += f',x:{x},y:0,scale:{scale}'
        lines.append(line)
        x += round(mode.width / scale)
    return '\n'.join(lines) + '\n'


def current_keyboard():
    """The effective layout: last xkb_rules_* value across config.conf then local/input.conf."""
    found = {}
    for p in (MANGO / 'config.conf', LOCAL / 'input.conf'):
        if p.exists():
            for key, value in re.findall(r'^\s*xkb_rules_(layout|variant|options)\s*=\s*(\S*)', p.read_text(), re.M):
                found[key] = value
    layouts = found.get('layout', 'us').split(',')
    variants = (found.get('variant', '').split(',') + ['', ''])[:len(layouts)]
    names = {pair: name for name, pair in KEYBOARDS.items()}
    chosen = [names.get((l, v), f'{l} {v}'.strip()) for l, v in zip(layouts, variants)]
    switch = next((name for name, option in LAYOUT_SWITCH.items() if option in found.get('options', '')), 'Alt + Shift')
    return {'primary': chosen[0], 'secondary': chosen[1] if len(chosen) > 1 else 'None', 'switch': switch}


def keyboard_rules(keyboard, secondary='None', switch='Alt + Shift'):
    keyboard = KEYBOARD_ALIASES.get(keyboard, keyboard)
    secondary = KEYBOARD_ALIASES.get(secondary, secondary)
    if keyboard not in KEYBOARDS or (secondary != 'None' and secondary not in KEYBOARDS) or switch not in LAYOUT_SWITCH:
        raise ValueError('Unsupported keyboard selection.')
    pairs = [KEYBOARDS[keyboard]] + ([KEYBOARDS[secondary]] if secondary not in ('None', keyboard) else [])
    lines = ['xkb_rules_layout=' + ','.join(l for l, _ in pairs)]
    # Mango rejects empty values: write variants only when one is set ("intl," is valid).
    if any(v for _, v in pairs):
        lines.append('xkb_rules_variant=' + ','.join(v for _, v in pairs))
    if len(pairs) > 1:
        lines.append('xkb_rules_options=' + LAYOUT_SWITCH[switch])
    return '\n'.join(lines)


def apply_setup(keyboard, layout, scale, terminal, browser, secondary='None', switch='Alt + Shift'):
    rules = keyboard_rules(keyboard, secondary, switch)
    if terminal not in ('Keep current', *TERMINALS) or browser not in ('Keep current', *BROWSERS):
        raise ValueError('Unsupported setup selection.')
    for app in (terminal, browser):
        if app != 'Keep current' and not shutil.which(app):
            raise RuntimeError(f'{app} is not installed. Choose an installed app or Keep current.')
    paths = [LOCAL / 'input.conf', LOCAL / 'monitor.conf', MANGO / 'bind.conf']
    before = snapshot(paths)
    try:
        p = paths[0]
        # Drop unmanaged keyboard lines so an old variant can't leak into the new layout.
        text = re.sub(r'^\s*xkb_rules_(layout|variant|options)\s*=.*\n?', '', p.read_text() if p.exists() else '', flags=re.M)
        atomic(p, managed(text, rules))
        if layout == 'Automatic side by side':
            atomic(paths[1], display_rules(scale))
        elif layout != 'Keep current':
            raise ValueError('Unsupported monitor layout.')
        text = paths[2].read_text()
        for key, app in [('Return', terminal), ('w', browser)]:
            if app != 'Keep current':
                text = re.sub(r'^bind=SUPER,' + key + r',.*\n?', '', text, flags=re.M)
                text += f'\nbind=SUPER,{key},spawn,{app}\n'
        atomic(paths[2], text)
        check_mango()
        return before
    except Exception:
        restore(before)
        raise


def diagnostics():
    rows = []
    for name in ('mango', 'quickshell', 'wallust', 'swaync', 'rofi', 'awww', 'jq', 'magick', 'qs', 'pipewire', 'wireplumber', 'cava', 'hyprlock', 'swayidle', 'wlsunset', 'grim', 'slurp'):
        rows.append((bool(shutil.which(name)), name, f'Install {name} using your distribution package manager.'))
    for name in ('config.conf', 'local/custom.conf', 'waybar/config.jsonc'):
        rows.append(((MANGO / name).is_file(), name, 'Run the dotfiles installer in config-only mode.'))
    if shutil.which('mango'):
        result = command(['mango', '-c', str(MANGO / 'config.conf'), '-p'], required=False)
        rows.append((result.returncode == 0, 'Mango configuration', result.stderr.strip() or 'Review local/custom.conf and local/monitor.conf.'))
    if shutil.which('wpctl') and os.environ.get('WAYLAND_DISPLAY'):
        result = command(['wpctl', 'status'], required=False)
        rows.append((result.returncode == 0, 'Audio connection', 'Check PipeWire and WirePlumber in your session; sign out and back in after installing them.'))
    if shutil.which('awww') and os.environ.get('WAYLAND_DISPLAY'):
        result = command(['awww', 'query'], required=False)
        rows.append((result.returncode == 0, 'Wallpaper connection', 'Use Restore wallpaper below.'))
    cache = Path(os.environ.get('XDG_CACHE_HOME') or HOME / '.cache') / 'wallust'
    rows.append(((cache / 'victoria-generation').exists(), 'Wallpaper palette', 'Use Refresh colors below; details are in ~/.cache/wallust/victoria.log.'))
    return rows


def repair(action):
    actions = {
        'Refresh colors': ['python3', str(MANGO / 'scripts/theme.py'), 'apply'],
        'Restore wallpaper': ['bash', str(MANGO / 'scripts/wallpaper-start.sh')],
        'Reload notifications': ['bash', '-c', 'if pgrep -x swaync >/dev/null; then swaync-client -sw -R; else echo "Notifications are handled by the Quickshell bar; nothing to reload."; fi'],
    }
    if action not in actions:
        raise ValueError('Unknown repair action.')
    return command(actions[action], timeout=60).stdout

# ---------- Profile picture ----------
AVATAR = HOME / '.face'
PROFILE = STATE / 'profile.json'
AVATAR_FOLDER = HOME / 'Pictures/Avatars'
# Round, transparent copy for the UI: the bar renders in software, where QML can't mask.
AVATAR_ROUND = Path(os.environ.get('XDG_CACHE_HOME') or HOME / '.cache') / 'victoria/face-round.png'


def round_avatar():
    if not AVATAR.is_file():
        AVATAR_ROUND.unlink(missing_ok=True)
        return None
    if AVATAR_ROUND.is_file() and AVATAR_ROUND.stat().st_mtime >= AVATAR.stat().st_mtime:
        return AVATAR_ROUND
    if not shutil.which('magick'):
        return None
    AVATAR_ROUND.parent.mkdir(parents=True, exist_ok=True)
    tmp = AVATAR_ROUND.with_suffix('.tmp.png')
    # White disc as the opacity mask -> transparent corners.
    command(['magick', str(AVATAR), '-resize', '256x256', '(', '+clone', '-threshold', '101%', '-fill', 'white',
             '-draw', 'circle 127.5,127.5 127.5,0', ')', '-alpha', 'off', '-compose', 'CopyOpacity', '-composite',
             str(tmp)], timeout=30)
    os.replace(tmp, AVATAR_ROUND)
    return AVATAR_ROUND


def profile():
    import pwd
    data = json.loads(PROFILE.read_text()) if PROFILE.exists() else {}
    user = os.environ.get('USER') or pwd.getpwuid(os.getuid()).pw_name
    gecos = pwd.getpwuid(os.getuid()).pw_gecos.split(',')[0].strip()
    AVATAR_FOLDER.mkdir(parents=True, exist_ok=True)
    rounded = round_avatar()
    return {'user': user, 'name': data.get('name') or gecos or user,
            'avatar': str(AVATAR) if AVATAR.is_file() else None,
            'round': str(rounded) if rounded else None, 'folder': str(AVATAR_FOLDER)}


def set_profile_name(name):
    name = ' '.join(str(name).split())[:40]
    data = json.loads(PROFILE.read_text()) if PROFILE.exists() else {}
    data['name'] = name
    atomic(PROFILE, json.dumps(data) + '\n')
    return profile()


def set_avatar(path):
    """Center-crop any image to a 512 px square at ~/.face (also used by display managers)."""
    if path is None:
        AVATAR.unlink(missing_ok=True)
        icon = HOME / '.face.icon'
        if icon.is_symlink() and os.readlink(icon) == '.face':
            icon.unlink()
        return profile()
    source = Path(os.path.expanduser(str(path)))
    if not source.is_file():
        raise ValueError('That image no longer exists.')
    if not shutil.which('magick'):
        raise RuntimeError('ImageMagick (magick) is needed to crop the picture.')
    fd, tmp = tempfile.mkstemp(prefix='.face-', suffix='.png', dir=HOME)
    os.close(fd)
    try:
        command(['magick', str(source) + '[0]', '-auto-orient', '-resize', '512x512^', '-gravity', 'center',
                 '-extent', '512x512', '-strip', tmp], timeout=30)
        os.chmod(tmp, 0o644)
        os.replace(tmp, AVATAR)
    finally:
        Path(tmp).unlink(missing_ok=True)
    icon = HOME / '.face.icon'
    if not icon.exists() and not icon.is_symlink():
        icon.symlink_to('.face')
    return profile()


def choose_avatar():
    """Open a file chooser (zenity) and apply the picked image; None if cancelled."""
    if not shutil.which('zenity'):
        raise RuntimeError('Install zenity to browse for any image, or use the Avatars folder.')
    result = subprocess.run(['zenity', '--file-selection', '--title=Choose a profile picture',
                             '--filename=' + str(HOME / 'Pictures') + '/',
                             '--file-filter=Images | *.png *.jpg *.jpeg *.webp *.gif *.bmp'],
                            capture_output=True, text=True)
    chosen = result.stdout.strip()
    return set_avatar(chosen) if result.returncode == 0 and chosen else None


# ---------- Keyboard indicator ----------
def keyboard_labels():
    """Configured layouts with the description Mango reports (from evdev.lst) and a short code."""
    found = {}
    for p in (MANGO / 'config.conf', LOCAL / 'input.conf'):
        if p.exists():
            for key, value in re.findall(r'^\s*xkb_rules_(layout|variant)\s*=\s*(\S*)', p.read_text(), re.M):
                found[key] = value
    layouts = found.get('layout', 'us').split(',')
    variants = (found.get('variant', '').split(',') + [''] * len(layouts))[:len(layouts)]
    descriptions = {}
    try:
        section = None
        for line in Path('/usr/share/X11/xkb/rules/evdev.lst').read_text().splitlines():
            if line.startswith('!'):
                section = line[1:].strip()
                continue
            match = re.match(r'\s+(\S+)\s+(.*)', line)
            if not match:
                continue
            name, text = match.groups()
            if section == 'layout':
                descriptions[(name, '')] = text.strip()
            elif section == 'variant' and ':' in text:
                layout, text = text.split(':', 1)
                descriptions[(layout.strip(), name)] = text.strip()
    except OSError:
        pass
    result = []
    for layout, variant in zip(layouts, variants):
        code = layout.upper() + ('-' + variant.upper()[:4] if variant and variant != 'intl' else '')
        if variant == 'intl':
            code = layout.upper() + '·I'
        result.append({'code': code, 'description': descriptions.get((layout, variant), layout)})
    return result
