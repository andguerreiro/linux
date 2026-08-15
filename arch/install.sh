#!/usr/bin/env bash

set -Eeuo pipefail
set -o errtrace

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
# HELPERS
# ============================================================

msg() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

error_handler() {
    local code=$?
    echo
    echo "============================================================"
    echo "INSTALLATION FAILED"
    echo "Exit code : $code"
    echo "Line      : ${BASH_LINENO[0]}"
    echo "Command   : ${BASH_COMMAND}"
    echo "============================================================"
    exit "$code"
}

trap error_handler ERR


# ============================================================
# CHECKS
# ============================================================

[[ $EUID -eq 0 ]] || die "Run this script as root."
[[ -d /sys/firmware/efi/efivars ]] || die "UEFI boot required."
[[ -b "$DISK" ]] || die "Disk not found: $DISK"

for cmd in \
    awk blkid bootctl genfstab grep lsblk \
    mkfs.ext4 mkfs.fat mount pacman pacstrap \
    partprobe sed sgdisk timedatectl umount \
    udevadm wipefs
do
    command -v "$cmd" >/dev/null || die "Missing command: $cmd"
done


# ============================================================
# WARNING
# ============================================================

msg "TARGET DISK"

lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS "$DISK"

echo
echo "WARNING: $DISK WILL BE COMPLETELY ERASED."
echo

sleep 2


# ============================================================
# PREPARE INSTALLATION ENVIRONMENT
# ============================================================

timedatectl set-ntp true || true

swapoff -a 2>/dev/null || true

umount -R /mnt 2>/dev/null || true
mkdir -p /mnt


# ============================================================
# MULTILIB
# ============================================================

msg "Enabling multilib"

if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    cat >> /etc/pacman.conf <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
else
    sed -i \
        '/^\[multilib\]/,/^Include/ s/^#//' \
        /etc/pacman.conf
fi

pacman -Sy --noconfirm


# ============================================================
# PARTITION DISK
# ============================================================

msg "Partitioning $DISK"

wipefs -af "$DISK"
sgdisk --zap-all "$DISK"
sgdisk --clear "$DISK"

sgdisk \
    --new=1:1MiB:+1GiB \
    --typecode=1:EF00 \
    --change-name=1:"EFI System" \
    "$DISK"

sgdisk \
    --new=2:0:${ROOT_SIZE} \
    --typecode=2:8300 \
    --change-name=2:"Arch Linux root" \
    "$DISK"

sgdisk \
    --largest-new=3 \
    --typecode=3:8300 \
    --change-name=3:"Arch Linux home" \
    "$DISK"

partprobe "$DISK"
udevadm settle


if [[ "$DISK" == *nvme* || "$DISK" == *mmcblk* ]]; then
    EFI="${DISK}p1"
    ROOT="${DISK}p2"
    HOME="${DISK}p3"
else
    EFI="${DISK}1"
    ROOT="${DISK}2"
    HOME="${DISK}3"
fi

[[ -b "$EFI" ]] || die "EFI partition missing."
[[ -b "$ROOT" ]] || die "ROOT partition missing."
[[ -b "$HOME" ]] || die "HOME partition missing."


# ============================================================
# FORMAT
# ============================================================

msg "Formatting partitions"

mkfs.fat -F32 "$EFI"
mkfs.ext4 -F "$ROOT"
mkfs.ext4 -F "$HOME"


# ============================================================
# MOUNT
# ============================================================

msg "Mounting filesystems"

mount "$ROOT" /mnt

mkdir -p /mnt/boot /mnt/home

mount "$EFI" /mnt/boot
mount "$HOME" /mnt/home


# ============================================================
# INSTALL SYSTEM
# ============================================================

msg "Installing Arch Linux"

pacstrap -K /mnt \
    base \
    linux \
    linux-firmware-amdgpu \
    linux-firmware-realtek \
    linux-firmware-mediatek \
    amd-ucode \
    sudo \
    nano \
    networkmanager \
    iwd \
    mesa \
    vulkan-radeon \
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
    sddm-kcm \
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
# FSTAB
# ============================================================

msg "Generating fstab"

genfstab -U /mnt > /mnt/etc/fstab

ROOT_UUID="$(blkid -s UUID -o value "$ROOT")"

[[ -n "$ROOT_UUID" ]] || die "Could not determine root UUID."


# ============================================================
# CHROOT CONFIGURATION
# ============================================================

msg "Configuring installed system"

cat > /mnt/root/configure.sh <<EOF
#!/usr/bin/env bash

set -Eeuo pipefail

HOSTNAME='$HOSTNAME'
USERNAME='$USERNAME'
USER_PASS='$USER_PASS'
TIMEZONE='$TIMEZONE'
LOCALE='$LOCALE'
KEYMAP='$KEYMAP'
ROOT_UUID='$ROOT_UUID'


# ------------------------------------------------------------
# Basic system configuration
# ------------------------------------------------------------

