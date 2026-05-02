#!/usr/bin/env bash

set -e

echo "[INFO] Configurando regras udev para WebHID..."

# Garante grupo plugdev
if ! getent group plugdev > /dev/null; then
    echo "[INFO] Criando grupo plugdev..."
    sudo groupadd plugdev
fi

echo "[INFO] Adicionando usuário ao grupo plugdev..."
sudo usermod -aG plugdev $USER

#---------------------------------------------------------
# Razer (Vendor ID: 1532)
#---------------------------------------------------------
echo "[Razer] Aplicando regras udev..."
sudo tee /etc/udev/rules.d/99-razer-webhid.rules > /dev/null <<EOF
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", MODE="0660", GROUP="plugdev"
EOF

#---------------------------------------------------------
# VXE / ATK (Vendor ID: 3554)
#---------------------------------------------------------
echo "[VXE/ATK] Aplicando regras udev..."
sudo tee /etc/udev/rules.d/99-vxe-webhid.rules > /dev/null <<EOF
KERNEL=="hidraw*", ATTRS{idVendor}=="3554", MODE="0660", GROUP="plugdev"
EOF

# Recarregar regras
echo "[INFO] Recarregando udev..."
sudo udevadm control --reload-rules
sudo udevadm trigger

echo "[OK] Tudo pronto."
echo "[IMPORTANTE] Faça logout e login novamente para aplicar o grupo."
