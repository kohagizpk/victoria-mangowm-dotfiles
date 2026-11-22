#!/bin/sh
# Run as root (pkexec or sudo). Packages remain installed.
set -eu
for service in waydroid-container libvirtd sshd; do
    if [ -L "/etc/dinit.d/boot.d/$service" ]; then
        dinitctl --system disable "$service"
    fi
    dinitctl --system stop "$service"
done
# libvirt helpers may remain active after the parent service stops.
# No --force: refuse to stop a service still required by another consumer.
for service in virtlogd virtlockd; do
    dinitctl --system stop "$service"
done
