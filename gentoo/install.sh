#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Gentoo Automated Installer
#
# Target hardware:
#   AMD Ryzen 7 5700X
#   AMD Radeon RX 7600
#   Kingston KC3000 512 GB NVMe
#   16 GB RAM
#
# Installation:
#   UEFI
#   GPT
#   1 GiB EFI System Partition
#   Remaining space: ext4 /
#   amd64 multilib
#   OpenRC
#   KDE Plasma 6
#   SDDM
#   NetworkManager
#   PipeWire + WirePlumber
#   gentoo-kernel-bin
#   dracut initramfs
#   GRUB UEFI
#   8 GiB zram swap
#
# WARNING:
#   /dev/nvme0n1 WILL BE COMPLETELY ERASED.
#
# IMPORTANT:
#   This installer intentionally does NOT ask for an ERASE
#   confirmation. The target disk is fixed to /dev/nvme0n1.
#
# ============================================================

set -o errtrace

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

DISK="/dev/nvme0n1"
EFI="${DISK}p1"
ROOT="${DISK}p2"

TARGET="/mnt/gentoo"

HOSTNAME="gentoo"
USERNAME="and"

TIMEZONE="America/Sao_Paulo"
LOCALE="en_US.UTF-8"
KEYMAP="us"

CFLAGS="-O2 -pipe -march=znver3"
CXXFLAGS="${CFLAGS}"

MAKEOPTS="-j8"

STAGE_BASE="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc"

# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

msg() {
    echo
    echo "============================================================"
    echo " $*"
    echo "============================================================"
}

die() {
    echo
    echo "ERROR: $*" >&2
    exit 1
}

cleanup_on_error() {
    local status=$?

    if [[ "${status}" -ne 0 ]]; then
        echo
        echo "============================================================"
        echo "INSTALLATION STOPPED"
        echo "============================================================"
        echo
        echo "The installer stopped because a command failed."
        echo
        echo "Target root:"
        echo "  ${TARGET}"
        echo
        echo "The system has NOT been rebooted."
        echo
    fi

    exit "${status}"
}

trap cleanup_on_error EXIT

# ------------------------------------------------------------
# Basic checks
# ------------------------------------------------------------

[[ "${EUID}" -eq 0 ]] || \
    die "This installer must be run as root."

[[ -d /sys/firmware/efi ]] || \
    die "The LiveGUI was not booted in UEFI mode."

[[ -b "${DISK}" ]] || \
    die "${DISK} does not exist."

command -v lsblk >/dev/null 2>&1 || \
    die "lsblk is not available."

command -v wipefs >/dev/null 2>&1 || \
    die "wipefs is not available."

command -v sgdisk >/dev/null 2>&1 || \
    die "sgdisk is not available."

command -v partprobe >/dev/null 2>&1 || \
    die "partprobe is not available."

command -v mkfs.fat >/dev/null 2>&1 || \
    die "mkfs.fat is not available."

command -v mkfs.ext4 >/dev/null 2>&1 || \
    die "mkfs.ext4 is not available."

command -v wget >/dev/null 2>&1 || \
    die "wget is not available."

command -v sha256sum >/dev/null 2>&1 || \
    die "sha256sum is not available."

command -v tar >/dev/null 2>&1 || \
    die "tar is not available."

command -v chroot >/dev/null 2>&1 || \
    die "chroot is not available."

command -v mount >/dev/null 2>&1 || \
    die "mount is not available."

command -v umount >/dev/null 2>&1 || \
    die "umount is not available."

# ------------------------------------------------------------
# Detect target disk
# ------------------------------------------------------------

DISK_TYPE="$(lsblk -dn -o TYPE "${DISK}" | tr -d ' ')"
MODEL="$(lsblk -dn -o MODEL "${DISK}" | sed 's/^[[:space:]]*//')"
SIZE="$(lsblk -dn -o SIZE "${DISK}")"

[[ "${DISK_TYPE}" == "disk" ]] || \
    die "${DISK} does not appear to be a physical disk."

# ------------------------------------------------------------
# Installation information
# ------------------------------------------------------------

clear

