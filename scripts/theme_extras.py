#!/usr/bin/env python3
"""Extend an already validated palette to Kitty, GTK and existing Vencord clients."""
import json
import os
from pathlib import Path
import re
import shutil
import tempfile

HOME=Path.home()
CONFIG=HOME/'.config'
STATE=Path(os.environ.get('XDG_STATE_HOME') or HOME/'.local/state')/'victoria/theme-originals'


def write(path,text):
    path.parent.mkdir(parents=True,exist_ok=True)
    # Keep the original user file once; later refreshes only replace our block.
    relative=path.relative_to(HOME)
    backup=STATE/relative
    if path.exists() and not backup.exists():
        backup.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,backup)
    fd,tmp=tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd,'w') as stream:stream.write(text)
        os.replace(tmp,path)
    finally:Path(tmp).unlink(missing_ok=True)


def block(path,body,css=False):
    begin='/* BEGIN VICTORIA PALETTE */' if css else '# BEGIN VICTORIA PALETTE'
    end='/* END VICTORIA PALETTE */' if css else '# END VICTORIA PALETTE'
    old=path.read_text() if path.exists() else ''
    old=re.sub(re.escape(begin)+'.*?'+re.escape(end)+'\n?', '', old, flags=re.S)
    write(path,old.rstrip()+'\n\n'+begin+'\n'+body.rstrip()+'\n'+end+'\n')


def performance_assets(colors, directory=None):
    directory=directory or CONFIG/'swaync'
    directory.mkdir(parents=True,exist_ok=True)
    fg,accent=colors['foreground'],colors['color5']
    for state in ('on','off'):
        fill=accent if state=='on' else fg
        opacity='1' if state=='on' else '0.12'
        cx=20 if state=='on' else 8
        (directory/f'performance-{state}.svg').write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="28" height="18"><rect y="3" width="28" height="12" rx="6" fill="{fill}" fill-opacity="{opacity}"/><circle cx="{cx}" cy="9" r="8" fill="{fg}"/></svg>')
    (directory/'performance-label.svg').write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="160" height="18"><text x="0" y="13" font-family="JetBrainsMono Nerd Font,monospace" font-size="12" fill="{fg}">Visual performance</text></svg>')


def power_icons(colors, directory=None):
    directory=directory or CONFIG/'wlogout/icons'
    directory.mkdir(parents=True,exist_ok=True)
    shapes={
        'lock':'<rect x="15" y="28" width="34" height="29" rx="5" fill="{accent}" stroke="none"/><path d="M22 28V19a10 10 0 0 1 20 0v9"/>',
        'logout':'<path d="M30 10H12v44h18M25 32h30M45 22l10 10-10 10"/>',
        'suspend':'<circle cx="32" cy="32" r="24"/><path d="M26 23v18M38 23v18"/>',
        'hibernate':'<circle cx="32" cy="32" r="24"/><path d="M32 20v24"/>',
        'shutdown':'<path d="M32 7v25M20 15a23 23 0 1 0 24 0"/>',
        'reboot':'<path d="M12 44A24 24 0 1 1 34 56M10 32l2 12 12-2"/>',
    }
    for name,shape in shapes.items():
        icon='<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><g fill="none" stroke="'+colors['color5']+'" stroke-width="4" stroke-linecap="round" stroke-linejoin="round">'+shape.replace('{accent}',colors['color5'])+'</g></svg>'
        (directory/(name+'.svg')).write_text(icon)


def apply(colors):
    for key in ['background','foreground',*[f'color{i}' for i in range(16)]]:
        if not re.fullmatch(r'#[0-9a-fA-F]{6}',colors.get(key,'')):raise ValueError('Invalid theme color: '+key)
    bg,fg,accent=colors['background'],colors['foreground'],colors['color5']
    performance_assets(colors)
    power_icons(colors)
    from qt_theme import apply as apply_qt
    apply_qt(colors,CONFIG,write)
    kitty=f'background {bg}\nforeground {fg}\ncursor {accent}\nselection_background {accent}\nselection_foreground {bg}\n'
    kitty+=''.join(f'color{i} {colors[f"color{i}"]}\n' for i in range(16))
    write(CONFIG/'kitty/victoria-colors.conf',kitty)
    block(CONFIG/'kitty/kitty.conf','include victoria-colors.conf')
    from gtk_theme import apply as apply_gtk
    apply_gtk(colors,CONFIG,write,block)
    discord=f''':root, .theme-dark {{
  --background-primary: {bg}; --background-secondary: {colors['color0']};
  --background-secondary-alt: {bg}; --background-tertiary: {colors['color0']};
  --background-base-low: {bg}; --background-base-lower: {colors['color0']};
  --background-base-lowest: {bg}; --background-surface-high: {colors['color8']};
  --background-floating: {colors['color0']}; --text-normal: {fg}; --text-default: {fg};
  --header-primary: {fg}; --interactive-active: {fg}; --brand-experiment: {accent};
  --brand-500: {accent}; --brand-560: {colors['color4']}; --text-link: {accent};
}}'''
    for client in ('Vencord','vesktop'):
        directory=CONFIG/client/'settings'
        if directory.is_dir():block(directory/'quickCss.css',discord,css=True)
