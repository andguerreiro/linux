#!/bin/bash
set -e

echo "=== openSUSE Leap 16 post-install (UEFI + RTX 4070) ==="

### 1. System update
echo ">> Refreshing repositories and updating system..."
zypper refresh
zypper update -y

### 2. GRUB configuration (timeout zero)
echo ">> Configuring GRUB..."

GRUB_FILE="/etc/default/grub"

# Create a safety backup
cp "$GRUB_FILE" "${GRUB_FILE}.bak"

# Set GRUB timeout to zero
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' "$GRUB_FILE"
grep -q "^GRUB_TIMEOUT=" "$GRUB_FILE" || echo "GRUB_TIMEOUT=0" >> "$GRUB_FILE"

# Ensure nouveau is blacklisted
if ! grep -q "rd.driver.blacklist=nouveau" "$GRUB_FILE"; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="rd.driver.blacklist=nouveau /' "$GRUB_FILE"
fi

# Regenerate GRUB configuration (UEFI)
echo ">> Regenerating GRUB (UEFI)..."
grub2-mkconfig -o /boot/efi/EFI/opensuse/grub.cfg

### 3. NVIDIA repository setup
echo ">> Setting up NVIDIA repository..."

if ! zypper lr | grep -qi nvidia; then
    zypper ar -f https://download.nvidia.com/opensuse/leap/16.0/ nvidia || \
    zypper ar -f https://download.nvidia.com/opensuse/leap/15.6/ nvidia
fi

zypper refresh

### 4. Install NVIDIA proprietary driver (G06)
echo ">> Installing NVIDIA proprietary driver (G06)..."
zypper install -y nvidia-driver-G06 nvidia-compute-G06 nvidia-gl-G06

### 5. Rebuild initramfs
echo ">> Rebuilding initramfs..."
mkinitrd

echo
echo "=== Completed successfully ==="
echo "Reboot the system to apply changes."
