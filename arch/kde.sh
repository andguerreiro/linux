#!/bin/bash
set -euo pipefail

# Package Installation
sudo pacman -S --needed --noconfirm \
    dolphin kate ark gwenview kcalc okular \
    unrar zip unzip power-profiles-daemon

# Package Removal
sudo pacman -Rns --noconfirm vim
sudo pacman -Rdd --noconfirm discover

# Boot Configuration (Timeout 0)
echo "timeout 0" | sudo tee /boot/loader/loader.conf

# Wi-Fi Power Management & Stability Fixes
echo "options mt76x2u disable_usb_lpm=1" | sudo tee /etc/modprobe.d/mt76x2u.conf
sudo mkdir -p /etc/NetworkManager/conf.d && echo -e "[connection]\nwifi.powersave = 2" | sudo tee /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf

echo "System updated and secured. Reboot recommended."
