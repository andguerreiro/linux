#!/usr/bin/env bash

set -euo pipefail

echo "=========================================="
echo " Strawberry + TIDAL — Setup"
echo "=========================================="
echo

# ------------------------------------------
# 1. Install required packages
# ------------------------------------------

echo "[1/5] Installing Strawberry and Python..."

sudo pacman -S --needed strawberry python python-pip

# ------------------------------------------
# 2. Create Python virtual environment
# ------------------------------------------

echo
echo "[2/5] Creating TIDAL virtual environment..."

VENV="$HOME/.venvs/tidal"

python -m venv "$VENV"

# shellcheck disable=SC1091
source "$VENV/bin/activate"

echo "Installing/updating tidalapi..."

python -m pip install --upgrade pip
python -m pip install --upgrade tidalapi

# ------------------------------------------
# 3. Prepare Strawberry configuration
# ------------------------------------------

echo
echo "[3/5] Preparing Strawberry configuration..."

STRAWBERRY_CONFIG="$HOME/.config/strawberry/strawberry.conf"

mkdir -p "$HOME/.config/strawberry"

# Create a timestamped backup if the configuration already exists
if [[ -f "$STRAWBERRY_CONFIG" ]]; then
    BACKUP="$STRAWBERRY_CONFIG.backup.$(date +%Y%m%d-%H%M%S)"

    echo "Backing up:"
    echo "  $STRAWBERRY_CONFIG"
    echo "to:"
    echo "  $BACKUP"

    cp "$STRAWBERRY_CONFIG" "$BACKUP"
fi

# ------------------------------------------
# 4. Create TIDAL authentication script
# ------------------------------------------

echo
echo "[4/5] Creating TIDAL authentication script..."

LOGIN_SCRIPT="$HOME/strawberry-tidal-login.py"

cat > "$LOGIN_SCRIPT" <<'PYTHON'
import configparser
import tidalapi
from pathlib import Path

print("Starting TIDAL authentication...")
print("A TIDAL login page will be opened in your browser.")
print()

session = tidalapi.Session()
session.login_pkce()

if not session.check_login():
    raise RuntimeError("TIDAL login was not completed.")

print()
print("TIDAL login successful!")

conf_path = Path.home() / ".config/strawberry/strawberry.conf"

config = configparser.ConfigParser(strict=False)
config.read(conf_path)

if not config.has_section("Tidal"):
    config.add_section("Tidal")

# Strawberry TIDAL integration settings
config.set("Tidal", "enabled", "true")
config.set("Tidal", "oauth", "true")
config.set("Tidal", "type", "2")
config.set("Tidal", "streamurl", "2")

# Credentials obtained through PKCE authentication
config.set("Tidal", "client_id", session.config.client_id_pkce)
config.set("Tidal", "token_type", session.token_type)
config.set("Tidal", "access_token", session.access_token)
config.set("Tidal", "refresh_token", session.refresh_token)
config.set("Tidal", "session_id", session.session_id)

# Maximum quality available with the subscription
config.set("Tidal", "quality", "HI_RES_LOSSLESS")

# Country
config.set("Tidal", "country_code", "BR")

with open(conf_path, "w") as f:
    config.write(f)

print()
print("TIDAL login and Strawberry configuration completed successfully!")
print()
print("Configuration file:")
print(conf_path)
print()
print("You can now open Strawberry.")
print("Look for TIDAL in the left sidebar.")
PYTHON

chmod 700 "$LOGIN_SCRIPT"

# ------------------------------------------
# 5. Authenticate with TIDAL
# ------------------------------------------

echo
echo "[5/5] TIDAL authentication"
echo
echo "Your browser will open so you can log in to TIDAL."
echo

"$VENV/bin/python" "$LOGIN_SCRIPT"

echo
echo "=========================================="
echo " Setup completed successfully!"
echo "=========================================="
echo
echo "Virtual environment:"
echo "  $VENV"
echo
echo "Login script:"
echo "  $LOGIN_SCRIPT"
echo
echo "Strawberry configuration:"
echo "  $STRAWBERRY_CONFIG"
echo
echo "You can start Strawberry with:"
echo "  strawberry"
echo
