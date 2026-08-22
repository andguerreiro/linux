#!/usr/bin/env bash
set -e

echo "== Configuring strict firewall =="

sudo firewall-cmd --set-default-zone=public

for service in $(sudo firewall-cmd --zone=public --list-services); do
    sudo firewall-cmd --zone=public --remove-service="$service"
done

for port in $(sudo firewall-cmd --zone=public --list-ports); do
    sudo firewall-cmd --zone=public --remove-port="$port"
done

sudo firewall-cmd --runtime-to-permanent

echo
echo "=== FIREWALL CONFIGURED ==="
sudo firewall-cmd --zone=public --list-all
