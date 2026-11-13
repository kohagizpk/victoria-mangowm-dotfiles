#!/usr/bin/env python3
"""GTK4 controls for Victoria. No package installation or privileged operations."""
import argparse
import json
import os
import re
from pathlib import Path
import sys
import threading

import victoria_settings as backend


def launch(page='appearance', first_run=False):
    try:
        import gi
        gi.require_version('Gtk', '4.0')
        from gi.repository import Gtk, Gdk, GLib, Gio
    except (ImportError, ValueError):
        raise SystemExit('Victoria Settings needs GTK4 and Python GObject (Arch: gtk4 python-gobject).')

    class Window(Gtk.ApplicationWindow):
        def __init__(self, app):
            super().__init__(application=app, title='Victoria Settings', default_width=880, default_height=700)
            self.pending_display = None
            self.timer = None
            self.busy = False
            self.values = backend.read_settings()
            self.controls = {}
            header = Gtk.HeaderBar()
            self.set_titlebar(header)
            self.focus_button = Gtk.Button(label='Leave focus mode' if (backend.STATE / 'focus.json').exists() else 'Focus mode')
            self.focus_button.connect('clicked', self.toggle_focus)
            header.pack_end(self.focus_button)
            center = Gtk.Button(label='Control center')
            center.connect('clicked', lambda *_: __import__('subprocess').Popen(['python3', str(backend.MANGO/'scripts/control-center.py')], start_new_session=True))
            header.pack_start(center)
            self.root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
            self.root.set_margin_start(20); self.root.set_margin_end(20)
            self.root.set_margin_top(12); self.root.set_margin_bottom(16)
            self.set_child(self.root)
            self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, vexpand=True)
            switcher = Gtk.StackSwitcher(stack=self.stack, halign=Gtk.Align.CENTER)
            self.root.append(switcher); self.root.append(self.stack)
            self.status = Gtk.Label(label='Personal settings · changes apply only when you choose Apply', wrap=True, xalign=0)
            self.status.add_css_class('status'); self.root.append(self.status)
            startup=Gtk.ToggleButton()
            startup.set_active(not (backend.STATE/'settings-autostart-disabled').exists() and ((backend.STATE/'settings-autostart-enabled').exists() or not (backend.STATE/'setup-complete').exists()))
            def update_startup_label(button):
                button.set_label('Open Settings automatically at login: '+('ON' if button.get_active() else 'OFF'))
                if button.get_active():button.add_css_class('suggested-action')
                else:button.remove_css_class('suggested-action')
            update_startup_label(startup)
            def set_startup(button):
                update_startup_label(button)
                if button.get_active():
                    (backend.STATE/'settings-autostart-disabled').unlink(missing_ok=True)
                    backend.atomic(backend.STATE/'settings-autostart-enabled','1\n')
                else:
                    (backend.STATE/'settings-autostart-enabled').unlink(missing_ok=True)
                    backend.atomic(backend.STATE/'settings-autostart-disabled','1\n')
            startup.connect('toggled',set_startup);self.root.append(startup)
            self.appearance(); self.setup_page(); self.shortcuts_page(); self.diagnostics_page()
            self.stack.set_visible_child_name(page)
            self.connect('close-request', self.on_close)
            self.load_style()
            self.update_preview()

        def load_style(self):
            palette = backend.MANGO / 'waybar/colors.css'
            palette_text = palette.read_text() if palette.exists() else ''
            colors = dict(re.findall(r'@define-color\s+(\w+)\s+(#[0-9A-Fa-f]{6});', palette_text))
            self.preview_accent = colors.get('color5', '#a88bd8')
            css = ''
            css += '''
window, window.background { background: @background; background-image: none; color: @foreground; }
label { color: @foreground; }
button { border-radius: 9px; padding: 7px 12px; }
button.suggested-action { background: mix(@color5, @background, 0.2); color: @foreground; }
.card { background: alpha(@foreground, 0.045); border: 1px solid alpha(@foreground, 0.10); border-radius: 14px; padding: 16px; }
.title { font-size: 22px; font-weight: 700; }
.group-title { font-size: 15px; font-weight: 700; }
expander { background: alpha(@foreground, 0.035); border: 1px solid alpha(@foreground, 0.08); border-radius: 14px; padding: 14px; }
.settings-card { padding: 6px 4px; }
.settings-card > box { padding: 3px 0; }
spinbutton, entry, dropdown > button { border-radius: 8px; background-color: alpha(@foreground, 0.045); border-color: alpha(@foreground, 0.12); }
switch:checked { background: @color5; }
stackswitcher button:checked { background: alpha(@color5, 0.22); color: @foreground; }
button.suggested-action { background-image: none; box-shadow: none; border: 1px solid alpha(@foreground, 0.1); }
.subtitle, .status { color: alpha(@foreground, 0.65); font-size: 12px; }
.preview { padding: 18px; }
.shortcut-key { font-family: monospace; font-weight: bold; color: mix(@color5, @foreground, 0.4); }
'''
            for name, fallback in [('background','#17151b'),('foreground','#ece7ee'),('color5','#a88bd8')]:
                css = css.replace('@' + name, colors.get(name, fallback))
            provider = Gtk.CssProvider(); provider.load_from_data(css.encode())
            Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)
            self.preview_provider = Gtk.CssProvider()
            Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), self.preview_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER + 2)

        def box(self, spacing=12):
            return Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=spacing)

        def title(self, box, heading, subtitle):
            label = Gtk.Label(label=heading, xalign=0); label.add_css_class('title'); box.append(label)
            label = Gtk.Label(label=subtitle, xalign=0, wrap=True); label.add_css_class('subtitle'); box.append(label)

        def scroll_page(self, name, title, content):
            sc = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
            sc.set_child(content); self.stack.add_titled(sc, name, title)

        def row(self, parent, title, widget):
            row = Gtk.Box(spacing=20)
            row.append(Gtk.Label(label=title, xalign=0, hexpand=True))
            widget.set_valign(Gtk.Align.CENTER); row.append(widget); parent.append(row)
            return widget

        def dropdown(self, values, selected=0):
            w = Gtk.DropDown.new_from_strings(values); w.set_selected(selected)
            return w

        def choice(self, widget):
            return widget.get_selected_item().get_string()

        def run_job(self, function, success=None):
            if self.busy:
                return
            self.busy = True; self.stack.set_sensitive(False); self.focus_button.set_sensitive(False)
            self.status.set_text('Working…')
            def finish(value, error):
                self.busy = False; self.stack.set_sensitive(True); self.focus_button.set_sensitive(True)
                if error:
                    self.status.set_text('Could not complete: ' + error)
                elif success:
                    success(value)
                else:
                    self.status.set_text('Done.')
                return False
            def work():
                try:
                    value = function(); GLib.idle_add(finish, value, None)
                except Exception as exc:
                    GLib.idle_add(finish, None, str(exc))
            threading.Thread(target=work, daemon=True).start()

        def appearance(self):
            page = self.box(14)
            self.title(page, 'Your desktop, your way', 'A few thoughtful controls. Changes stay in preview until you apply them.')
            scroller = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
            box = self.box(12); scroller.set_child(box); page.append(scroller)
            profiles = self.dropdown(['Custom', *backend.PROFILES])
            self.row(box, 'Start with a profile', profiles)
            profiles.connect('notify::selected', self.select_profile)

            def group(title, subtitle, expanded=False):
                expander = Gtk.Expander(expanded=expanded)
                heading = self.box(3)
                name = Gtk.Label(label=title, xalign=0); name.add_css_class('group-title'); heading.append(name)
                hint = Gtk.Label(label=subtitle, xalign=0, wrap=True); hint.add_css_class('subtitle'); heading.append(hint)
                expander.set_label_widget(heading)
                card = self.box(12); card.add_css_class('settings-card'); card.set_margin_top(12)
                expander.set_child(card); box.append(expander)
                return card

            def number(card, key, label, lo, hi, step=1):
                w = Gtk.SpinButton.new_with_range(lo, hi, step); w.set_value(self.values[key])
                w.set_digits(2 if key == 'opacity' else 0)
                w.connect('value-changed', lambda *_: self.update_preview())
                self.controls[key] = self.row(card, label, w)

            def toggle(card, key, label):
                w = Gtk.Switch(active=self.values[key]); self.controls[key] = self.row(card, label, w)
                w.connect('notify::active', lambda *_: self.update_preview())

            def select(card, key, label, options):
                w = self.dropdown(options, options.index(self.values[key])); self.controls[key] = self.row(card, label, w)
                w.connect('notify::selected', lambda *_: self.update_preview())

            card = group('Appearance', 'Colors, spacing and a little personality')
            select(card,'color_mode','Color palette',['wallpaper','fixed'])
            entry = Gtk.Entry(text=self.values['accent'], max_length=7, width_chars=10)
            entry.connect('changed', lambda *_: self.update_preview()); self.controls['accent'] = self.row(card, 'Accent color · #RRGGBB', entry)
            for key,label,lo,hi in [('font_size','Interface text size',10,20),('gaps','Space between windows',0,30),('border','Border thickness',0,8),('radius','Rounded corners',0,30)]:
                number(card,key,label,lo,hi)
            number(card,'opacity','Inactive window opacity',0.7,1,0.01)
            toggle(card,'animations','Window animations')
            select(card,'animation_speed','Animation speed',['fast','normal','relaxed'])
            toggle(card,'blur','Background blur'); toggle(card,'shadows','Window shadows')
            wallpaper=Gtk.Button(label='Choose wallpaper…')
            wallpaper.connect('clicked',lambda *_: self.open_wallpaper()); card.append(wallpaper)

            card = group('Bar & clock', 'Only the information you want to see')
            select(card,'bar_position','Bar position',['top','bottom'])
            number(card,'bar_margin','Space from screen edges',0,16)
            for key,label in [('show_stats','CPU, memory and temperature'),('show_media','Now playing'),('show_visualizer','Audio visualizer'),('show_tray','App tray'),('clock_seconds','Show seconds'),('clock_24h','Use a 24-hour clock')]:
                toggle(card,key,label)

            card = group('Notifications', 'Less interruption, the way you prefer')
            select(card,'notification_position','Corner',['top-right','top-left','bottom-right','bottom-left'])
            number(card,'notification_timeout','Normal notification duration · seconds',3,20)
            number(card,'notification_width','Notification width · pixels',300,600,20)
            toggle(card,'notification_images','Show notification images')
            hint=Gtk.Label(label='Critical alerts remain visible. Position also applies to the notification panel.',wrap=True,xalign=0);hint.add_css_class('subtitle');card.append(hint)

            card = group('Mouse & touchpad', 'Make moving around feel natural')
            number(card,'cursor_size','Pointer size',16,64,4)
            toggle(card,'focus_follows_mouse','Focus windows when the pointer enters')
            toggle(card,'natural_scroll','Natural scrolling on the touchpad')
            toggle(card,'tap_to_click','Tap the touchpad to click')

            card = group('Lock & idle', 'Automatic locking, screens and sleep — optional')
            toggle(card,'idle_enabled','Enable automatic idle actions')
            number(card,'idle_lock_minutes','Lock after · minutes',1,120)
            number(card,'idle_screen_minutes','Turn screens off after · minutes',1,180)
            number(card,'idle_suspend_minutes','Suspend after · minutes · 0 means never',0,240)
            hint=Gtk.Label(label='Locking always happens before screen-off or sleep. Idle inhibitors from media apps are respected.',wrap=True,xalign=0)
            hint.add_css_class('subtitle');card.append(hint)

            self.preview = self.box(6); self.preview.add_css_class('preview'); self.preview.add_css_class('card')
            self.preview.append(Gtk.Label(label='STYLE PREVIEW', xalign=0))
            self.preview.append(Gtk.Label(label='1    2    3                    Victoria', xalign=0))
            box.append(self.preview)
            footer=Gtk.Box(spacing=12)
            note=Gtk.Label(label='Your other personal settings stay intact.',xalign=0,hexpand=True);note.add_css_class('subtitle');footer.append(note)
            apply=Gtk.Button(label='Apply changes');apply.add_css_class('suggested-action')
            apply.connect('clicked',self.apply_appearance);footer.append(apply);page.append(footer)
            self.stack.add_titled(page,'appearance','Personalize')

        def open_wallpaper(self):
            import subprocess
            try:
                subprocess.Popen(['waypaper'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            except OSError as exc:
                self.status.set_text(str(exc))

        def collect(self):
            data = {}
            for key, w in self.controls.items():
                data[key] = w.get_active() if isinstance(w, Gtk.Switch) else self.choice(w) if isinstance(w, Gtk.DropDown) else w.get_text() if isinstance(w, Gtk.Entry) else w.get_value() if key == 'opacity' else w.get_value_as_int()
            return backend.validate_settings(data)

        def update_preview(self):
            if not hasattr(self, 'preview_provider'):
                return
            try:
                v = self.collect()
                accent = v['accent'] if v['color_mode'] == 'fixed' else self.preview_accent
                self.preview_provider.load_from_data(f'.preview {{ border-radius: {v["radius"]}px; border: {v["border"]}px solid {accent}; padding: {12+v["gaps"]}px; opacity: {v["opacity"]}; }} .preview label {{ font-size: {v["font_size"]}px; }}'.encode())
                self.controls['accent'].set_sensitive(v['color_mode'] == 'fixed')
            except ValueError:
                pass

        def select_profile(self, widget, *_):
            profile = backend.PROFILES.get(self.choice(widget))
            if not profile:
                return
            for key, value in profile.items():
                w = self.controls[key]
                w.set_active(value) if isinstance(w, Gtk.Switch) else w.set_value(value)
            self.update_preview()

        def apply_appearance(self, *_):
            try:
                values = self.collect()
            except ValueError as exc:
                self.status.set_text(str(exc)); return
            self.run_job(lambda: backend.save_appearance(values), lambda _: self.status.set_text('Changes applied. Relaunch existing apps if their font or pointer size has not updated.'))

        def setup_page(self):
            box = self.box(); self.title(box,'Welcome to Victoria','A short setup for your keyboard, displays and preferred apps. No packages are installed here.')
            self.wizard = Gtk.Stack(vexpand=True)
            self.steps = ['Keyboard','Displays','Applications','Review']; self.step = 0
            self.step_label = Gtk.Label(xalign=0); box.append(self.step_label); box.append(self.wizard)
            keyboard = self.box(); keyboard.add_css_class('card')
            self.keyboard = self.row(keyboard, 'Keyboard layout', self.dropdown(['US','US international','Brazil ABNT2'], 1))
            keyboard.append(Gtk.Label(label='Changes the graphical session layout. The console keyboard stays unchanged.', wrap=True, xalign=0))
            self.wizard.add_named(keyboard,'Keyboard')
            displays = self.box(); displays.add_css_class('card')
            self.layout = self.row(displays,'Monitor layout',self.dropdown(['Keep current','Automatic side by side']))
            self.scale = self.row(displays,'Display scale',self.dropdown(['1','1.25','1.5','2']))
            displays.append(Gtk.Label(label='Automatic layout uses detected monitors and their advertised modes, with the laptop panel first. You will have 20 seconds to keep the new layout.',wrap=True,xalign=0))
            self.monitor_label = Gtk.Label(label='Detecting displays…',wrap=True,xalign=0); displays.append(self.monitor_label)
            try:
                import monitors
                self.monitor_label.set_text('\n'.join(f'{name} · {mode.width} × {mode.height}' for name,mode in monitors.detect()) or 'No readable displays. Keep the current layout.')
            except Exception:
                self.monitor_label.set_text('Display detection unavailable. Keep the current layout.')
            self.wizard.add_named(displays,'Displays')
            apps = self.box(); apps.add_css_class('card')
            self.terminal = self.row(apps,'Terminal shortcut',self.dropdown(['Keep current','kitty','foot']))
            self.browser = self.row(apps,'Browser shortcut',self.dropdown(['Keep current','firefox','helium-browser','brave']))
            self.setup_profile = self.row(apps,'Appearance',self.dropdown(['Keep current',*backend.PROFILES]))
            apps.append(Gtk.Label(label='These choices update Super + Enter and Super + W. Applications must already be installed.',wrap=True,xalign=0))
            self.wizard.add_named(apps,'Applications')
            review = self.box(); review.add_css_class('card'); self.review = Gtk.Label(wrap=True,xalign=0); review.append(self.review)
            self.keep_display = Gtk.Button(label='Keep this display layout'); self.keep_display.set_visible(False)
            self.keep_display.connect('clicked',self.keep_layout); review.append(self.keep_display)
            self.wizard.add_named(review,'Review')
            buttons=Gtk.Box(spacing=10); self.back=Gtk.Button(label='Back'); self.next=Gtk.Button(label='Next')
            self.next.add_css_class('suggested-action'); self.back.connect('clicked',lambda *_: self.wizard_move(-1)); self.next.connect('clicked',lambda *_: self.wizard_move(1))
            buttons.append(self.back);buttons.append(self.next);box.append(buttons)
            self.scroll_page('setup','Setup',box); self.wizard_move(0)

        def wizard_move(self, delta):
            if self.pending_display:
                return
            if self.step == 3 and delta == 1:
                values = (self.choice(self.keyboard),self.choice(self.layout),float(self.choice(self.scale)),self.choice(self.terminal),self.choice(self.browser))
                profile = self.choice(self.setup_profile)
                def apply():
                    # Display changes are applied last so their confirmation timer starts promptly.
                    if profile in backend.PROFILES:
                        appearance=backend.read_settings();appearance.update(backend.PROFILES[profile]);backend.save_appearance(appearance)
                    return backend.apply_setup(*values)
                def done(saved):
                    if values[1] != 'Keep current':
                        self.pending_display=saved;self.remaining=20;self.keep_display.set_visible(True)
                        self.next.set_sensitive(False);self.back.set_sensitive(False)
                        self.timer=GLib.timeout_add_seconds(1,self.tick_layout)
                        self.status.set_text('Keep the new display layout within 20 seconds, or it will revert.')
                    else:
                        self.finish_setup()
                self.run_job(apply,done);return
            self.step=max(0,min(3,self.step+delta));self.wizard.set_visible_child_name(self.steps[self.step])
            self.step_label.set_text(f'Step {self.step+1} of 4 · {self.steps[self.step]}')
            self.back.set_sensitive(self.step>0);self.next.set_label('Finish setup' if self.step==3 else 'Next')
            self.review.set_text(f'Keyboard: {self.choice(self.keyboard)}\nDisplays: {self.choice(self.layout)}\nScale: {self.choice(self.scale)}\nTerminal: {self.choice(self.terminal)}\nBrowser: {self.choice(self.browser)}\nAppearance: {self.choice(self.setup_profile)}\n\nExisting personal settings outside these choices are preserved.')

        def tick_layout(self):
            self.remaining-=1
            if not self.pending_display:
                self.timer=None;return False
            if self.remaining<=0:
                backend.restore(self.pending_display);self.pending_display=None;self.timer=None
                self.keep_display.set_visible(False);self.next.set_sensitive(True);self.back.set_sensitive(True)
                self.status.set_text('Display setup reverted because it was not confirmed.');return False
            self.keep_display.set_label(f'Keep this display layout ({self.remaining}s)');return True

        def keep_layout(self,*_):
            self.pending_display=None
            if self.timer:GLib.source_remove(self.timer);self.timer=None
            self.keep_display.set_visible(False);self.next.set_sensitive(True);self.back.set_sensitive(True);self.finish_setup()

        def finish_setup(self):
            backend.atomic(backend.STATE/'setup-complete','1\n')
            self.status.set_text('Setup complete. You can revisit these choices any time.')

        def shortcuts_page(self):
            box=self.box();self.title(box,'Your shortcuts','Search the bindings actually loaded by Mango, including personal overrides.')
            search=Gtk.SearchEntry(placeholder_text='Search a key, app or action…');box.append(search)
            self.shortcut_list=self.box(4);box.append(self.shortcut_list)
            self.shortcut_rows=[]
            for combo,desc,kind in backend.shortcuts():
                row=Gtk.Box(spacing=18);row.add_css_class('card')
                key=Gtk.Label(label=combo,xalign=0,width_chars=23);key.add_css_class('shortcut-key');row.append(key)
                row.append(Gtk.Label(label=desc,wrap=True,xalign=0,hexpand=True))
                self.shortcut_list.append(row);self.shortcut_rows.append((row,(combo+' '+desc+' '+kind).lower()))
            search.connect('search-changed',lambda w:[row.set_visible(w.get_text().lower() in text) for row,text in self.shortcut_rows])
            self.scroll_page('shortcuts','Shortcuts',box)

        def diagnostics_page(self):
            box=self.box();self.title(box,'Desktop health','Checks explain what is missing. Repair actions run only when you select them.')
            self.report=Gtk.Label(label='Run a check to inspect your desktop.',wrap=True,xalign=0,selectable=True);self.report.add_css_class('card');box.append(self.report)
            button=Gtk.Button(label='Run diagnostics');button.add_css_class('suggested-action');button.connect('clicked',self.check_health);box.append(button)
            for action in ('Refresh colors','Restore wallpaper','Reload notifications'):
                button=Gtk.Button(label=action);button.connect('clicked',lambda _, a=action:self.run_job(lambda:backend.repair(a),lambda result:self.status.set_text(result.strip() or 'Repair completed.')));box.append(button)
            self.scroll_page('diagnostics','Diagnostics',box)

        def check_health(self,*_):
            def done(rows):
                self.report.set_text('\n\n'.join(('✓ ' if ok else '⚠ ')+name+('' if ok else '\n'+hint) for ok,name,hint in rows))
                self.status.set_text(f'{sum(not r[0] for r in rows)} issue(s) found. No changes were made.')
            self.run_job(backend.diagnostics,done)

        def toggle_focus(self,*_):
            def done(active):
                self.focus_button.set_label('Leave focus mode' if active else 'Focus mode')
                self.status.set_text('Focus mode on: notifications silenced and secondary bar modules hidden.' if active else 'Focus mode off: previous notification preference restored.')
            self.run_job(backend.focus,done)

        def on_close(self,*_):
            if self.busy:
                self.status.set_text('Wait for the current change to finish before closing.');return True
            if self.pending_display:
                backend.restore(self.pending_display);self.pending_display=None
            if self.timer:GLib.source_remove(self.timer)
            return False

    app=Gtk.Application(application_id='io.victoria.Settings', flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
    def activate(app):
        window=app.get_active_window()
        if window is None: window=Window(app)
        else: window.stack.set_visible_child_name(page)
        window.present()
    app.connect('activate',activate)
    def dispatch(app, command_line):
        args = command_line.get_arguments()
        app.activate()
        if len(args) > 1 and args[1] in ('appearance', 'setup', 'shortcuts', 'diagnostics'):
            app.get_active_window().stack.set_visible_child_name(args[1])
        return 0
    app.connect('command-line', dispatch)
    return app.run([sys.argv[0], page])


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--shortcuts',action='store_true')
    parser.add_argument('--setup',action='store_true')
    parser.add_argument('--diagnostics',action='store_true')
    parser.add_argument('--focus',action='store_true')
    parser.add_argument('--first-run',action='store_true')
    args=parser.parse_args()
    if args.focus:
        print('Focus on' if backend.focus() else 'Focus off');return
    if args.first_run:
        if (backend.STATE / 'focus.json').exists():
            backend.command(['swaync-client', '-sw', '-dn'], required=False)
        if (backend.STATE/'settings-autostart-disabled').exists():return
        if (backend.STATE/'setup-complete').exists() and not (backend.STATE/'settings-autostart-enabled').exists():return
    page='setup' if args.setup or args.first_run else 'shortcuts' if args.shortcuts else 'diagnostics' if args.diagnostics else 'appearance'
    launch(page,args.first_run)

if __name__=='__main__':
    try:main()
    except (OSError,RuntimeError,ValueError) as exc:sys.exit(str(exc))
