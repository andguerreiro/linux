#!/usr/bin/env bash

set -e

echo "==> Updating system packages..."
sudo apt update
sudo apt install -y wget gnupg ca-certificates

echo "==> Removing Firefox ESR if installed..."
if dpkg -l | grep -q firefox-esr; then
    sudo apt remove -y firefox-esr
    sudo apt autoremove -y
    echo "Firefox ESR removed."
else
    echo "Firefox ESR is not installed. Skipping."
fi

echo "==> Removing Mozilla Firefox user data (config/cache)..."
rm -rf "$HOME/.mozilla" \
       "$HOME/.cache/mozilla" \
       "$HOME/.config/mozilla" 2>/dev/null || true

echo "==> Creating keyring directory..."
sudo install -d -m 0755 /etc/apt/keyrings

echo "==> Downloading Mozilla repository signing key..."
wget -qO- https://packages.mozilla.org/apt/repo-signing-key.gpg | \
sudo gpg --dearmor -o /etc/apt/keyrings/mozilla.gpg

echo "==> Adding Mozilla APT repository..."
echo "deb [signed-by=/etc/apt/keyrings/mozilla.gpg] https://packages.mozilla.org/apt mozilla main" | \
sudo tee /etc/apt/sources.list.d/mozilla.list > /dev/null

echo "==> Updating package lists..."
sudo apt update

echo "==> Installing Firefox from Mozilla repository..."
sudo apt install -y firefox || {
    echo "Firefox package not found yet. Retrying after update..."
    sudo apt update
    sudo apt install -y firefox
}

echo "==> Verifying installation..."
if command -v firefox >/dev/null 2>&1; then
    echo "Firefox installed successfully."
else
    echo "ERROR: Firefox installation failed."
    exit 1
fi

echo "==> Done."
