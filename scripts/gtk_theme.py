#!/usr/bin/env python3
"""Wallpaper colors for GTK controls, layered over the user's existing theme."""
import configparser
import io
from qt_theme import mix


def apply(colors,config,write,block):
    bg,fg,accent=colors['background'],colors['foreground'],colors['color5']
    peak=max(int(bg[i:i+2],16) for i in (1,3,5))
    if peak>48:bg=mix('#000000',bg,48/peak)
    if sum(int(fg[i:i+2],16) for i in (1,3,5))/3<160:fg=mix(fg,'#ffffff',.75)
    surface=mix(bg,fg,.065)
    # Use a readable foreground even for very bright wallpaper accents.
    brightness=sum(w*int(accent[i:i+2],16) for w,i in ((.2126,1),(.7152,3),(.0722,5)))
    on_accent='#111111' if brightness>150 else '#ffffff'
    css=f'''@define-color theme_bg_color {bg};
@define-color theme_fg_color {fg};
@define-color theme_base_color {bg};
@define-color theme_text_color {fg};
@define-color theme_selected_bg_color {accent};
@define-color theme_selected_fg_color {on_accent};
@define-color accent_bg_color {accent};
@define-color accent_fg_color {on_accent};
@define-color accent_color {accent};
@define-color window_bg_color {bg};
@define-color window_fg_color {fg};
@define-color view_bg_color {bg};
@define-color view_fg_color {fg};
@define-color headerbar_bg_color {surface};
@define-color headerbar_fg_color {fg};
@define-color card_bg_color {surface};
@define-color card_fg_color {fg};
@define-color popover_bg_color {surface};
@define-color popover_fg_color {fg};
@define-color dialog_bg_color {surface};
@define-color dialog_fg_color {fg};
window.background, .background {{ background-color: {bg}; color: {fg}; }}
headerbar, popover > contents, dialog {{ background-color: {surface}; color: {fg}; }}
entry, textview, textview text, treeview, list, view {{ background-color: {bg}; color: {fg}; caret-color: {accent}; }}
button {{ background-color: {surface}; color: {fg}; }}
button:hover {{ background-color: mix({surface}, {accent}, 0.22); }}
button:checked, button:active, button.suggested-action, switch:checked {{ background-color: {accent}; color: {on_accent}; background-image: none; }}
button:disabled {{ color: alpha({fg}, 0.4); }}
entry:focus, entry:focus-within, spinbutton:focus-within {{ border-color: {accent}; box-shadow: inset 0 -2px {accent}; }}
selection, row:selected, treeview:selected, iconview:selected {{ background-color: {accent}; color: {on_accent}; }}
check:checked, check:indeterminate, radio:checked {{ background-color: {accent}; color: {on_accent}; border-color: {accent}; }}
check, radio {{ color: {accent}; }}
scale highlight, progressbar progress {{ background-color: {accent}; background-image: none; border-color: {accent}; }}
scale slider {{ background-color: {accent}; background-image: none; border: 2px solid {accent}; border-radius: 999px; min-width: 14px; min-height: 14px; }}
switch slider {{ background-color: {fg}; background-image: none; }}
notebook > header > tabs > tab:checked {{ border-color: {accent}; box-shadow: inset 0 -2px {accent}; }}
button.link, link, label:link {{ color: {accent}; }}'''
    for version in (3,4):
        folder=config/f'gtk-{version}.0'
        block(folder/'gtk.css',css,css=True)
        path=folder/'settings.ini'
        ini=configparser.ConfigParser(interpolation=None,strict=False);ini.optionxform=str
        if path.exists():ini.read(path)
        if not ini.has_section('Settings'):ini.add_section('Settings')
        ini['Settings']['gtk-application-prefer-dark-theme']='1'
        if version==4:
            for key in ('gtk-toolbar-style','gtk-toolbar-icon-size','gtk-button-images','gtk-menu-images'):ini['Settings'].pop(key,None)
        output=io.StringIO();ini.write(output,space_around_delimiters=False);write(path,output.getvalue())
