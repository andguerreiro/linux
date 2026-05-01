#---------------------------------------------------------
# Razer Synapse Web Udev Rules
#---------------------------------------------------------
echo "[Razer] Applying udev rules"
sudo bash -c 'cat <<EOF > /etc/udev/rules.d/99-razer-huntsman-v3.rules
KERNEL=="hidraw*", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1532", MODE="0666", GROUP="wheel"
EOF
udevadm control --reload-rules && udevadm trigger'
echo "[OK] Razer udev rules applied."

#---------------------------------------------------------
# VXE / ATK Mouse WebHID
#---------------------------------------------------------
echo "[VXE/ATK] Applying udev rules"
sudo bash -c 'cat <<EOF > /etc/udev/rules.d/99-vxe-atk-mouse.rules
# VXE / ATK (Mouse WebHID)
ACTION=="add", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3554", MODE="0666", GROUP="wheel"
ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="3554", MODE="0666", GROUP="wheel"
EOF
udevadm control --reload-rules && udevadm trigger'
echo "[OK] VXE/ATK udev rules applied."
