#!/bin/bash
set -euo pipefail

# Package Installation
sudo pacman -S --needed --noconfirm \
    dolphin kate ark gwenview kcalc okular \
    unrar zip unzip ufw wireless-regdb power-profiles-daemon

# Boot Security (fstab & permissions)
# Replaces existing options with secure masks (0077)
sudo sed -i -E '/\/boot/ s/(vfat\s+)\S+/\1rw,relatime,fmask=0077,dmask=0077/' /etc/fstab
sudo systemctl daemon-reload
sudo umount /boot || true
sudo mount /boot
sudo bootctl random-seed

# Boot Configuration (Timeout 0)
echo "timeout 0" | sudo tee /boot/loader/loader.conf

echo "System updated and secured. Reboot recommended."
