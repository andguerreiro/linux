#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing basic dependencies..."
sudo apt update
sudo apt install -y curl ca-certificates gnupg

echo "==> Creating keyrings directory (if it doesn't exist)..."
sudo install -d -m 0755 /etc/apt/keyrings

echo "==> Downloading official Spotify GPG key..."
curl -fsSL https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc \
| sudo gpg --dearmor --yes -o /etc/apt/keyrings/spotify.gpg

echo "==> Setting correct permissions for the key..."
sudo chmod 644 /etc/apt/keyrings/spotify.gpg

echo "==> Adding Spotify repository (if not already present)..."

REPO_LINE="deb [signed-by=/etc/apt/keyrings/spotify.gpg] https://repository.spotify.com stable non-free"
LIST_FILE="/etc/apt/sources.list.d/spotify.list"

if [ ! -f "$LIST_FILE" ] || ! grep -Fxq "$REPO_LINE" "$LIST_FILE"; then
    echo "$REPO_LINE" | sudo tee "$LIST_FILE > /dev/null"
else
    echo "==> Repository already configured."
fi

echo "==> Updating APT package list..."
sudo apt update

echo "==> Installing Spotify client..."
sudo apt install -y spotify-client

echo "==> Cleaning up unused packages..."
sudo apt autoremove -y

echo "==> Done! Spotify has been successfully installed."