echo "============================================================"
echo "              GENTOO AUTOMATED INSTALLER"
echo "============================================================"
echo
echo "TARGET DISK"
echo
echo "  Device : ${DISK}"
echo "  Model  : ${MODEL}"
echo "  Size   : ${SIZE}"
echo
echo "THE FOLLOWING PARTITION TABLE WILL BE CREATED:"
echo
echo "  ${EFI}    1 GiB       EFI System Partition"
echo "  ${ROOT}   remaining   ext4 root filesystem"
echo
echo "SYSTEM CONFIGURATION:"
echo
echo "  CPU         : AMD Ryzen 7 5700X"
echo "  GPU         : AMD Radeon RX 7600"
echo "  Architecture: amd64 multilib"
echo "  Init        : OpenRC"
echo "  Desktop     : KDE Plasma 6"
echo "  Login       : SDDM"
echo "  Kernel      : gentoo-kernel-bin"
echo "  Initramfs   : dracut"
echo "  Bootloader  : GRUB UEFI"
echo "  Swap        : 8 GiB zram"
echo "  Hostname    : ${HOSTNAME}"
echo "  User        : ${USERNAME}"
echo "  Locale      : ${LOCALE}"
echo "  Keyboard    : ${KEYMAP}"
echo "  Timezone    : ${TIMEZONE}"
echo
echo "============================================================"
echo
echo "ALL DATA ON ${DISK} WILL BE DESTROYED."
echo
echo "The Ventoy USB drive (/dev/sda) will NOT be touched."
echo
echo "Current disks:"
echo
lsblk -o NAME,SIZE,MODEL,FSTYPE,MOUNTPOINTS
echo
echo "============================================================"
echo
echo "Automatic destructive installation will continue."
echo

sleep 3

# ------------------------------------------------------------
# Password
# ------------------------------------------------------------

echo
echo "Set the initial password for user '${USERNAME}'."
echo

read -r -s -p "Password: " USER_PASSWORD
echo

read -r -s -p "Confirm password: " USER_PASSWORD_CONFIRM
echo

[[ "${USER_PASSWORD}" == "${USER_PASSWORD_CONFIRM}" ]] || \
    die "Passwords do not match."

[[ -n "${USER_PASSWORD}" ]] || \
    die "Password cannot be empty."

# ------------------------------------------------------------
# Network check
# ------------------------------------------------------------

msg "CHECKING INTERNET CONNECTION"

wget \
    --spider \
    --timeout=15 \
    --tries=3 \
    "https://distfiles.gentoo.org/" \
    >/dev/null 2>&1 || \
    die "Internet connection is not working."

echo "Internet connection OK."

# ------------------------------------------------------------
# Disable existing swap
# ------------------------------------------------------------

msg "DISABLING LIVE SYSTEM SWAP"

swapoff -a 2>/dev/null || true

# ------------------------------------------------------------
# Unmount old target partitions
# ------------------------------------------------------------

msg "UNMOUNTING OLD TARGET PARTITIONS"

umount -R "${TARGET}" 2>/dev/null || true

umount "${DISK}"p1 2>/dev/null || true
umount "${DISK}"p2 2>/dev/null || true

# ------------------------------------------------------------
# Erase existing partition table
# ------------------------------------------------------------

msg "ERASING EXISTING PARTITION TABLE"

wipefs -a "${DISK}"
sgdisk --zap-all "${DISK}"

# ------------------------------------------------------------
# Create GPT partition table
# ------------------------------------------------------------

msg "CREATING GPT PARTITION TABLE"

sgdisk \
    --clear \
    --mbrtogpt \
    --new=1:0:+1G \
    --typecode=1:ef00 \
    --change-name=1:"EFI System Partition" \
    --new=2:0:0 \
    --typecode=2:8300 \
    --change-name=2:"Gentoo Root" \
    "${DISK}"

partprobe "${DISK}"

sleep 5

udevadm settle 2>/dev/null || true

[[ -b "${EFI}" ]] || \
    die "EFI partition was not created."

[[ -b "${ROOT}" ]] || \
    die "Root partition was not created."

# ------------------------------------------------------------
# Format filesystems
# ------------------------------------------------------------

msg "FORMATTING EFI PARTITION"

mkfs.fat \
    -F 32 \
    -n EFI \
    "${EFI}"

msg "FORMATTING ROOT PARTITION"

mkfs.ext4 \
    -F \
    -L gentoo-root \
    "${ROOT}"

# ------------------------------------------------------------
# Mount target
# ------------------------------------------------------------

msg "MOUNTING TARGET FILESYSTEM"

mkdir -p "${TARGET}"

mount "${ROOT}" "${TARGET}"

mkdir -p "${TARGET}/efi"

mount "${EFI}" "${TARGET}/efi"

mountpoint -q "${TARGET}" || \
    die "Root filesystem is not mounted."

mountpoint -q "${TARGET}/efi" || \
    die "EFI filesystem is not mounted."

# ------------------------------------------------------------
# Download Stage 3
# ------------------------------------------------------------

msg "FINDING LATEST AMD64 OPENRC STAGE 3"

STAGE_INDEX="${STAGE_BASE}/latest-stage3-amd64-openrc.txt"

