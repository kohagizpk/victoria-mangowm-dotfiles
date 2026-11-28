#!/usr/bin/env bash
# D-Bus activation for org.freedesktop.Notifications, installed by install-controls.py as
# ~/.local/share/dbus-1/services/org.freedesktop.Notifications.service (user services win
# over /usr/share, where mako/swaync/dunst register themselves).
#
# With the Quickshell bar, an app that notifies before the bar is up must not start
# another daemon: wait for Quickshell to take the name (the message is delivered to it).
# With Waybar, start the themed swaync.
choice="$(cat "$HOME/.config/mango/local/bar-backend" 2>/dev/null || echo quickshell)"
if [[ "$choice" != waybar ]] && command -v quickshell >/dev/null; then
    for _ in $(seq 150); do
        busctl --user status org.freedesktop.Notifications >/dev/null 2>&1 && exit 0
        sleep 0.2
    done
    exit 0
fi
GSK_RENDERER=cairo exec swaync
