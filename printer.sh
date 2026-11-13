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
# 1. Detect Linux Distribution
# ==========================================================

if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: Cannot identify Linux distribution."
    exit 1
fi

source /etc/os-release

echo "Detected: ${PRETTY_NAME}"

case "$ID" in
    arch|omarchy|cachyos|endeavouros|manjaro)
        DISTRO="arch"
        ;;

    fedora)
        DISTRO="fedora"
        ;;

    debian|ubuntu|linuxmint|pop)
        DISTRO="debian"
        ;;

    *)
        echo "ERROR: Unsupported distribution: $ID"
        exit 1
        ;;
esac

# ==========================================================
# 2. Install Required Packages
# ==========================================================

echo
echo "=== Installing CUPS Packages ==="

case "$DISTRO" in
    arch)
        sudo pacman -S --needed --noconfirm \
            cups cups-filters ghostscript
        ;;

    fedora)
        sudo dnf install -y \
            cups cups-filters ghostscript
        ;;

    debian)
        sudo apt-get update
        sudo apt-get install -y \
            cups cups-filters ghostscript
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
    echo "Check the printer and network, then run this script again."

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

# ==========================================================
# 7. Verify Installation
# ==========================================================

echo
echo "=== Printer Status ==="

lpstat -p "$PRINTER_NAME" -l
lpstat -d

echo
echo "=================================================="
echo " HP DeskJet 3776 CONFIGURED SUCCESSFULLY!"
echo "=================================================="
