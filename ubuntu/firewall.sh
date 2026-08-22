#!/usr/bin/env bash
set -e

echo "== Configuring firewall =="

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw --force enable

echo
echo "=== FIREWALL CONFIGURED ==="
echo "Incoming connections: BLOCKED"
echo "Outgoing connections: ALLOWED"
echo