STAGE_FILE="$(
    wget \
        -qO- \
        "${STAGE_INDEX}" |
    awk '
        !/^#/ &&
        /stage3-amd64-openrc-.*\.tar\.xz$/ {
            print $1
            exit
        }
    '
)"

[[ -n "${STAGE_FILE}" ]] || \
    die "Could not determine the latest Stage 3 archive."

echo
echo "Selected Stage 3:"
echo "  ${STAGE_FILE}"
echo

cd "${TARGET}"

wget \
    -c \
    "${STAGE_BASE}/${STAGE_FILE}"

wget \
    -c \
    "${STAGE_BASE}/${STAGE_FILE}.sha256"

# ------------------------------------------------------------
# Verify Stage 3 checksum
# ------------------------------------------------------------

msg "VERIFYING STAGE 3 CHECKSUM"

(
    cd "${TARGET}"

    sha256sum \
        -c \
        "${STAGE_FILE}.sha256"
)

# ------------------------------------------------------------
# Extract Stage 3
# ------------------------------------------------------------

msg "EXTRACTING STAGE 3"

tar \
    xpvf \
    "${TARGET}/${STAGE_FILE}" \
    --xattrs-include='*.*' \
    --numeric-owner

rm -f \
    "${TARGET}/${STAGE_FILE}" \
    "${TARGET}/${STAGE_FILE}.sha256"

# ------------------------------------------------------------
# DNS
# ------------------------------------------------------------

msg "CONFIGURING DNS"

if [[ -e /etc/resolv.conf ]]; then
    cp \
        --dereference \
        /etc/resolv.conf \
        "${TARGET}/etc/resolv.conf"
else
    cat > "${TARGET}/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
fi

# ------------------------------------------------------------
# Generate fstab
# ------------------------------------------------------------

msg "GENERATING FSTAB"

ROOT_UUID="$(blkid -s UUID -o value "${ROOT}")"
EFI_UUID="$(blkid -s UUID -o value "${EFI}")"

[[ -n "${ROOT_UUID}" ]] || \
    die "Could not determine root filesystem UUID."

[[ -n "${EFI_UUID}" ]] || \
    die "Could not determine EFI filesystem UUID."

cat > "${TARGET}/etc/fstab" <<EOF
# Gentoo root filesystem
UUID=${ROOT_UUID}    /       ext4    noatime,errors=remount-ro    0 1

# EFI System Partition
UUID=${EFI_UUID}     /efi    vfat    umask=0077                   0 2
EOF

# ------------------------------------------------------------
# Prepare virtual filesystems
# ------------------------------------------------------------

msg "MOUNTING VIRTUAL FILESYSTEMS"

mkdir -p \
    "${TARGET}/proc" \
    "${TARGET}/sys" \
    "${TARGET}/dev" \
    "${TARGET}/run"

mountpoint -q "${TARGET}/proc" || \
    mount \
        --types proc \
        /proc \
        "${TARGET}/proc"

mountpoint -q "${TARGET}/sys" || {
    mount \
        --rbind \
        /sys \
        "${TARGET}/sys"

    mount \
        --make-rslave \
        "${TARGET}/sys"
}

mountpoint -q "${TARGET}/dev" || {
    mount \
        --rbind \
        /dev \
        "${TARGET}/dev"

    mount \
        --make-rslave \
        "${TARGET}/dev"
}

mountpoint -q "${TARGET}/run" || {
    mount \
        --rbind \
        /run \
        "${TARGET}/run"

    mount \
        --make-rslave \
        "${TARGET}/run"
}

# ------------------------------------------------------------
# DNS after Stage 3 extraction
# ------------------------------------------------------------

msg "FINALIZING CHROOT DNS"

if [[ -e /etc/resolv.conf ]]; then
    cp \
        --dereference \
        /etc/resolv.conf \
        "${TARGET}/etc/resolv.conf"
else
    cat > "${TARGET}/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
fi

# ------------------------------------------------------------
# Export installation variables
# ------------------------------------------------------------

export GENTOO_HOSTNAME="${HOSTNAME}"
export GENTOO_USERNAME="${USERNAME}"
export GENTOO_PASSWORD="${USER_PASSWORD}"
export GENTOO_TIMEZONE="${TIMEZONE}"
export GENTOO_LOCALE="${LOCALE}"
export GENTOO_KEYMAP="${KEYMAP}"
export GENTOO_CFLAGS="${CFLAGS}"
export GENTOO_CXXFLAGS="${CXXFLAGS}"
export GENTOO_MAKEOPTS="${MAKEOPTS}"

# ------------------------------------------------------------
# Create chroot installer
# ------------------------------------------------------------

msg "PREPARING CHROOT INSTALLER"

cat > "${TARGET}/root/install-inside-gentoo.sh" <<'CHROOT_SCRIPT'
#!/usr/bin/env bash

