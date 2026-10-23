"""Exercise real deployment twice in an isolated HOME; forbid system commands."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='victoria deploy ')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / 'bin'; self.bin.mkdir()
        for name in ('sudo', 'pacman', 'systemctl', 'loginctl', 'git'):
            script = self.bin / name
            script.write_text('#!/bin/sh\necho forbidden >> "$HOME/forbidden"; exit 99\n')
            script.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin',
                        XDG_CACHE_HOME=str(self.home / 'cache'), XDG_STATE_HOME=str(self.home / 'state'))
        # Keep this deployment test offline even on CI machines with real Wallust.
        script = self.bin / 'wallust'
        script.write_text('#!/bin/sh\nexit 0\n'); script.chmod(0o755)

    def run_install(self, *args):
        return subprocess.run(['bash', str(ROOT / 'install.sh'), *args], env=self.env,
                              text=True, capture_output=True, timeout=30)

    def test_deployment_preserves_preferences_and_backup(self):
        # Mock Wallust delegates rendering to the already tested deterministic fixture.
        from test_theme import ThemeTests
        theme = ThemeTests(); theme.setUp(); self.addCleanup(theme.doCleanups)
        (self.bin / 'wallust').write_text((theme.bin / 'wallust').read_text())
        mango = self.home / '.config/mango'; mango.mkdir(parents=True)
        (mango / 'config.conf').write_text('xkb_rules_layout=br\nxkb_rules_variant=\n')
        (mango / 'monitor.conf').write_text('monitorrule=DP-9,1920x1080@60,0.0,1\n')
        (mango / 'apps.conf').write_text('START_BROWSER=1\n')
        (mango / 'bind.conf').write_text('# personal bindings\n')
        (mango / 'waybar').mkdir()
        (mango / 'waybar/config.jsonc').write_text('{"power":"loginctl poweroff","script":"WaybarCava.sh"}')
        for _ in range(2):
            result = self.run_install('--config-only')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('xkb_rules_layout=br', (mango / 'local/input.conf').read_text())
            self.assertIn('DP-9', (mango / 'local/monitor.conf').read_text())
            self.assertEqual((mango / 'apps.conf').read_text(), 'START_BROWSER=1\n')
            self.assertEqual((mango / 'bind.conf').read_text(), '# personal bindings\n')
            self.assertIn('loginctl poweroff', (mango / 'waybar/config.jsonc').read_text())
            self.assertIn('waybar-cava.sh', (mango / 'waybar/config.jsonc').read_text())
            (mango / 'local/custom.conf').write_text('gap_outer_horizontal=17\n')
        self.assertEqual((mango / 'local/custom.conf').read_text(), 'gap_outer_horizontal=17\n')
        backups = list(self.home.glob('victoria-backup.*'))
        self.assertEqual(len(backups), 2)
        self.assertTrue(any((b / '.config/mango/config.conf').read_text().startswith('xkb_rules_layout=br') for b in backups))
        self.assertFalse((self.home / 'forbidden').exists())
        self.assertFalse((mango / 'tests').exists())
        self.assertFalse((mango / '.git').exists())
        self.assertTrue((mango / 'config/terminal_configs/img_terminal/example.png').is_file())
        self.assertTrue((mango / 'scripts/waybar-cava.sh').stat().st_mode & 0o100)

    def test_dry_run_and_diagnostic_are_read_only(self):
        before = sorted(str(p.relative_to(self.home)) for p in self.home.rglob('*'))
        for args in [('--config-only', '--dry-run'), ('--diagnose', '--dry-run'), ('--diagnose',)]:
            result = self.run_install(*args)
            self.assertIn(result.returncode, (0, 1), result.stderr)
        self.assertEqual(before, sorted(str(p.relative_to(self.home)) for p in self.home.rglob('*')))
