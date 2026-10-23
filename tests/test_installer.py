"""Regression tests: isolated HOME, mocked applications, no package installs."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
INSTALL = '\n'.join((ROOT / 'installer' / name).read_text() for name in ('full.sh', 'packages.sh', 'desktop.sh'))


def section(start, end):
    return INSTALL.split(start, 1)[1].split(end, 1)[0]


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='victoria test ')
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin',
                        XDG_CACHE_HOME=str(self.home / 'cache'), XDG_RUNTIME_DIR=str(self.home / 'runtime'))
        (self.home / 'runtime').mkdir()

    def mock(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/bash\n' + body + '\n')
        path.chmod(0o755)

    def run_bash(self, script, data='', check=True):
        return subprocess.run(['/bin/bash', '-euc', script], input=data, text=True,
                              env=self.env, capture_output=True, check=check, timeout=15)

    def test_dry_run_and_help_never_execute_mutating_commands(self):
        for cmd in ('sudo', 'pacman', 'git', 'mkdir', 'mv', 'cp', 'rm', 'curl', 'timeout', 'tput'):
            self.mock(cmd, 'echo called >> "$HOME/unexpected-command"; exit 99')
        before = sorted(str(p.relative_to(self.home)) for p in self.home.rglob('*'))
        for arg in ('--dry-run', '--help'):
            r = subprocess.run(['/bin/bash', str(ROOT / 'install.sh'), arg], env=self.env,
                               text=True, capture_output=True, timeout=5)
            self.assertEqual(r.returncode, 0, r.stderr)
        after = sorted(str(p.relative_to(self.home)) for p in self.home.rglob('*'))
        self.assertEqual(before, after)

    def test_unknown_argument_fails(self):
        r = self.run_bash(f'bash "{ROOT}/install.sh" --unknown', check=False)
        self.assertEqual(r.returncode, 2)

    def test_all_browser_and_app_choices(self):
        choices = section('# Application choices are stored separately from autostart commands.', '# Back up every user')
        functions = 'confirm() { local a; read -r a || return 1; [[ "$a" == y ]]; }; warn() { :; }; err() { :; };\n'
        for number, command in ((1, 'helium-browser'), (2, 'firefox'), (3, 'brave'), (4, '')):
            for discord in (0, 1):
                for spotify in (0, 1):
                    answers = ['y' if discord else 'n', 'y' if spotify else 'n', str(number)]
                    answers += ['n'] * (discord + spotify + bool(command))
                    result = self.run_bash(functions + choices + '\nprintf "RESULT:%s,%s,%s,%s,%s,%s" "$INSTALL_DISCORD" "$INSTALL_SPOTIFY" "$BROWSER_COMMAND" "$START_DISCORD" "$START_SPOTIFY" "$START_BROWSER"', '\n'.join(answers) + '\n')
                    self.assertIn(f'RESULT:{discord},{spotify},{command},0,0,0', result.stdout)

    def test_backup_preserves_existing_files_and_symlinks(self):
        kitty = self.home / '.config/kitty'
        kitty.mkdir(parents=True)
        (kitty / 'kitty.conf').write_text('my settings')
        (kitty / 'link').symlink_to('kitty.conf')
        block = section('# Back up every user', '# ---------- where are the dotfiles')
        # The marker splits a prose comment, so resume at the first statement.
        block = block[block.index('BACKUP_DIR='):]
        result = self.run_bash('info() { :; };\n' + block + '\nprintf "%s" "$BACKUP_DIR"')
        backup = Path(result.stdout)
        self.assertEqual((backup / '.config/kitty/kitty.conf').read_text(), 'my settings')
        self.assertTrue((backup / '.config/kitty/link').is_symlink())
        self.assertEqual((kitty / 'kitty.conf').read_text(), 'my settings')

    def test_qt_theme_and_repeated_app_configuration(self):
        config = self.home / '.config/mango'
        config.mkdir(parents=True)
        for filename in ('env.conf', 'autostart.sh', 'bind.conf'):
            (config / filename).write_text((ROOT / 'config/mango' / filename).read_text())
        self.mock('gsettings', 'exit 0')
        self.mock('xdg-settings', 'exit 0')
        backup = self.home / 'backup'; backup.mkdir()
        block = '# Qt widgets' + section('# Qt widgets', '# ---------- fastfetch')
        prefix = f'CONFIG_DIR="$HOME/.config/mango"; AUTOSTART="$CONFIG_DIR/autostart.sh"; BACKUP_DIR="$HOME/backup"; warn() {{ :; }}; info() {{ :; }};\n'
        for browser, discord, spotify in [('firefox', 1, 1), ('', 0, 0), ('brave', 1, 0)]:
            values = f'BROWSER_COMMAND={browser}; BROWSER_DESKTOP=""; INSTALL_DISCORD={discord}; INSTALL_SPOTIFY={spotify}; START_DISCORD=0; START_SPOTIFY=0; START_BROWSER=0;\n'
            self.run_bash(prefix + values + block)
            binds = (config / 'bind.conf').read_text()
            self.assertEqual(binds.count('bind=SUPER,w,spawn,'), int(bool(browser)))
            self.assertEqual(binds.count('bind=SUPER,a,spawn,'), discord)
            self.assertEqual(binds.count('bind=SUPER,s,spawn,'), spotify)
            self.assertEqual((config / 'env.conf').read_text().count('env=QT_STYLE_OVERRIDE,kvantum'), 1)
        self.assertIn('theme=MateriaDark', (self.home / '.config/Kvantum/kvantum.kvconfig').read_text())

    def test_waybar_retries_failure_and_cleans_runtime_config(self):
        config = self.home / '.config/mango/waybar'
        config.mkdir(parents=True)
        (config / 'config.jsonc').write_text('{}')
        (config / 'style.css').write_text('')
        self.mock('waybar', 'echo call >> "$HOME/calls"; exit 1')
        self.mock('sleep', ':')
        r = subprocess.run(['bash', str(ROOT / 'scripts/waybar-launch.sh')], env=self.env, capture_output=True, timeout=5)
        self.assertEqual(r.returncode, 1)
        self.assertEqual(len((self.home / 'calls').read_text().splitlines()), 5)
        self.assertEqual(list((self.home / 'runtime/victoria-waybar').glob('config.*')), [])

    def test_waybar_does_not_retry_clean_exit(self):
        config = self.home / '.config/mango/waybar'; config.mkdir(parents=True)
        (config / 'config.jsonc').write_text('{}'); (config / 'style.css').write_text('')
        self.mock('waybar', 'echo call >> "$HOME/calls"; exit 0')
        self.run_bash(f'bash "{ROOT}/scripts/waybar-launch.sh"')
        self.assertEqual((self.home / 'calls').read_text().splitlines(), ['call'])

    def test_explicit_autostart_choices(self):
        choices = section('# Application choices are stored separately from autostart commands.', '# Back up every user')
        functions = 'confirm() { local a; read -r a || return 1; [[ "$a" == y ]]; }; warn() { :; }; err() { :; };\n'
        result = self.run_bash(functions + choices + '\nprintf "START:%s,%s,%s" "$START_DISCORD" "$START_SPOTIFY" "$START_BROWSER"', 'y\ny\n2\ny\ny\ny\n')
        self.assertIn('START:1,1,1', result.stdout)

    def test_existing_waybar_lock_requests_reload_without_new_process(self):
        import fcntl
        state = self.home / 'runtime/victoria-waybar'
        state.mkdir()
        self.mock('waybar', 'echo unexpected > "$HOME/new-waybar"')
        self.mock('pkill', 'printf "%s " "$@" > "$HOME/reload"')
        with (state / 'launcher.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.run_bash(f'bash "{ROOT}/scripts/waybar-launch.sh"')
        self.assertFalse((self.home / 'new-waybar').exists())
        self.assertIn('-USR2', (self.home / 'reload').read_text())

    def test_shell_syntax(self):
        for script in ROOT.rglob('*.sh'):
            subprocess.run(['bash', '-n', str(script)], check=True, capture_output=True)
        subprocess.run(['sh', '-n', str(ROOT / 'config/mango/autostart.sh')], check=True)


if __name__ == '__main__':
    unittest.main(verbosity=2)
