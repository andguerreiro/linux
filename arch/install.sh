#!/usr/bin/env bash

set -Eeuo pipefail
set -o errtrace

# ============================================================
# ARCH LINUX AUTOMATED INSTALLER
# ============================================================
#
# WARNING:
# This script will COMPLETELY ERASE the disk configured below.
#
# NO confirmation is requested.
#
# Target hardware:
#   CPU        : AMD Ryzen 7 5700X
#   GPU        : Radeon RX 7600
#
# System:
#   Desktop    : KDE Plasma
#   Session    : Wayland
#   Display    : SDDM
#   Bootloader : systemd-boot
#   Root       : ext4 ~48 GiB
#   Home       : ext4 remaining space
#   Swap       : ZRAM 4 GiB
#   Network    : NetworkManager + iwd
#   Audio      : PipeWire + WirePlumber
#   GPU stack  : Mesa + RADV
#   Multilib   : enabled
#
# Users:
#   and        : only normal user, sudo access
#   root       : account locked
#
# ============================================================


# ============================================================
# CONFIGURATION
# ============================================================

DISK="/dev/nvme0n1"

HOSTNAME="archlinux"
USERNAME="and"
USER_PASS="100tempo"

TIMEZONE="America/Sao_Paulo"
LOCALE="en_US.UTF-8"
KEYMAP="us"

ROOT_SIZE="+48GiB"


# ============================================================
# FUNCTIONS
# ============================================================

msg() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

die() {
    echo
    echo "============================================================"
    echo "ERROR: $*"
    echo "============================================================"
    exit 1
}

error_handler() {
    local exit_code=$?
    echo
    echo "============================================================"
    echo "INSTALLATION FAILED"
    echo "============================================================"
    echo "Exit code : ${exit_code}"
    echo "Line      : ${BASH_LINENO[0]}"
    echo "Command   : ${BASH_COMMAND}"
    echo "============================================================"
    exit "${exit_code}"
}

trap error_handler ERR


# ============================================================
# PRE-INSTALLATION CHECKS
# ============================================================

msg "Checking installation environment"

[[ $EUID -eq 0 ]] \
    || die "This installer must be run as root."

[[ -d /sys/firmware/efi/efivars ]] \
    || die "The system was not booted in UEFI mode."

[[ -b "$DISK" ]] \
    || die "Disk not found: $DISK"


# ============================================================
# REQUIRED COMMANDS
# ============================================================

for cmd in \
    awk \
    blkid \
    bootctl \
    genfstab \
    grep \
    lsblk \
    mkfs.ext4 \
    mkfs.fat \
    mount \
    pacman \
    pacstrap \
    partprobe \
    sed \
    sgdisk \
    timedatectl \
    umount \
    udevadm \
    wipefs
do
    command -v "$cmd" >/dev/null 2>&1 \
        || die "Required command not found: $cmd"
done


# ============================================================
# DISPLAY TARGET
# ============================================================

echo
echo "============================================================"
echo "TARGET DISK"
echo "============================================================"
echo

lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS "$DISK"

echo
echo "The disk above WILL BE COMPLETELY ERASED."
echo "No confirmation will be requested."
echo

sleep 2


# ============================================================
# TIME SYNCHRONIZATION
# ============================================================

msg "Synchronizing system clock"

timedatectl set-ntp true || true


# ============================================================
# ENABLE MULTILIB
# ============================================================

msg "Enabling multilib repository"

if grep -q '^\[multilib\]' /etc/pacman.conf; then

    sed -i \
        '/^\[multilib\]/,/^#Include/ s/^#//' \
        /etc/pacman.conf

else

    cat >> /etc/pacman.conf <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF

fi


# ============================================================
# DISABLE SWAP
# ============================================================

msg "Disabling existing swap"

swapoff -a 2>/dev/null || true


# ============================================================
# UNMOUNT /mnt
# ============================================================

msg "Unmounting existing /mnt"

if mountpoint -q /mnt; then
    umount -R /mnt || true
fi

mkdir -p /mnt


# ============================================================
# UNMOUNT TARGET DISK
# ============================================================

msg "Unmounting partitions from target disk"

while read -r mountpoint; do

    [[ -n "$mountpoint" ]] || continue

    umount "$mountpoint" 2>/dev/null || true

done < <(
    lsblk -nrpo MOUNTPOINT "$DISK" 2>/dev/null |
    awk 'NF' |
    sort -r
)


