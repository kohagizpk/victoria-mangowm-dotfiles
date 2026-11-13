#!/usr/bin/env python3
"""Screen locking, managed idle and a reversible compositor performance overlay."""
import argparse
import fcntl
import json
import os
import re
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import sys
import time

from victoria_settings import HOME, MANGO, LOCAL, STATE, atomic, command, check_mango
ROOT=Path(__file__).resolve().parent
RUNTIME=Path(os.environ.get('XDG_RUNTIME_DIR') or HOME/'.cache')/'victoria-session'


def ensure_overlay():
    p=LOCAL/'performance.conf'
    if not p.exists():atomic(p,'# Performance mode is off.\n')
    p=MANGO/'config.conf';text=p.read_text()
    line='source=./local/performance.conf'
    if line not in text:atomic(p,text.rstrip()+'\n\n# Temporary performance overrides, after personal settings.\n'+line+'\n')


def performance_enabled():
    p=LOCAL/'performance.conf'
    return p.exists() and 'animations=0' in p.read_text()


def performance(enabled=None):
    LOCAL.mkdir(parents=True,exist_ok=True)
    with (LOCAL/'performance.lock').open('w') as lockfile:
        fcntl.flock(lockfile,fcntl.LOCK_EX)
        ensure_overlay();p=LOCAL/'performance.conf';previous=p.read_text()
        if enabled is None:enabled='animations=0' not in previous
        atomic(p,'# Performance mode: temporary; personal preferences are unchanged.\n'+
               ('animations=0\nlayer_animations=0\nblur=0\nblur_layer=0\nshadows=0\nlayer_shadows=0\n' if enabled else ''))
        try:check_mango()
        except Exception:atomic(p,previous);raise
        panel=MANGO.parent/'swaync/config.json'
        if panel.exists():
            STATE.mkdir(parents=True,exist_ok=True)
            with (STATE/'calendar.lock').open('w') as calendar_lock:
                fcntl.flock(calendar_lock,fcntl.LOCK_EX)
                config=json.loads(panel.read_text())
                actions=config.get('widget-config',{}).get('buttons-grid#performance',{}).get('actions',[])
                if actions:
                    actions[0]['active']=enabled
                    atomic(panel,json.dumps(config,ensure_ascii=False,indent=2)+'\n')
            if shutil.which('swaync-client'):command(['swaync-client','-R'],required=False)
        if shutil.which('notify-send'):
            command(['notify-send','-a','Victoria','Performance mode','Enabled · effects disabled' if enabled else 'Disabled · personal effects restored'],required=False)
        return enabled


def hyprlock_config():
    """Generate from the current palette; keep paths outside Hyprlang syntax."""
    RUNTIME.mkdir(parents=True,exist_ok=True)
    colors={}
    palette=Path(os.environ.get('XDG_CACHE_HOME') or HOME/'.cache')/'wallust/victoria-palette.json'
    try:colors=json.loads(palette.read_text())
    except (OSError,ValueError):pass
    def color(key,fallback):
        value=colors.get(key,'')
        return value[1:] if re.fullmatch(r'#[0-9a-fA-F]{6}',value) else fallback
    template=(ROOT.parent/'config/hyprlock/hyprlock.conf').read_text()
    for name,key,fallback in [('BACKGROUND','background','151218'),('FOREGROUND','foreground','eeeeee'),('ACCENT','color5','b18aa6')]:
        template=template.replace('@'+name+'@',color(key,fallback))
    background=''
    try:
        import theme
        image=theme.saved_wallpaper()
        link=RUNTIME/'wallpaper'
        link.unlink(missing_ok=True);link.symlink_to(image)
        background=str(link)
    except (OSError,RuntimeError):pass
    template=template.replace('@WALLPAPER@',background)
    target=RUNTIME/'hyprlock.conf';atomic(target,template)
    return target


