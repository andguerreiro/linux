#!/bin/bash
set -euo pipefail

echo "--- Starting System Optimization & Fixes ---"

# 1. Package Installation
echo "Installing packages..."
sudo pacman -S --needed --noconfirm \
    dolphin kate ark gwenview kcalc okular \
    unrar zip unzip ufw

# 2. Security & Firewall
echo "Hardening system..."
sudo systemctl enable --now ufw.service
sudo ufw allow 631
sudo ufw --force enable

# 3. Fix /boot security hole (permissions)
echo "Fixing boot permissions in fstab..."
sudo sed -i 's/\(\/boot.*defaults\)/\1,fmask=0077,dmask=0077/' /etc/fstab
sudo mount -o remount /boot || true

# 4. Audio Optimization (Pipewire)
echo "Setting Pipewire sample rates..."
mkdir -p ~/.config/pipewire/pipewire.conf.d/
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
systemctl --user restart pipewire pipewire-pulse wireplumber || true

# 5. Hardware Rules (Fixed Udev Syntax)
echo "Applying Razer Huntsman v3 rules..."
sudo tee /etc/udev/rules.d/99-razer-huntsman-v3.rules <<EOF >/dev/null
ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
EOF
sudo udevadm control --reload-rules && sudo udevadm trigger

# 6. Boot Configuration (Timeout 0)
echo "Setting boot timeout to 0..."
[ -f /boot/loader/loader.conf ] && sudo sed -i 's/^timeout.*/timeout 0/' /boot/loader/loader.conf
sudo bootctl update

echo "Done! Please REBOOT to finalize changes."
