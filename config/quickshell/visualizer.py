#!/usr/bin/env python3
import os, signal, subprocess, tempfile
from pathlib import Path

def stop(*_):raise SystemExit(0)
signal.signal(signal.SIGTERM,stop)
signal.signal(signal.SIGINT,stop)
fd,name=tempfile.mkstemp(prefix='victoria-cava-',suffix='.conf',dir=os.environ.get('XDG_RUNTIME_DIR'))
child=None
try:
    with os.fdopen(fd,'w') as f:f.write('[general]\nframerate = 20\nbars = 10\n[input]\nmethod = pulse\nsource = auto\n[output]\nmethod = raw\nraw_target = /dev/stdout\ndata_format = ascii\nascii_max_range = 7\n')
    child=subprocess.Popen(['cava','-p',name],stdout=subprocess.PIPE,text=True)
    for line in child.stdout:
        print(''.join('▁▂▃▄▅▆▇█'[int(n)] for n in line.strip().split(';') if n.isdigit() and int(n)<8),flush=True)
finally:
    if child:
        child.terminate()
        try:child.wait(timeout=2)
        except subprocess.TimeoutExpired:child.kill();child.wait()
    Path(name).unlink(missing_ok=True)