set -Eeuo pipefail
set -o errtrace

# ============================================================
# Gentoo Installation Inside Chroot
# ============================================================

HOSTNAME="${GENTOO_HOSTNAME}"
USERNAME="${GENTOO_USERNAME}"
USER_PASSWORD="${GENTOO_PASSWORD}"

TIMEZONE="${GENTOO_TIMEZONE}"
LOCALE="${GENTOO_LOCALE}"
KEYMAP="${GENTOO_KEYMAP}"

CFLAGS="${GENTOO_CFLAGS}"
CXXFLAGS="${GENTOO_CXXFLAGS}"
MAKEOPTS="${GENTOO_MAKEOPTS}"

# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

msg() {
    echo
    echo "============================================================"
    echo " $*"
    echo "============================================================"
}

die() {
    echo
    echo "ERROR: $*" >&2
    exit 1
}

# ------------------------------------------------------------
# Basic checks
# ------------------------------------------------------------

[[ "${EUID}" -eq 0 ]] || \
    die "This installer must run as root."

[[ -d /sys/firmware/efi ]] || \
    die "UEFI firmware interface is not available inside the chroot."

[[ -d /efi ]] || \
    die "/efi does not exist."

mountpoint -q /efi || \
    die "/efi is not mounted."

command -v emerge >/dev/null 2>&1 || \
    die "emerge is not available in the Stage 3."

command -v eselect >/dev/null 2>&1 || \
    die "eselect is not available in the Stage 3."

# ------------------------------------------------------------
# Portage directories
# ------------------------------------------------------------

msg "CONFIGURING PORTAGE"

mkdir -p \
    /etc/portage \
    /etc/portage/package.use \
    /etc/portage/package.license \
    /etc/portage/repos.conf

# ------------------------------------------------------------
# Configure Portage
# ------------------------------------------------------------

cat > /etc/portage/make.conf <<EOF
COMMON_FLAGS="${CFLAGS}"

CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

MAKEOPTS="${MAKEOPTS}"

ABI_X86="64 32"

VIDEO_CARDS="amdgpu radeonsi"

INPUT_DEVICES="libinput"

GRUB_PLATFORMS="efi-64"

L10N="en-US"
LINGUAS="en"

ACCEPT_LICENSE="-* @FREE @BINARY-REDISTRIBUTABLE"
EOF

# ------------------------------------------------------------
# Configure binary kernel installation
# ------------------------------------------------------------

cat > /etc/portage/package.use/installkernel <<'EOF'
sys-kernel/installkernel dracut grub
EOF

# ------------------------------------------------------------
# Configure firmware license
# ------------------------------------------------------------

cat > /etc/portage/package.license/firmware <<'EOF'
sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE
EOF

# ------------------------------------------------------------
# Configure desktop USE flags
# ------------------------------------------------------------

cat > /etc/portage/package.use/desktop <<'EOF'
kde-plasma/plasma-meta sddm wayland xwayland
net-misc/networkmanager elogind wifi
media-video/pipewire sound-server pipewire-alsa pipewire-pulse
media-video/wireplumber
x11-misc/sddm wayland
EOF

# ------------------------------------------------------------
# Configure repository
# ------------------------------------------------------------

msg "CONFIGURING GENTOO REPOSITORY"

mkdir -p /etc/portage/repos.conf

if [[ ! -f /etc/portage/repos.conf/gentoo.conf ]]; then
    cat > /etc/portage/repos.conf/gentoo.conf <<'EOF'
[DEFAULT]
main-repo = gentoo

[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
sync-openpgp-key-path = /usr/share/openpgp-keys/gentoo-release.asc
sync-openpgp-key-refresh-retry-count = 3
sync-openpgp-key-refresh-retry-delay = 10
EOF
fi

mkdir -p /var/db/repos/gentoo

# ------------------------------------------------------------
# Synchronize repository
# ------------------------------------------------------------

msg "SYNCHRONIZING GENTOO REPOSITORY"

emerge --sync

[[ -d /var/db/repos/gentoo/profiles ]] || \
    die "Gentoo repository was not created after repository synchronization."

[[ -f /var/db/repos/gentoo/profiles/categories ]] || \
    die "Gentoo repository is incomplete."

# ------------------------------------------------------------
# Select AMD64 23.0 Plasma profile
# ------------------------------------------------------------

msg "SELECTING AMD64 23.0 PLASMA OPENRC PROFILE"

PROFILE_TARGET="default/linux/amd64/23.0/desktop/plasma"

PROFILE_INDEX="$(
    eselect profile list |
    awk -v target="${PROFILE_TARGET}" '
        index($0, target) &&
        $0 !~ /systemd/ &&
        $0 !~ /nomultilib/ {
            line=$0
            sub(/^[[:space:]]*\[[[:space:]]*/, "", line)
            sub(/\].*$/, "", line)
            print line
            exit
        }
    '
)"

