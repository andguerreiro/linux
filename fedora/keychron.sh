#!/usr/bin/env bash
set -euo pipefail

# --- Flatpak + Flathub (Flatpak ships with Fedora KDE, but Flathub may not be enabled) ---
if ! command -v flatpak > /dev/null; then
    sudo dnf install -y flatpak
fi

flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# --- Chromium (Flatpak) ---
flatpak install --user -y flathub org.chromium.Chromium

# Allow the sandbox to access /dev/hidraw* (required for WebHID / Keychron Launcher)
flatpak override --user --device=all org.chromium.Chromium

# --- udev rule for Keychron (vendor ID 3434) ---
# Fedora doesn't use a "plugdev" group; TAG+="uaccess" gives the
# currently logged-in user access automatically, so no group change is needed.
sudo tee /etc/udev/rules.d/99-keychron-webhid.rules > /dev/null <<'EOF'
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3434", MODE="0660", TAG+="uaccess"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger

echo "Done! Unplug and replug your Keychron keyboard (or reboot), then open"
echo "https://launcher.keychron.com in Chromium: flatpak run org.chromium.Chromium"
