#!/usr/bin/env bash
set -euo pipefail

echo "== Installing HP DeskJet 3776 =="

echo ">> Installing CUPS and printing dependencies..."
sudo dnf install -y cups cups-filters ghostscript

echo ">> Enabling CUPS..."
sudo systemctl enable --now cups.service

echo ">> Configuring printer..."
sudo lpadmin \
    -p HP_DeskJet_3776 \
    -E \
    -v "ipp://192.168.15.72/ipp/print" \
    -m everywhere

echo ">> Configuring printer defaults..."
sudo lpadmin \
    -p HP_DeskJet_3776 \
    -o PageSize=A4 \
    -o cupsPrintQuality=Draft \
    -o ColorModel=Gray

echo ">> Setting default printer..."
lpoptions -d HP_DeskJet_3776

echo
echo "--- PRINTER CONFIG COMPLETED ---"
echo "HP_DeskJet_3776 is now your default printer."
echo

lpstat -p HP_DeskJet_3776
lpstat -d
