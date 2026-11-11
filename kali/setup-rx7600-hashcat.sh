#!/bin/bash
set -e

# RX 7600 + Hashcat requirements on Kali

sudo apt update

sudo apt install -y \
    hashcat \
    rocm-opencl-icd \
    rocminfo \
    libamdhip64-6 \
    hip-utils

sudo usermod -aG render,video "$USER"

sudo ldconfig

echo "Done. Log out/in or reboot for group changes to apply."
echo "Test with: hashcat -I"
