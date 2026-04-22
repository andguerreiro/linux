#!/bin/bash
set -euo pipefail

echo "--- Starting System Optimization ---"

# 1. Package Installation (KDE Apps + Utilities)
echo "Installing packages..."
sudo pacman -S --needed --noconfirm \
    dolphin kate ark gwenview kcalc okular \
    unrar zip unzip ufw

# 2. Security & Firewall
echo "Hardening system..."
sudo bootctl random-seed
sudo systemctl enable --now ufw.service
sudo ufw allow 631
sudo ufw --force enable

# 3. Audio Optimization (Pipewire)
echo "Setting Pipewire sample rates..."
mkdir -p ~/.config/pipewire/pipewire.conf.d/
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
systemctl --user restart pipewire pipewire-pulse wireplumber

# 4. Hardware & Boot Tweaks
echo "Applying hardware rules and boot timeout..."
# Set boot timeout to 0
[ -f /boot/loader/loader.conf ] && sudo sed -i 's/^timeout.*/timeout 0/' /boot/loader/loader.conf

# Razer Huntsman v3 Rules
sudo tee /etc/udev/rules.d/99-razer-huntsman-v3.rules <<EOF >/dev/null
KERNEL=="hidraw*", ATTRS{idVendor}==1532, MODE="0666", GROUP="wheel"
SUBSYSTEM=="usb", ATTRS{idVendor}==1532, MODE="0666", GROUP="wheel"
EOF

sudo udevadm control --reload-rules && sudo udevadm trigger

echo "Done! Please REBOOT to finalize changes."