# ============================================================
# ERASE DISK
# ============================================================

msg "ERASING $DISK"

wipefs -af "$DISK"

sgdisk --zap-all "$DISK"

sgdisk --clear "$DISK"


# ============================================================
# CREATE GPT
# ============================================================

msg "Creating GPT partition table"

#
# Partition 1:
# EFI System Partition
# 1 GiB
#

sgdisk \
    --new=1:1MiB:+1GiB \
    --typecode=1:EF00 \
    --change-name=1:"EFI System" \
    "$DISK"


#
# Partition 2:
# Root
# ~48 GiB
#

sgdisk \
    --new=2:0:${ROOT_SIZE} \
    --typecode=2:8300 \
    --change-name=2:"Arch Linux root" \
    "$DISK"


#
# Partition 3:
# Home
# Remaining disk space
#

sgdisk \
    --largest-new=3 \
    --typecode=3:8300 \
    --change-name=3:"Arch Linux home" \
    "$DISK"


# ============================================================
# REREAD PARTITION TABLE
# ============================================================

msg "Refreshing partition table"

partprobe "$DISK" || true

udevadm settle

sleep 2


# ============================================================
# DETERMINE PARTITION NAMES
# ============================================================

if [[ "$DISK" == *nvme* || "$DISK" == *mmcblk* ]]; then

    EFI="${DISK}p1"
    ROOT="${DISK}p2"
    HOME="${DISK}p3"

else

    EFI="${DISK}1"
    ROOT="${DISK}2"
    HOME="${DISK}3"

fi


# ============================================================
# VERIFY PARTITIONS
# ============================================================

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
# FORMAT PARTITIONS
# ============================================================

msg "Formatting partitions"

mkfs.fat \
    -F32 \
    "$EFI"

mkfs.ext4 \
    -F \
    "$ROOT"

mkfs.ext4 \
    -F \
    "$HOME"


# ============================================================
# MOUNT ROOT
# ============================================================

msg "Mounting root filesystem"

mount "$ROOT" /mnt


# ============================================================
# MOUNT EFI
# ============================================================

msg "Mounting EFI filesystem"

mkdir -p /mnt/boot

mount "$EFI" /mnt/boot


# ============================================================
# MOUNT HOME
# ============================================================

msg "Mounting home filesystem"

mkdir -p /mnt/home

mount "$HOME" /mnt/home


# ============================================================
# INSTALL BASE SYSTEM
# ============================================================

msg "Installing Arch Linux"

pacstrap -K /mnt \
    base \
    linux \
    linux-firmware \
    amd-ucode \
    sudo \
    nano \
    vim \
    networkmanager \
    iwd \
    mesa \
    lib32-mesa \
    vulkan-radeon \
    lib32-vulkan-radeon \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    wireplumber \
    power-profiles-daemon \
    zram-generator \
    plasma-desktop \
    plasma-nm \
    plasma-pa \
    sddm \
    xdg-desktop-portal \
    xdg-desktop-portal-kde \
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
# GET ROOT UUID
# ============================================================

ROOT_UUID="$(blkid -s UUID -o value "$ROOT")"

[[ -n "$ROOT_UUID" ]] \
    || die "Could not determine ROOT UUID."


# ============================================================
# GET EFI UUID
# ============================================================

EFI_UUID="$(blkid -s UUID -o value "$EFI")"

[[ -n "$EFI_UUID" ]] \
    || die "Could not determine EFI UUID."


# ============================================================
# WRITE INSTALL VARIABLES
# ============================================================

cat > /mnt/root/install-vars <<EOF
HOSTNAME='${HOSTNAME}'
USERNAME='${USERNAME}'
USER_PASS='${USER_PASS}'
TIMEZONE='${TIMEZONE}'
LOCALE='${LOCALE}'
KEYMAP='${KEYMAP}'
ROOT_UUID='${ROOT_UUID}'
EFI_UUID='${EFI_UUID}'
EOF


# ============================================================
# CREATE CHROOT CONFIGURATION SCRIPT
# ============================================================

cat > /mnt/root/configure-system.sh <<'CHROOT'
#!/usr/bin/env bash

set -Eeuo pipefail

source /root/install-vars


# ============================================================
# FUNCTIONS
# ============================================================

msg() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

die() {
    echo
    echo "ERROR: $*"
    exit 1
}


# ============================================================
# TIMEZONE
# ============================================================

msg "Configuring timezone"

