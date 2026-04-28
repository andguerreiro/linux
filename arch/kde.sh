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

# 5. Hardware Rules (Razer & VXE/ATK)
sudo tee /etc/udev/rules.d/99-peripherals.rules <<EOF >/dev/null
# Razer Huntsman v3 pro mini
ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"

# VXE / ATK (Mouse WebHID)
ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3554", MODE="0666", GROUP="wheel"
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="3554", MODE="0666", GROUP="wheel"
EOF
sudo udevadm control --reload-rules && sudo udevadm trigger

# 6. Boot Configuration (Timeout 0)
if [ -f /boot/loader/loader.conf ]; then
    sudo sed -i 's/^timeout.*/timeout 0/' /boot/loader/loader.conf
fi
sudo bootctl update || true

echo "System updated and secured. Reboot recommended."
