#!/usr/bin/env bash
set -euo pipefail

# GRUB: Zero timeout & Hidden menu
echo "[GRUB] Optimizing boot speed..."
sudo sed -i -e 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' \
            -e 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
sudo update-grub

# Bluetooth: Kill service
echo "[Bluetooth] Disabling service..."
sudo systemctl disable --now bluetooth.service 2>/dev/null || true

# Purge Bloat (GNOME, LibreOffice, Firefox-ESR)
echo "[APT] Purging unwanted software..."
TO_PURGE=(
    # GNOME Bloat
    gnome-games gnome-characters gnome-clocks gnome-calendar 
    gnome-software gnome-software-common gnome-tweaks 
    gnome-color-manager gnome-contacts gnome-font-viewer gnome-logs 
    gnome-maps gnome-music gnome-sound-recorder gnome-weather 
    gnome-tour totem showtime im-config evolution rhythmbox 
    shotwell yelp simple-scan gnome-snapshot seahorse malcontent
    gnome-connections "libreoffice*"
)
sudo apt-get purge -y "${TO_PURGE[@]}"
sudo apt-get autoremove -y && sudo apt-get autoclean

# GNOME Desktop Tweaks
echo "[GNOME] Applying desktop tweaks..."
gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1
gsettings set org.gnome.SessionManager logout-prompt false
gsettings set org.gnome.desktop.interface enable-animations false
