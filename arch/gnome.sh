#!/bin/bash
set -euo pipefail

# Boot Configuration
sudo sed -i 's/^timeout .*/timeout 0/' /boot/loader/loader.conf

# GNOME Desktop Tweaks
gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1
gsettings set org.gnome.SessionManager logout-prompt false

echo "Done. Reboot recommended."
