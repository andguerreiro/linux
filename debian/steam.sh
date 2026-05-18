#!/usr/bin/env bash
set -euo pipefail

cd /tmp
wget https://cdn.cloudflare.steamstatic.com/client/installer/steam.deb
sudo apt update
sudo apt install -y ./steam.deb
rm -f ./steam_latest.deb
