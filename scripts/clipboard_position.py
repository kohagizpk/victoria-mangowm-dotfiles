"""Locate a focused input without reading its text; mouse is the fallback."""
import json
import os
from pathlib import Path
import subprocess
import sys


def query(name):
    return json.loads(subprocess.check_output(['mmsg','get',name],timeout=1,text=True))


def anchor():
    try:
        pointer=query('cursorpos');monitors=query('all-monitors')['monitors']
        focus=query('focusing-client') or {};focus=focus.get('client',focus) or {}
        if focus.get('pid'):
            try:
                probe=subprocess.run([sys.executable,str(Path(__file__)),'caret',str(focus['pid'])],capture_output=True,text=True,timeout=.6)
                rect=json.loads(probe.stdout)
                # Reject local/stale coordinates supplied by an accessibility backend.
                if focus['x']<=rect['x']<focus['x']+focus['width'] and focus['y']<=rect['y']<focus['y']+focus['height']:
                    pointer.update(rect)
            except (ValueError,KeyError,subprocess.SubprocessError):pass
        monitor=next((m for m in monitors if m['x']<=pointer['x']<m['x']+m['width'] and m['y']<=pointer['y']<m['y']+m['height']),monitors[0])
        return pointer,monitor
    except (OSError,ValueError,KeyError,IndexError,subprocess.SubprocessError):return None


def position(point,monitor,width,height):
    x=point['x'];y=point['y']+point.get('height',0)+10
    if y+height>monitor['y']+monitor['height']-8:y=point['y']-height-10
    x=max(monitor['x']+8,min(x,monitor['x']+monitor['width']-width-8))
    y=max(monitor['y']+36,min(y,monitor['y']+monitor['height']-height-8))
    return int(x),int(y)


def caret(pid):
    import gi
    gi.require_version('Atspi','2.0')
    from gi.repository import Atspi
    Atspi.set_timeout(80,80)
    desktop=Atspi.get_desktop(0)
    apps=[desktop.get_child_at_index(i) for i in range(desktop.get_child_count())]
    queue=[a for a in apps if a and a.get_process_id()==pid]
    for _ in range(300):
        if not queue:return
        item=queue.pop(0)
        if item.get_state_set().contains(Atspi.StateType.FOCUSED):
            text=item.get_text_iface()
            if text:
                offset=text.get_caret_offset();count=text.get_character_count()
                if count:
                    rect=text.get_character_extents(min(offset,count-1),Atspi.CoordType.SCREEN)
                    if rect.width>=0 and rect.height>0:
                        return {'x':rect.x+(rect.width if offset>=count else 0),'y':rect.y,'height':rect.height}
            component=item.get_component_iface()
            if component:
                r=component.get_extents(Atspi.CoordType.SCREEN)
                if r.width>0 and r.height>0:return {'x':r.x,'y':r.y,'height':r.height}
        for i in range(min(item.get_child_count(),100)):
            child=item.get_child_at_index(i)
            if child:queue.append(child)

if __name__=='__main__':
    try:
        result=caret(int(sys.argv[2]))
        if result:print(json.dumps(result))
    except Exception:pass
