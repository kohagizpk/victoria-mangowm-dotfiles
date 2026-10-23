"""Exercise the complete setup/refresh path with a deterministic Wallust stand-in."""
import configparser
import ctypes
import ctypes.util
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ThemeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="victoria's home ")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.mango = self.home / '.config/mango'
        shutil.copytree(ROOT / 'config/wallust', self.mango / 'config/wallust')
        shutil.copytree(ROOT / 'config/fish', self.mango / 'config/fish')
        (self.mango / 'waybar').mkdir()
        (self.mango / 'wallpaper').mkdir()
        (self.mango / 'wallpaper/wallpaper.jpg').write_bytes(b'image fixture')
        self.bin = self.home / 'bin'; self.bin.mkdir()
        self.cache = self.home / 'custom cache/wallust'
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin', XDG_CACHE_HOME=str(self.cache.parent))
        self.env.pop('WAYLAND_DISPLAY', None)
        self.env.pop('XDG_STATE_HOME', None)
        self.mock('wallust', '''#!/usr/bin/env python3
import json, os, re, sys, tomllib
from pathlib import Path
args=sys.argv
assert '--skip-sequences' in args and '--no-hooks' in args
config=tomllib.loads(Path(args[args.index('--config-file')+1]).read_text())
assert config['backend']=='kmeans' and config['palette']=='dark'
root=Path(args[args.index('--templates-dir')+1])
colors={'background':'#111827','foreground':'#e5e7eb'}
colors.update({f'color{i}':f'#{i+80:02x}8090' for i in range(16)})
Path(os.environ['HOME'],'last-image').write_text(args[-1])
for template in config['templates'].values():
    text=(root/template['template']).read_text()
    def render(match):
        parts=match.group(1).strip().split('|')
        color=colors[parts[0].strip()]
        return color.lstrip('#') if len(parts)>1 else color
    text=re.sub(r'{{(.*?)}}',render,text)
    Path(template['target']).write_text(text)
''')

    def mock(self, name, source):
        p = self.bin / name; p.write_text(source); p.chmod(0o755)

    def run_theme(self, *args, success=True):
        r = subprocess.run(['python3', str(ROOT / 'scripts/theme.py'), *args], env=self.env, capture_output=True, text=True, timeout=45)
        if success:
            self.assertEqual(r.returncode, 0, r.stderr)
        else:
            self.assertNotEqual(r.returncode, 0)
        return r

    def ini(self):
        config = configparser.ConfigParser(interpolation=None)
        config.read(self.home / '.config/waypaper/config.ini')
        return config['Settings']

    def test_fresh_install_generates_all_colors_and_fish_loader(self):
        self.run_theme('setup')
        self.run_theme('apply', '--install')
        self.assertEqual(self.ini()['backend'], 'awww')
        self.assertTrue((self.cache / 'sequences').read_bytes().startswith(b'\x1b]4;0;'))
        self.assertIn('fish_color_command', (self.cache / 'victoria-colors.fish').read_text())
        self.assertTrue((self.cache / 'victoria-generation').exists())
        self.assertIn('focus_color=0x', (self.mango / 'colors.conf').read_text())
        self.assertNotIn('{{', (self.mango / 'waybar/colors.css').read_text())
        self.assertTrue((self.home / '.config/fish/conf.d/victoria-wallust.fish').is_file())

    def test_existing_multimonitor_settings_and_custom_hook_are_preserved(self):
        dp = self.home / 'dp image.jpg'; dp.touch()
        hdmi = self.home / 'hdmi image.jpg'; hdmi.touch()
        path = self.home / '.config/waypaper/config.ini'; path.parent.mkdir()
        path.write_text(f'[Settings]\nbackend=swaybg\nmonitors=DP-1\n HDMI-A-1\nwallpaper={dp}\n {hdmi}\nfill=stretch\npost_command=echo custom\n')
        fish = self.home / '.config/fish/config.fish'; fish.parent.mkdir()
        fish.write_text('# user prompt and PATH\n')
        self.run_theme('setup'); self.run_theme('setup')
        self.assertEqual(self.ini()['fill'], 'stretch')
        self.assertEqual(self.ini()['wallpaper'], f'{dp}\n{hdmi}')
        self.assertEqual(self.ini()['post_command'].count('wallust-reload.sh'), 1)
        self.assertTrue(self.ini()['post_command'].startswith('echo custom; '))
        self.assertEqual(fish.read_text(), '# user prompt and PATH\n')
        self.run_theme('apply', '--install')
        self.assertEqual((self.home / 'last-image').read_text(), str(hdmi))

    def test_active_preferred_monitor_wins_over_callback_argument(self):
        self.run_theme('setup')
        first = self.home / 'one.jpg'; first.touch()
        second = self.home / 'two.jpg'; second.touch()
        self.mock('awww', f'#!/bin/sh\nprintf "%s\\n" "DP-1: currently displaying: image: {first}" "HDMI-A-1: currently displaying: image: {second}"\n')
        self.run_theme('apply', str(first))
        self.assertEqual((self.home / 'last-image').read_text(), str(second))

    def test_single_monitor_and_offline_fallback(self):
        self.run_theme('setup')
        image = self.home / 'laptop image.jpg'; image.touch()
        self.mock('awww', f'#!/bin/sh\nprintf "%s\\n" "eDP-1: currently displaying: image: {image}"\n')
        self.run_theme('apply')
        self.assertEqual((self.home / 'last-image').read_text(), str(image))
        self.mock('awww', '#!/bin/sh\nexit 1\n')
        self.run_theme('apply')
        self.assertEqual((self.home / 'last-image').read_text(), str(self.mango / 'wallpaper/wallpaper.jpg'))

    def test_failed_or_incomplete_render_keeps_previous_palette(self):
        self.run_theme('setup'); self.run_theme('apply', '--install')
        before = (self.mango / 'waybar/colors.css').read_bytes()
        generation = (self.cache / 'victoria-generation').read_bytes()
        for code in (0, 1):
            self.mock('wallust', f'#!/bin/sh\nexit {code}\n')
            self.run_theme('apply', '--install', success=False)
            self.assertEqual((self.mango / 'waybar/colors.css').read_bytes(), before)
            self.assertEqual((self.cache / 'victoria-generation').read_bytes(), generation)

    def test_install_does_not_query_active_session(self):
        self.run_theme('setup')
        self.mock('awww', '#!/bin/sh\ntouch "$HOME/unwanted-query"\n')
        self.run_theme('apply', '--install')
        self.assertFalse((self.home / 'unwanted-query').exists())

    def test_waypaper_xdg_state(self):
        image = self.home / 'state.jpg'; image.touch()
        path = self.home / '.config/waypaper/config.ini'; path.parent.mkdir()
        path.write_text('[Settings]\nuse_xdg_state=True\n')
        state = self.home / '.local/state/waypaper/state.ini'; state.parent.mkdir(parents=True)
        state.write_text(f'[State]\nbackend=swaybg\nmonitors=All\nwallpaper={image}\n')
        self.run_theme('setup'); self.run_theme('apply', '--install')
        self.assertEqual((self.home / 'last-image').read_text(), str(image))
        self.assertEqual(self.ini()['use_xdg_state'], 'True')
        state_config = configparser.ConfigParser()
        state_config.read(state)
        self.assertEqual(state_config['State']['backend'], 'awww')

    def test_actual_fish_loader_and_prompt_refresh(self):
        fish = shutil.which('fish')
        if not fish:
            self.skipTest('fish binary unavailable')
        self.run_theme('setup'); self.run_theme('apply', '--install')
        loader = self.home / '.config/fish/conf.d/victoria-wallust.fish'
        subprocess.run([fish, '--no-config', '--no-execute', str(loader)], check=True, capture_output=True)
        program = 'source "$HOME/.config/fish/conf.d/victoria-wallust.fish"; printf "%s" "$fish_color_command"'
        result = subprocess.run([fish, '--no-config', '-i', '-c', program], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('558090', result.stdout)

    def test_actual_wallust_templates(self):
        binary = shutil.which('wallust')
        if not binary:
            self.skipTest('wallust binary unavailable')
        import struct
        import zlib
        # A small PNG with varied colors, generated without extra dependencies.
        def chunk(kind, data):
            return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data) & 0xffffffff)
        raw = b''.join(b'\x00' + bytes(channel for x in range(64) for channel in (x * 4, y * 4, ((x + y) % 64) * 4)) for y in range(64))
        png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', 64, 64, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
        image = self.mango / 'wallpaper/test.png'; image.write_bytes(png)
        (self.bin / 'wallust').unlink(); (self.bin / 'wallust').symlink_to(binary)
        self.run_theme('setup'); self.run_theme('apply', '--install', str(image))
        self.assertTrue((self.cache / 'victoria-generation').is_file())
        self.assertIn('focus_color=0x', (self.mango / 'colors.conf').read_text())

    def test_css_with_native_gtk_parser(self):
        library = ctypes.util.find_library('gtk-3')
        if not library:
            self.skipTest('GTK 3 library unavailable')
        class Error(ctypes.Structure):
            _fields_ = [('domain', ctypes.c_uint), ('code', ctypes.c_int), ('message', ctypes.c_char_p)]
        gtk = ctypes.CDLL(library)
        gtk.gtk_css_provider_new.restype = ctypes.c_void_p
        gtk.gtk_css_provider_load_from_path.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(ctypes.POINTER(Error))]
        gtk.gtk_css_provider_load_from_path.restype = ctypes.c_int
        error = ctypes.POINTER(Error)()
        provider = gtk.gtk_css_provider_new()
        valid = gtk.gtk_css_provider_load_from_path(provider, str(ROOT / 'waybar/style.css').encode(), ctypes.byref(error))
        self.assertTrue(valid, error.contents.message.decode() if error else '')


if __name__ == '__main__':
    unittest.main(verbosity=2)
