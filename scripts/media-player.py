#!/usr/bin/env python3
"""Compact MPRIS record player, using the desktop's GTK and Wallust palette."""
import ctypes
import json
import re
import subprocess
import threading
import time
from pathlib import Path
from urllib.parse import urlparse, unquote
from urllib.request import urlopen

try:
    ctypes.CDLL('libgtk4-layer-shell.so.0', mode=ctypes.RTLD_GLOBAL)
except OSError:
    pass
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Gsk', '4.0')
gi.require_version('Graphene', '1.0')
from gi.repository import Gtk, Gdk, Gio, GLib, Gsk, Graphene, Pango
try:
    gi.require_version('Gtk4LayerShell', '1.0')
    from gi.repository import Gtk4LayerShell as Layer
except (ImportError, ValueError):
    Layer = None

PLAYER = 'org.mpris.MediaPlayer2.Player'
PATH = '/org/mpris/MediaPlayer2'


def rect(x, y, w, h):
    return Graphene.Rect().init(x, y, w, h)


def rgba(value):
    color = Gdk.RGBA()
    color.parse(value)
    return color


class Record(Gtk.Widget):
    def __init__(self):
        super().__init__()
        self.set_size_request(132, 132)
        self.angle = 0
        self.playing = False
        self.texture = None
        self.accent = '#b18aa6'
        self.last_frame = None
        GLib.timeout_add(33, self.tick)

    def tick(self):
        now = time.monotonic_ns() // 1000
        if self.playing and self.last_frame is not None:
            self.angle = (self.angle + (now - self.last_frame) * 0.000018) % 360
            self.queue_draw()
        self.last_frame = now
        return True

    def do_snapshot(self, snapshot):
        snapshot.save()
        snapshot.translate(Graphene.Point().init(66, 66))
        snapshot.rotate(self.angle)
        def circle(radius, color):
            bounds = rect(-radius, -radius, radius * 2, radius * 2)
            clip = Gsk.RoundedRect()
            clip.init_from_rect(bounds, radius)
            snapshot.push_rounded_clip(clip)
            snapshot.append_color(rgba(color), bounds)
            snapshot.pop()
        circle(64, self.accent)
        circle(62, '#111116')
        for radius in (56, 50, 44, 38):
            circle(radius, '#303039')
            circle(radius - 1, '#111116')
        bounds = rect(-32, -32, 64, 64)
        art_clip = Gsk.RoundedRect()
        art_clip.init_from_rect(bounds, 32)
        snapshot.push_rounded_clip(art_clip)
        if self.texture:
            w, h = self.texture.get_width(), self.texture.get_height()
            factor = 64 / min(w, h)
            snapshot.append_texture(self.texture, rect(-w * factor / 2, -h * factor / 2, w * factor, h * factor))
        else:
            snapshot.append_color(rgba(self.accent), bounds)
            snapshot.append_color(rgba('#ffffff44'), rect(-32, -12, 64, 10))
        snapshot.pop()
        circle(6, '#111116')
        circle(2, '#dddddd')
        snapshot.restore()


