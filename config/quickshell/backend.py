#!/usr/bin/env python3
"""Bounded system sampling for Victoria; UI and media live in Quickshell."""
import json, subprocess, time, sys, os, re, select, signal, ctypes
from pathlib import Path
HOME=Path.home()
network_previous=None
command_cache={}

def cached(*args, ttl=15):
    now=time.monotonic()
    saved=command_cache.get(args)
    if saved is None or now-saved[0]>=ttl:
        command_cache[args]=(now,run(*args))
    return command_cache[args][1]

def audio_child_setup():
    # Quickshell may kill the sampler during reload before finally can run.
    # Linux PR_SET_PDEATHSIG keeps the event subscription tied to its parent.
    parent=os.getppid()
    if ctypes.CDLL(None, use_errno=True).prctl(1, signal.SIGTERM, 0, 0, 0) != 0:
        raise OSError(ctypes.get_errno(), 'PR_SET_PDEATHSIG')
    if os.getppid()!=parent or parent==1:os._exit(0)

class AudioEvents:
    """Invalidate audio snapshots on Pulse events, with a timed fallback."""
    def __init__(self):
        self.child=None
        self.retry_at=0

    def poll(self):
        if self.child is None or self.child.poll() is not None:
            if time.monotonic()<self.retry_at:return
            self.close()
            self.retry_at=time.monotonic()+30
            try:
                self.child=subprocess.Popen(['pactl','subscribe'],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,preexec_fn=audio_child_setup)
            except OSError:return
        changed=False
        while select.select([self.child.stdout],[],[],0)[0]:
            if not os.read(self.child.stdout.fileno(),65536):break
            changed=True
        if changed:
            for key in list(command_cache):
                if key[0]=='pactl':del command_cache[key]

    def close(self):
        if self.child is not None:
            if self.child.poll() is None:
                self.child.terminate()
                try:self.child.wait(timeout=2)
                except subprocess.TimeoutExpired:self.child.kill();self.child.wait()
            self.child.stdout.close()
            self.child=None

def run(*args):
    try:return subprocess.check_output(args,text=True,timeout=2).strip()
    except (OSError,subprocess.SubprocessError):return ''
def parsed(*args,default=None):
    try:return json.loads(cached(*args,ttl=30))
    except ValueError:return default

def sample(previous):
    global network_previous
    cpu=list(map(int,Path('/proc/stat').read_text().splitlines()[0].split()[1:9])); total=sum(cpu);idle=cpu[3]+cpu[4]
    usage=round(100*(1-(idle-previous[1])/max(1,total-previous[0]))) if previous else 0
    mem=dict(re.findall(r'^(\w+):\s+(\d+)',Path('/proc/meminfo').read_text(),re.M))
    temp=None
    for d in Path('/sys/class/hwmon').glob('hwmon*'):
        try:
            if (d/'name').read_text().strip() in ('coretemp','k10temp','zenpower','cpu_thermal'):
                temp=round(int(next(d.glob('temp*_input')).read_text())/1000);break
        except (OSError,ValueError,StopIteration):pass
    settings={}
    try:settings=json.loads((HOME/'.config/mango/local/settings.json').read_text())
    except (OSError,ValueError):pass
    network=cached('nmcli','-t','-f','DEVICE,TYPE,STATE,CONNECTION','device').splitlines()
    connection=next((l.split(':',3) for l in network if ':connected:' in l),[])
    rates=''
    if connection:
        iface=connection[0]
        counters=next((line.split(':',1)[1].split() for line in Path('/proc/net/dev').read_text().splitlines() if line.split(':',1)[0].strip()==iface),None)
        if counters:
            now=time.monotonic();rx=int(counters[0]);tx=int(counters[8])
            if network_previous and network_previous[0]==iface:
                _,then,oldrx,oldtx=network_previous
                rates=f' · {(tx-oldtx)/max(.01,now-then)/1024:.1f} KiB/s ↑ · {(rx-oldrx)/max(.01,now-then)/1024:.1f} KiB/s ↓'
            network_previous=(iface,now,rx,tx)
    battery=[]
    for b in Path('/sys/class/power_supply').glob('BAT*'):
        try:battery.append({'percent':int((b/'capacity').read_text()),'status':(b/'status').read_text().strip()})
        except (OSError,ValueError):pass
    out={'cpu':usage,'memory':round((int(mem['MemTotal'])-int(mem['MemAvailable']))/1048576,1),'temperature':temp,'network':connection[-1] if connection else 'Offline','networkTip':cached('hostname','-I',ttl=30)+rates,'settings':settings,'focus':(HOME/'.local/state/victoria/focus.json').exists(),'battery':battery}
    for kind in ('sinks','sources','sink-inputs','source-outputs'):
        items=parsed('pactl','-f','json','list',kind,default=[]) or []
        out[kind]=[{'id':i['index'],'name':i.get('name',''),'label':i.get('description') or i.get('properties',{}).get('application.name') or i.get('properties',{}).get('media.name','Application'),'corked':i.get('corked',False),'mute':i.get('mute',False),'volume':round(sum(v['value'] for v in i.get('volume',{}).values())/max(1,len(i.get('volume',{})))/65536*100)} for i in items]
    dnd=run('swaync-client','-D')
    out['dnd']=dnd=='true'
    out['dndAvailable']=dnd in ('true','false')
    try:out['performance']='animations=0' in (HOME/'.config/mango/local/performance.conf').read_text()
    except OSError:out['performance']=False
    out['sink']=cached('pactl','get-default-sink',ttl=30);out['source']=cached('pactl','get-default-source',ttl=30)
    return out,(total,idle)
if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='workspace':
        monitor,tag,action=sys.argv[2:]
        if action=='toggle':
            run('mmsg','dispatch','focusmon,'+monitor)
            run('mmsg','dispatch','toggleview,'+str(int(tag)))
        else:run('mmsg','dispatch','viewcrossmon,'+str(int(tag))+','+monitor)
        raise SystemExit(0)
    def stop(*_):raise SystemExit(0)
    signal.signal(signal.SIGTERM,stop)
    signal.signal(signal.SIGINT,stop)
    previous=None
    events=AudioEvents()
    try:
        while True:
            try:
                events.poll()
                data,previous=sample(previous);print(json.dumps(data),flush=True)
            except BrokenPipeError:break
            except Exception as exc:print(str(exc),file=sys.stderr)
            time.sleep(2)
    finally:events.close()
