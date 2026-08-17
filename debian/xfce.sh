#!/usr/bin/env bash
set -euo pipefail

sudo sed -i \
    -e 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' \
    -e 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' \
    /etc/default/grub

sudo update-grub

sudo systemctl disable --now bluetooth.service 2>/dev/null || true
sudo systemctl disable --now ModemManager.service 2>/dev/null || true

mkdir -p ~/.config/pipewire/pipewire.conf.d/

printf '%s\n' \
'context.properties = {' \
'    default.clock.allowed-rates = [ 44100 48000 96000 192000 ]' \
'}' \
> ~/.config/pipewire/pipewire.conf.d/custom-rates.conf

systemctl --user restart pipewire pipewire-pulse wireplumber

rm -f ~/.config/autostart/xfce4-screensaver.desktop

xfconf-query -c xfce4-power-manager \
  -p /xfce4-power-manager/presentation-mode \
  --create -t bool -s true

xfconf-query -c xfce4-power-manager \
  -p /xfce4-power-manager/dpms-enabled \
  --create -t bool -s false

xfce4-power-manager --restart

echo "Done. Reboot recommended."
