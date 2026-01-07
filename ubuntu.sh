#!/bin/bash

# Ubuntu Fresh Install Post-Setup Script
# --------------------------------------

echo "🚀 Starting post-install setup..."

# 1. Update System
echo "📦 Updating repositories and upgrading packages..."
sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y
sudo snap refresh

# 2. Security: Enable UFW
echo "🛡️ Configuring Firewall (UFW)..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable

# 3. Hardware: Disable Bluetooth
echo "📡 Disabling Bluetooth service..."
sudo systemctl disable bluetooth.service
sudo systemctl stop bluetooth.service

# 4. GNOME Customization: Notifications & Volume
echo "⚙️ Tweaking GNOME settings (Notifications & Volume step)..."
# Disable Print Notifications
gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
# Set Volume Step to 1
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1

# 5. Audio: Pipewire Bit-perfect setup
echo "🎵 Configuring Pipewire for high-res audio..."
mkdir -p ~/.config/pipewire/pipewire.conf.d/
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 88200 96000 192000 ] }' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
systemctl --user restart pipewire

# 6. Install Software via APT
echo "📥 Installing APT packages (mpv, qbittorrent, libreoffice)..."
sudo apt install -y mpv qbittorrent libreoffice-calc libreoffice-gnome libreoffice-writer

# 7. Install Software via Snap
echo "📥 Installing Snap packages (Spotify)..."
sudo snap install spotify

echo "✅ Setup complete! It is recommended to reboot for all changes to take effect."
