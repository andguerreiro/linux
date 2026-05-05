#!/bin/bash
set -euo pipefail

# 1. Package Installation
sudo pacman -S --needed --noconfirm \
    dolphin kate ark gwenview kcalc okular \
    unrar zip unzip ufw wireless-regdb

# 2. Security & Firewall
sudo systemctl enable --now ufw.service
sudo ufw allow 631
sudo ufw --force enable

# 3. Boot Security (fstab & permissions)
# Replaces existing options with secure masks (0077)
sudo sed -i -E '/\/boot/ s/(vfat\s+)\S+/\1rw,relatime,fmask=0077,dmask=0077/' /etc/fstab
sudo systemctl daemon-reload
sudo umount /boot || true
sudo mount /boot
sudo bootctl random-seed

# 4. Audio Optimization (Pipewire)
mkdir -p ~/.config/pipewire/pipewire.conf.d/
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
systemctl --user restart pipewire pipewire-pulse wireplumber || true

# 5. Boot Configuration (Timeout 0)
echo "timeout 0" | sudo tee /boot/loader/loader.conf

echo "System updated and secured. Reboot recommended."
