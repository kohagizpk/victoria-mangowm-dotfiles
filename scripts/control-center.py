#!/usr/bin/env python3
"""Small Rofi/Fuzzel control center. Commands use argument arrays, never shell input."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
HOME = Path.home()
ENV = dict(os.environ, LC_ALL='C', LANGUAGE='en')


def run(args, timeout=15):
    result = subprocess.run(args, capture_output=True, text=True, env=ENV, timeout=timeout)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or f'{args[0]} failed')
    return result.stdout.strip()


def choose(title, entries):
    if not entries:
        raise RuntimeError('No available items.')
    labels = [' '.join(label.splitlines()) for label, _ in entries]
    if os.environ.get('VICTORIA_MENU') == 'fuzzel' or not shutil.which('rofi'):
        args = ['fuzzel', '--dmenu', '--index', '--prompt', title + ': ', '--config', str(HOME / '.config/mango/config/fuzzel.ini')]
    else:
        args = ['rofi', '-dmenu', '-i', '-format', 'i', '-p', title, '-theme', str(HOME / '.config/mango/config/rofi/control-center.rasi')]
    result = subprocess.run(args, input='\n'.join(labels), text=True, capture_output=True, env=ENV)
    if result.returncode or not result.stdout.strip().isdigit(): return None
    index = int(result.stdout.strip())
    return entries[index][1] if 0 <= index < len(entries) else None


def terminal(args):
    if not shutil.which('kitty'): raise RuntimeError('Install kitty for interactive authentication.')
    subprocess.Popen(['kitty', '--title', 'Victoria · Connection', '--hold', *args], start_new_session=True, env=ENV)


def nm_fields(line):
    fields, part, escaped = [], '', False
    for char in line:
        if escaped: part += char; escaped = False
        elif char == '\\': escaped = True
        elif char == ':': fields.append(part); part = ''
        else: part += char
    fields.append(part)
    return fields


def wifi():
    enabled = run(['nmcli', 'radio', 'wifi']) == 'enabled'
    action = choose('Wi-Fi', [('Turn Wi-Fi off' if enabled else 'Turn Wi-Fi on','toggle'), ('Connect to a network…','networks')])
    if action == 'toggle': run(['nmcli','radio','wifi','off' if enabled else 'on'])
    elif action == 'networks':
        rows=[]
        for line in run(['nmcli','-t','-f','BSSID,SSID,SIGNAL,SECURITY,DEVICE','device','wifi','list','--rescan','auto'],timeout=30).splitlines():
            parts=nm_fields(line)
            if len(parts)!=5:continue
            bssid,ssid,signal,security,device=parts
            if not re.fullmatch(r'(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}',bssid):continue
            rows.append((f'{ssid or "Hidden network"} · {signal}% · {security or "Open"}',(bssid,device,ssid)))
        selected=choose('Networks',rows)
        if selected:
            bssid,device,ssid=selected
            subprocess.run([sys.executable,str(ROOT/'wifi-connect.py'),bssid,device,ssid],env=ENV,check=True)


def bluetooth():
    enabled='Powered: yes' in run(['bluetoothctl','show'])
    entries=[('Turn Bluetooth off' if enabled else 'Turn Bluetooth on',('power',not enabled)),('Pair or manage devices…',('pair',None))]
    for line in run(['bluetoothctl','devices','Paired']).splitlines():
        match=re.match(r'Device ([0-9A-F:]{17}) (.*)',line,re.I)
        if match:entries.append((match[2],('device',match[1])))
    choice=choose('Bluetooth',entries)
    if not choice:return
    action,value=choice
    if action=='power':run(['bluetoothctl','power','on' if value else 'off'])
    elif action=='pair':
        if not shutil.which('blueman-manager'):raise RuntimeError('Install blueman to pair devices with authentication dialogs.')
        subprocess.Popen(['blueman-manager'],start_new_session=True)
    else:
        connected='Connected: yes' in run(['bluetoothctl','info',value])
        operation=choose('Device',[('Disconnect' if connected else 'Connect','disconnect' if connected else 'connect')])
        if operation:run(['bluetoothctl',operation,value],timeout=30)


def audio(kind):
    plural='sinks' if kind=='output' else 'sources'
    devices=json.loads(run(['pactl','--format=json','list',plural]))
    current=run(['pactl','get-default-sink' if kind=='output' else 'get-default-source'])
    entries=[]
    for item in devices:
        if kind=='input' and item['name'].endswith('.monitor'):continue
        entries.append((('● ' if item['name']==current else '')+item.get('description',item['name']),item['name']))
    selected=choose('Audio '+kind,entries)
    if selected:
        run(['pactl','set-default-sink' if kind=='output' else 'set-default-source',selected])
        # Move already-playing streams, rather than only affecting future apps.
        stream_type='sink-inputs' if kind=='output' else 'source-outputs'
        for stream in json.loads(run(['pactl','--format=json','list',stream_type])):
            try:run(['pactl','move-sink-input' if kind=='output' else 'move-source-output',str(stream['index']),selected])
            except RuntimeError:pass  # A stream can end between listing and moving.


def power():
    if not shutil.which('powerprofilesctl'):
        raise RuntimeError('Power profiles need power-profiles-daemon and its service. This machine does not have it installed.')
    available=run(['powerprofilesctl','list'])
    current=run(['powerprofilesctl','get'])
    profiles=re.findall(r'^\s*\*?\s*(power-saver|balanced|performance):',available,re.M)
    chosen=choose('Hardware power profile',[(('● ' if p==current else '')+p,p) for p in profiles])
    if chosen:run(['powerprofilesctl','set',chosen])


def vpn():
    active=set(run(['nmcli','-t','-f','UUID','connection','show','--active']).splitlines())
    entries=[]
    for line in run(['nmcli','-t','-f','UUID,TYPE,NAME','connection','show']).splitlines():
        fields=nm_fields(line)
        if len(fields)==3 and fields[1] in ('vpn','wireguard'):
            uuid,_,name=fields
            entries.append((('Disconnect ' if uuid in active else 'Connect ')+name,(uuid,uuid in active)))
    if not entries:raise RuntimeError('No saved VPN profiles. Import a VPN or WireGuard connection in NetworkManager first.')
    selected=choose('VPN',entries)
    if selected:
        uuid,is_active=selected
        if is_active:run(['nmcli','connection','down','uuid',uuid])
        else:terminal(['nmcli','--ask','connection','up','uuid',uuid])


def main():
    items=[('Wi-Fi',wifi),('Bluetooth',bluetooth),('Audio output',lambda:audio('output')),
           ('Microphone input',lambda:audio('input')),('Hardware power profile',power)]
    for title, action in [('Turn screens off','screen-off'),('Suspend','suspend')]:
        items.append((title,lambda a=action:run(['python3',str(ROOT/'session-controls.py'),a],timeout=60)))
    while True:
        selected=choose('Control center',items)
        if selected is None:return
        try:selected()
        except (RuntimeError,OSError,subprocess.TimeoutExpired,json.JSONDecodeError) as exc:
            choose('Could not complete',[(str(exc),None)])


if __name__=='__main__':
    # Prefer the Quickshell control center; this Rofi menu stays as the Waybar fallback.
    if '--gtk' not in sys.argv and shutil.which('quickshell') and subprocess.run(
            ['quickshell','ipc','-p',str(HOME/'.config/mango/quickshell'),'call','bar','controlCenter'],
            capture_output=True,timeout=5).returncode==0:
        sys.exit(0)
    main()
