#!/usr/bin/env bash
set -euo pipefail

#  Set GRUB timeout to 0
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
sudo sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
sudo update-grub

# Disable Bluetooth
sudo systemctl disable --now bluetooth.service 2>/dev/null || true

# Purge software
sudo apt purge xterm kmail* konqueror akregator bluez
sudo apt autoremove
