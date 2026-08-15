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

for cmd in \
    sgdisk \
    wipefs \
    partprobe \
    mkfs.fat \
    mkfs.ext4 \
    mount \
    umount \
    pacstrap \
    genfstab \
    arch-chroot \
    bootctl
do
    command -v "$cmd" >/dev/null 2>&1 \
        || die "Required command not found: $cmd"
done

echo
echo "SELECTED DISK: $DISK"
echo
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS "$DISK"
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

# Make absolutely sure nothing from a previous installation is mounted.
swapoff -a 2>/dev/null || true
umount -R /mnt 2>/dev/null || true

# Unmount anything belonging to the selected disk.
while read -r mountpoint; do
    [[ -n "$mountpoint" ]] || continue
    umount "$mountpoint" 2>/dev/null || true
done < <(
    lsblk -nrpo MOUNTPOINT "$DISK" 2>/dev/null |
    grep -v '^$' |
    sort -r
)

# Remove old filesystem signatures.
wipefs -af "$DISK"

# Remove existing GPT/MBR partition structures.
sgdisk --zap-all "$DISK"

# Create a fresh GPT.
sgdisk --clear "$DISK"

# ------------------------------------------------------------
# EFI SYSTEM PARTITION - 1 GiB
# ------------------------------------------------------------

sgdisk \
    --new=1:1MiB:+1GiB \
    --typecode=1:ef00 \
    --change-name=1:"EFI System" \
    "$DISK"

# ------------------------------------------------------------
# ROOT PARTITION - 48 GiB
# ------------------------------------------------------------

sgdisk \
    --new=2:0:+48GiB \
    --typecode=2:8300 \
    --change-name=2:"Arch Linux root" \
    "$DISK"

# ------------------------------------------------------------
# HOME PARTITION - REMAINING SPACE
# ------------------------------------------------------------

sgdisk \
    --largest-new=3 \
    --typecode=3:8300 \
    --change-name=3:"Arch Linux home" \
    "$DISK"

# Tell the kernel to reread the partition table.
partprobe "$DISK" || true

# Give udev time to create the partition devices.
udevadm settle

# ------------------------------------------------------------
# DETERMINE PARTITION NAMES
# ------------------------------------------------------------

if [[ "$DISK" == *nvme* || "$DISK" == *mmcblk* ]]; then
    EFI="${DISK}p1"
    ROOT="${DISK}p2"
    HOME="${DISK}p3"
else
    EFI="${DISK}1"
    ROOT="${DISK}2"
    HOME="${DISK}3"
fi

# Verify that all partitions actually exist.
[[ -b "$EFI" ]] \
    || die "EFI partition was not created: $EFI"

[[ -b "$ROOT" ]] \
    || die "ROOT partition was not created: $ROOT"

[[ -b "$HOME" ]] \
    || die "HOME partition was not created: $HOME"

echo
echo "Created partitions:"
echo
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS "$DISK"
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

mkdir -p /mnt/boot
mount "$EFI" /mnt/boot

mkdir -p /mnt/home
mount "$HOME" /mnt/home

# ============================================================
# INSTALL BASE SYSTEM
# ============================================================

msg "Installing base system"

pacstrap -K /mnt \
    base \
    linux \
    linux-firmware \
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

genfstab -U /mnt > /mnt/etc/fstab

# ============================================================
# SYSTEM CONFIGURATION
# ============================================================

msg "Configuring installed system"

arch-chroot /mnt /bin/bash <<EOF

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

[[ -n "\${ROOT_UUID}" ]] \
    || { echo "ERROR: Could not determine ROOT UUID."; exit 1; }

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

# NetworkManager manages iwd as the Wi-Fi backend.
# iwd.service does not need to be enabled separately.

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

# zram-generator creates the zram swap automatically.

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

pacman -Rdd --noconfirm \
    bluedevil \
    bluez-qt \
    bluez || true

# ============================================================
# REMOVE DISCOVER
# ============================================================

pacman -Rdd --noconfirm \
    discover || true

EOF

# ============================================================
# FINAL STATUS
# ============================================================

msg "Installation completed successfully"

echo
echo "Installed configuration:"
echo
echo "  Hostname   : ${HOSTNAME}"
echo "  User       : ${USERNAME}"
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
echo "  Locale     : ${LOCALE}"
echo "  Keyboard   : ${KEYMAP}"
echo "  Timezone   : ${TIMEZONE}"
echo "  Multilib   : enabled"
echo "  Bluetooth  : removed"
echo "  Discover   : removed"
echo
echo "Done. Reboot."
echo
