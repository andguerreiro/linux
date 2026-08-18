#!/usr/bin/env bash
set -euo pipefail

sudo sed -i \
    -e 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' \
    -e 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' \
    /etc/default/grub

sudo update-grub

xfconf-query -c xfce4-power-manager \
  -p /xfce4-power-manager/presentation-mode \
  --create -t bool -s true

xfconf-query -c xfce4-power-manager \
  -p /xfce4-power-manager/dpms-enabled \
  --create -t bool -s false

xfce4-power-manager --restart

echo "Done. Reboot recommended."