if [[ -z "${PROFILE_INDEX}" ]]; then
    echo
    echo "Available AMD64 23.0 Plasma profiles:"
    echo
    eselect profile list |
        grep -E 'amd64/23\.0.*plasma' ||
        true
    echo
    die "Could not locate the AMD64 23.0 Plasma profile."
fi

echo
echo "Selected profile index:"
echo "  ${PROFILE_INDEX}"
echo

eselect profile set "${PROFILE_INDEX}"

PROFILE_LINK="$(readlink -f /etc/portage/make.profile)"

echo
echo "Selected profile:"
echo "  ${PROFILE_LINK}"

[[ "${PROFILE_LINK}" == *"/amd64/23.0/desktop/plasma" ]] || \
    die "The selected profile is not the AMD64 23.0 Plasma profile."

[[ "${PROFILE_LINK}" != *"/systemd/"* ]] || \
    die "The selected profile uses systemd."

[[ "${PROFILE_LINK}" != *"/nomultilib/"* ]] || \
    die "The selected profile is nomultilib."

# ------------------------------------------------------------
# Reassert multilib configuration
# ------------------------------------------------------------

msg "CONFIGURING AMD64 MULTILIB"

grep -q '^ABI_X86="64 32"$' /etc/portage/make.conf || \
    die "ABI_X86 configuration is missing."

ABI_X86_CURRENT="$(
    emerge --info |
    sed -n 's/^ABI_X86="\([^"]*\)".*/\1/p'
)"

if [[ -z "${ABI_X86_CURRENT}" ]]; then
    echo
    echo "Portage did not report ABI_X86."
    echo
    echo "Current Portage configuration:"
    emerge --info |
        grep -E '^(CHOST|ARCH|ACCEPT_KEYWORDS|ABI_X86|USE)=' ||
        true
    echo
    die "ABI_X86 could not be detected."
fi

echo "ABI_X86=${ABI_X86_CURRENT}"

echo "${ABI_X86_CURRENT}" | grep -qw "64" || \
    die "ABI_X86=64 is not enabled."

echo "${ABI_X86_CURRENT}" | grep -qw "32" || \
    die "ABI_X86=32 is not enabled."

# ------------------------------------------------------------
# Install required kernel build infrastructure
# ------------------------------------------------------------

msg "INSTALLING KERNEL INSTALLATION TOOLS"

emerge \
    --ask=n \
    sys-kernel/installkernel \
    sys-kernel/dracut

# ------------------------------------------------------------
# Update base system
# ------------------------------------------------------------

msg "UPDATING BASE SYSTEM"

emerge \
    --ask=n \
    --verbose \
    --update \
    --deep \
    --newuse \
    --with-bdeps=y \
    @world

# ------------------------------------------------------------
# Locale
# ------------------------------------------------------------

msg "CONFIGURING LOCALE"

cat > /etc/locale.gen <<'EOF'
en_US.UTF-8 UTF-8
EOF

locale-gen

eselect locale set en_US.utf8

# ------------------------------------------------------------
# Timezone
# ------------------------------------------------------------

msg "CONFIGURING TIMEZONE"

[[ -e "/usr/share/zoneinfo/${TIMEZONE}" ]] || \
    die "Invalid timezone: ${TIMEZONE}"

ln -sf \
    "/usr/share/zoneinfo/${TIMEZONE}" \
    /etc/localtime

echo "${TIMEZONE}" > /etc/timezone

# ------------------------------------------------------------
# Keyboard
# ------------------------------------------------------------

msg "CONFIGURING KEYBOARD"

cat > /etc/conf.d/keymaps <<EOF
keymap="${KEYMAP}"
EOF

# ------------------------------------------------------------
# Hostname
# ------------------------------------------------------------

msg "CONFIGURING HOSTNAME"

echo "${HOSTNAME}" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1       localhost
::1             localhost
127.0.1.1       ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# ------------------------------------------------------------
# Kernel and firmware
# ------------------------------------------------------------

msg "INSTALLING KERNEL AND FIRMWARE"

emerge \
    --ask=n \
    sys-kernel/gentoo-kernel-bin \
    sys-kernel/linux-firmware

# ------------------------------------------------------------
# KDE Plasma
# ------------------------------------------------------------

msg "INSTALLING KDE PLASMA"

emerge \
    --ask=n \
    kde-plasma/plasma-meta

# ------------------------------------------------------------
# KDE applications
# ------------------------------------------------------------

