#!/usr/bin/env bash
set -euo pipefail

#  Set GRUB timeout to 0
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
sudo sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
sudo update-grub

# Disable Services
sudo systemctl disable --now bluetooth.service 2>/dev/null || true
sudo systemctl disable --now ModemManager.service 2>/dev/null || true
sudo systemctl disable --now switcheroo-control 2>/dev/null || true
sudo systemctl disable --now packagekit.service 2>/dev/null || true
sudo systemctl disable --now avahi-daemon.socket 2>/dev/null || true
sudo systemctl disable --now avahi-daemon 2>/dev/null || true
sudo systemctl disable --now avahi-daemon 2>/dev/null || true

# Purge software
sudo apt purge xterm vim kmail* konqueror kontrast kdeconnect akregator bluez imagemagick imagemagick-7.q16 plasma-discover -y
sudo apt autoremove -y

echo "Done!"
