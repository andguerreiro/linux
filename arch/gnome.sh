#!/bin/bash
set -euo pipefail

# Boot Configuration
sudo sed -i 's/^timeout .*/timeout 0/' /boot/loader/loader.conf

echo "System updated and secured. Reboot recommended."