msg "INSTALLING KDE APPLICATIONS"

emerge \
    --ask=n \
    kde-apps/dolphin \
    kde-apps/konsole \
    kde-apps/ark

# ------------------------------------------------------------
# System utilities
# ------------------------------------------------------------

msg "INSTALLING SYSTEM UTILITIES"

emerge \
    --ask=n \
    app-admin/sudo \
    app-editors/nano \
    app-portage/gentoolkit \
    app-portage/eix \
    sys-apps/pciutils \
    sys-apps/usbutils \
    sys-process/htop

# ------------------------------------------------------------
# NetworkManager
# ------------------------------------------------------------

msg "CONFIGURING NETWORKMANAGER"

emerge \
    --ask=n \
    net-misc/networkmanager

rc-update add NetworkManager default

# ------------------------------------------------------------
# D-Bus
# ------------------------------------------------------------

msg "CONFIGURING D-BUS"

emerge \
    --ask=n \
    sys-apps/dbus

rc-update add dbus default

# ------------------------------------------------------------
# elogind
# ------------------------------------------------------------

msg "CONFIGURING ELOGIND"

emerge \
    --ask=n \
    sys-auth/elogind

rc-update add elogind boot

# ------------------------------------------------------------
# SDDM
# ------------------------------------------------------------

msg "CONFIGURING SDDM"

emerge \
    --ask=n \
    x11-misc/sddm \
    gui-libs/display-manager-init

cat > /etc/conf.d/display-manager <<'EOF'
DISPLAYMANAGER="sddm"
EOF

rc-update add display-manager default

# ------------------------------------------------------------
# PipeWire
# ------------------------------------------------------------

msg "CONFIGURING PIPEWIRE AUDIO"

emerge \
    --ask=n \
    media-video/pipewire \
    media-video/wireplumber

# ------------------------------------------------------------
# AMD GPU
# ------------------------------------------------------------

msg "CONFIGURING AMD GPU"

mkdir -p /etc/modprobe.d

cat > /etc/modprobe.d/amdgpu.conf <<'EOF'
# AMD Radeon RX 7600
options amdgpu dc=1
EOF

# ------------------------------------------------------------
# ZRAM
# ------------------------------------------------------------

msg "CONFIGURING 8 GIB ZRAM SWAP"

emerge \
    --ask=n \
    sys-apps/util-linux

cat > /etc/init.d/zram-swap <<'EOF'
#!/sbin/openrc-run

description="Compressed zram swap"

depend() {
    need localmount
    after bootmisc
}

start_pre() {
    modprobe zram num_devices=1

    if [ ! -b /dev/zram0 ]; then
        eerror "/dev/zram0 was not created"
        return 1
    fi

    zramctl --reset /dev/zram0 2>/dev/null || true

    if [ -e /sys/block/zram0/comp_algorithm ]; then
        if grep -qw zstd /sys/block/zram0/comp_algorithm; then
            echo zstd > /sys/block/zram0/comp_algorithm
        fi
    fi

    echo 8589934592 > /sys/block/zram0/disksize

    mkswap \
        -L zram0 \
        /dev/zram0 \
        >/dev/null
}

start() {
    ebegin "Enabling 8 GiB zram swap"

    swapon \
        --priority 100 \
        /dev/zram0

    eend $?
}

stop() {
    ebegin "Disabling zram swap"

    swapoff \
        /dev/zram0 \
        2>/dev/null || true

    zramctl \
        --reset \
        /dev/zram0 \
        2>/dev/null || true

    eend 0
}
EOF

chmod +x /etc/init.d/zram-swap

rc-update add zram-swap default

# ------------------------------------------------------------
# GRUB
# ------------------------------------------------------------

msg "INSTALLING GRUB"

emerge \
    --ask=n \
    sys-boot/grub \
    sys-boot/efibootmgr

[[ -d /sys/firmware/efi ]] || \
    die "UEFI firmware interface is unavailable."

mountpoint -q /efi || \
    die "/efi is not mounted."

mkdir -p /boot/grub

grub-install \
    --target=x86_64-efi \
    --efi-directory=/efi \
    --bootloader-id=Gentoo \
    --recheck

grub-mkconfig \
    -o /boot/grub/grub.cfg

# ------------------------------------------------------------
# User account
# ------------------------------------------------------------

msg "CREATING USER ACCOUNT"

if id "${USERNAME}" >/dev/null 2>&1; then
    usermod \
        --shell /bin/bash \
        --groups wheel,audio,video,input \
        "${USERNAME}"
else
    useradd \
        --create-home \
        --shell /bin/bash \
        --groups wheel,audio,video,input \
        "${USERNAME}"
fi

