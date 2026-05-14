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

# 3. Purge Bloat (GNOME, LibreOffice, Firefox-ESR)
echo "[APT] Purging unwanted software..."
TO_PURGE=(
    # GNOME Bloat
    gnome-games gnome-characters gnome-clocks gnome-calendar 
    gnome-software gnome-software-common gnome-tweaks 
    gnome-color-manager gnome-contacts gnome-font-viewer gnome-logs 
    gnome-maps gnome-music gnome-sound-recorder gnome-weather 
    gnome-tour totem showtime im-config evolution rhythmbox 
    shotwell yelp simple-scan gnome-snapshot seahorse
    # LibreOffice & Firefox-ESR
    "libreoffice*" firefox-esr
)
sudo apt-get purge -y "${TO_PURGE[@]}"
sudo apt-get autoremove -y && sudo apt-get autoclean

# 4. Deep Clean Firefox-ESR leftovers
echo "[Cleanup] Removing Firefox-ESR config and cache..."
rm -rf "$HOME/.mozilla/firefox"
rm -rf "$HOME/.cache/mozilla/firefox"
# Removing system-wide policy dirs if they exist
sudo rm -rf /etc/firefox-esr

# 5. Flatpak Setup
echo "[Flatpak] Installing Flatpak and Firefox from Flathub..."
sudo apt-get update
sudo apt-get install -y flatpak
# Add Flathub repository
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
# Install Firefox via Flatpak
sudo flatpak install -y flathub org.mozilla.firefox

# 6. PipeWire: Audio optimization
echo "[PipeWire] Setting high-fidelity sample rates..."
CONF_DIR="$HOME/.config/pipewire/pipewire.conf.d"
mkdir -p "$CONF_DIR"
cat <<EOF > "$CONF_DIR/custom-rates.conf"
context.properties = { 
    default.clock.allowed-rates = [ 44100 48000 96000 192000 ] 
}
EOF

systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true

# 7. GNOME Desktop Tweaks
echo "[GNOME] Applying desktop tweaks..."
gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1
gsettings set org.gnome.SessionManager logout-prompt false

echo "== Done! Reboot recommended. =="
