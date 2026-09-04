#!/usr/bin/env bash
set -euo pipefail

PRINTER_NAME="HP_DeskJet_3776"
PRINTER_HOST="192.168.15.200"
PRINTER_URI="ipp://${PRINTER_HOST}/ipp/print"

echo "== Installing HP DeskJet 3776 =="

echo ">> Updating package lists..."
sudo apt update

echo ">> Installing CUPS and printing dependencies..."
sudo apt install -y cups cups-filters ghostscript

echo ">> Enabling CUPS..."
sudo systemctl enable --now cups.service

echo ">> Checking printer connectivity..."
if ! timeout 5 bash -c "</dev/tcp/${PRINTER_HOST}/631"; then
    echo "Warning: IPP port 631 did not respond."
    echo "Check the printer IP address and make sure the printer is powered on and connected to the same network."
fi

echo ">> Configuring printer..."

sudo lpadmin \
    -p "$PRINTER_NAME" \
    -E \
    -v "$PRINTER_URI" \
    -m everywhere

echo ">> Configuring printer defaults..."

sudo lpadmin \
    -p "$PRINTER_NAME" \
    -o PageSize=A4 \
    -o cupsPrintQuality=Draft \
    -o ColorModel=Gray \
    -o printer-is-shared=false

echo ">> Setting default printer..."

lpoptions -d "$PRINTER_NAME"

echo
echo "--- PRINTER CONFIGURATION COMPLETED ---"
echo "Printer: $PRINTER_NAME"
echo "Address: $PRINTER_URI"
echo

lpstat -p "$PRINTER_NAME"
lpstat -d
