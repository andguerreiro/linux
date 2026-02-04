#!/usr/bin/env bash
set -euo pipefail

echo "== Debian post-install hardening & cleanup =="

#----------------------------
# GRUB – set timeout to 0
#----------------------------
echo "[GRUB] Setting GRUB_TIMEOUT=0"
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
sudo update-grub

#----------------------------
# Firewall (UFW)
#----------------------------
echo "[UFW] Installing and configuring firewall"
sudo apt-get update
sudo apt-get install -y ufw
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw --force enable

#----------------------------
# Disable Bluetooth
#----------------------------
echo "[Bluetooth] Disabling bluetooth.service"
if systemctl is-enabled --quiet bluetooth.service; then
    sudo systemctl disable --now bluetooth.service
fi

#----------------------------
# Purge unwanted GNOME software
#----------------------------
echo "[GNOME] Purging unwanted GNOME packages"
sudo apt-get purge -y \
    gnome-games \
    gnome-characters \
    gnome-clocks \
    gnome-calendar \
    gnome-color-manager \
    gnome-contacts \
    gnome-font-viewer \
    gnome-logs \
    gnome-maps \
    gnome-music \
    gnome-sound-recorder \
    gnome-weather \
    gnome-tour \
    showtime \
    im-config \
    evolution \
    rhythmbox \
    shotwell \
    yelp \
    simple-scan \
    gnome-snapshot \
    seahorse \
    gnome-tweaks

sudo apt-get autoremove -y

#----------------------------
# GNOME customization (current user session)
#----------------------------
echo "[GNOME] Applying gsettings for user: $USER"

if command -v gsettings &>/dev/null; then
    gsettings set \
        org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ \
        enable false

    gsettings set \
        org.gnome.settings-daemon.plugins.media-keys \
        volume-step 1
fi

#----------------------------
# PipeWire – bit-perfect audio
#----------------------------
echo "[PipeWire] Configuring bit-perfect sample rates"

PIPEWIRE_DIR="$HOME/.config/pipewire/pipewire.conf.d"
mkdir -p "$PIPEWIRE_DIR"

cat > "$PIPEWIRE_DIR/custom-rates.conf" <<'EOF'
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 96000 192000 ]
}
EOF

systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true

sudo apt-get update

echo "== Post-install complete. Reboot recommended. =="
