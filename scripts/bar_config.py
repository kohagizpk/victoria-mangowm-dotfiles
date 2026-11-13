#!/usr/bin/env python3
"""Build the effective Waybar configuration without changing personal modules."""
import json
import os
from pathlib import Path
import re
import sys


def parse(text):
    text = re.sub(r'("(?:\\.|[^"\\])*")|//[^\n]*|/\*.*?\*/', lambda m: m[1] or '', text, flags=re.S)
    text = re.sub(r'("(?:\\.|[^"\\])*")|,\s*([}\]])', lambda m: m[1] or m[2], text)
    return json.loads(text)


def temperature_sensor(root=Path('/sys/class/hwmon')):
    """Find a readable CPU sensor by identity, not boot-dependent hwmon index."""
    priorities = {'coretemp': 0, 'k10temp': 0, 'zenpower': 0, 'k8temp': 1,
                  'cpu_thermal': 1, 'cpu-thermal': 1, 'soc_thermal': 2}
    candidates = []
    for device in sorted(root.glob('hwmon*')):
        try:
            name = (device / 'name').read_text().strip()
        except OSError:
            continue
        if name not in priorities:
            continue
        for sensor in sorted(device.glob('temp*_input')):
            try:
                value = int(sensor.read_text().strip())
                if not 0 < value < 150000:
                    continue
                label_file = sensor.with_name(sensor.name.replace('_input', '_label'))
                label = label_file.read_text().strip().lower() if label_file.exists() else ''
            except (OSError, ValueError):
                continue
            rank = 0 if label.startswith('package') or label == 'tdie' else 1 if label == 'tctl' else 2
            candidates.append((priorities[name], rank, str(sensor)))
    return min(candidates)[2] if candidates else None


VISIBILITY = {'show_stats': ('cpu','memory','temperature'), 'show_media': ('mpris',),
              'show_visualizer': ('custom/cava_mviz',), 'show_tray': ('tray',)}


def build(source, focus=False, battery=False, preferences=None):
    preferences = preferences or {}
    data = parse(source)
    configs = data if isinstance(data, list) else [data]
    for config in configs:
        right = config.setdefault('modules-right', [])
        for side in ('left','center','right'):
            key='modules-'+side
            config[key]=[m for m in config.get(key,[]) if m not in ('custom/victoria-settings','custom/control-center')]
        right=config['modules-right']
        side=next((config['modules-'+side] for side in ('left','center','right') if 'pulseaudio#mic' in config['modules-'+side]),right)
        side.insert(side.index('pulseaudio#mic') if 'pulseaudio#mic' in side else len(side),'custom/victoria-settings')
        right.insert(right.index('custom/power') if 'custom/power' in right else len(right),'custom/control-center')
        config['custom/victoria-settings'] = {
            'format': '', 'tooltip-format': 'Settings',
            'on-click': 'python3 "$HOME/.config/mango/scripts/victoria-controls.py"',
        }
        config['custom/control-center'] = {
            'format': '', 'tooltip-format': 'Control center',
            'on-click': 'python3 "$HOME/.config/mango/scripts/control-center.py"',
        }
        for name, mode in [('pulseaudio#audio','output'), ('pulseaudio#mic','mic')]:
            if name in config:
                config[name]['on-click-right'] = f'python3 "$HOME/.config/mango/scripts/audio-mixer.py" {mode}'
        if battery and 'battery' not in right:
            right.insert(0, 'battery')
        for option, names in VISIBILITY.items():
            if option not in preferences:
                continue
            if preferences[option]:
                present = sum((config.get('modules-' + side, []) for side in ('left','center','right')), [])
                for name in names:
                    if name not in present:
                        side = 'center' if name == 'tray' else 'left' if name in ('cpu','memory') else 'right'
                        config.setdefault('modules-' + side, []).append(name)
            else:
                for side in ('left','center','right'):
                    key = 'modules-' + side
                    config[key] = [name for name in config.get(key, []) if name not in names]
        if 'clock_seconds' in preferences or 'clock_24h' in preferences:
            hour = '%H' if preferences.get('clock_24h', True) else '%I'
            fmt = hour + ':%M' + (':%S' if preferences.get('clock_seconds', True) else '')
            if not preferences.get('clock_24h', True): fmt += ' %p'
            config.setdefault('clock', {})['format'] = '󰥔 {:' + fmt + '}'
        if 'bar_margin' in preferences:
            for side in ('top','bottom','left','right'): config['margin-' + side] = preferences['bar_margin']
        if focus:
            hidden = {'cpu', 'memory', 'temperature', 'custom/cava_mviz', 'mpris', 'custom/sep'}
            for side in ('left', 'center', 'right'):
                key = 'modules-' + side
                config[key] = [name for name in config.get(key, []) if name not in hidden]
            config['modules-right'].insert(0, 'custom/focus')
            config['custom/focus'] = {'format': 'FOCUS', 'tooltip-format': 'Focus mode · click to leave',
                                      'on-click': 'python3 "$HOME/.config/mango/scripts/victoria-controls.py" --focus'}
    return json.dumps(data, indent=2) + '\n'


def current():
    home = Path.home()
    state = Path(os.environ.get('XDG_STATE_HOME') or home / '.local/state') / 'victoria/focus.json'
    settings = home / '.config/mango/local/settings.json'
    preferences = json.loads(settings.read_text()) if settings.exists() else {}
    content = build((home / '.config/mango/waybar/config.jsonc').read_text(), state.exists(),
                    any(Path('/sys/class/power_supply').glob('BAT*')), preferences)
    data = json.loads(content)
    sensor = temperature_sensor()
    for config in data if isinstance(data, list) else [data]:
        if sensor:
            module = config.setdefault('temperature', {})
            for key in ('thermal-zone', 'hwmon-path-abs', 'input-filename'):
                module.pop(key, None)
            module.update({'hwmon-path': sensor, 'interval': 5, 'tooltip': True,
                           'tooltip-format': 'CPU temperature: {temperatureC}°C'})
        else:
            for side in ('left', 'center', 'right'):
                key = 'modules-' + side
                config[key] = ['custom/temperature-unavailable' if name == 'temperature' else name
                               for name in config.get(key, [])]
            config['custom/temperature-unavailable'] = {
                'format': ' —', 'tooltip-format': 'CPU sensor unavailable. Reload Waybar after checking sensors.'}
    return json.dumps(data, indent=2) + '\n'


if __name__ == '__main__':
    Path(sys.argv[1]).write_text(current())