printf '%s\n' \
    "${USERNAME}:${USER_PASSWORD}" |
    chpasswd

printf '%s\n' \
    "root:${USER_PASSWORD}" |
    chpasswd

# ------------------------------------------------------------
# Sudo
# ------------------------------------------------------------

msg "CONFIGURING SUDO"

mkdir -p /etc/sudoers.d

cat > /etc/sudoers.d/wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF

chmod 440 /etc/sudoers.d/wheel

visudo -c

# ------------------------------------------------------------
# Final world update
# ------------------------------------------------------------

msg "RUNNING FINAL SYSTEM UPDATE"

emerge \
    --ask=n \
    --update \
    --deep \
    --newuse \
    --with-bdeps=y \
    @world

# ------------------------------------------------------------
# Regenerate kernel initramfs if necessary
# ------------------------------------------------------------

msg "VERIFYING KERNEL INSTALLATION"

KERNEL_COUNT="$(
    find /boot \
        -maxdepth 1 \
        -type f \
        -name 'vmlinuz-*' |
    wc -l
)"

[[ "${KERNEL_COUNT}" -gt 0 ]] || \
    die "No kernel image was found in /boot."

# ------------------------------------------------------------
# Regenerate GRUB
# ------------------------------------------------------------

msg "REGENERATING GRUB CONFIGURATION"

grub-mkconfig \
    -o /boot/grub/grub.cfg

[[ -s /boot/grub/grub.cfg ]] || \
    die "GRUB configuration was not generated."

# ------------------------------------------------------------
# Verify initramfs
# ------------------------------------------------------------

msg "VERIFYING INITRAMFS"

INITRAMFS_COUNT="$(
    find /boot \
        -maxdepth 1 \
        -type f \
        \( \
            -name 'initramfs-*' \
            -o \
            -name 'initramfs' \
        \) |
    wc -l
)"

if [[ "${INITRAMFS_COUNT}" -eq 0 ]]; then
    echo
    echo "No initramfs image was detected."
    echo "Running dracut manually."

    KERNEL_VERSION="$(
        ls \
            /lib/modules |
        sort -V |
        tail -n 1
    )"

    [[ -n "${KERNEL_VERSION}" ]] || \
        die "Could not determine installed kernel version."

    dracut \
        --kver "${KERNEL_VERSION}" \
        --force

    INITRAMFS_COUNT="$(
        find /boot \
            -maxdepth 1 \
            -type f \
            \( \
                -name 'initramfs-*' \
                -o \
                -name 'initramfs' \
            \) |
        wc -l
    )
fi

[[ "${INITRAMFS_COUNT}" -gt 0 ]] || \
    die "No initramfs was found in /boot."

# ------------------------------------------------------------
# Verify GRUB
# ------------------------------------------------------------

msg "VERIFYING GRUB"

[[ -s /boot/grub/grub.cfg ]] || \
    die "GRUB configuration is missing."

grep -q "linux" /boot/grub/grub.cfg || \
    die "GRUB configuration does not contain a Linux entry."

# ------------------------------------------------------------
# Verify services
# ------------------------------------------------------------

msg "VERIFYING OPENRC SERVICES"

rc-update show

rc-update show |
    grep -q 'NetworkManager' ||
    die "NetworkManager is not enabled."

rc-update show |
    grep -q 'dbus' ||
    die "D-Bus is not enabled."

rc-update show |
    grep -q 'elogind' ||
    die "elogind is not enabled."

rc-update show |
    grep -q 'display-manager' ||
    die "display-manager is not enabled."

rc-update show |
    grep -q 'zram-swap' ||
    die "zram-swap is not enabled."

# ------------------------------------------------------------
# Verify multilib
# ------------------------------------------------------------

msg "VERIFYING MULTILIB CONFIGURATION"

FINAL_PROFILE="$(readlink -f /etc/portage/make.profile)"

echo
echo "Profile:"
echo "  ${FINAL_PROFILE}"

[[ "${FINAL_PROFILE}" == *"/amd64/23.0/desktop/plasma" ]] || \
    die "Final profile is incorrect."

[[ "${FINAL_PROFILE}" != *"/systemd/"* ]] || \
    die "Final profile uses systemd."

[[ "${FINAL_PROFILE}" != *"/nomultilib/"* ]] || \
    die "Final profile is nomultilib."

ABI_X86_FINAL="$(
    emerge --info |
    sed -n 's/^ABI_X86="\([^"]*\)".*/\1/p'
)"

echo
echo "ABI_X86=${ABI_X86_FINAL}"

[[ -n "${ABI_X86_FINAL}" ]] || \
    die "Final ABI_X86 could not be detected."

echo "${ABI_X86_FINAL}" |
    grep -qw "64" ||
    die "Final ABI_X86 does not contain 64."

