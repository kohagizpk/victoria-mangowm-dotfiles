#!/usr/bin/env python3
"""Render a private MateriaDark variant from Wallust; leave packaged assets intact."""
import configparser
import io
from pathlib import Path
import re

BASE=Path('/usr/share/Kvantum/MateriaDark')
NAME='VictoriaWallustDark'


def mix(a,b,amount):
    return '#'+''.join(f'{round(int(a[i:i+2],16)*(1-amount)+int(b[i:i+2],16)*amount):02x}' for i in (1,3,5))


def update_ini(path,section,values,write):
    ini=configparser.ConfigParser(interpolation=None,strict=False);ini.optionxform=str
    if path.exists():ini.read(path)
    if not ini.has_section(section):ini.add_section(section)
    ini[section].update(values)
    out=io.StringIO();ini.write(out,space_around_delimiters=False);write(path,out.getvalue())


def apply(colors,config,write,base=BASE):
    if not all((base/('MateriaDark.'+ext)).is_file() for ext in ('svg','kvconfig')):return False
    bg,fg,accent=colors['background'],colors['foreground'],colors['color5']
    # Even a light wallpaper must keep the requested dark application theme.
    peak=max(int(bg[i:i+2],16) for i in (1,3,5))
    if peak>48:bg=mix('#000000',bg,48/peak)
    if sum(int(fg[i:i+2],16) for i in (1,3,5))/3<160:fg=mix(fg,'#ffffff',0.75)
    mapping={'#121212':bg,'#dfdfdf':fg,'#8ab4f8':accent,'#ce93d8':colors['color13'],
             '#1e1e1e':mix(bg,fg,.055),'#2e2e2e':mix(bg,fg,.10),
             '#272727':mix(bg,fg,.08),'#363636':mix(bg,fg,.13),
             '#3d434e':mix(bg,accent,.25),'#141b1e':mix(bg,accent,.06),
             '#1b1b1b':mix(bg,fg,.04),'#141414':mix(bg,fg,.02)}
    target=config/'Kvantum'/NAME
    for ext in ('svg','kvconfig'):
        text=(base/('MateriaDark.'+ext)).read_text()
        # Replace RGB only; preserve Kvantum's trailing alpha components.
        text=re.sub(r'#[0-9a-fA-F]{6}',lambda m:mapping.get(m[0].lower(),m[0]),text)
        if ext=='kvconfig':text=text.replace('respect_DE=true','respect_DE=false')
        write(target/(NAME+'.'+ext),text)
    for name in ('LICENSE','AUTHORS'):
        if (base/name).exists():write(target/name,(base/name).read_text())
    write(target/'VICTORIA-README.txt','Generated from MateriaDark by Victoria/Wallust. Original authors and license are retained. Color substitutions are regenerated on wallpaper changes.\n')
    update_ini(config/'Kvantum/kvantum.kvconfig','General',{'theme':NAME},write)
    for qt in ('qt5ct','qt6ct'):
        path=config/qt/(qt+'.conf')
        if path.exists():update_ini(path,'Appearance',{'style':'kvantum','custom_palette':'false'},write)
    return True
