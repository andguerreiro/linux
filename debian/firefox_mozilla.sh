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
fi

echo "==> Removing Mozilla Firefox user data..."
rm -rf "$HOME/.mozilla" \
       "$HOME/.cache/mozilla" \
       "$HOME/.config/mozilla" 2>/dev/null || true

echo "==> Setting up Mozilla APT repository..."
sudo install -d -m 0755 /etc/apt/keyrings

wget -qO- https://packages.mozilla.org/apt/repo-signing-key.gpg | \
sudo gpg --dearmor -o /etc/apt/keyrings/mozilla.gpg

echo "deb [signed-by=/etc/apt/keyrings/mozilla.gpg] https://packages.mozilla.org/apt mozilla main" | \
sudo tee /etc/apt/sources.list.d/mozilla.list > /dev/null

echo "==> Installing Firefox..."
sudo apt update
sudo apt install -y firefox

echo "==> Done."
