"""Searchable clipboard browser with a scrollbar and decoded image thumbnails."""
import re
import os
import json
import subprocess
import threading


def preview(row):
    text=row.partition(b'\t')[2].decode('utf-8','replace')
    binary='binary data' in text.lower()
    html=bool(re.search(r'<(?:html|body|img|div|span|meta|!--)\b',text,re.I))
    if binary:return 'Image / binary attachment',text,True
    if html:return 'HTML fragment (not image data)',text,False
    return 'Text',text,False


def choose(rows):
    import gi
    gi.require_version('Gtk','4.0');gi.require_version('GdkPixbuf','2.0')
    from gi.repository import Gtk,Gdk,GdkPixbuf,GLib
    from clipboard_position import anchor,position
    origin=anchor()
    result=[None];limit=[50];serial=[0];workers=threading.Semaphore(2)
    app=Gtk.Application(application_id='io.victoria.Clipboard')
    def activate(app):
        window=Gtk.ApplicationWindow(application=app,title='Clipboard history',default_width=480,default_height=450)
        header=Gtk.HeaderBar();window.set_titlebar(header)
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=8)
        for side in ('top','bottom','start','end'):getattr(box,'set_margin_'+side)(12)
        window.set_child(box)
        search=Gtk.SearchEntry(placeholder_text='Search copied text or image entries');box.append(search)
        status=Gtk.Label(xalign=0);box.append(status)
        scroll=Gtk.ScrolledWindow(vexpand=True,hscrollbar_policy=Gtk.PolicyType.NEVER,vscrollbar_policy=Gtk.PolicyType.ALWAYS)
        listing=Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE);scroll.set_overlay_scrolling(False);scroll.set_child(listing);box.append(scroll)
        more=Gtk.Button(label='Load older copies');box.append(more)
        box.append(Gtk.Label(label='Scroll · Enter to copy · Esc to cancel',xalign=0))
        def select(_list,row):
            if row is not None:result[0]=row.history_index;window.close()
        listing.connect('row-activated',select)
        def thumbnail(row,picture,label,generation):
            def work():
                with workers:
                    if serial[0]!=generation:return
                    try:
                        decoded=subprocess.run(['cliphist','decode'],input=row+b'\n',capture_output=True,timeout=15)
                        if decoded.returncode:return
                        loader=GdkPixbuf.PixbufLoader()
                        def size_ready(loader,w,h):
                            scale=min(72/w,54/h,1);loader.set_size(max(1,int(w*scale)),max(1,int(h*scale)))
                        loader.connect('size-prepared',size_ready);loader.write(decoded.stdout);loader.close();pixbuf=loader.get_pixbuf()
                        def done():
                            if serial[0]==generation:
                                picture.set_paintable(Gdk.Texture.new_for_pixbuf(pixbuf));label.set_text('Image')
                            return False
                        GLib.idle_add(done)
                    except Exception:pass # Non-image binary entries remain selectable.
            threading.Thread(target=work,daemon=True).start()
        def populate(reset=True):
            old_scroll=scroll.get_vadjustment().get_value()
            serial[0]+=1;generation=serial[0]
            if reset:limit[0]=50;scroll.get_vadjustment().set_value(0)
            while listing.get_first_child():listing.remove(listing.get_first_child())
            query=search.get_text().casefold()
            matches=[(i,row) for i,row in enumerate(rows) if not query or query in preview(row)[1].casefold() or query in preview(row)[0].casefold()]
            for i,row in matches[:limit[0]]:
                title,text,binary=preview(row);entry=Gtk.ListBoxRow();entry.history_index=i
                line=Gtk.Box(spacing=12);line.set_margin_top(6);line.set_margin_bottom(6);line.set_margin_start(10);line.set_margin_end(10)
                labels=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=5,hexpand=True)
                name=Gtk.Label(label=title,xalign=0);labels.append(name)
                detail=Gtk.Label(label=text,wrap=True,xalign=0,max_width_chars=42);detail.set_lines(2);detail.set_ellipsize(3);labels.append(detail)
                if binary:
                    picture=Gtk.Picture(width_request=72,height_request=54,can_shrink=True);line.append(picture);thumbnail(row,picture,name,generation)
                line.append(labels);entry.set_child(line);listing.append(entry)
            status.set_text(f'{min(limit[0],len(matches))} of {len(matches)} saved copies · newest first')
            more.set_visible(len(matches)>limit[0]);listing.select_row(listing.get_row_at_index(0))
            if not reset:GLib.idle_add(lambda:scroll.get_vadjustment().set_value(old_scroll) or False)
        search.connect('search-changed',lambda *_:populate())
        search.connect('activate',lambda *_:select(listing,listing.get_selected_row()))
        more.connect('clicked',lambda *_:(limit.__setitem__(0,limit[0]+50),populate(False)))
        key=Gtk.EventControllerKey()
        def pressed(_,value,*args):
            if value==Gdk.KEY_Escape:window.close();return True
            if value==Gdk.KEY_Down and search.has_focus():listing.grab_focus();return True
            return False
        key.connect('key-pressed',pressed);window.add_controller(key)
        window.connect('close-request',lambda *_:serial.__setitem__(0,serial[0]+1) or False)
        attempts=[0]
        def place():
            attempts[0]+=1
            try:
                clients=json.loads(subprocess.check_output(['mmsg','get','all-clients'],text=True,timeout=1))['clients']
                client=next((c for c in clients if c['pid']==os.getpid() and c['appid']=='io.victoria.Clipboard'),None)
                if client and origin:
                    x,y=position(*origin,client['width'],client['height'])
                    subprocess.run(['mmsg','dispatch',f"movewin,{x-client['x']:+d},{y-client['y']:+d}",f"client,{client['id']}"],capture_output=True,timeout=1)
                elif attempts[0]<100:return True
            except (OSError,ValueError,KeyError,subprocess.SubprocessError):pass
            window.set_opacity(1);return False
        # Zero opacity delays the first rendered buffer: Mango cannot find/move
        # the client until it becomes visible. Keep a nonzero initial opacity.
        if origin:window.set_opacity(0.01)
        populate();window.present();search.grab_focus()
        if origin:GLib.timeout_add(20,place)
    app.connect('activate',activate);app.run([]);return result[0]