def lock_screen():
    RUNTIME.mkdir(parents=True,exist_ok=True)
    with (RUNTIME/'locking.lock').open('w') as guard:
        fcntl.flock(guard,fcntl.LOCK_EX)
        state=RUNTIME/'hyprlock.json'
        if state.exists():
            data=json.loads(state.read_text())
            if process_token(data['pid'])==data['start']:
                return  # This record is only written after the compositor confirms locking.
        if shutil.which('hyprlock'):
            path=hyprlock_config();logpath=RUNTIME/'hyprlock.log'
            with logpath.open('w') as log:
                os.chmod(logpath,0o600)
                child=subprocess.Popen(['hyprlock','--config',str(path),'--grace','0'],stdout=log,stderr=log,start_new_session=True)
            # Hyprlock has no ready-fd. Wait for its ext-session-lock locked callback,
            # never just a process or arbitrary delay before powering down/suspending.
            for _ in range(200):
                if child.poll() is not None:raise RuntimeError('Hyprlock could not lock. See '+str(logpath))
                if 'onLockLocked called' in logpath.read_text():
                    atomic(state,json.dumps({'pid':child.pid,'start':process_token(child.pid)}));return
                time.sleep(0.05)
            raise RuntimeError('Lock was not confirmed; screens and suspend were left unchanged. See '+str(logpath))
        # Keep a working locker until Hyprlock has been installed.
        if not shutil.which('swaylock'):raise RuntimeError('Install hyprlock before locking.')
        if subprocess.run(['pgrep','-u',str(os.getuid()),'-x','swaylock'],capture_output=True).returncode==0:return
        command(['swaylock','--config','/dev/null','--daemonize','--ignore-empty-password','--color','151218'],timeout=15)


def monitor_names():
    data=json.loads(command(['mmsg','get','all-monitors']).stdout)
    monitors=data.get('monitors',[]) if isinstance(data,dict) else data
    return [m['name'] for m in monitors]


def set_screens(on,names=None):
    names=monitor_names() if names is None else names
    for name in names:
        command(['mmsg','dispatch',('wakeup_monitor' if on else 'sleep_monitor')+','+name])


def screen_resume():
    RUNTIME.mkdir(parents=True,exist_ok=True)
    with (RUNTIME/'screen-power.lock').open('w') as guard:
        fcntl.flock(guard,fcntl.LOCK_EX)
        path=RUNTIME/'screens.json'
        names=json.loads(path.read_text()) if path.exists() else monitor_names()
        (RUNTIME/'screen-resumed').touch()
        set_screens(True,names)


