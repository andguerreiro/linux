#!/usr/bin/env bash
set -euo pipefail

# Debian Trixie (KDE Plasma) Post-Install Script
echo "== Starting Debian post-install cleanup & optimization =="

#---------------------------------------------------------
# GRUB – Set timeout to 0
#---------------------------------------------------------
echo "[GRUB] Setting GRUB_TIMEOUT=0"
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
sudo sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
sudo update-grub
echo "[OK] GRUB timeout set to 0."

#---------------------------------------------------------
# Bluetooth – Disable Service
#---------------------------------------------------------
echo "[Bluetooth] Disabling bluetooth.service"
sudo systemctl disable --now bluetooth.service 2>/dev/null || true
echo "[OK] Bluetooth service disabled."

#---------------------------------------------------------
# PipeWire – Set Allowed Rates
#---------------------------------------------------------
echo "[PipeWire] Configuring allowed-rates"
sudo mkdir -p /etc/pipewire/pipewire.conf.d/
sudo bash -c 'cat <<EOF > /etc/pipewire/pipewire.conf.d/custom-rates.conf
context.properties = {
    default.clock.allowed-rates = [ 44100 48000 88200 96000 192000 ]
}
EOF'
echo "[OK] PipeWire allowed-rates configured."

#---------------------------------------------------------
# Finalizing
#---------------------------------------------------------
echo "[Audio] Restarting PipeWire services..."
systemctl --user restart pipewire pipewire-pulse wireplumber
echo "[OK] PipeWire services restarted."

echo "== Post-install complete. =="
