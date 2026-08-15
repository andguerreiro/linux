#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# CONFIGURATION
# ============================================================

DISK="/dev/nvme0n1"

HOSTNAME="archlinux"
USERNAME="and"

TIMEZONE="America/Sao_Paulo"
LOCALE="en_US.UTF-8"
KEYMAP="us"

# ============================================================
# FUNCTIONS
# ============================================================

die() {
    echo
    echo "ERROR: $1"
    exit 1
}

msg() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

# ============================================================
# PRE-INSTALLATION CHECKS
# ============================================================

[[ $EUID -eq 0 ]] || die "Run this script as root."

[[ -d /sys/firmware/efi/efivars ]] \
    || die "The system was not booted in UEFI mode."

[[ -b "$DISK" ]] \
    || die "Disk $DISK was not found."

echo
echo "SELECTED DISK: $DISK"
echo
lsblk "$DISK"
echo

read -rp \
    "WARNING! ALL DATA ON $DISK WILL BE ERASED. Type ERASE to continue: " \
    CONFIRM

[[ "$CONFIRM" == "ERASE" ]] \
    || die "Operation cancelled."

# ============================================================
# INTERNET AND TIME SYNCHRONIZATION
# ============================================================

msg "Checking internet connection"

ping -c 3 archlinux.org >/dev/null \
    || die "No internet connection."

timedatectl set-ntp true

# ============================================================
# ENABLE MULTILIB
# ============================================================

msg "Enabling multilib repository"

sed -i \
    '/^\[multilib\]/,/^Include/ s/^#//' \
    /etc/pacman.conf

# ============================================================
# PARTITIONING
# ============================================================

msg "Partitioning $DISK"

umount -R /mnt 2>/dev/null || true

sgdisk --zap-all "$DISK"

# ------------------------------------------------------------
# EFI SYSTEM PARTITION - 1 GiB
# ------------------------------------------------------------

sgdisk \
    -n 1:0:+1G \
    -t 1:ef00 \
    -c 1:"EFI System" \
    "$DISK"

# ------------------------------------------------------------
# ROOT PARTITION - 48 GiB
# ------------------------------------------------------------

sgdisk \
    -n 2:0:+48G \
    -t 2:8300 \
    -c 2:"Arch Linux root" \
    "$DISK"

# ------------------------------------------------------------
# HOME PARTITION - REMAINING SPACE
# ------------------------------------------------------------

sgdisk \
    -n 3:0:0 \
    -t 3:8300 \
    -c 3:"Arch Linux home" \
    "$DISK"

partprobe "$DISK"

if [[ "$DISK" == *"nvme"* ]]; then
    EFI="${DISK}p1"
    ROOT="${DISK}p2"
    HOME="${DISK}p3"
else
    EFI="${DISK}1"
    ROOT="${DISK}2"
    HOME="${DISK}3"
fi

echo
echo "EFI : $EFI"
echo "ROOT: $ROOT"
echo "HOME: $HOME"
echo

# ============================================================
# FORMATTING
# ============================================================

msg "Formatting partitions"

mkfs.fat -F32 "$EFI"
mkfs.ext4 -F "$ROOT"
mkfs.ext4 -F "$HOME"

# ============================================================
# MOUNTING
# ============================================================

msg "Mounting filesystems"

mount "$ROOT" /mnt

# Mount the EFI System Partition directly at /boot.
mkdir -p /mnt/boot
mount "$EFI" /mnt/boot

# Mount the separate home partition.
mkdir -p /mnt/home
mount "$HOME" /mnt/home

# ============================================================
# INSTALL BASE SYSTEM
# ============================================================

msg "Installing base system"

pacstrap -K /mnt \
    base \
    linux \
    linux-firmware-amdgpu \
    linux-firmware-mediatek \
    linux-firmware-realtek \
    amd-ucode \
    sudo \
    nano \
    networkmanager \
    iwd \
    mesa \
    vulkan-radeon \
    lib32-mesa \
    lib32-vulkan-radeon \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    wireplumber \
    power-profiles-daemon \
    zram-generator \
    plasma-meta \
    sddm \
    firefox \
    alacritty \
    dolphin \
    kate \
    ark \
    gwenview \
    kcalc \
    okular \
    unrar \
    zip \
    unzip

# ============================================================
# GENERATE FSTAB
# ============================================================

msg "Generating fstab"

genfstab -U /mnt >> /mnt/etc/fstab

# ============================================================
# SYSTEM CONFIGURATION
# ============================================================

msg "Configuring installed system"

arch-chroot -S /mnt /bin/bash <<EOF

