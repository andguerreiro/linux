#!/bin/bash
set -e

echo "Running post-install optimizations..."

# Disable Bluethooth
sudo systemctl disable --now bluetooth.service

# GNOME Desktop Tweaks
gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1
gsettings set org.gnome.SessionManager logout-prompt false

echo "Setup complete!"
