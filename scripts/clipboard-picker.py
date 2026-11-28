#!/usr/bin/env python3
"""Restore a selected clip only after the menu and decode both succeed."""
import fcntl
import os
from pathlib import Path
import subprocess
import sys


def notify(message):
    subprocess.run(['notify-send','-a','Victoria','Clipboard history',message],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=False)


def pick(chooser=None):
    listing=subprocess.run(['cliphist','list'],capture_output=True,timeout=10)
    if listing.returncode:raise RuntimeError('Could not read clipboard history. Your current clipboard was left unchanged.')
    rows=listing.stdout.splitlines()
    if not rows:
        notify('No clipboard history yet. Copy something first.');return
    if chooser is not None:
        index=chooser(rows)
        if index is None:return
    else:
        # An index identifies the original row even with identical/truncated previews.
        selection=subprocess.run(['fuzzel','--config',str(Path.home()/'.config/mango/config/fuzzel.ini'),
                                  '--dmenu','--index','--only-match','--with-nth','2','--prompt','Clipboard ❯ '],
                                 input=listing.stdout,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
        if selection.returncode:return  # Escape must never touch the clipboard.
        try:index=int(selection.stdout.strip())
        except ValueError:return
    if not 0<=index<len(rows):return
    row=rows[index]
    if not row.partition(b'\t')[0].isdigit():raise RuntimeError('Invalid history entry. Your current clipboard was left unchanged.')
    decoded=subprocess.run(['cliphist','decode'],input=row+b'\n',capture_output=True,timeout=15)
    if decoded.returncode or not decoded.stdout:
        raise RuntimeError('This history entry could not be restored. Your current clipboard was left unchanged.')
    # Keep bytes and all whitespace. wl-copy infers the MIME type (including images).
    copied=subprocess.run(['wl-copy'],input=decoded.stdout,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=10)
    if copied.returncode:raise RuntimeError('Could not restore the clipboard entry.')


def main():
    runtime=Path(os.environ.get('XDG_RUNTIME_DIR') or Path.home()/'.cache')/'victoria-clipboard'
    runtime.mkdir(mode=0o700,parents=True,exist_ok=True)
    with (runtime/'picker.lock').open('w') as guard:
        try:fcntl.flock(guard,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:return
        try:
            from clipboard_history import choose
            pick(choose)
        except (OSError,RuntimeError,subprocess.SubprocessError) as exc:
            # Do not expose history data or subprocess output in notifications.
            message=str(exc) if isinstance(exc,RuntimeError) else 'Clipboard history could not be opened. Check cliphist, fuzzel and wl-clipboard.'
            try:notify(message)
            except OSError:pass
            return 1
    return 0

if __name__=='__main__':sys.exit(main())
