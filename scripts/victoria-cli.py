#!/usr/bin/env python3
"""JSON bridge between the Quickshell UI and victoria_settings.

Usage: victoria-cli.py COMMAND [JSON]. Always prints one JSON line:
{"ok": true, "data": ...} or {"ok": false, "error": "..."}.
"""
import json
import shutil
import sys
from pathlib import Path

sys.dont_write_bytecode = True
import victoria_settings as backend  # noqa: E402

REVERT = backend.STATE / 'display-revert.json'


def state(_):
    try:
        import monitors
        displays = [{'name': name, 'width': mode.width, 'height': mode.height,
                     'refresh': round(mode.refresh or 0)} for name, mode in monitors.detect()]
    except Exception:  # detection is best-effort; the UI shows "unavailable"
        displays = []
    flags = backend.STATE
    return {
        'settings': backend.read_settings(),
        'defaults': backend.DEFAULTS,
        'profiles': backend.PROFILES,
        'keyboards': list(backend.KEYBOARDS),
        'switches': list(backend.LAYOUT_SWITCH),
        'keyboard': backend.current_keyboard(),
        'terminals': [t for t in backend.TERMINALS if shutil.which(t)],
        'browsers': [b for b in backend.BROWSERS if shutil.which(b)],
        'displays': displays,
        'setupComplete': (flags / 'setup-complete').exists(),
        'openAtLogin': not (flags / 'settings-autostart-disabled').exists()
                       and ((flags / 'settings-autostart-enabled').exists() or not (flags / 'setup-complete').exists()),
    }


def save(values):
    backend.save_appearance(values)
    return backend.read_settings()


def setup(choice):
    saved = backend.apply_setup(choice['keyboard'], choice.get('layout', 'Keep current'), float(choice.get('scale', 1)),
                                choice.get('terminal', 'Keep current'), choice.get('browser', 'Keep current'),
                                choice.get('secondary', 'None'), choice.get('switch', 'Alt + Shift'))
    if choice.get('layout', 'Keep current') != 'Keep current':
        # Keep the previous files until the user confirms the new monitor layout.
        backend.atomic(REVERT, json.dumps({str(k): (v.decode() if v is not None else None) for k, v in saved.items()}))
        return {'confirmDisplays': True}
    backend.atomic(backend.STATE / 'setup-complete', '1\n')
    return {'confirmDisplays': False}


def displays(action):
    if not REVERT.exists():
        return False
    if action == 'revert':
        saved = json.loads(REVERT.read_text())
        backend.restore({Path(k): (v.encode() if v is not None else None) for k, v in saved.items()})
    REVERT.unlink()
    backend.atomic(backend.STATE / 'setup-complete', '1\n')
    return True


def open_at_login(enabled):
    on, off = backend.STATE / 'settings-autostart-enabled', backend.STATE / 'settings-autostart-disabled'
    (off if enabled else on).unlink(missing_ok=True)
    backend.atomic(on if enabled else off, '1\n')
    return enabled


COMMANDS = {
    'state': state,
    'save': save,
    'setup': setup,
    'displays': displays,
    'open-at-login': open_at_login,
    'shortcuts': lambda _: [{'keys': k, 'action': d, 'kind': kind} for k, d, kind in backend.shortcuts()],
    'diagnostics': lambda _: [{'ok': ok, 'name': n, 'hint': h} for ok, n, h in backend.diagnostics()],
    'repair': lambda name: backend.repair(name).strip() or 'Done.',
    'focus': lambda _: backend.focus(),
    'keyboard': lambda _: backend.keyboard_labels(),
    'profile': lambda _: backend.profile(),
    'profile-name': backend.set_profile_name,
    'avatar': backend.set_avatar,
    'avatar-choose': lambda _: backend.choose_avatar(),
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(json.dumps({'ok': False, 'error': 'Unknown command'}))
        return 2
    argument = json.loads(sys.argv[2]) if len(sys.argv) > 2 else None
    try:
        print(json.dumps({'ok': True, 'data': COMMANDS[sys.argv[1]](argument)}, ensure_ascii=False))
        return 0
    except Exception as exc:  # report every failure to the UI instead of a traceback
        print(json.dumps({'ok': False, 'error': str(exc) or exc.__class__.__name__}))
        return 1


if __name__ == '__main__':
    sys.exit(main())
