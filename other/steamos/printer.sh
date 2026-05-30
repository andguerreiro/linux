#!/bin/bash

# Configuration
PRINTER_NAME="HP_DeskJet_3776"
PRINTER_URI="ipp://192.168.15.72/ipp/print"

# Add the printer using IPP Everywhere
sudo lpadmin -p "$PRINTER_NAME" -E -v "$PRINTER_URI" -m everywhere

# Set A4, Draft, and Grayscale defaults
sudo lpadmin -p "$PRINTER_NAME" -o PageSize=A4 -o cupsPrintQuality=Draft -o ColorModel=Gray

# Set as system default
lpoptions -d "$PRINTER_NAME"

echo "Printer $PRINTER_NAME configured successfully."
