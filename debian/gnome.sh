#!/usr/bin/env bash
set -euo pipefail

echo "== Starting Debian Cleanup & Optimization =="

# 1. GRUB: Zero timeout & Hidden menu
echo "[GRUB] Optimizing boot speed..."
sudo sed -i -e 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' \
            -e 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
sudo update-grub

# 2. Bluetooth: Kill service
echo "[Bluetooth] Disabling service..."
sudo systemctl disable --now bluetooth.service 2>/dev/null || true

# 3. GNOME: Purge bloat in one shot
echo "[GNOME] Purging unwanted software..."
TO_PURGE=(
    gnome-games gnome-characters gnome-clocks gnome-calendar 
    gnome-software gnome-software-common gnome-tweaks 
    gnome-color-manager gnome-contacts gnome-font-viewer gnome-logs 
    gnome-maps gnome-music gnome-sound-recorder gnome-weather 
    gnome-tour totem showtime im-config evolution rhythmbox 
    shotwell yelp simple-scan gnome-snapshot seahorse
)
sudo apt-get purge -y "${TO_PURGE[@]}"
sudo apt-get autoremove -y && sudo apt-get autoclean

# 4. PipeWire: Audio optimization
echo "[PipeWire] Setting high-fidelity sample rates..."
CONF_DIR="$HOME/.config/pipewire/pipewire.conf.d"
mkdir -p "$CONF_DIR"
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }' > "$CONF_DIR/custom-rates.conf"

systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true

# 5. GNOME Desktop Tweaks
gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1
gsettings set org.gnome.SessionManager logout-prompt false

echo "== Done! Reboot recommended. =="
