#!/usr/bin/env python3
"""Install discoverable desktop controls and unoccupied default shortcuts."""
import sys
sys.dont_write_bytecode = True
from pathlib import Path
import re
from victoria_settings import atomic, MANGO, HOME, read_settings, save_appearance


def install():
    script = str(MANGO / 'scripts/victoria-controls.py')
    # Desktop Exec quoting is not shell quoting.
    quoted = '"' + script.replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$') + '"'
    for suffix, name, arg in [('', 'Victoria Settings', ''), ('-shortcuts', 'Victoria Shortcuts', ' --shortcuts')]:
        atomic(HOME / f'.local/share/applications/victoria{suffix}.desktop',
               '[Desktop Entry]\nType=Application\nName=' + name + '\nComment=Personalize your Victoria desktop\n'
               'Exec=python3 ' + quoted + arg + '\nIcon=preferences-desktop\nTerminal=false\nCategories=Settings;DesktopSettings;\n')
    p = MANGO / 'bind.conf'
    if p.exists():
        text = p.read_text()
        text = re.sub(r'^bind=SUPER,v,spawn_shell,cliphist list[^\n]*$', 'bind=SUPER,v,spawn,python3 ~/.config/mango/scripts/clipboard-picker.py', text, flags=re.M)
        for modifiers, key, arg in [('SUPER', 'slash', '--shortcuts'), ('SUPER', 'comma', ''), ('SUPER+SHIFT', 'f', '--focus')]:
            if not re.search(r'^bind\s*=\s*' + re.escape(modifiers) + r'\s*,\s*' + key + r'\s*,', text, re.M):
                text += f'\nbind={modifiers},{key},spawn,python3 ~/.config/mango/scripts/victoria-controls.py {arg}\n'
        atomic(p, text)
    p = MANGO / 'rule.conf'
    if p.exists():
        text = p.read_text()
        if 'app_id:^io[.]victoria[.]Settings$' not in text:
            text += '\n# Keep desktop settings floating, with room for its controls.\nwindow_rule=is_floating:1,width:0.65,height:0.80,app_id:^io[.]victoria[.]Settings$\n'
            atomic(p, text)
    p = MANGO / 'rule.conf'
    text = p.read_text()
    if 'app_id:^io[.]victoria[.]Mixer' not in text:
        atomic(p,text+'\nwindow_rule=is_floating:1,app_id:^io[.]victoria[.]Mixer.*$\n')
    p = MANGO / 'rule.conf'
    text = p.read_text()
    for rule in ['layer_rule=animation_type_open:slide,animation_type_close:fade,layer_name:victoria-mixer','window_rule=is_floating:1,app_id:^io[.]victoria[.]Wifi$']:
        if rule not in text:text+='\n'+rule+'\n'
    atomic(p,text)
    p = MANGO / 'bind.conf'
    text = p.read_text()
    for modifiers, key, script_name, action in [('SUPER','c','control-center.py',''), ('SUPER','l','session-controls.py','lock'), ('SUPER+SHIFT','p','session-controls.py','performance')]:
        if not re.search(r'^bind\s*=\s*' + re.escape(modifiers) + r'\s*,\s*' + key + r'\s*,', text, re.M):
            text += f'\nbind={modifiers},{key},spawn,python3 ~/.config/mango/scripts/{script_name} {action}\n'
    atomic(p,text)
    import importlib.util
    spec=importlib.util.spec_from_file_location('session_controls', MANGO/'scripts/session-controls.py')
    session=importlib.util.module_from_spec(spec);spec.loader.exec_module(session)
    session.ensure_overlay()
    p = MANGO / 'rule.conf'
    rule='window_rule=is_floating:1,no_animation:1,app_id:^io[.]victoria[.]Clipboard$'
    if p.exists() and rule not in p.read_text():atomic(p,p.read_text()+'\n'+rule+'\n')
    p = MANGO / 'autostart.sh'
    if p.exists():atomic(p,p.read_text().replace('wl-paste --watch cliphist store >/dev/null 2>&1 &','wl-paste --type text --watch cliphist store >/dev/null 2>&1 &\nwl-paste --type image --watch cliphist store >/dev/null 2>&1 &'))
    if p.exists() and '--first-run' not in p.read_text():
        atomic(p, p.read_text() + '\n# Show guided setup until the user completes it.\npython3 "$HOME/.config/mango/scripts/victoria-controls.py" --first-run &\n')

    if p.exists() and 'idle-restart' not in p.read_text():
        atomic(p, p.read_text() + '\npython3 "$HOME/.config/mango/scripts/session-controls.py" idle-restart &\n')

    for directory in (MANGO / 'config/wlogout', HOME / '.config/wlogout'):
        layout = directory / 'layout'
        if layout.exists():
            text = layout.read_text().replace('swaylock -f', 'python3 ~/.config/mango/scripts/session-controls.py lock')
            text = re.sub(r'("action"\s*:\s*)"hyprlock"', r'\1"python3 ~/.config/mango/scripts/session-controls.py lock"', text)
            text = text.replace('loginctl suspend', 'python3 ~/.config/mango/scripts/session-controls.py suspend')
            atomic(layout, text)

    if (MANGO / 'local/settings.json').exists():
        save_appearance(read_settings())


if __name__ == '__main__':
    install()
