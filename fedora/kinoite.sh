#!/usr/bin/env bash
set -Eeuo pipefail

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

sudo rpm-ostree override remove firefox firefox-langpacks || true

rm -rf ~/.mozilla
rm -rf ~/.config/mozilla
rm -rf ~/.cache/mozilla

flatpak install -y flathub org.mozilla.firefox || \
sudo flatpak install -y flathub org.mozilla.firefox

sudo systemctl disable --now bluetooth.service || true
sudo systemctl mask bluetooth.service || true

sudo systemctl disable --now sshd.service || true
sudo systemctl mask sshd.service || true

sudo systemctl mask systemd-coredump.socket || true
sudo systemctl mask systemd-coredump@.service || true

sudo udevadm control --reload-rules