echo "${ABI_X86_FINAL}" |
    grep -qw "32" ||
    die "Final ABI_X86 does not contain 32."

# ------------------------------------------------------------
# Final command checks
# ------------------------------------------------------------

msg "FINAL INSTALLATION CHECK"

command -v grub-install >/dev/null 2>&1 ||
    die "grub-install is missing."

command -v grub-mkconfig >/dev/null 2>&1 ||
    die "grub-mkconfig is missing."

command -v sudo >/dev/null 2>&1 ||
    die "sudo is missing."

command -v sddm >/dev/null 2>&1 ||
    die "sddm is missing."

command -v NetworkManager >/dev/null 2>&1 ||
    die "NetworkManager is missing."

command -v zramctl >/dev/null 2>&1 ||
    die "zramctl is missing."

command -v dracut >/dev/null 2>&1 ||
    die "dracut is missing."

id "${USERNAME}" >/dev/null 2>&1 ||
    die "The user account was not created."

# ------------------------------------------------------------
# Final report
# ------------------------------------------------------------

echo
echo "============================================================"
echo "              INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Hostname       : ${HOSTNAME}"
echo "User           : ${USERNAME}"
echo "Profile        : ${FINAL_PROFILE}"
echo "Desktop        : KDE Plasma 6"
echo "Login          : SDDM"
echo "Init           : OpenRC"
echo "Network        : NetworkManager"
echo "Audio          : PipeWire + WirePlumber"
echo "Kernel         : gentoo-kernel-bin"
echo "Initramfs      : dracut"
echo "GPU            : AMD Radeon RX 7600"
echo "Architecture   : amd64 multilib"
echo "ABI_X86        : ${ABI_X86_FINAL}"
echo "Swap           : 8 GiB zram"
echo
echo "Kernel images:"
ls -lh /boot/vmlinuz-* 2>/dev/null || true

echo
echo "Initramfs images:"
ls -lh /boot/initramfs-* 2>/dev/null || true

echo
echo "GRUB:"
ls -lh /boot/grub/grub.cfg

echo
echo "EFI files:"
find /efi/EFI \
    -maxdepth 3 \
    -type f \
    2>/dev/null || true

echo
echo "User:"
id "${USERNAME}"

echo
echo "Root filesystem:"
df -h /

echo
echo "ZRAM:"
zramctl 2>/dev/null || true

echo
echo "Enabled services:"
rc-update show

echo
echo "============================================================"
echo "Installation finished successfully."
echo "The system is ready to reboot."
echo "============================================================"

# ------------------------------------------------------------
# Remove sensitive variables and installer
# ------------------------------------------------------------

unset USER_PASSWORD
unset GENTOO_PASSWORD

rm -f /root/install-inside-gentoo.sh

exit 0
CHROOT_SCRIPT

chmod 700 "${TARGET}/root/install-inside-gentoo.sh"

# ------------------------------------------------------------
# Run chroot installer
# ------------------------------------------------------------

msg "STARTING GENTOO INSTALLATION"

chroot \
    "${TARGET}" \
    /usr/bin/env \
    -i \
    HOME=/root \
    TERM="${TERM:-xterm}" \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    GENTOO_HOSTNAME="${GENTOO_HOSTNAME}" \
    GENTOO_USERNAME="${GENTOO_USERNAME}" \
    GENTOO_PASSWORD="${GENTOO_PASSWORD}" \
    GENTOO_TIMEZONE="${GENTOO_TIMEZONE}" \
    GENTOO_LOCALE="${GENTOO_LOCALE}" \
    GENTOO_KEYMAP="${GENTOO_KEYMAP}" \
    GENTOO_CFLAGS="${GENTOO_CFLAGS}" \
    GENTOO_CXXFLAGS="${GENTOO_CXXFLAGS}" \
    GENTOO_MAKEOPTS="${GENTOO_MAKEOPTS}" \
    /bin/bash \
    /root/install-inside-gentoo.sh

# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------

msg "FINAL CLEANUP"

rm -f \
    "${TARGET}/root/install-inside-gentoo.sh"

unset USER_PASSWORD
unset USER_PASSWORD_CONFIRM
unset GENTOO_PASSWORD

sync

echo
echo "============================================================"
echo "          GENTOO INSTALLATION FINISHED"
echo "============================================================"
echo
echo "The system has been installed on:"
echo
echo "    ${DISK}"
echo
echo "Next steps:"
echo
echo "    umount -R ${TARGET}"
echo "    sync"
echo "    reboot"
echo
echo "Remove the LiveGUI USB drive when the machine restarts."
echo
echo "============================================================"

trap - EXIT

exit 0
