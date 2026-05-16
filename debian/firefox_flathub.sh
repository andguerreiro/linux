#!/usr/bin/env bash
set -euo pipefail

# Purge Firefox ESR
sudo apt-get purge -y firefox-esr
sudo apt-get autoremove -y && sudo apt-get autoclean

# Deep Clean Firefox-ESR leftovers
echo "[Cleanup] Removing Firefox-ESR config and cache..."
rm -rf "$HOME/.mozilla/firefox"
rm -rf "$HOME/.cache/mozilla/firefox"
# Removing system-wide policy dirs if they exist
sudo rm -rf /etc/firefox-esr

# Flatpak Setup
echo "[Flatpak] Installing Flatpak and Firefox from Flathub..."
sudo apt-get update
sudo apt-get install -y flatpak
# Add Flathub repository
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
# Install Firefox via Flatpak
sudo flatpak install -y flathub org.mozilla.firefox

echo "== Done! Reboot recommended. =="