ln -sf "/usr/share/zoneinfo/\$TIMEZONE" /etc/localtime
hwclock --systohc

sed -i "s/^#\$LOCALE/\$LOCALE/" /etc/locale.gen
locale-gen

printf 'LANG=%s\n' "\$LOCALE" > /etc/locale.conf
printf 'KEYMAP=%s\n' "\$KEYMAP" > /etc/vconsole.conf

printf '%s\n' "\$HOSTNAME" > /etc/hostname

cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   \$HOSTNAME.localdomain \$HOSTNAME
HOSTS


# ------------------------------------------------------------
# NetworkManager + iwd
# ------------------------------------------------------------

mkdir -p /etc/NetworkManager/conf.d

cat > /etc/NetworkManager/conf.d/wifi_backend.conf <<NET
[device]
wifi.backend=iwd
NET

systemctl enable NetworkManager


# ------------------------------------------------------------
# SDDM
# ------------------------------------------------------------

systemctl enable sddm


# ------------------------------------------------------------
# Power profiles
# ------------------------------------------------------------

systemctl enable power-profiles-daemon


# ------------------------------------------------------------
# ZRAM
# ------------------------------------------------------------

mkdir -p /etc/systemd/zram-generator.conf.d

cat > /etc/systemd/zram-generator.conf.d/zram.conf <<ZRAM
[zram0]
zram-size = 4096
compression-algorithm = zstd
fs-type = swap
swap-priority = 100
ZRAM


# ------------------------------------------------------------
# User
# ------------------------------------------------------------

useradd \
    --create-home \
    --groups wheel \
    --shell /bin/bash \
    "\$USERNAME"

echo "\$USERNAME:\$USER_PASS" | chpasswd

cat > /etc/sudoers.d/10-wheel <<SUDO
%wheel ALL=(ALL:ALL) ALL
SUDO

chmod 440 /etc/sudoers.d/10-wheel
visudo -cf /etc/sudoers.d/10-wheel

passwd -l root


# ------------------------------------------------------------
# systemd-boot
# ------------------------------------------------------------

bootctl --esp-path=/boot install

mkdir -p /boot/loader/entries

cat > /boot/loader/loader.conf <<LOADER
default arch.conf
timeout 0
console-mode max
editor no
LOADER

cat > /boot/loader/entries/arch.conf <<ENTRY
title   Arch Linux
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options root=UUID=\$ROOT_UUID rw
ENTRY


# ------------------------------------------------------------
# Initramfs
# ------------------------------------------------------------

mkinitcpio -P


# ------------------------------------------------------------
# Final update
# ------------------------------------------------------------

pacman -Syu --noconfirm

mkinitcpio -P


# ------------------------------------------------------------
# Validation
# ------------------------------------------------------------

test -f /etc/fstab
test -f /boot/loader/loader.conf
test -f /boot/loader/entries/arch.conf
test -f /boot/vmlinuz-linux
test -f /boot/initramfs-linux.img
test -f /boot/amd-ucode.img

id "\$USERNAME" >/dev/null
id -nG "\$USERNAME" | grep -qw wheel
passwd -S root | grep -q ' L '


# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------

rm -f /root/configure.sh

EOF

chmod +x /mnt/root/configure.sh

arch-chroot /mnt /root/configure.sh


# ============================================================
# FINAL VALIDATION
# ============================================================

msg "Final validation"

for file in \
    /mnt/etc/fstab \
    /mnt/boot/loader/loader.conf \
    /mnt/boot/loader/entries/arch.conf \
    /mnt/boot/vmlinuz-linux \
    /mnt/boot/initramfs-linux.img \
    /mnt/boot/amd-ucode.img
do
    [[ -f "$file" ]] || die "Missing: $file"
done


# ============================================================
# FINISH
# ============================================================

sync

echo
echo "============================================================"
echo "       ARCH LINUX INSTALLATION COMPLETED"
echo "============================================================"
echo
echo "Disk       : $DISK"
echo "Hostname   : $HOSTNAME"
echo "User       : $USERNAME"
echo "Root       : LOCKED"
echo
echo "CPU        : AMD Ryzen 7 5700X"
echo "GPU        : Radeon RX 7600"
echo
echo "Desktop    : KDE Plasma"
echo "Session    : Wayland"
echo "Display    : SDDM"
echo "Audio      : PipeWire + WirePlumber"
echo "Network    : NetworkManager + iwd"
echo "ZRAM       : 4 GiB / zstd"
echo "Bootloader : systemd-boot"
echo "Root       : ext4 (~48 GiB)"
echo "Home       : ext4 (remaining space)"
echo "Multilib   : enabled"
echo
echo "Discover   : not explicitly installed"
echo "Bluetooth  : not explicitly installed"
echo "CUPS       : not installed"
echo
echo "============================================================"
echo "Unmounting /mnt"
echo "============================================================"

umount -R /mnt

echo
echo "DONE. You can reboot."
echo
