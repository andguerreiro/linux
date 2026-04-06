#!/bin/bash

echo "Starting post-install script..."

# Update System
echo "Updating system packages and Snaps..."
sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y
sudo snap refresh
echo "System update complete."

# Security: Enable UFW
echo "Configuring UFW Firewall..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw --force enable
echo "Firewall configured and enabled."

# Hardware: Disable Bluetooth
echo "Disabling Bluetooth services..."
sudo systemctl disable bluetooth.service
sudo systemctl stop bluetooth.service
echo "Bluetooth has been turned off."

# GNOME Customization
echo "Applying GNOME desktop customizations..."
gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1
gsettings set org.gnome.SessionManager logout-prompt false
echo "GNOME settings applied."

# Audio: Pipewire Bit-perfect
echo "Configuring Pipewire for bit-perfect audio..."
mkdir -p ~/.config/pipewire/pipewire.conf.d/
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
systemctl --user restart pipewire
echo "Audio configuration complete (Sample rates: 44.1k to 192k)."

echo "----------------------------"
echo "Script complete!"