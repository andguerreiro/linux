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
https://github.com/andguerreiro/linux/blob/main/arch/gnome.sh

echo "System updated and secured. Reboot recommended."
