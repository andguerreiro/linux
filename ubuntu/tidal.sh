#!/usr/bin/env bash

set -euo pipefail

# ==========================================================
# Strawberry 1.2.30 + TIDAL — Ubuntu Setup V2
# ==========================================================

STRAWBERRY_VERSION="1.2.30"
VENV="$HOME/.venvs/tidal"
LOGIN_SCRIPT="$HOME/strawberry-tidal-login.py"
STRAWBERRY_CONFIG="$HOME/.config/strawberry/strawberry.conf"

echo "=========================================="
echo " Strawberry + TIDAL — Ubuntu Setup V2"
echo "=========================================="
echo

# ----------------------------------------------------------
# 0. Check operating system
# ----------------------------------------------------------

if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: Cannot determine operating system."
    exit 1
fi

source /etc/os-release

if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "ERROR: This script is intended for Ubuntu."
    echo "Detected: ${PRETTY_NAME:-unknown}"
    exit 1
fi

UBUNTU_VERSION="${VERSION_ID}"
UBUNTU_CODENAME="${VERSION_CODENAME:-}"

echo "Detected Ubuntu:"
echo "  Version : $UBUNTU_VERSION"
echo "  Codename: ${UBUNTU_CODENAME:-unknown}"
echo

# ----------------------------------------------------------
# 1. Validate supported Ubuntu version
# ----------------------------------------------------------

case "$UBUNTU_CODENAME" in

    noble)
        echo "Supported Ubuntu release: 24.04 Noble"
        ;;

    resolute)
        echo "Supported Ubuntu release: 26.04 Resolute"
        ;;

    stonking)
        echo "Supported Ubuntu release: 26.10 Stonking"
        ;;

    *)
        echo
        echo "ERROR: Unsupported Ubuntu release."
        echo
        echo "This V2 script currently supports:"
        echo "  Ubuntu 24.04 Noble"
        echo "  Ubuntu 26.04 Resolute"
        echo "  Ubuntu 26.10 Stonking"
        echo
        echo "Detected:"
        echo "  Version : $UBUNTU_VERSION"
        echo "  Codename: $UBUNTU_CODENAME"
        echo
        exit 1
        ;;

esac

# ----------------------------------------------------------
# 2. Check architecture
# ----------------------------------------------------------

ARCH="$(dpkg --print-architecture)"

if [[ "$ARCH" != "amd64" ]]; then
    echo
    echo "ERROR: The official Strawberry 1.2.30 Ubuntu packages"
    echo "used by this script are x86_64/amd64 packages."
    echo
    echo "Detected architecture: $ARCH"
    exit 1
fi

echo "Architecture: $ARCH"
echo

# ----------------------------------------------------------
# 3. Install system dependencies
# ----------------------------------------------------------

echo "[1/5] Installing required Ubuntu packages..."
echo

sudo apt update

sudo apt install -y \
    curl \
    ca-certificates \
    python3 \
    python3-pip \
    python3-venv

# ----------------------------------------------------------
# 4. Download and install Strawberry 1.2.30
# ----------------------------------------------------------

echo
echo "[2/5] Installing Strawberry $STRAWBERRY_VERSION..."
echo

STRAWBERRY_DEB="/tmp/strawberry_${STRAWBERRY_VERSION}-${UBUNTU_CODENAME}_amd64.deb"

STRAWBERRY_URL="https://files.strawberrymusicplayer.org/strawberry_${STRAWBERRY_VERSION}-${UBUNTU_CODENAME}_amd64.deb"

echo "Downloading:"
echo "  $STRAWBERRY_URL"
echo

curl -fL \
    --retry 3 \
    --retry-delay 2 \
    -o "$STRAWBERRY_DEB" \
    "$STRAWBERRY_URL"

echo
echo "Installing Strawberry..."
echo

sudo apt install -y "$STRAWBERRY_DEB"

rm -f "$STRAWBERRY_DEB"

# ----------------------------------------------------------
# Verify Strawberry version
# ----------------------------------------------------------

echo
echo "Checking installed Strawberry version..."

if ! command -v strawberry >/dev/null 2>&1; then
    echo
    echo "ERROR: Strawberry was not installed correctly."
    exit 1
fi

INSTALLED_STRAWBERRY="$(strawberry --version 2>/dev/null || true)"

echo
echo "Installed Strawberry:"
echo "  $INSTALLED_STRAWBERRY"
echo

if ! echo "$INSTALLED_STRAWBERRY" | grep -q "$STRAWBERRY_VERSION"; then
    echo "WARNING:"
    echo "The installed Strawberry version does not appear to be"
    echo "$STRAWBERRY_VERSION."
    echo
    echo "Please verify the installation before continuing."
    echo

    exit 1
fi

