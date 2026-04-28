#!/usr/bin/env bash
set -euo pipefail

echo "== Fedora Post-Install Script (DNF) =="

# Initial system upgrade (base system)
echo ">> Updating base system..."
sudo dnf upgrade --refresh -y

# Enable RPM Fusion (free + nonfree)
echo ">> Enabling RPM Fusion repositories..."
sudo dnf install -y \
  https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Multimedia packages (now that RPM Fusion is enabled)
echo ">> Installing multimedia group..."
sudo dnf group upgrade multimedia \
  --setopt=install_weak_deps=False \
  --exclude=PackageKit-gstreamer-plugin -y

# Enable Flathub
echo ">> Adding Flathub repository..."
sudo flatpak remote-add --if-not-exists \
  flathub https://flathub.org/repo/flathub.flatpakrepo

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

# Final system upgrade & cleanup
echo ">> Final upgrade and cleanup..."
sudo dnf upgrade -y
sudo dnf autoremove -y

echo "== Post-install completed successfully =="