ln -sf \
    "/usr/share/zoneinfo/${TIMEZONE}" \
    /etc/localtime

hwclock --systohc


# ============================================================
# LOCALE
# ============================================================

msg "Configuring locale"

sed -i \
    "s/^#${LOCALE}/${LOCALE}/" \
    /etc/locale.gen

locale-gen

cat > /etc/locale.conf <<EOF
LANG=${LOCALE}
EOF


# ============================================================
# KEYBOARD
# ============================================================

msg "Configuring keyboard"

cat > /etc/vconsole.conf <<EOF
KEYMAP=${KEYMAP}
EOF


# ============================================================
# HOSTNAME
# ============================================================

msg "Configuring hostname"

printf '%s\n' "$HOSTNAME" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF


# ============================================================
# INITRAMFS
# ============================================================

msg "Generating initramfs"

mkinitcpio -P


# ============================================================
# SYSTEMD-BOOT
# ============================================================

msg "Installing systemd-boot"

bootctl \
    --esp-path=/boot \
    install


# ============================================================
# SYSTEMD-BOOT CONFIGURATION
# ============================================================

mkdir -p /boot/loader/entries

cat > /boot/loader/loader.conf <<EOF
default arch.conf
timeout 0
console-mode max
editor no
EOF


# ============================================================
# ARCH KERNEL ENTRY
# ============================================================

cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options root=UUID=${ROOT_UUID} rw
EOF


# ============================================================
# NETWORKMANAGER
# ============================================================

msg "Configuring NetworkManager"

mkdir -p /etc/NetworkManager/conf.d

cat > /etc/NetworkManager/conf.d/wifi_backend.conf <<EOF
[device]
wifi.backend=iwd
EOF

systemctl enable NetworkManager


# ============================================================
# IWD
# ============================================================

#
# NetworkManager uses iwd as its Wi-Fi backend.
#
# iwd.service is intentionally NOT enabled separately.
#


# ============================================================
# SDDM
# ============================================================

msg "Enabling SDDM"

systemctl enable sddm


# ============================================================
# POWER PROFILES
# ============================================================

msg "Enabling power-profiles-daemon"

systemctl enable power-profiles-daemon


# ============================================================
# ZRAM
# ============================================================

msg "Configuring ZRAM"

mkdir -p /etc/systemd/zram-generator.conf.d

cat > /etc/systemd/zram-generator.conf.d/zram.conf <<EOF
[zram0]
zram-size = 4096
compression-algorithm = zstd
fs-type = swap
swap-priority = 100
EOF


# ============================================================
# USER ACCOUNT
# ============================================================

msg "Creating user: ${USERNAME}"

if id "$USERNAME" >/dev/null 2>&1; then

    echo "User ${USERNAME} already exists."

else

    useradd \
        --create-home \
        --groups wheel \
        --shell /bin/bash \
        "$USERNAME"

fi


# ============================================================
# USER PASSWORD
# ============================================================

msg "Setting password for user: ${USERNAME}"

echo "${USERNAME}:${USER_PASS}" | chpasswd


# ============================================================
# SUDO
# ============================================================

msg "Configuring sudo"

cat > /etc/sudoers.d/10-wheel <<EOF
%wheel ALL=(ALL:ALL) ALL
EOF

chmod 440 /etc/sudoers.d/10-wheel

visudo -cf /etc/sudoers.d/10-wheel


# ============================================================
# ROOT ACCOUNT
# ============================================================

msg "Locking root account"

#
# root remains part of the operating system, as required by
# Linux, but its login/password authentication is disabled.
#
# The user "and" uses sudo for administrative operations.
#

passwd -l root


# ============================================================
# BLUETOOTH
# ============================================================

msg "Ensuring Bluetooth is not installed"

#
# We intentionally use plasma-desktop instead of plasma-meta.
#
# Therefore Bluetooth packages such as:
#
#   bluez
#   bluez-qt
#   bluedevil
#
# are not explicitly installed.
#

if pacman -Q bluez >/dev/null 2>&1; then
    pacman -Rns --noconfirm bluez
fi

if pacman -Q bluedevil >/dev/null 2>&1; then
    pacman -Rns --noconfirm bluedevil
fi


# ============================================================
# DISCOVER
# ============================================================

msg "Ensuring Discover is not installed"

if pacman -Q discover >/dev/null 2>&1; then
    pacman -Rns --noconfirm discover
fi


