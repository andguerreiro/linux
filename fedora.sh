#!/usr/bin/env bash
set -euo pipefail

echo "== Fedora Post-Install Script =="

# 1️⃣ Initial system upgrade
echo ">> Updating system..."
sudo dnf5 upgrade --refresh -y

# 2️⃣ Enable RPM Fusion (free + nonfree)
echo ">> Enabling RPM Fusion repositories..."
sudo dnf5 install -y \
  https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# 3️⃣ Refresh after enabling new repos
sudo dnf5 upgrade --refresh -y

# 4️⃣ Multimedia groups
echo ">> Installing multimedia groups..."
sudo dnf5 group upgrade multimedia \
  --setopt=install_weak_deps=False \
  --exclude=PackageKit-gstreamer-plugin -y

sudo dnf5 group upgrade sound-and-video -y

# 5️⃣ Enable Flathub (with sudo to avoid password prompt later)
echo ">> Adding Flathub repository..."
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# 6️⃣ PipeWire configuration
echo ">> Configuring PipeWire..."
mkdir -p ~/.config/pipewire/pipewire.conf.d/
echo 'context.properties = { default.clock.allowed-rates = [ 44100 48000 96000 192000 ] }' \
  > ~/.config/pipewire/pipewire.conf.d/custom-rates.conf
systemctl --user restart pipewire

# 7️⃣ Hardware: disable Bluetooth
echo ">> Disabling Bluetooth..."
sudo systemctl disable bluetooth.service
sudo systemctl stop bluetooth.service

# 8️⃣ GNOME customization
echo ">> Applying GNOME settings..."
gsettings set org.gnome.desktop.notifications.application:/org/gnome/desktop/notifications/application/gnome-printers-panel/ enable false
gsettings set org.gnome.settings-daemon.plugins.media-keys volume-step 1

# 9️⃣ Final cleanup
echo ">> Final upgrade and cleanup..."
sudo dnf5 upgrade -y
sudo dnf5 autoremove -y

echo "== Post-install completed successfully =="
