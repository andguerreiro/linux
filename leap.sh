#!/bin/bash
set -e

echo "=== openSUSE Leap 16 post-install (UEFI + AMD RX 7600 + Audiophile Tweak) ==="

### 1. System update
echo ">> Refreshing repositories and updating system..."
zypper refresh
zypper up -y

### 2. GRUB configuration (timeout zero)
echo ">> Configuring GRUB..."

GRUB_FILE="/etc/default/grub"

# Set GRUB timeout to zero
if grep -q "^GRUB_TIMEOUT=" "$GRUB_FILE"; then
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' "$GRUB_FILE"
else
    echo "GRUB_TIMEOUT=0" >> "$GRUB_FILE"
fi

# Regenerate GRUB configuration (UEFI)
echo ">> Regenerating GRUB (UEFI)..."
grub2-mkconfig -o /boot/efi/EFI/opensuse/grub.cfg

### 3. Rebuild initramfs
echo ">> Rebuilding initramfs..."
mkinitrd

### 4. PipeWire Audiophile Setup (44.1kHz for IE 100 Pro)
echo ">> Configuring PipeWire for Bit-Perfect 44.1kHz (Deezer FLAC)..."

PW_CONF_DIR="/etc/pipewire/pipewire.conf.d"

# Create system-wide config directory if it doesn't exist
mkdir -p "$PW_CONF_DIR"

# Create the config file to allow native 44.1kHz and 48kHz without resampling
cat <<EOF > "$PW_CONF_DIR/custom-rates.conf"
context.properties = {
    default.clock.rate = 44100
    default.clock.allowed-rates = [ 44100 48000 ]
}
EOF

echo ">> Audio configuration applied to $PW_CONF_DIR/custom-rates.conf"

echo
echo "=== Completed successfully ==="
echo "Reboot the system to apply GRUB and Audio tweaks."
