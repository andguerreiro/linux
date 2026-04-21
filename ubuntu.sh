#!/bin/bash
set -e  # Exit on error

echo "Running post-install optimizations..."

# 1. System Maintenance
sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y
sudo snap refresh

# 2. Security & Hardware
sudo ufw default deny incoming && sudo ufw default allow outgoing
sudo ufw --force enable
sudo systemctl disable --now bluetooth.service

# 3. GNOME Desktop Tweaks
gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1
gsettings set org.gnome.SessionManager logout-prompt false

# 4. PipeWire Audio (Bit-perfect)
CONF_DIR="$HOME/.config/pipewire/pipewire.conf.d"
mkdir -p "$CONF_DIR"
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }' > "$CONF_DIR/custom-rates.conf"

systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true

echo "Setup complete!"
