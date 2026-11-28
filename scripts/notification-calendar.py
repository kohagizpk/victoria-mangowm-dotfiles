#!/usr/bin/env python3
"""Calendar inside SwayNC, using widgets available in version 0.12."""
import calendar
import datetime
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

MONTHS = ('January February March April May June July August September October November December').split()
CONFIG = Path.home() / '.config/swaync/config.json'
STATE = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state') / 'victoria/calendar.json'

def render(year, month, today):
    rows = [' MON TUE WED THU FRI SAT SUN']
    for week in calendar.Calendar(firstweekday=0).monthdayscalendar(year, month):
        rows.append(''.join('    ' if not day else f'[{day:2}]' if (year, month, day) == (today.year, today.month, today.day) else f' {day:2} ' for day in week).rstrip())
    return '\n'.join(rows)

def write(path, text):
    fd, name = tempfile.mkstemp(dir=path.parent)
    with os.fdopen(fd, 'w') as stream:
        stream.write(text)
    os.replace(name, path)

def main(action='open'):
    if action not in ('open', 'next', 'previous', 'today', 'refresh', 'prepare'):
        raise SystemExit('Unknown calendar action')
    today = datetime.date.today()
    STATE.parent.mkdir(parents=True, exist_ok=True)
    with STATE.with_suffix('.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        year, month = today.year, today.month
        if action in ('next', 'previous', 'refresh') and STATE.exists():
            year, month = json.loads(STATE.read_text())
        offset = 1 if action == 'next' else -1 if action == 'previous' else 0
        year, month0 = divmod(year * 12 + month - 1 + offset, 12)
        month = month0 + 1
        config = json.loads(CONFIG.read_text())
        widgets = config['widget-config']
        widgets['title#calendar']['text'] = f'{MONTHS[month - 1]} {year}'
        widgets['label#calendar']['text'] = render(year, month, today)
        write(CONFIG, json.dumps(config, ensure_ascii=False, indent=2) + '\n')
        write(STATE, json.dumps([year, month]))
    if action == 'prepare':
        return
    subprocess.run(['swaync-client', '-sw', '-R'], check=True, timeout=5)
    if action != 'refresh':
        subprocess.run(['swaync-client', '-sw', '-t' if action == 'open' else '-op'], check=True, timeout=5)

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'open')
