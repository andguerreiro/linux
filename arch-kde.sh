#!/bin/bash
set -e

# --- 1. Package Management ---
echo "Managing packages..."
sudo pacman -Rdd --noconfirm qt6-tools v4l-utils hwloc vim discover 2>/dev/null || true
sudo pacman -S --needed --noconfirm \
    dolphin konsole kate ark gwenview kcalc okular \
    unrar zip unzip ufw firefox chromium libreoffice-fresh mpv qbittorrent

# --- 2. Security & Firewall ---
echo "Configuring UFW..."
sudo systemctl enable --now ufw.service
sudo ufw allow 631 >/dev/null
sudo ufw --force enable >/dev/null

# --- 3. Audio Optimization ---
echo "Optimizing Pipewire..."
mkdir -p ~/.config/pipewire/pipewire.conf.d/
cat <<EOF > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }
EOF
systemctl --user restart pipewire pipewire-pulse wireplumber

# --- 4. Bootloader & UDEV ---
echo "Applying system tweaks..."
# Short-circuit: only runs sed if the file exists
[ -f /boot/loader/loader.conf ] && sudo sed -i 's/^timeout.*/timeout 0/' /boot/loader/loader.conf

sudo tee /etc/udev/rules.d/99-razer-huntsman-v3.rules > /dev/null <<EOF
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
EOF

sudo udevadm control --reload-rules && sudo udevadm trigger

echo "Configuration completed successfully!"