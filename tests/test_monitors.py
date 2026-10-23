"""Hardware-independent regression coverage for detection and deployment."""
import ctypes as C
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, Mock
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import monitors as m
spec = importlib.util.spec_from_file_location('deploy', ROOT / 'installer/deploy.py')
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class MonitorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.sysfs = self.root / 'drm'; self.sysfs.mkdir()

    def connector(self, name, modes='1920x1080\n1280x720\n', status='connected'):
        path = self.sysfs / name; path.mkdir()
        (path / 'status').write_text(status)
        (path / 'modes').write_text(modes)
        (path / 'connector_id').write_text('42')
        return path

    def test_native_resolution_then_fastest_refresh(self):
        modes = [m.Mode(1920, 1080, 60, True), m.Mode(1920, 1080, 165.002),
                 m.Mode(1280, 720, 240), m.Mode(3840, 2160, 30)]
        self.assertEqual(m.choose_mode(modes), modes[1])
        text = m.render([('DP-1', modes[1]), ('HDMI-A-1', m.Mode(1920, 1080, 59.94))])
        self.assertIn('refresh:165.002000,x:0,y:0', text)
        self.assertIn('refresh:59.940000,x:1920,y:0', text)
        self.assertNotIn('custom:', text)

    def test_tty_sysfs_fallback_connected_only_laptop_first(self):
        self.connector('card1-HDMI-A-2', '2560x1440\n1920x1080\n')
        self.connector('card0-eDP-1')
        self.connector('card0-DP-1', status='disconnected')
        self.connector('card0-DP-2', modes='garbage\n')
        with patch.object(m, 'driver_modes', return_value=[]):
            outputs = m.detect(self.sysfs)
        self.assertEqual([o[0] for o in outputs], ['eDP-1', 'HDMI-A-2'])
        text = m.render(outputs)
        self.assertNotIn(',refresh:', text)
        self.assertIn('name:^HDMI-A-2$,x:1920,y:0', text)

    def test_multi_gpu_ambiguous_names_not_guessed(self):
        self.connector('card0-DP-1'); self.connector('card1-DP-1')
        self.connector('card1-eDP-1')
        with patch.object(m, 'driver_modes', return_value=[]):
            self.assertEqual([o[0] for o in m.detect(self.sysfs)], ['eDP-1'])

    def test_missing_gpu_and_atomic_repeat(self):
        self.assertEqual(m.detect(self.sysfs), [])
        path = self.root / 'monitor.conf'
        m.configure(path, [])
        before = path.stat().st_mtime_ns
        m.configure(path, [])
        self.assertEqual(before, path.stat().st_mtime_ns)
        self.assertNotIn('monitor_rule=', path.read_text())

    def test_output_refuses_manual_file_and_parent_symlink(self):
        import subprocess
        path = self.root / 'manual.conf'
        path.write_text('monitor_rule=name:^DP-9$,x:100,y:0\n')
        before = path.read_bytes()
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/monitors.py'), '--output', str(path)],
                                capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(path.read_bytes(), before)
        (self.root / 'link').symlink_to(self.sysfs)
        with self.assertRaises(RuntimeError):
            m.configure(self.root / 'link/new/monitor.conf', [])
        self.assertFalse((self.sysfs / 'new').exists())

    def test_driver_query_fractional_refresh_filters_and_releases(self):
        path = self.connector('card0-DP-1')
        modes = (m.ModeInfo * 3)()
        for mode in modes:
            mode.hdisplay = 1920; mode.vdisplay = 1080
            mode.htotal = 2200; mode.vtotal = 1125; mode.clock = 148352
        modes[0].type = 1 << 3
        modes[1].flags = 1 << 4
        modes[2].flags = 1 << 5
        conn = m.Connector(); conn.connection = 1; conn.count_modes = 3; conn.modes = modes
        lib = Mock(); lib.drmModeGetConnectorCurrent.return_value = C.pointer(conn)
        with patch.object(m.C, 'CDLL', return_value=lib), patch.object(m.os, 'open', return_value=9), patch.object(m.os, 'close') as close:
            result = m.driver_modes(path, Path('/dev/dri/card0'))
        self.assertEqual(len(result), 1)
        self.assertAlmostEqual(result[0].refresh, 59.940202, places=5)
        self.assertTrue(result[0].preferred)
        lib.drmModeFreeConnector.assert_called_once()
        close.assert_called_once_with(9)

    def test_permission_denied_falls_back(self):
        path = self.connector('card0-DP-1')
        with patch.object(m.C, 'CDLL', return_value=Mock()), patch.object(m.os, 'open', side_effect=PermissionError):
            self.assertEqual(m.driver_modes(path, Path('/dev/dri/card0')), [])

    def test_default_pair_recognized_but_custom_layout_not(self):
        text = '\n'.join(sorted(m.LEGACY_RULES))
        self.assertTrue(m.legacy_defaults(text))
        self.assertFalse(m.legacy_defaults(text.replace('165.001999', '144')))
        self.assertFalse(m.legacy_defaults(text + '\nmonitor_rule=name:^eDP-1$,x:0,y:0'))

    def stage(self, home, target, config_only=True):
        with patch.object(deploy, 'HOME', home), patch.object(deploy, 'CONFIG', home / '.config'), patch.object(deploy, 'MANGO', home / '.config/mango'), patch.object(m, 'detect', return_value=[('eDP-1', m.Mode(1920, 1080, 60))]):
            deploy.stage(target, config_only=config_only)

    def test_full_and_config_only_migrate_legacy_and_keep_personal(self):
        for config_only in (False, True):
            home = self.root / str(config_only); home.mkdir()
            mango = home / '.config/mango'; mango.mkdir(parents=True)
            (mango / 'monitor.conf').write_text('\n'.join(m.LEGACY_RULES))
            (mango / 'local').mkdir()
            (mango / 'local/monitor.conf').write_text('\n'.join(m.LEGACY_RULES))
            target = self.root / ('stage-' + str(config_only))
            self.stage(home, target, config_only)
            self.assertNotIn('DP-1', (target / 'local/monitor.conf').read_text())
            self.assertIn('name:^eDP-1$', (target / 'monitor.conf').read_text())
            custom = 'monitor_rule=name:^DP-9$,width:2560,height:1440,x:0,y:0\n'
            (mango / 'local/monitor.conf').write_text(custom)
            self.stage(home, target, config_only)
            self.assertEqual((target / 'local/monitor.conf').read_text(), custom)
            conf = (target / 'config.conf').read_text()
            self.assertLess(conf.index('source=./local/monitor.conf'), conf.index('source=./monitor.conf'))

    def test_cursor_fallback_and_preserve_installed_cursor(self):
        home = self.root / 'home'; home.mkdir()
        mango = home / '.config/mango'; mango.mkdir(parents=True)
        (mango / 'config.conf').write_text('cursor_theme=My Cursor\n')
        (mango / 'env.conf').write_text('env=XCURSOR_THEME,My Cursor\n')
        target = self.root / 'stage'
        self.stage(home, target)
        self.assertIn('cursor_theme=Animated-Mew-Cursor', (target / 'config.conf').read_text())
        self.assertIn('env=XCURSOR_THEME,Animated-Mew-Cursor', (target / 'env.conf').read_text())
        (home / '.local/share/icons/My Cursor/cursors').mkdir(parents=True)
        self.stage(home, target)
        self.assertIn('cursor_theme=My Cursor', (target / 'config.conf').read_text())
        self.assertIn('export XCURSOR_THEME="My Cursor"', (target / 'autostart.sh').read_text())

    def test_cursor_metadata_is_valid_ini(self):
        import configparser
        for name in ('index.theme', 'cursor.theme'):
            ini = configparser.ConfigParser()
            ini.read(ROOT / 'themes/Animated-Mew-Cursor' / name)
            self.assertEqual(ini['Icon Theme']['Name'], 'Animated Mew Cursor')


if __name__ == '__main__':
    unittest.main()
