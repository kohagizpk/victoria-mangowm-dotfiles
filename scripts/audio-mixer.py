#!/usr/bin/env python3
"""Small PipeWire/PulseAudio mixers: playback streams or microphone gain."""
import json
import os
import re
import subprocess
import sys
import threading
import time
from pathlib import Path


def pactl(*args):
    result=subprocess.run(['pactl',*map(str,args)],capture_output=True,text=True,timeout=4)
    if result.returncode:raise RuntimeError(result.stderr.strip() or 'Audio server unavailable')
    return result.stdout


def volume(item):
    channels=list(item.get('volume',{}).values())
    return round(sum(c['value'] for c in channels)/len(channels)/65536*100) if channels else 0


def snapshot(mode):
    kind='sources' if mode=='mic' else 'sinks'
    devices=json.loads(pactl('-f','json','list',kind))
    default=pactl('get-default-source' if mode=='mic' else 'get-default-sink').strip()
    streams=[] if mode=='mic' else json.loads(pactl('-f','json','list','sink-inputs'))
    return devices,default,streams


def main(mode):
    import ctypes
    try:ctypes.CDLL('libgtk4-layer-shell.so.0', mode=ctypes.RTLD_GLOBAL)
    except OSError:pass
    import gi
    gi.require_version('Gtk','4.0')
    from gi.repository import Gtk,Gdk,Gio,GLib
    try:
        gi.require_version('Gtk4LayerShell','1.0')
        from gi.repository import Gtk4LayerShell as Layer
    except (ImportError,ValueError):Layer=None
    class Mixer(Gtk.Application):
        def __init__(self):
            super().__init__(application_id='io.victoria.Mixer.'+mode,flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
            self.window=None;self.loading=False;self.signature=None;self.updating=False;self.edited=0;self.pending={};self.sliders={}
        def position(self):
            if getattr(self,"layer_popup",False):return False
            try:
                clients=json.loads(subprocess.check_output(['mmsg','get','all-clients'],text=True,timeout=2))['clients']
                c=next((c for c in clients if c['pid']==os.getpid()),None)
                if not c:
                    self.position_attempts+=1
                    return self.position_attempts<15
                monitors=json.loads(subprocess.check_output(['mmsg','get','all-monitors'],text=True,timeout=2))['monitors']
                m=next(m for m in monitors if m['name']==self.anchor['monitor'])
                x=max(m['x']+8,min(int(self.anchor['x'])-24,m['x']+m['width']-c['width']-8))
                bottom=self.anchor['y']>m['y']+m['height']/2
                y=m['y']+m['height']-c['height']-40 if bottom else m['y']+40
                subprocess.run(['mmsg','dispatch',f'movewin,{x},{y}',f"client,{c['id']}"],capture_output=True,timeout=2)
            except (OSError,ValueError,KeyError,StopIteration,subprocess.SubprocessError):pass
            return False
        def anchor_layer(self):
            monitors=Gdk.Display.get_default().get_monitors()
            for i in range(monitors.get_n_items()):
                monitor=monitors.get_item(i)
                if monitor.get_connector()==self.anchor['monitor']:
                    Layer.set_monitor(self.window,monitor);geo=monitor.get_geometry()
                    Layer.set_anchor(self.window,Layer.Edge.TOP,True);Layer.set_anchor(self.window,Layer.Edge.LEFT,True)
                    Layer.set_margin(self.window,Layer.Edge.TOP,40)
                    Layer.set_margin(self.window,Layer.Edge.LEFT,max(8,min(int(self.anchor['x'])-geo.x-24,geo.width-472)))
                    break
        def do_activate(self):
            try:self.anchor=json.loads(subprocess.check_output(['mmsg','get','cursorpos'],text=True,timeout=2))
            except (OSError,ValueError,subprocess.SubprocessError):self.anchor={}
            self.position_attempts=0
            GLib.timeout_add(30,self.position)
            if self.window:
                if self.layer_popup:self.anchor_layer()
                self.window.present();return
            self.window=Gtk.ApplicationWindow(application=self,title='Microphone' if mode=='mic' else 'Volume mixer',default_width=460,default_height=300 if mode=='mic' else 560)
            self.layer_popup=bool(Layer and Layer.is_supported() and self.anchor)
            if self.layer_popup:
                Layer.init_for_window(self.window);Layer.set_namespace(self.window,'victoria-mixer')
                Layer.set_layer(self.window,Layer.Layer.TOP);Layer.set_keyboard_mode(self.window,Layer.KeyboardMode.ON_DEMAND)
                self.anchor_layer()
            self.window.set_titlebar(Gtk.HeaderBar())
            self.box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=16)
            for side in ('top','bottom','start','end'):getattr(self.box,'set_margin_'+side)(20)
            self.window.set_child(self.box)
            heading=Gtk.Box(spacing=12)
            title=Gtk.Label(label='Microphone' if mode=='mic' else 'Volume mixer',xalign=0,hexpand=True);title.add_css_class('heading');heading.append(title)
            close=Gtk.Button(label='Close');close.set_tooltip_text('Close mixer (Esc)');close.connect('clicked',lambda *_:self.window.close());heading.append(close);self.box.append(heading)
            keys=Gtk.EventControllerKey()
            def key_pressed(_controller,keyval,_keycode,_state):
                if keyval==Gdk.KEY_Escape:self.window.close();return True
                return False
            keys.connect('key-pressed',key_pressed);self.window.add_controller(keys)
            self.content=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=16)
            scroll=Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER,vexpand=True);scroll.set_child(self.content);self.box.append(scroll)
            self.status=Gtk.Label(xalign=0,wrap=True);self.box.append(self.status)
            colors={'background':'#17151b','foreground':'#eeeeee','color5':'#b18aa6'}
            try:colors.update(dict(re.findall(r'@define-color\s+(\w+)\s+(#[0-9a-fA-F]{6});',(Path.home()/'.config/mango/waybar/colors.css').read_text())))
            except OSError:pass
            css='window.background {background: @background; color: @foreground;} label {color: @foreground;} scale highlight {background: @color5;} dropdown button {border-radius: 10px;} scale trough {min-height: 6px;} .heading {font-size: 16px; font-weight: bold;}'
            for name,value in colors.items():css=css.replace('@'+name,value)
            provider=Gtk.CssProvider();provider.load_from_data(css.encode());Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(),provider,Gtk.STYLE_PROVIDER_PRIORITY_USER+1)
            self.window.present();self.refresh();GLib.timeout_add_seconds(2,self.refresh)
        def job(self,work,done=None):
            def run():
                try:result=work();GLib.idle_add(finish,result,None)
                except Exception as exc:GLib.idle_add(finish,None,str(exc))
            def finish(result,error):
                if error:self.status.set_text(error)
                elif done:done(result)
                return False
            threading.Thread(target=run,daemon=True).start()
        def refresh(self):
            if self.loading or time.monotonic()-self.edited<1:return True
            self.loading=True
            def work():
                try:return snapshot(mode)
                except Exception as exc:return exc
            def done(data):
                self.loading=False
                if isinstance(data,Exception):self.status.set_text(str(data));return
                if time.monotonic()-self.edited>=1:self.render(data)
            self.job(work,done);return True
        def slider(self,label,command,index,item):
            row=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=4)
            row.append(Gtk.Label(label=label,xalign=0,wrap=True))
            scale=Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL,0,100,1)
            scale.set_format_value_func(lambda _, value: f'{value:.0f}%');scale.set_draw_value(True);scale.set_value_pos(Gtk.PositionType.RIGHT);scale.set_digits(0);scale.set_value(min(100,volume(item)))
            scale.connect('value-changed',self.change,command,index)
            row.append(scale);self.content.append(row);self.sliders[(command,index)]=scale
        def change(self,scale,command,index):
            if self.updating:return
            self.edited=time.monotonic();key=(command,index)
            if key in self.pending:GLib.source_remove(self.pending.pop(key))
            def send():
                self.pending.pop(key,None)
                self.job(lambda:pactl(command,index,f'{round(scale.get_value())}%'))
                return False
            self.pending[key]=GLib.timeout_add(100,send)
        def select_output(self,dropdown,_param,devices,streams):
            index=dropdown.get_selected()
            if index>=len(devices):return
            device=devices[index];self.edited=time.monotonic()
            def work():
                pactl('set-default-source' if mode=='mic' else 'set-default-sink',device['name'])
                current=json.loads(pactl('-f','json','list','source-outputs')) if mode=='mic' else streams
                for stream in current:
                    try:pactl('move-source-output' if mode=='mic' else 'move-sink-input',stream['index'],device['name'])
                    except RuntimeError:pass # A stream may finish during the move.
            self.job(work,lambda _:self.status.set_text('Microphone updated' if mode=='mic' else 'Output device updated'))
        def render(self,data):
            devices,default,streams=data
            selected=next((d for d in devices if d['name']==default),None)
            signature=(default,tuple((d['index'],d['name'],d.get('description')) for d in devices),tuple((s['index'],s.get('sink'),s.get('properties',{}).get('application.name'),s.get('mute')) for s in streams),selected.get('mute') if selected else None)
            if signature!=self.signature:
                self.signature=signature;self.sliders={}
                while self.content.get_first_child():self.content.remove(self.content.get_first_child())
                title=Gtk.Label(label='Input device' if mode=='mic' else 'Output device',xalign=0);title.add_css_class('heading');self.content.append(title)
                dropdown=Gtk.DropDown.new_from_strings([d.get('description',d['name']) for d in devices])
                if selected:dropdown.set_selected(devices.index(selected))
                dropdown.connect('notify::selected',self.select_output,devices,streams);self.content.append(dropdown)
                if selected:
                    label=selected.get('description',default) if mode=='mic' else 'Output volume'
                    if selected.get('mute'):label+=' · muted'
                    self.slider(label,'set-source-volume' if mode=='mic' else 'set-sink-volume',selected['index'],selected)
                if mode=='output':
                    title=Gtk.Label(label='Applications',xalign=0);title.add_css_class('heading');self.content.append(title)
                    for stream in streams:
                        props=stream.get('properties',{});label=props.get('application.name',props.get('media.name','Application'))
                        if stream.get('mute'):label+=' · muted'
                        self.slider(label,'set-sink-input-volume',stream['index'],stream)
                    if not streams:self.content.append(Gtk.Label(label='No applications are playing audio',xalign=0))
                self.status.set_text('' if selected else 'No audio device available')
            self.updating=True
            try:
                items=[('set-source-volume' if mode=='mic' else 'set-sink-volume',d) for d in devices]+[('set-sink-input-volume',s) for s in streams]
                for cmd,item in items:
                    key=(cmd,item['index'])
                    if key in self.sliders and key not in self.pending:self.sliders[key].set_value(min(100,volume(item)))
            finally:self.updating=False
    return Mixer().run([])

if __name__=='__main__':
    mode=sys.argv[1] if len(sys.argv)>1 else 'output'
    if mode not in ('mic','output'):raise SystemExit('Choose mic or output')
    raise SystemExit(main(mode))
