#!/usr/bin/env bash
set -e

echo "== Configuring strict firewall =="

sudo firewall-cmd --set-default-zone=public

sudo firewall-cmd --zone=public --remove-services="$(sudo firewall-cmd --zone=public --list-services)" || true
sudo firewall-cmd --zone=public --remove-ports="$(sudo firewall-cmd --zone=public --list-ports)" || true

sudo firewall-cmd --runtime-to-permanent

echo
echo "=== FIREWALL CONFIGURED ==="
echo "Incoming connections: BLOCKED"
echo "Outgoing connections: ALLOWED"
echo
sudo firewall-cmd --zone=public --list-all