# ----------------------------------------------------------
# 5. Create Python virtual environment
# ----------------------------------------------------------

echo
echo "[3/5] Creating TIDAL Python virtual environment..."
echo

mkdir -p "$HOME/.venvs"

if [[ ! -d "$VENV" ]]; then
    python3 -m venv "$VENV"
else
    echo "Virtual environment already exists:"
    echo "  $VENV"
fi

echo
echo "Installing/updating tidalapi..."
echo

"$VENV/bin/python" -m pip install --upgrade pip
"$VENV/bin/python" -m pip install --upgrade tidalapi

# ----------------------------------------------------------
# 6. Prepare Strawberry configuration
# ----------------------------------------------------------

echo
echo "[4/5] Preparing Strawberry configuration..."
echo

mkdir -p "$HOME/.config/strawberry"

# Create timestamped backup if configuration already exists
if [[ -f "$STRAWBERRY_CONFIG" ]]; then

    BACKUP="$STRAWBERRY_CONFIG.backup.$(date +%Y%m%d-%H%M%S)"

    echo "Existing Strawberry configuration found."

    echo
    echo "Backing up:"
    echo "  $STRAWBERRY_CONFIG"

    echo "to:"
    echo "  $BACKUP"

    cp "$STRAWBERRY_CONFIG" "$BACKUP"

    echo
fi

# ----------------------------------------------------------
# 7. Create TIDAL authentication script
# ----------------------------------------------------------

echo "Creating TIDAL authentication script..."

cat > "$LOGIN_SCRIPT" <<'PYTHON'
import configparser
import tidalapi
from pathlib import Path


print("==========================================")
print(" TIDAL Authentication")
print("==========================================")
print()
print("A TIDAL login page will be opened in your")
print("default web browser.")
print()

session = tidalapi.Session()

print("Starting PKCE authentication...")
print()

session.login_pkce()

if not session.check_login():
    raise RuntimeError(
        "TIDAL login was not completed successfully."
    )

print()
print("TIDAL login successful!")
print()

conf_path = Path.home() / ".config/strawberry/strawberry.conf"

config = configparser.ConfigParser(strict=False)
config.read(conf_path)

if not config.has_section("Tidal"):
    config.add_section("Tidal")

# ----------------------------------------------------------
# Strawberry TIDAL integration
# ----------------------------------------------------------

config.set("Tidal", "enabled", "true")
config.set("Tidal", "oauth", "true")
config.set("Tidal", "type", "2")
config.set("Tidal", "streamurl", "2")

# ----------------------------------------------------------
# Credentials obtained through PKCE
# ----------------------------------------------------------

config.set(
    "Tidal",
    "client_id",
    session.config.client_id_pkce
)

config.set(
    "Tidal",
    "token_type",
    session.token_type
)

config.set(
    "Tidal",
    "access_token",
    session.access_token
)

config.set(
    "Tidal",
    "refresh_token",
    session.refresh_token
)

config.set(
    "Tidal",
    "session_id",
    session.session_id
)

# ----------------------------------------------------------
# Audio quality
# ----------------------------------------------------------

config.set(
    "Tidal",
    "quality",
    "HI_RES_LOSSLESS"
)

# ----------------------------------------------------------
# Country
# ----------------------------------------------------------

config.set(
    "Tidal",
    "country_code",
    "BR"
)

# ----------------------------------------------------------
# Save configuration
# ----------------------------------------------------------

with open(conf_path, "w") as f:
    config.write(f)

print("Strawberry TIDAL configuration saved.")
print()
print("Configuration file:")
print(f"  {conf_path}")
print()
print("TIDAL authentication completed successfully!")
PYTHON

chmod 700 "$LOGIN_SCRIPT"

# ----------------------------------------------------------
# 8. Authenticate with TIDAL
# ----------------------------------------------------------

echo
echo "[5/5] TIDAL authentication"
echo
echo "Your browser will open so you can log in to TIDAL."
echo

"$VENV/bin/python" "$LOGIN_SCRIPT"

# ----------------------------------------------------------
# 9. Final information
# ----------------------------------------------------------

echo
echo "=========================================="
echo " Setup completed successfully!"
echo "=========================================="
echo
echo "Ubuntu:"
echo "  $PRETTY_NAME"
echo
echo "Strawberry:"
echo "  $INSTALLED_STRAWBERRY"
echo
echo "Virtual environment:"
echo "  $VENV"
echo
echo "TIDAL login script:"
echo "  $LOGIN_SCRIPT"
echo
echo "Strawberry configuration:"
echo "  $STRAWBERRY_CONFIG"
echo
echo "Start Strawberry with:"
echo "  strawberry"
echo
echo "TIDAL should now be available in Strawberry."
echo
