import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))

def module(name,filename):
    spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/filename)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

class SessionTests(unittest.TestCase):
    def setUp(self):
        self.session=module('session','session-controls.py')
        self.menu=module('control_center','control-center.py')
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.home=Path(self.temp.name)

    def test_nmcli_escaped_ssid_and_bssid(self):
        fields=self.menu.nm_fields(r'AA\:BB\:CC\:DD\:EE\:FF:My\:WiFi:91:WPA2:wlan0')
        self.assertEqual(fields,['AA:BB:CC:DD:EE:FF','My:WiFi','91','WPA2','wlan0'])

    def test_menu_rejects_free_text_and_cancel(self):
        with patch.object(self.menu.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'untrusted\n','')):
            self.assertIsNone(self.menu.choose('Test',[('safe','value')]))
        with patch.object(self.menu.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'0\n','')):
            self.assertEqual(self.menu.choose('Test',[('safe','value')]),'value')

    def test_idle_off_by_default_and_order_validation(self):
        self.assertNotIn('timeout', self.session.idle_command({}))
        self.assertIn('before-sleep', self.session.idle_command({}))
        args=self.session.idle_command({'idle_enabled':True,'idle_lock_minutes':5,'idle_screen_minutes':10,'idle_suspend_minutes':0})
        self.assertIn('300',args);self.assertIn('600',args)
        self.assertFalse(any(value.endswith(' suspend') for value in args))
        self.assertIn('before-sleep',args)
        with self.assertRaises(ValueError):self.session.idle_command({'idle_enabled':True,'idle_lock_minutes':10,'idle_screen_minutes':5})

    def test_performance_overlay_preserves_user_preferences(self):
        mango=self.home/'mango';local=mango/'local';local.mkdir(parents=True)
        (mango/'config.conf').write_text('source=./local/custom.conf\n')
        original='animations=1\nblur=1\ngap_inner_horizontal=11\n'
        (local/'custom.conf').write_text(original)
        with patch.object(self.session,'MANGO',mango),patch.object(self.session,'LOCAL',local),patch.object(self.session,'check_mango'),patch.object(self.session.shutil,'which',return_value=None):
            self.assertTrue(self.session.performance())
            self.assertIn('blur=0',(local/'performance.conf').read_text())
            self.assertFalse(self.session.performance())
            self.assertNotIn('blur=0',(local/'performance.conf').read_text())
        self.assertEqual((local/'custom.conf').read_text(),original)
        self.assertEqual((mango/'config.conf').read_text().count('source=./local/performance.conf'),1)

    def test_screen_power_is_not_changed_when_lock_fails(self):
        with patch.object(self.session,'lock_screen',side_effect=RuntimeError('Lock failed')),patch.object(self.session,'command') as command:
            with self.assertRaises(RuntimeError):self.session.screens(False)
            command.assert_not_called()

    def test_screen_resume_uses_saved_names_when_outputs_are_hidden(self):
        runtime=self.home/'runtime';runtime.mkdir()
        (runtime/'screens.json').write_text(json.dumps(['DP-1','HDMI-A-1']))
        with patch.object(self.session,'RUNTIME',runtime),patch.object(self.session,'monitor_names',return_value=[]) as query,patch.object(self.session,'set_screens') as power:
            self.session.screen_resume()
            query.assert_not_called()
            power.assert_called_once_with(True,['DP-1','HDMI-A-1'])
            self.assertTrue((runtime/'screen-resumed').exists())

    def test_screen_off_refuses_without_active_resume_watcher(self):
        runtime=self.home/'runtime';runtime.mkdir()
        with patch.object(self.session,'RUNTIME',runtime),patch.object(self.session,'set_screens') as power:
            with self.assertRaises(RuntimeError):self.session.screen_off_ready()
            power.assert_not_called()

    def test_performance_explicit_state_is_idempotent(self):
        mango=self.home/'mango';local=mango/'local';local.mkdir(parents=True)
        (mango/'config.conf').write_text('')
        with patch.object(self.session,'MANGO',mango),patch.object(self.session,'LOCAL',local),patch.object(self.session,'check_mango'),patch.object(self.session.shutil,'which',return_value=None):
            self.session.performance(True);self.session.performance(True)
            self.assertTrue(self.session.performance_enabled())
            self.session.performance(False);self.session.performance(False)
            self.assertFalse(self.session.performance_enabled())

    def test_screen_watcher_recovers_when_idle_process_exits(self):
        runtime=self.home/'runtime';runtime.mkdir()
        from unittest.mock import MagicMock
        child=MagicMock();child.poll.return_value=1
        with patch.object(self.session,'RUNTIME',runtime),patch.object(self.session,'monitor_names',return_value=['DP-1']),patch.object(self.session.subprocess,'Popen',return_value=child),patch.object(self.session,'set_screens') as power:
            self.session.screen_watch()
            power.assert_called_once_with(True,['DP-1'])
            self.assertFalse((runtime/'screens.json').exists())

    def test_theme_extensions_are_idempotent_and_keep_custom_css(self):
        extras=module('extras','theme_extras.py')
        config=self.home/'.config';vencord=config/'Vencord/settings';vencord.mkdir(parents=True)
        (vencord/'quickCss.css').write_text('/* my custom CSS */\n')
        colors={'background':'#121212','foreground':'#eeeeee',**{f'color{i}':'#aa7788' for i in range(16)}}
        with patch.object(extras,'HOME',self.home),patch.object(extras,'CONFIG',config),patch.object(extras,'STATE',self.home/'backups'):
            extras.apply(colors);colors['color5']='#abcdef';extras.apply(colors)
        css=(vencord/'quickCss.css').read_text()
        self.assertIn('my custom CSS',css);self.assertIn('#abcdef',css)
        self.assertEqual(css.count('BEGIN VICTORIA PALETTE'),1)
        self.assertEqual((config/'kitty/kitty.conf').read_text().count('include victoria-colors.conf'),1)
        self.assertIn('#abcdef',(config/'gtk-4.0/gtk.css').read_text())
        self.assertTrue((self.home/'backups/.config/Vencord/settings/quickCss.css').exists())

if __name__=='__main__':unittest.main()
