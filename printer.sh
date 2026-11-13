#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Printer Configuration
# ==========================================================

PRINTER_NAME="HP_DeskJet_3776"
PRINTER_IP="192.168.15.200"
PRINTER_URI="ipp://${PRINTER_IP}/ipp/print"

echo "=== HP DeskJet 3776 Installation ==="

# ==========================================================
# 1. Detect Package Manager
# ==========================================================

echo
echo "=== Detecting Package Manager ==="

if command -v pacman >/dev/null 2>&1; then
    PKG_MANAGER="pacman"

elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"

elif command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"

else
    echo "ERROR: No supported package manager found."
    exit 1
fi

echo "Package manager: ${PKG_MANAGER}"

# ==========================================================
# 2. Install Required Packages
# ==========================================================

echo
echo "=== Installing CUPS Packages ==="

case "$PKG_MANAGER" in
    pacman)
        sudo pacman -S --needed --noconfirm \
            cups \
            cups-filters \
            ghostscript
        ;;

    dnf)
        sudo dnf install -y \
            cups \
            cups-filters \
            ghostscript
        ;;

    apt)
        sudo apt-get update
        sudo apt-get install -y \
            cups \
            cups-filters \
            ghostscript
        ;;
esac

# ==========================================================
# 3. Start CUPS
# ==========================================================

echo
echo "=== Starting CUPS ==="

sudo systemctl enable --now cups.service

# ==========================================================
# 4. Check Printer Connectivity
# ==========================================================

echo
echo "=== Checking Printer Connectivity ==="

if ! timeout 5 bash -c \
    "</dev/tcp/${PRINTER_IP}/631" 2>/dev/null; then

    echo "ERROR: Printer is offline or IPP port 631 is unreachable."
    echo "Check the printer IP and network connection."
    exit 1
fi

echo "Printer is reachable!"

# ==========================================================
# 5. Configure Driverless IPP
# ==========================================================

echo
echo "=== Configuring Driverless IPP ==="

# Remove existing queue if present
if lpstat -p "$PRINTER_NAME" >/dev/null 2>&1; then
    echo "Removing existing printer queue..."
    sudo lpadmin -x "$PRINTER_NAME"
fi

sudo lpadmin \
    -p "$PRINTER_NAME" \
    -E \
    -v "$PRINTER_URI" \
    -m everywhere

# ==========================================================
# 6. Configure Printing Options
# ==========================================================

echo
echo "=== Configuring Printing Options ==="

sudo lpadmin -p "$PRINTER_NAME" \
    -o PageSize=A4 \
    -o print-quality=3 \
    -o ColorModel=Gray

# Set default printer
lpoptions -d "$PRINTER_NAME"

# Enable printer and accept jobs
sudo cupsenable "$PRINTER_NAME"
sudo cupsaccept "$PRINTER_NAME"

# ==========================================================
# 7. Verify Installation
# ==========================================================

echo
echo "=== Printer Status ==="

lpstat -p "$PRINTER_NAME" -l
lpstat -d

echo
echo "=================================================="
echo " HP DESKJET 3776 CONFIGURED SUCCESSFULLY!"
echo "=================================================="