# ============================================================
# KDE / WAYLAND
# ============================================================

msg "Checking KDE Wayland session"

if [[ ! -d /usr/share/wayland-sessions ]]; then
    die "Wayland session directory does not exist."
fi


# ============================================================
# FINAL SYSTEM UPDATE
# ============================================================

msg "Updating installed system"

pacman -Syu --noconfirm


# ============================================================
# REBUILD INITRAMFS
# ============================================================

msg "Rebuilding initramfs"

mkinitcpio -P


# ============================================================
# FINAL VALIDATION
# ============================================================

msg "Validating installation"

[[ -f /etc/fstab ]] \
    || die "fstab is missing."

[[ -f /boot/loader/loader.conf ]] \
    || die "systemd-boot loader.conf is missing."

[[ -f /boot/loader/entries/arch.conf ]] \
    || die "systemd-boot Arch entry is missing."

[[ -f /boot/vmlinuz-linux ]] \
    || die "Linux kernel is missing."

[[ -f /boot/initramfs-linux.img ]] \
    || die "Linux initramfs is missing."

[[ -f /boot/amd-ucode.img ]] \
    || die "AMD microcode image is missing."

id "$USERNAME" >/dev/null 2>&1 \
    || die "User $USERNAME does not exist."

id -nG "$USERNAME" | grep -qw wheel \
    || die "User $USERNAME is not a member of wheel."

passwd -S root | grep -q ' L ' \
    || die "Root account is not locked."


# ============================================================
# CLEANUP
# ============================================================

rm -f /root/install-vars
rm -f /root/configure-system.sh

msg "System configuration completed"

CHROOT


# ============================================================
# MAKE CHROOT SCRIPT EXECUTABLE
# ============================================================

chmod +x /mnt/root/configure-system.sh


# ============================================================
# ENTER INSTALLED SYSTEM
# ============================================================

msg "Configuring installed system"

arch-chroot /mnt /root/configure-system.sh


# ============================================================
# FINAL HOST-SIDE VALIDATION
# ============================================================

msg "Running final validation"

[[ -f /mnt/etc/fstab ]] \
    || die "Final validation failed: fstab missing."

[[ -f /mnt/boot/loader/entries/arch.conf ]] \
    || die "Final validation failed: boot entry missing."

[[ -f /mnt/boot/vmlinuz-linux ]] \
    || die "Final validation failed: kernel missing."

[[ -f /mnt/boot/initramfs-linux.img ]] \
    || die "Final validation failed: initramfs missing."

[[ -f /mnt/boot/amd-ucode.img ]] \
    || die "Final validation failed: AMD microcode missing."


# ============================================================
# SYNC
# ============================================================

msg "Syncing filesystems"

sync


# ============================================================
# SHOW FINAL CONFIGURATION
# ============================================================

echo
echo "============================================================"
echo "       ARCH LINUX INSTALLATION COMPLETED"
echo "============================================================"
echo
echo "Disk       : ${DISK}"
echo
echo "Hostname   : ${HOSTNAME}"
echo "User       : ${USERNAME}"
echo "Root       : LOCKED"
echo
echo "CPU        : AMD Ryzen 7 5700X"
echo "GPU        : Radeon RX 7600"
echo
echo "Kernel     : linux"
echo "Microcode  : amd-ucode"
echo "GPU stack  : Mesa + RADV"
echo
echo "Bootloader : systemd-boot"
echo "Root       : ext4 (~48 GiB)"
echo "Home       : ext4 (remaining space)"
echo
echo "Desktop    : KDE Plasma"
echo "Session    : Wayland"
echo "Display    : SDDM"
echo
echo "Audio      : PipeWire + WirePlumber"
echo "Network    : NetworkManager + iwd"
echo "ZRAM       : 4 GiB / zstd"
echo
echo "Locale     : ${LOCALE}"
echo "Keyboard   : ${KEYMAP}"
echo "Timezone   : ${TIMEZONE}"
echo "Multilib   : enabled"
echo
echo "Bluetooth  : disabled / not installed"
echo "Discover   : not installed"
echo
echo "User       : ${USERNAME}"
echo "Sudo       : enabled"
echo "Root login : LOCKED"
echo
echo "============================================================"
echo "Unmounting /mnt..."
echo "============================================================"
echo

umount -R /mnt

echo
echo "============================================================"
echo "DONE"
echo "============================================================"
echo
echo "You can now reboot."
echo
