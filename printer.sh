#!/bin/bash

# Define variables for easy editing
PRINTER_NAME="HP_DeskJet_3776"
PRINTER_URI="ipp://192.168.15.72/ipp/print"

echo "Starting printer configuration for $PRINTER_NAME..."

# 1. Install necessary packages
echo "Installing CUPS and dependencies..."
sudo pacman -S --noconfirm cups cups-filters ghostscript

# 2. Enable and start the CUPS service
echo "Starting CUPS service..."
sudo systemctl enable --now cups.service

# 3. Add the printer using IPP Everywhere (Driverless)
echo "Registering printer on the network..."
sudo lpadmin -p "$PRINTER_NAME" -E -v "$PRINTER_URI" -m everywhere

# 4. Configure default print options (A4, Draft, Grayscale)
echo "Setting print defaults..."
sudo lpadmin -p "$PRINTER_NAME" \
    -o PageSize=A4 \
    -o cupsPrintQuality=Draft \
    -o ColorModel=Gray

# 5. Set as the default system printer
lpoptions -d "$PRINTER_NAME"

echo -e "\n--- PRINTER CONFIG COMPLETED ---"
echo "$PRINTER_NAME is now your default printer."