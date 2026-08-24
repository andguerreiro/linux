#!/bin/bash
set -euo pipefail

pacman -Q vim &>/dev/null && sudo pacman -Rns --noconfirm vim

https://github.com/andguerreiro/linux/blob/main/arch/gnome.sh

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
