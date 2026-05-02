#!/usr/bin/env bash

set -e

if ! getent group plugdev > /dev/null; then
    sudo groupadd plugdev
fi

sudo usermod -aG plugdev $USER

sudo tee /etc/udev/rules.d/99-razer-webhid.rules > /dev/null <<EOF
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", MODE="0660", GROUP="plugdev"
EOF

sudo tee /etc/udev/rules.d/99-vxe-webhid.rules > /dev/null <<EOF
KERNEL=="hidraw*", ATTRS{idVendor}=="3554", MODE="0660", GROUP="plugdev"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger
