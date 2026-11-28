"""Behavioral checks for controls, rollback, focus state and portable configuration."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import victoria_settings as settings
import bar_config


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name); self.mango = self.home / '.config/mango'; self.local = self.mango / 'local'
        self.local.mkdir(parents=True)
        self.state = self.home / 'state'
        for key, value in [('HOME', self.home), ('MANGO', self.mango), ('LOCAL', self.local), ('STATE', self.state)]:
            p = patch.object(settings, key, value); p.start(); self.addCleanup(p.stop)

    def test_saved_blur_is_disabled_for_screencast_compatibility(self):
        (self.local / 'settings.json').write_text(json.dumps({'blur': True}))
        (self.local / 'custom.conf').write_text('blur=1\nblur_layer=1\n')
        self.assertFalse(settings.read_settings()['blur'])
        self.assertFalse(settings.validate_settings(dict(settings.DEFAULTS, blur=True))['blur'])

    def test_profile_validation_and_invalid_color(self):
        for profile in settings.PROFILES.values():
            data = dict(settings.DEFAULTS, **profile)
            self.assertEqual(settings.validate_settings(data), data)
        with self.assertRaises(ValueError): settings.validate_settings(dict(settings.DEFAULTS, accent='red; shell'))
        with self.assertRaises(ValueError): settings.validate_settings(dict(settings.DEFAULTS, opacity=2))

    def test_invalid_compositor_change_restores_personal_settings(self):
        p = self.local / 'custom.conf'; p.write_text('blur_optimized=0\n# keep me\n')
        with patch.object(settings, 'check_mango', side_effect=RuntimeError('invalid')), patch.object(settings, 'reload_ui'):
            with self.assertRaises(RuntimeError): settings.save_appearance(settings.DEFAULTS)
        self.assertEqual(p.read_text(), 'blur_optimized=0\n# keep me\n')
        self.assertFalse((self.local / 'settings.json').exists())

    def test_managed_settings_do_not_duplicate_or_erase_personal_text(self):
        a = settings.managed('blur_optimized=0\n', 'border_px=3')
        b = settings.managed(a, 'border_px=5')
        self.assertIn('blur_optimized=0', b)
        self.assertNotIn('border_px=3', b)
        self.assertEqual(b.count(settings.BEGIN), 1)

    def test_shortcuts_follow_sources_and_ignore_comments_and_cycles(self):
        (self.mango / 'config.conf').write_text('source=./bind.conf\nsource=./local/custom.conf\n')
        (self.mango / 'bind.conf').write_text('# bind=SUPER,x,quit\nbind=SUPER,q,killclient,\nsource=./config.conf\n')
        (self.local / 'custom.conf').write_text('bind=SUPER,comma,spawn,python3 panel.py\n')
        rows = settings.shortcuts()
        self.assertEqual(len(rows), 2)
        self.assertTrue(any('panel.py' in row[1] for row in rows))

    def _focus_twice(self, quickshell):
        calls = []
        def command(args, **kwargs):
            calls.append(args)
            return subprocess.CompletedProcess(args, 0, stdout='true\n', stderr='')
        which = (lambda name: '/usr/bin/' + name) if quickshell else (lambda name: None if name == 'quickshell' else '/usr/bin/' + name)
        with patch.object(settings, 'command', side_effect=command), patch.object(settings, 'refresh_bar_config'), \
                patch.object(settings.shutil, 'which', side_effect=which):
            self.assertTrue(settings.focus())
            self.assertTrue(json.loads((self.state / 'focus.json').read_text())['previous_dnd'])
            self.assertFalse(settings.focus())
        return calls

    def test_focus_restores_previous_dnd_and_preserves_base_bar(self):
        # Waybar setups: swaync owns notifications.
        calls = self._focus_twice(quickshell=False)
        self.assertEqual(sum('-dn' in call for call in calls), 2)
        self.assertFalse(any('-df' in call for call in calls))

    def test_focus_uses_quickshell_dnd_when_the_bar_is_quickshell(self):
        calls = self._focus_twice(quickshell=True)
        ipc = [call for call in calls if call[:2] == ['quickshell', 'ipc']]
        self.assertEqual([call[-2:] for call in ipc if call[-2] == 'dnd'], [['dnd', 'true'], ['dnd', 'true']])
        self.assertFalse(any('swaync-client' in call for call in calls))

    def test_jsonc_comments_and_focus_filter_do_not_touch_actions(self):
        text = '''{ // personal bar
          "modules-right": ["cpu", "clock", "battery",],
          "clock": {"on-click": "echo https://example.org",},
        }'''
        focused = json.loads(bar_config.build(text, focus=True))
        normal = json.loads(bar_config.build(text))
        self.assertEqual(normal['modules-right'], ['cpu', 'clock', 'battery', 'custom/victoria-settings', 'custom/control-center'])
        self.assertEqual(focused['modules-right'], ['custom/focus', 'clock', 'battery', 'custom/victoria-settings', 'custom/control-center'])
        self.assertEqual(focused['clock']['on-click'], 'echo https://example.org')

    def test_cpu_sensor_ignores_wifi_and_prefers_package_over_core(self):
        root = self.home / 'hwmon'
        for directory, name, values in [('hwmon0','iwlwifi_1',{'temp1_input':'0'}),
                ('hwmon8','coretemp',{'temp1_input':'43000','temp1_label':'Core 0',
                                     'temp2_input':'47000','temp2_label':'Package id 0'})]:
            p = root / directory; p.mkdir(parents=True)
            (p / 'name').write_text(name)
            for key, value in values.items(): (p / key).write_text(value)
        self.assertEqual(bar_config.temperature_sensor(root), str(root / 'hwmon8/temp2_input'))
        (root / 'hwmon8').rename(root / 'hwmon2')
        self.assertEqual(bar_config.temperature_sensor(root), str(root / 'hwmon2/temp2_input'))

    def test_cpu_sensor_missing_or_unreadable_is_not_zero(self):
        root = self.home / 'hwmon'; root.mkdir()
        p = root / 'hwmon1'; p.mkdir(); (p / 'name').write_text('coretemp')
        (p / 'temp1_input').write_text('not available')
        self.assertIsNone(bar_config.temperature_sensor(root))
        (p / 'temp1_input').write_text('0')
        self.assertIsNone(bar_config.temperature_sensor(root))

    def test_bar_preferences_are_reversible_without_erasing_modules(self):
        source = json.dumps({'modules-left':['cpu','memory'], 'modules-center':['tray'],
                             'modules-right':['temperature','mpris','clock','custom/power'],
                             'clock':{'on-click-right':'calendar.sh'}})
        prefs = {'show_stats':False,'show_media':False,'show_tray':False,
                 'clock_seconds':False,'clock_24h':False,'bar_margin':8}
        modified = json.loads(bar_config.build(source, preferences=prefs))
        self.assertNotIn('cpu', modified['modules-left'])
        self.assertNotIn('mpris', modified['modules-right'])
        self.assertEqual(modified['clock']['format'], '󰥔 {:%I:%M %p}')
        self.assertEqual(modified['clock']['on-click-right'], 'calendar.sh')
        self.assertEqual(modified['margin-top'], 8)
        restored = json.loads(bar_config.build(source))
        self.assertIn('mpris', restored['modules-right'])
        self.assertIn('cpu', restored['modules-left'])

    def test_expanded_settings_save_preserves_notification_and_local_preferences(self):
        (self.local/'custom.conf').write_text('blur_optimized=0\n')
        (self.mango/'waybar').mkdir()
        (self.mango/'waybar/config.jsonc').write_text('{"position":"top","modules-right":["clock"]}')
        (self.mango/'env.conf').write_text('env=XCURSOR_SIZE,24\nenv=LANGUAGE,en\n')
        (self.mango/'autostart.sh').write_text('#!/bin/sh\nexport XCURSOR_SIZE=24\n')
        nc = self.home/'.config/swaync/config.json'; nc.parent.mkdir()
        nc.write_text(json.dumps({'timeout-critical':0,'widgets':['title','notifications'],'positionX':'right'}))
        values = dict(settings.DEFAULTS, notification_position='bottom-left',notification_timeout=12,
                      notification_images=False,cursor_size=40,natural_scroll=True,animation_speed='fast')
        with patch.object(settings,'check_mango'), patch.object(settings,'reload_ui'), patch.dict(os.environ,{'WAYLAND_DISPLAY':''}):
            settings.save_appearance(values)
        actual = json.loads(nc.read_text())
        self.assertEqual(actual['timeout-critical'],0)
        self.assertEqual(actual['widgets'],['title','notifications'])
        self.assertEqual(actual['positionX'],'left')
        self.assertEqual(actual['positionY'],'bottom')
        self.assertEqual(actual['timeout'],12)
        self.assertEqual(actual['image-visibility'],'never')
        self.assertIn('blur_optimized=0',(self.local/'custom.conf').read_text())
        self.assertIn('animation_duration_open=210',(self.local/'custom.conf').read_text())
        self.assertIn('env=XCURSOR_SIZE,40',(self.mango/'env.conf').read_text())
        self.assertIn('env=LANGUAGE,en',(self.mango/'env.conf').read_text())
        self.assertEqual(settings.read_settings(),values)

    def test_monitor_positions_respect_scale(self):
        from monitors import Mode
        rules = settings.display_rules(2, [('DP-1', Mode(1920,1080,60)), ('HDMI-A-1', Mode(1600,900,60))])
        self.assertIn('x:960,y:0,scale:2', rules)
        with self.assertRaises(RuntimeError): settings.display_rules(1, [])

    def test_calendar_english_leap_year(self):
        import datetime
        spec = importlib.util.spec_from_file_location('cal', ROOT / 'scripts/notification-calendar.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        text = module.render(2024, 2, datetime.date(2024,2,29))
        self.assertIn('[29]', text); self.assertIn('MON TUE', text)

if __name__ == '__main__': unittest.main()


class KeyboardTests(unittest.TestCase):
    """Setup wizard keyboard rules: Mango rejects empty values, so they must never be written."""

    def test_single_layout_without_variant_writes_no_empty_lines(self):
        rules = settings.keyboard_rules('English (US)')
        self.assertEqual(rules, 'xkb_rules_layout=us')
        self.assertNotRegex(rules, r'=\s*$')

    def test_second_layout_and_switch_shortcut(self):
        rules = settings.keyboard_rules('Portuguese (Brazil, ABNT2)', 'English (US, international)', 'Super + Space')
        self.assertEqual(rules.splitlines(), ['xkb_rules_layout=br,us', 'xkb_rules_variant=,intl', 'xkb_rules_options=grp:win_space_toggle'])

    def test_old_names_and_duplicate_secondary(self):
        self.assertEqual(settings.keyboard_rules('US international'), 'xkb_rules_layout=us\nxkb_rules_variant=intl')
        self.assertEqual(settings.keyboard_rules('English (US)', 'English (US)'), 'xkb_rules_layout=us')

    def test_unknown_layout_is_rejected(self):
        with self.assertRaises(ValueError): settings.keyboard_rules('Klingon')
        with self.assertRaises(ValueError): settings.keyboard_rules('English (US)', 'None', 'Shift + F12')

    def test_every_offered_layout_is_a_real_xkb_layout(self):
        rules = Path('/usr/share/X11/xkb/rules/evdev.lst')
        if not rules.is_file():
            self.skipTest('xkeyboard-config is not installed')
        text = rules.read_text()
        for name, (layout, variant) in settings.KEYBOARDS.items():
            pattern = rf'^\s+{variant}\s+{layout}:' if variant else rf'^\s+{layout}\s'
            with self.subTest(name=name):
                self.assertRegex(text, '(?m)' + pattern)
