#!/bin/bash
set -euo pipefail

# Package Installation
sudo pacman -S --needed --noconfirm \
    dolphin kate ark gwenview kcalc okular \
    unrar zip unzip power-profiles-daemon

# Package Removal
sudo pacman -Rns --noconfirm vim
sudo pacman -Rdd --noconfirm discover

# Boot Configuration
sudo sed -i 's/^timeout .*/timeout 0/' /boot/loader/loader.conf

echo "System updated and secured. Reboot recommended."
