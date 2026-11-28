#!/usr/bin/env python3
"""Bounded system sampling for the Victoria bar.

Only what Quickshell cannot read natively lives here: CPU, memory, temperature,
network and battery. Audio comes from Quickshell's PipeWire service, DND from a
swaync subscription and settings from a FileView, so this loop spawns at most
one short process every 15 s.
"""
import json
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
FOCUS = HOME / '.local/state/victoria/focus.json'
SENSORS = ('coretemp', 'k10temp', 'zenpower', 'cpu_thermal')
command_cache = {}


def run(*args):
    try:
        return subprocess.check_output(args, text=True, timeout=2, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.SubprocessError):
        return ''


def cached(*args, ttl=15):
    now = time.monotonic()
    saved = command_cache.get(args)
    if saved is None or now - saved[0] >= ttl:
        command_cache[args] = (now, run(*args))
    return command_cache[args][1]


def find_sensor():
    """Resolve the CPU temperature file once instead of globbing every sample."""
    for hwmon in Path('/sys/class/hwmon').glob('hwmon*'):
        try:
            if (hwmon / 'name').read_text().strip() in SENSORS:
                return next(hwmon.glob('temp*_input'))
        except (OSError, StopIteration):
            continue
    return None


class Sampler:
    def __init__(self):
        self.cpu_previous = None
        self.net_previous = None
        self.sensor = find_sensor()

    def cpu(self):
        fields = list(map(int, Path('/proc/stat').read_text().split('\n', 1)[0].split()[1:9]))
        total, idle = sum(fields), fields[3] + fields[4]
        usage = 0
        if self.cpu_previous:
            usage = round(100 * (1 - (idle - self.cpu_previous[1]) / max(1, total - self.cpu_previous[0])))
        self.cpu_previous = (total, idle)
        return usage

    def temperature(self):
        if self.sensor is None:
            return None
        try:
            return round(int(self.sensor.read_text()) / 1000)
        except (OSError, ValueError):
            self.sensor = find_sensor()  # hwmon numbering can change after resume
            return None

    def network(self):
        devices = cached('nmcli', '-t', '-f', 'DEVICE,TYPE,STATE,CONNECTION', 'device').splitlines()
        connection = next((line.split(':', 3) for line in devices if ':connected:' in line), [])
        if not connection:
            self.net_previous = None
            return 'Offline', ''
        iface, rates = connection[0], ''
        for line in Path('/proc/net/dev').read_text().splitlines():
            name, _, counters = line.partition(':')
            if name.strip() != iface:
                continue
            values = counters.split()
            now, rx, tx = time.monotonic(), int(values[0]), int(values[8])
            if self.net_previous and self.net_previous[0] == iface:
                _, then, old_rx, old_tx = self.net_previous
                span = max(0.01, now - then)
                rates = f' · {(tx - old_tx) / span / 1024:.1f} KiB/s ↑ · {(rx - old_rx) / span / 1024:.1f} KiB/s ↓'
            self.net_previous = (iface, now, rx, tx)
            break
        address = cached('ip', '-4', '-brief', 'address', 'show', iface, ttl=30).split()
        return connection[-1], (address[2] if len(address) > 2 else iface) + rates

    def sample(self):
        mem = dict(re.findall(r'^(\w+):\s+(\d+)', Path('/proc/meminfo').read_text(), re.M))
        battery = []
        for supply in Path('/sys/class/power_supply').glob('BAT*'):
            try:
                battery.append({'percent': int((supply / 'capacity').read_text()),
                                'status': (supply / 'status').read_text().strip()})
            except (OSError, ValueError):
                pass
        network, tip = self.network()
        return {
            'cpu': self.cpu(),
            'memory': round((int(mem['MemTotal']) - int(mem['MemAvailable'])) / 1048576, 1),
            'temperature': self.temperature(),
            'network': network,
            'networkTip': tip,
            'focus': FOCUS.exists(),
            'battery': battery,
        }


def main():
    def stop(*_):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    sampler = Sampler()
    while True:
        try:
            print(json.dumps(sampler.sample()), flush=True)
        except BrokenPipeError:
            break
        except Exception as exc:  # keep the bar alive on a transient read error
            print(exc, file=sys.stderr)
        time.sleep(2)


if __name__ == '__main__':
    main()
