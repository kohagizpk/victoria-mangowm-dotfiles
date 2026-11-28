#!/usr/bin/env python3
"""Small graphical nmcli authentication prompt; passwords travel over stdin only."""
import os
import subprocess
import sys
import threading
import gi
gi.require_version('Gtk','4.0')
from gi.repository import Gtk,GLib

def main():
    bssid,device,ssid=sys.argv[1:4]
    app=Gtk.Application(application_id='io.victoria.Wifi')
    def activate(app):
        window=Gtk.ApplicationWindow(application=app,title='Connect to Wi-Fi',default_width=440,default_height=360)
        window.set_titlebar(Gtk.HeaderBar())
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=16)
        for side in ('top','bottom','start','end'):getattr(box,'set_margin_'+side)(20)
        window.set_child(box)
        box.append(Gtk.Label(label=ssid or 'Hidden network',xalign=0,wrap=True))
        box.append(Gtk.Label(label='Wi-Fi password · leave empty for saved or open networks',wrap=True,xalign=0))
        password=Gtk.PasswordEntry(show_peek_icon=True);box.append(password)
        status=Gtk.Label(xalign=0,wrap=True);box.append(status)
        connect=Gtk.Button(label='Connect');connect.add_css_class('suggested-action');box.append(connect)
        busy=False
        def submit(*_):
            nonlocal busy
            if busy:return
            busy=True;connect.set_sensitive(False);password.set_sensitive(False);status.set_text('Connecting…')
            secret=password.get_text();password.set_text('')
            def work():
                try:
                    result=subprocess.run(['nmcli','--wait','30','--ask','device','wifi','connect',bssid,'ifname',device],input=secret+'\n',text=True,capture_output=True,timeout=40,env=dict(os.environ,LC_ALL='C'))
                    ok=result.returncode==0
                except (OSError,subprocess.SubprocessError):ok=False
                GLib.idle_add(finish,ok)
            threading.Thread(target=work,daemon=True).start()
        def finish(ok):
            nonlocal busy
            busy=False
            if ok:window.close()
            else:
                status.set_text('Could not connect. Check the password and try again. Enterprise networks may need NetworkManager configuration.')
                connect.set_sensitive(True);password.set_sensitive(True);password.grab_focus()
            return False
        connect.connect('clicked',submit);password.connect('activate',submit)
        window.connect('close-request',lambda *_:busy)
        window.present();password.grab_focus()
    app.connect('activate',activate);return app.run([])
if __name__=='__main__':raise SystemExit(main())