set -e

# ============================================================
# TIMEZONE
# ============================================================

ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime

hwclock --systohc

# ============================================================
# LOCALE
# ============================================================

sed -i 's/^#${LOCALE}/${LOCALE}/' /etc/locale.gen

locale-gen

cat > /etc/locale.conf <<LOCALE
LANG=${LOCALE}
LOCALE

# ============================================================
# CONSOLE KEYBOARD
# ============================================================

cat > /etc/vconsole.conf <<KEYMAP
KEYMAP=${KEYMAP}
KEYMAP

# ============================================================
# HOSTNAME
# ============================================================

echo "${HOSTNAME}" > /etc/hostname

cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

# ============================================================
# INITRAMFS
# ============================================================

mkinitcpio -P

# ============================================================
# SYSTEMD-BOOT
# ============================================================

bootctl install

mkdir -p /boot/loader/entries

cat > /boot/loader/loader.conf <<LOADER
default arch.conf
timeout 0
console-mode max
editor no
LOADER

# ============================================================
# SYSTEMD-BOOT KERNEL ENTRY
# ============================================================

ROOT_UUID=\$(blkid -s UUID -o value "${ROOT}")

cat > /boot/loader/entries/arch.conf <<ENTRY
title   Arch Linux
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options root=UUID=\${ROOT_UUID} rw
ENTRY

# ============================================================
# NETWORKMANAGER + IWD
# ============================================================

mkdir -p /etc/NetworkManager/conf.d

cat > /etc/NetworkManager/conf.d/wifi_backend.conf <<NETWORK
[device]
wifi.backend=iwd
NETWORK

systemctl enable NetworkManager

# Do not enable iwd.service.
# NetworkManager manages iwd when configured as the Wi-Fi backend.

# ============================================================
# SDDM
# ============================================================

systemctl enable sddm

# ============================================================
# POWER PROFILES DAEMON
# ============================================================

systemctl enable power-profiles-daemon

# ============================================================
# ZRAM
# ============================================================

mkdir -p /etc/systemd/zram-generator.conf.d

cat > /etc/systemd/zram-generator.conf.d/zram.conf <<ZRAM
[zram0]
zram-size = 4096
compression-algorithm = zstd
fs-type = swap
swap-priority = 100
ZRAM

# zram-generator creates the zram swap automatically through systemd.
# No service enable command is required.

# ============================================================
# USER ACCOUNT
# ============================================================

useradd \
    -m \
    -G wheel \
    -s /bin/bash \
    "${USERNAME}"

echo
echo "Set the password for user ${USERNAME}:"
passwd "${USERNAME}"

# ============================================================
# SUDO
# ============================================================

cat > /etc/sudoers.d/10-wheel <<SUDO
%wheel ALL=(ALL:ALL) ALL
SUDO

chmod 440 /etc/sudoers.d/10-wheel

# ============================================================
# REMOVE KDE BLUETOOTH SUPPORT
# ============================================================

# plasma-meta currently depends on bluedevil.
# Bluetooth support is deliberately removed.

pacman -Rdd --noconfirm \
    bluedevil \
    bluez-qt \
    bluez

# ============================================================
# REMOVE DISCOVER
# ============================================================

# plasma-meta currently depends on discover.
# Discover is deliberately removed.

pacman -Rdd --noconfirm discover

EOF

# ============================================================
# FINAL STATUS
# ============================================================

msg "Installation completed successfully"

echo
echo "Installed configuration:"
echo
echo "  Hostname   : archlinux"
echo "  User       : and"
echo "  CPU        : Ryzen 7 5700X"
echo "  GPU        : Radeon RX 7600 / amdgpu + Mesa + RADV"
echo "  Kernel     : linux"
echo "  Microcode  : amd-ucode"
echo "  Bootloader : systemd-boot"
echo "  Root       : ext4 (~48 GiB)"
echo "  Home       : separate ext4 partition"
echo "  ZRAM       : 4 GiB / zstd"
echo "  Desktop    : KDE Plasma"
echo "  Session    : Wayland"
echo "  Display    : SDDM"
echo "  Audio      : PipeWire + WirePlumber"
echo "  Network    : NetworkManager + iwd"
echo "  Wi-Fi      : MediaTek MT7612U / mt76"
echo "  Locale     : en_US.UTF-8"
echo "  Keyboard   : us"
echo "  Timezone   : America/Sao_Paulo"
echo "  Multilib   : enabled"
echo "  Bluetooth  : removed"
echo "  Discover   : removed"
echo
echo "Remove the installation media and reboot:"
echo
