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
sudo bootctl set-timeout 0

echo "System updated and secured. Reboot recommended."
