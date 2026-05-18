#!/bin/bash
set -euo pipefail

# Package Installation
sudo pacman -S --needed --noconfirm \
    dolphin kate ark gwenview kcalc okular \
    unrar zip unzip ufw wireless-regdb

# Boot Security (fstab & permissions)
# Replaces existing options with secure masks (0077)
sudo sed -i -E '/\/boot/ s/(vfat\s+)\S+/\1rw,relatime,fmask=0077,dmask=0077/' /etc/fstab
sudo systemctl daemon-reload
sudo umount /boot || true
sudo mount /boot
sudo bootctl random-seed

# Audio Optimization (Pipewire)
mkdir -p ~/.config/pipewire/pipewire.conf.d/
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
systemctl --user restart pipewire pipewire-pulse wireplumber || true

# Boot Configuration (Timeout 0)
echo "timeout 0" | sudo tee /boot/loader/loader.conf

echo "System updated and secured. Reboot recommended."