class MediaPlayer(Gtk.Application):
    def __init__(self):
        super().__init__(application_id='io.victoria.MediaPlayer')
        self.window = None
        self.selected = None
        self.busy = False
        self.art_url = None
        self.palette_text = None
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    def call(self, name, interface, method, params=None, path=PATH):
        return self.bus.call_sync(name, path, interface, method, params, None,
                                  Gio.DBusCallFlags.NONE, 1200, None).unpack()

    def do_activate(self):
        if self.window:
            self.window.close()
            return
        self.window = Gtk.ApplicationWindow(application=self, title='Victoria Player')
        self.window.set_decorated(False)
        self.window.set_resizable(False)
        self.window.add_css_class('media-player')
        if Layer and Layer.is_supported():
            Layer.init_for_window(self.window)
            Layer.set_namespace(self.window, 'victoria-player')
            Layer.set_layer(self.window, Layer.Layer.TOP)
            Layer.set_keyboard_mode(self.window, Layer.KeyboardMode.ON_DEMAND)
            Layer.set_anchor(self.window, Layer.Edge.TOP, True)
            Layer.set_anchor(self.window, Layer.Edge.RIGHT, True)
            Layer.set_margin(self.window, Layer.Edge.TOP, 52)
            Layer.set_margin(self.window, Layer.Edge.RIGHT, 16)
            try:
                anchor = json.loads(subprocess.check_output(['mmsg', 'get', 'cursorpos'], text=True, timeout=1))
                monitors = Gdk.Display.get_default().get_monitors()
                for i in range(monitors.get_n_items()):
                    monitor = monitors.get_item(i)
                    if monitor.get_connector() == anchor.get('monitor'):
                        Layer.set_monitor(self.window, monitor)
            except (OSError, ValueError, subprocess.SubprocessError):
                pass
        box = Gtk.Box(spacing=18)
        for side in ('top', 'bottom', 'start', 'end'):
            getattr(box, 'set_margin_' + side)(20)
        self.window.set_child(box)
        self.record = Record()
        self.record.set_valign(Gtk.Align.CENTER)
        box.append(self.record)
        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=7)
        info.set_size_request(250, -1)
        box.append(info)
        header = Gtk.Box(spacing=8)
        self.source = Gtk.DropDown.new_from_strings(['No player'])
        self.source.set_hexpand(True)
        self.names = []
        self.source.connect('notify::selected', self.select)
        header.append(self.source)
        close = Gtk.Button(icon_name='window-close-symbolic')
        close.set_tooltip_text('Fechar (Esc)')
        close.connect('clicked', lambda *_: self.window.close())
        header.append(close)
        info.append(header)
        self.title = Gtk.Label(label='No music playing', xalign=0, ellipsize=Pango.EllipsizeMode.END, max_width_chars=27)
        self.title.add_css_class('track-title')
        self.artist = Gtk.Label(label='Open your music player to get started', xalign=0, ellipsize=Pango.EllipsizeMode.END, max_width_chars=30)
        self.artist.add_css_class('artist')
        info.append(self.title)
        info.append(self.artist)
        self.progress = Gtk.ProgressBar()
        info.append(self.progress)
        controls = Gtk.Box(spacing=10, halign=Gtk.Align.CENTER)
        self.buttons = {}
        for method, icon, tip in [('Previous', 'media-skip-backward-symbolic', 'Previous'), ('PlayPause', 'media-playback-start-symbolic', 'Play / pause'), ('Next', 'media-skip-forward-symbolic', 'Next')]:
            button = Gtk.Button(icon_name=icon)
            button.set_tooltip_text(tip)
            button.connect('clicked', lambda _, action=method: self.control(action))
            if method == 'PlayPause':
                button.add_css_class('play')
            controls.append(button)
            self.buttons[method] = button
        info.append(controls)
        self.status = Gtk.Label(xalign=0, ellipsize=Pango.EllipsizeMode.END, max_width_chars=30)
        self.status.add_css_class('artist')
        info.append(self.status)
        keys = Gtk.EventControllerKey()
        keys.connect('key-pressed', self.key)
        self.window.add_controller(keys)
        self.provider = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), self.provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        self.theme()
        self.window.present()
        self.refresh()
        GLib.timeout_add_seconds(1, self.refresh)

    def key(self, controller, key, code, state):
        if key == Gdk.KEY_Escape:
            self.window.close()
            return True
        return False

    def theme(self):
        try:
            text = (Path.home() / '.config/mango/waybar/colors.css').read_text()
        except OSError:
            text = ''
        if text == self.palette_text:
            return
        self.palette_text = text
        colors = {'background': '#17151b', 'foreground': '#eeeeee', 'color5': '#b18aa6'}
        colors.update(dict(re.findall(r'@define-color\s+(\w+)\s+(#[0-9a-fA-F]{6});', text)))
        css = '''window.media-player {background: @background; color: @foreground; border: 1px solid alpha(@color5, 0.55); border-radius: 22px;}
        .media-player label {color: @foreground;}
        .media-player .track-title {font-size: 18px; font-weight: 700;}
        .media-player .artist {opacity: 0.65; font-size: 11px;}
        .media-player button {border-radius: 18px; background: alpha(@foreground, 0.06); box-shadow: none; border: none; min-height: 28px;}
        .media-player button:hover {background: alpha(@color5, 0.4);}
        .media-player button.play {background: @color5; color: @foreground; min-width: 42px;}
        .media-player progressbar trough {min-height: 3px; background: alpha(@foreground, 0.12);}
        .media-player progressbar progress {min-height: 3px; background: @color5;}
        .media-player dropdown button {font-size: 11px; min-height: 20px;}'''
        css = re.sub(r'@(\w+)', lambda match: colors[match[1]], css)
        self.provider.load_from_data(css.encode())
        self.record.accent = colors['color5']
        self.record.queue_draw()

    def select(self, dropdown, param):
        index = dropdown.get_selected()
        if index < len(self.names):
            self.selected = self.names[index]

    def control(self, method):
        if not self.selected:
            return
        def done(bus, result):
            try:
                bus.call_finish(result)
                self.status.set_text('')
            except GLib.Error:
                self.status.set_text('Player unavailable')
            self.refresh()
        self.bus.call(self.selected, PATH, PLAYER, method, None, None,
                      Gio.DBusCallFlags.NONE, 1500, None, done)

    def refresh(self):
        self.theme()
        if self.busy:
            return True
        self.busy = True
        def worker():
            players = {}
            try:
                names = self.call('org.freedesktop.DBus', 'org.freedesktop.DBus', 'ListNames', path='/org/freedesktop/DBus')[0]
                for name in sorted(names):
                    if name.startswith('org.mpris.MediaPlayer2.'):
                        try:
                            players[name] = self.call(name, 'org.freedesktop.DBus.Properties', 'GetAll', GLib.Variant('(s)', (PLAYER,)))[0]
                        except GLib.Error:
                            pass
            except GLib.Error:
                pass
            GLib.idle_add(self.render, players)
        threading.Thread(target=worker, daemon=True).start()
        return True

    def render(self, players):
        self.busy = False
        if self.selected not in players:
            self.selected = next((n for n, p in players.items() if p.get('PlaybackStatus') == 'Playing'), next(iter(players), None))
        if list(players) != self.names:
            selected = self.selected
            self.names = list(players)
            self.source.set_model(Gtk.StringList.new([n.removeprefix('org.mpris.MediaPlayer2.') for n in self.names] or ['No player']))
            self.selected = selected
            self.source.set_selected(self.names.index(selected) if selected else 0)
        props = players.get(self.selected, {})
        meta = props.get('Metadata', {})
        playing = props.get('PlaybackStatus') == 'Playing'
        self.record.playing = playing
        self.title.set_text(meta.get('xesam:title') or 'No music playing')
        self.title.set_tooltip_text(self.title.get_text())
        self.artist.set_text(' · '.join(meta.get('xesam:artist', [])) or ('Unknown artist' if props else 'Open your music player to get started'))
        self.artist.set_tooltip_text(self.artist.get_text())
        self.buttons['PlayPause'].set_icon_name('media-playback-pause-symbolic' if playing else 'media-playback-start-symbolic')
        for method, capability in [('Previous', 'CanGoPrevious'), ('Next', 'CanGoNext'), ('PlayPause', 'CanPause' if playing else 'CanPlay')]:
            self.buttons[method].set_sensitive(bool(props.get('CanControl', False) and props.get(capability, False)))
        length = max(0, meta.get('mpris:length', 0))
        position = max(0, props.get('Position', 0))
        self.progress.set_fraction(min(1, position / length) if length else 0)
        def clock(value):
            seconds = int(value / 1000000)
            return f'{seconds // 60}:{seconds % 60:02}'
        self.status.set_text(f'{clock(position)} / {clock(length)}' if length else ('Live' if playing else 'Paused' if props else ''))
        url = meta.get('mpris:artUrl', '')
        if url != self.art_url:
            self.art_url = url
            self.record.texture = None
            self.record.queue_draw()
            threading.Thread(target=self.load_art, args=(url,), daemon=True).start()
        return False

    def load_art(self, url):
        data = None
        try:
            parsed = urlparse(url)
            if parsed.scheme == 'file' and parsed.netloc in ('', 'localhost'):
                with Path(unquote(parsed.path)).open('rb') as stream:
                    data = stream.read(8 * 1024 * 1024 + 1)
            elif parsed.scheme in ('https', 'http'):
                with urlopen(url, timeout=4) as stream:
                    data = stream.read(8 * 1024 * 1024 + 1)
            if data and len(data) <= 8 * 1024 * 1024:
                GLib.idle_add(self.apply_art, url, data)
        except (OSError, ValueError):
            pass

    def apply_art(self, url, data):
        if url == self.art_url:
            try:
                self.record.texture = Gdk.Texture.new_from_bytes(GLib.Bytes.new(data))
                self.record.queue_draw()
            except GLib.Error:
                pass
        return False


if __name__ == '__main__':
    raise SystemExit(MediaPlayer().run([]))
