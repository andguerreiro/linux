#!/usr/bin/env bash

set -euo pipefail

echo "Updating system packages..."
sudo pacman -Syu --noconfirm

echo "Installing Flatpak..."
sudo pacman -S --needed --noconfirm flatpak

echo "Adding Flathub repository..."
if ! flatpak remotes --user | grep -q '^flathub$'; then
    flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

echo "Installing Chromium..."
flatpak install --user -y flathub org.chromium.Chromium

echo "Applying device access permissions to Chromium..."
flatpak override --user --device=all org.chromium.Chromium

echo "Installation completed successfully!"
