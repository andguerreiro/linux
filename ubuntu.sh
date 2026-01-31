#!/bin/bash

echo "Starting post-install script..."

# Update System
sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y
sudo snap refresh

# Security: Enable UFW
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable

# Hardware: Disable Bluetooth
sudo systemctl disable bluetooth.service
sudo systemctl stop bluetooth.service

# GNOME Customization
gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1

# Audio: Pipewire Bit-perfect
mkdir -p ~/.config/pipewire/pipewire.conf.d/
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }' > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
systemctl --user restart pipewire

echo "Script complete!"