def screen_off_ready():
    with (RUNTIME/'screen-power.lock').open('w') as power:
        fcntl.flock(power,fcntl.LOCK_EX)
        with (RUNTIME/'screen-watch.lock').open('w') as guard:
            try:fcntl.flock(guard,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError:
                if not (RUNTIME/'screen-resumed').exists():
                    set_screens(False,json.loads((RUNTIME/'screens.json').read_text()))
            else:raise RuntimeError('No wake watcher; refusing to turn screens off.')


def screen_watch():
    """One-shot idle watcher, established before DPMS off, plus a recovery timer."""
    RUNTIME.mkdir(parents=True,exist_ok=True)
    with (RUNTIME/'screen-watch.lock').open('w') as guard:
        try:fcntl.flock(guard,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:return
        names=monitor_names()
        if not names:raise RuntimeError('No monitors found; screens were not powered down.')
        atomic(RUNTIME/'screens.json',json.dumps(names))
        resumed=RUNTIME/'screen-resumed';resumed.unlink(missing_ok=True)
        action=lambda name:shlex.join([sys.executable,str(ROOT/'session-controls.py'),name])
        # Power down from swayidle's callback: its resume listener is already armed.
        child=subprocess.Popen(['swayidle','-w','timeout','1',action('screen-off-ready'),'resume',action('screen-on')])
        try:
            deadline=time.monotonic()+60
            while child.poll() is None and time.monotonic()<deadline and not resumed.exists():time.sleep(0.1)
        finally:
            # Cancel callbacks before waking, including callbacks already in flight.
            (RUNTIME/'screen-resumed').touch()
            if child.poll() is None:
                child.terminate()
                try:child.wait(timeout=3)
                except subprocess.TimeoutExpired:child.kill();child.wait()
            with (RUNTIME/'screen-power.lock').open('w') as power:
                fcntl.flock(power,fcntl.LOCK_EX)
                set_screens(True,names)
            (RUNTIME/'screens.json').unlink(missing_ok=True)


def screens(on):
    if on:screen_resume();return
    lock_screen()
    if not shutil.which('swayidle'):raise RuntimeError('Install swayidle before turning screens off.')
    RUNTIME.mkdir(parents=True,exist_ok=True)
    with (RUNTIME/'screen-watch.log').open('a') as log:
        subprocess.Popen([sys.executable,str(ROOT/'session-controls.py'),'screen-watch'],stdout=log,stderr=log,start_new_session=True)


def idle_command(settings):
    def action(name):return shlex.join([sys.executable,str(ROOT/'session-controls.py'),name])
    if not settings.get('idle_enabled',False):
        return ['swayidle','-w','before-sleep',action('lock'),'after-resume',action('screen-on')]
    lock=int(settings.get('idle_lock_minutes',10))*60
    off=int(settings.get('idle_screen_minutes',15))*60
    suspend=int(settings.get('idle_suspend_minutes',0))*60
    if lock<60 or off<lock or (suspend and suspend<off):raise ValueError('Idle times must follow lock ≤ screen off ≤ suspend; 0 disables suspend.')
    args=['swayidle','-w','timeout',str(lock),action('lock'),'timeout',str(off),action('screen-off'),'resume',action('screen-on'),
          'before-sleep',action('lock'),'after-resume',action('screen-on')]
    if suspend:args+=['timeout',str(suspend),action('suspend')]
    return args


def process_token(pid):
    try:return Path(f'/proc/{pid}/stat').read_text().rsplit(')',1)[1].split()[19]
    except OSError:return None


def idle_restart():
    RUNTIME.mkdir(parents=True,exist_ok=True)
    with (RUNTIME/'idle.lock').open('w') as guard:
        fcntl.flock(guard,fcntl.LOCK_EX)
        state=RUNTIME/'idle.json'
        if state.exists():
            data=json.loads(state.read_text())
            if process_token(data['pid'])==data['start']:
                try:os.kill(data['pid'],signal.SIGTERM)
                except ProcessLookupError:pass
                for _ in range(30):
                    if process_token(data['pid'])!=data['start']:break
                    time.sleep(0.05)
            state.unlink(missing_ok=True)
        path=LOCAL/'settings.json';settings=json.loads(path.read_text()) if path.exists() else {}
        args=idle_command(settings)
        if not args:return
        if not shutil.which('swayidle') or not (shutil.which('hyprlock') or shutil.which('swaylock')):raise RuntimeError('Install swayidle and hyprlock before enabling automatic idle.')
        others=subprocess.run(['pgrep','-a','-u',str(os.getuid()),'-x','swayidle'],capture_output=True,text=True).stdout.splitlines()
        if any(str(ROOT/'session-controls.py')+' screen-off-ready' not in line for line in others):
            raise RuntimeError('Another swayidle is already running. Disable its autostart before using Victoria idle.')
        with (RUNTIME/'idle.log').open('a') as log:
            child=subprocess.Popen(args,stdout=log,stderr=log,start_new_session=True)
        time.sleep(0.2)
        if child.poll() is not None:raise RuntimeError('swayidle did not start. Check '+str(RUNTIME/'idle.log'))
        atomic(state,json.dumps({'pid':child.pid,'start':process_token(child.pid)}))


def main():
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['lock','screen-off','screen-on','suspend','performance','performance-set','performance-status','screen-watch','screen-off-ready','idle-restart','prepare']);action=parser.parse_args().action
    if action=='lock':lock_screen()
    elif action=='screen-off':screens(False)
    elif action=='screen-on':screens(True)
    elif action=='suspend':
        lock_screen();command(['loginctl','suspend'],timeout=30)
    elif action=='performance':performance()
    elif action=='performance-set':performance()  # Toggle the actual state, not a potentially stale widget value.
    elif action=='performance-status':print('true' if performance_enabled() else 'false')
    elif action=='screen-watch':screen_watch()
    elif action=='screen-off-ready':screen_off_ready()
    elif action=='prepare':ensure_overlay()
    else:idle_restart()

if __name__=='__main__':
    try:main()
    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as exc:sys.exit(str(exc))
