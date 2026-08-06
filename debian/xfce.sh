#!/usr/bin/env bash
set -euo pipefail

sudo sed -i \
    -e 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' \
    -e 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' \
    /etc/default/grub

sudo update-grub

sudo systemctl disable --now bluetooth.service 2>/dev/null || true
sudo systemctl disable --now ModemManager.service 2>/dev/null || true

xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || true
