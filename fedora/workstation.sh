#!/usr/bin/env bash
set -euo pipefail

echo "== Fedora Post-Install Script =="

# Initial system upgrade
echo ">> Updating base system..."
sudo dnf upgrade --refresh -y

# Remove Firefox RPM version completely
echo ">> Removing Firefox RPM package..."
sudo dnf remove -y firefox firefox-langpacks || true

echo ">> Removing Firefox user data..."
rm -rf ~/.mozilla
rm -rf ~/.cache/mozilla
rm -rf ~/.config/mozilla
rm -rf ~/.cache/firefox
rm -rf ~/.config/firefox

# Enable Flathub
echo ">> Adding Flathub repository..."
sudo flatpak remote-add --if-not-exists \
  flathub https://flathub.org/repo/flathub.flatpakrepo

# Install Firefox Flatpak
echo ">> Installing Firefox Flatpak..."
flatpak install -y flathub org.mozilla.firefox

# PipeWire configuration
echo ">> Configuring PipeWire..."
install -d ~/.config/pipewire/pipewire.conf.d

cat > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf <<'EOF'
context.properties = {
  default.clock.allowed-rates = [ 44100 48000 96000 192000 ]
}
EOF

# Restart user audio services (non-fatal if not running yet)
systemctl --user restart pipewire wireplumber || true

# Hardware tweaks
echo ">> Disabling Bluetooth..."
sudo systemctl disable --now bluetooth.service

# GNOME customization
echo ">> Applying GNOME settings..."
gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1
gsettings set org.gnome.SessionManager logout-prompt false
gsettings set org.gnome.desktop.interface enable-animations false

# Final cleanup
echo ">> Final cleanup..."
sudo dnf autoremove -y

echo "== Post-install completed successfully =="
