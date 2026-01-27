#!/usr/bin/env bash
set -euo pipefail

echo "== Debian post-install hardening & cleanup =="

#----------------------------
# GRUB – set timeout to 0
#----------------------------
echo "[GRUB] Setting GRUB_TIMEOUT=0"
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub || true
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
if systemctl list-units --type=service | grep -q "bluetooth.service"; then
    sudo systemctl disable --now bluetooth.service || true
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
    totem \
    im-config \
    evolution \
    rhythmbox \
    shotwell \
    yelp \
    simple-scan \
    gnome-snapshot \
    gnome-tweaks || true

sudo apt-get autoremove -y

#----------------------------
# GNOME customization (current user session)
#----------------------------
echo "[GNOME] Applying gsettings for user: $USER"

gsettings set \
    org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/appliorg.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ \
    enable false || true

gsettings set \
    org.gnome.settings-daemon.plugins.media-keys \
    volume-step 1 || true

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

systemctl --user restart pipewire pipewire-pulse wireplumber || true

#----------------------------
# Enable contrib / non-free repositories
#----------------------------
echo "[APT] Enabling contrib and non-free repositories"
sudo sed -i -E '
/^deb[[:space:]]/ {
    /contrib/! s/main/main contrib non-free non-free-firmware/
}
' /etc/apt/sources.list

sudo apt-get update

echo "== Post-install complete. Reboot recommended. =="
