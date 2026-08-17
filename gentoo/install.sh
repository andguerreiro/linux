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
#   This script intentionally does NOT ask for an ERASE
#   confirmation. The configured target disk is wiped
#   automatically.
#
# ============================================================

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

PROFILE_TARGET="default/linux/amd64/23.0/desktop/plasma"

# Correct GPT partition type GUIDs
EFI_PARTTYPE_GUID="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
ROOT_PARTTYPE_GUID="0fc63daf-8483-4772-8e79-3d69d8477de4"

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

cleanup_on_exit() {
    local status=$?

    if [[ ${status} -ne 0 ]]; then
        echo
        echo "============================================================"
        echo "              INSTALLATION STOPPED"
        echo "============================================================"
        echo
        echo "The installer stopped because an operation failed."
        echo
        echo "Target root:"
        echo "  ${TARGET}"
        echo
        echo "The system has NOT been rebooted."
        echo
    fi

    exit "${status}"
}

trap cleanup_on_exit EXIT

# ------------------------------------------------------------
# Basic checks
# ------------------------------------------------------------

[[ "${EUID}" -eq 0 ]] || \
    die "This installer must be run as root."

[[ -d /sys/firmware/efi ]] || \
    die "The LiveGUI was not booted in UEFI mode."

[[ -b "${DISK}" ]] || \
    die "${DISK} does not exist."

command -v sgdisk >/dev/null 2>&1 || \
    die "sgdisk is not available."

command -v mkfs.fat >/dev/null 2>&1 || \
    die "mkfs.fat is not available."

command -v mkfs.ext4 >/dev/null 2>&1 || \
    die "mkfs.ext4 is not available."

command -v wget >/dev/null 2>&1 || \
    die "wget is not available."

command -v sha256sum >/dev/null 2>&1 || \
    die "sha256sum is not available."

command -v chroot >/dev/null 2>&1 || \
    die "chroot is not available."

command -v lsblk >/dev/null 2>&1 || \
    die "lsblk is not available."

command -v blkid >/dev/null 2>&1 || \
    die "blkid is not available."

command -v wipefs >/dev/null 2>&1 || \
    die "wipefs is not available."

command -v partprobe >/dev/null 2>&1 || \
    die "partprobe is not available."

command -v udevadm >/dev/null 2>&1 || \
    die "udevadm is not available."

# ------------------------------------------------------------
# Detect target disk
# ------------------------------------------------------------

DISK_TYPE="$(lsblk -dn -o TYPE "${DISK}" | tr -d ' ')"
MODEL="$(lsblk -dn -o MODEL "${DISK}" | sed 's/^[[:space:]]*//')"
SERIAL="$(lsblk -dn -o SERIAL "${DISK}" | sed 's/^[[:space:]]*//')"
SIZE="$(lsblk -dn -o SIZE "${DISK}")"

[[ "${DISK_TYPE}" == "disk" ]] || \
    die "${DISK} does not appear to be a physical disk."

# ------------------------------------------------------------
# Display installation information
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
echo "  Serial : ${SERIAL}"
echo "  Size   : ${SIZE}"
echo
echo "PARTITION LAYOUT"
echo
echo "  ${EFI}"
echo "      1 GiB"
echo "      EFI System Partition"
echo
echo "  ${ROOT}"
echo "      remaining space"
echo "      ext4 root filesystem"
echo
echo "SYSTEM"
echo
echo "  CPU         : AMD Ryzen 7 5700X"
echo "  GPU         : AMD Radeon RX 7600"
echo "  Architecture: amd64 multilib"
echo "  Init        : OpenRC"
echo "  Profile     : ${PROFILE_TARGET}"
echo "  Desktop     : KDE Plasma 6"
echo "  Login       : SDDM"
echo "  Network     : NetworkManager"
echo "  Audio       : PipeWire + WirePlumber"
echo "  Kernel      : gentoo-kernel-bin"
echo "  Initramfs   : Dracut"
echo "  Bootloader  : GRUB UEFI"
echo "  Swap        : 8 GiB zram"
echo
echo "  Hostname    : ${HOSTNAME}"
echo "  User        : ${USERNAME}"
echo "  Locale      : ${LOCALE}"
echo "  Keyboard    : ${KEYMAP}"
echo "  Timezone    : ${TIMEZONE}"
echo
echo "============================================================"
echo
echo "!!! ALL DATA ON ${DISK} WILL BE DESTROYED !!!"
echo
echo "Current storage configuration:"
echo
lsblk -o NAME,PATH,SIZE,MODEL,FSTYPE,PARTTYPE,MOUNTPOINTS
echo
echo "============================================================"
echo

sleep 3

# ------------------------------------------------------------
# Password
# ------------------------------------------------------------

msg "CONFIGURING INITIAL PASSWORD"

echo "Set the initial password for '${USERNAME}'."
echo "The same password will initially be assigned to root."
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
    --quiet \
    --spider \
    --timeout=15 \
    --tries=3 \
    "https://distfiles.gentoo.org/" || \
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

msg "UNMOUNTING EXISTING TARGET"

umount -R "${TARGET}" 2>/dev/null || true

# Only unmount partitions belonging to the selected disk.
umount "${DISK}"* 2>/dev/null || true

# ------------------------------------------------------------
# Erase existing partition table
# ------------------------------------------------------------

msg "WIPING TARGET DISK"

wipefs -af "${DISK}"
sgdisk --zap-all "${DISK}"

# ------------------------------------------------------------
# Create GPT partition table
# ------------------------------------------------------------

msg "CREATING GPT PARTITION TABLE"

sgdisk \
    --clear \
    --new=1:2048:+1G \
    --typecode=1:ef00 \
    --change-name=1:"EFI System Partition" \
    --new=2:0:0 \
    --typecode=2:8300 \
    --change-name=2:"Gentoo Root" \
    "${DISK}"

partprobe "${DISK}"

udevadm settle 2>/dev/null || true

sleep 3

[[ -b "${EFI}" ]] || \
    die "EFI partition was not created."

[[ -b "${ROOT}" ]] || \
    die "Root partition was not created."

# ------------------------------------------------------------
# Verify partition table
# ------------------------------------------------------------

msg "VERIFYING PARTITION TABLE"

EFI_PARTTYPE="$(blkid -p -s PARTTYPE -o value "${EFI}" | tr '[:upper:]' '[:lower:]')"
ROOT_PARTTYPE="$(blkid -p -s PARTTYPE -o value "${ROOT}" | tr '[:upper:]' '[:lower:]')"

echo
echo "EFI type : ${EFI_PARTTYPE}"
echo "Root type: ${ROOT_PARTTYPE}"
echo

# IMPORTANT:
# blkid returns the actual GPT partition-type GUID.
# EF00 is sgdisk's short type code and must NOT be compared
# directly with blkid's C12A7328-... GUID.

[[ "${EFI_PARTTYPE}" == "${EFI_PARTTYPE_GUID}" ]] || \
    die "Partition 1 is not an EFI System Partition."

[[ "${ROOT_PARTTYPE}" == "${ROOT_PARTTYPE_GUID}" ]] || \
    die "Partition 2 is not a Linux filesystem partition."

echo "Partition table verification OK."

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
    die "Gentoo root filesystem is not mounted."

mountpoint -q "${TARGET}/efi" || \
    die "EFI filesystem is not mounted."

# ------------------------------------------------------------
# Prepare Stage 3 directory
# ------------------------------------------------------------

msg "PREPARING STAGE 3 DOWNLOAD"

mkdir -p "${TARGET}/var/tmp"

cd "${TARGET}/var/tmp"

# ------------------------------------------------------------
# Find latest Stage 3
# ------------------------------------------------------------

msg "FINDING LATEST AMD64 OPENRC STAGE 3"

STAGE_FILE="$(
    wget \
        -qO- \
        "${STAGE_BASE}/latest-stage3-amd64-openrc.txt" |
    awk '
        !/^#/ &&
        $1 ~ /^stage3-amd64-openrc-.*\.tar\.xz$/ {
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

# ------------------------------------------------------------
# Download Stage 3
# ------------------------------------------------------------

msg "DOWNLOADING STAGE 3"

wget \
    --progress=bar:force \
    --tries=5 \
    --timeout=30 \
    -c \
    "${STAGE_BASE}/${STAGE_FILE}"

wget \
    --progress=bar:force \
    --tries=5 \
    --timeout=30 \
    -c \
    "${STAGE_BASE}/${STAGE_FILE}.sha256"

# ------------------------------------------------------------
# Verify Stage 3 checksum
# ------------------------------------------------------------

msg "VERIFYING STAGE 3 CHECKSUM"

sha256sum -c "${STAGE_FILE}.sha256"

# ------------------------------------------------------------
# Extract Stage 3
# ------------------------------------------------------------

msg "EXTRACTING STAGE 3"

cd "${TARGET}"

tar \
    xpf \
    "/mnt/gentoo/var/tmp/${STAGE_FILE}" \
    --xattrs-include='*.*' \
    --numeric-owner

rm -f \
    "/mnt/gentoo/var/tmp/${STAGE_FILE}" \
    "/mnt/gentoo/var/tmp/${STAGE_FILE}.sha256"

# ------------------------------------------------------------
# Prepare directories
# ------------------------------------------------------------

mkdir -p \
    "${TARGET}/proc" \
    "${TARGET}/sys" \
    "${TARGET}/dev" \
    "${TARGET}/run" \
    "${TARGET}/efi" \
    "${TARGET}/etc/portage" \
    "${TARGET}/var/db/repos"

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
UUID=${EFI_UUID}     /efi    vfat    umask=0077                  0 2
EOF

# ------------------------------------------------------------
# Mount virtual filesystems
# ------------------------------------------------------------

msg "MOUNTING VIRTUAL FILESYSTEMS"

mountpoint -q "${TARGET}/proc" || \
    mount \
        --types proc \
        /proc \
        "${TARGET}/proc"

mountpoint -q "${TARGET}/sys" || \
    mount \
        --rbind \
        /sys \
        "${TARGET}/sys"

mount --make-rslave "${TARGET}/sys"

mountpoint -q "${TARGET}/dev" || \
    mount \
        --rbind \
        /dev \
        "${TARGET}/dev"

mount --make-rslave "${TARGET}/dev"

mountpoint -q "${TARGET}/run" || \
    mount \
        --rbind \
        /run \
        "${TARGET}/run"

mount --make-rslave "${TARGET}/run"

# ------------------------------------------------------------
# Fix /dev/shm for chroot
# ------------------------------------------------------------

if [[ -L "${TARGET}/dev/shm" ]]; then
    rm -f "${TARGET}/dev/shm"
    mkdir -p "${TARGET}/dev/shm"
fi

chmod 1777 "${TARGET}/dev/shm"

# ------------------------------------------------------------
# Configure repository before entering chroot
# ------------------------------------------------------------

msg "PREPARING GENTOO REPOSITORY CONFIGURATION"

mkdir -p "${TARGET}/etc/portage/repos.conf"

if [[ ! -f "${TARGET}/etc/portage/repos.conf/gentoo.conf" ]]; then
    cat > "${TARGET}/etc/portage/repos.conf/gentoo.conf" <<'EOF'
[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
sync-rsync-verify-metamanifest = yes
sync-rsync-verify-jobs = 1
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

PROFILE_TARGET="default/linux/amd64/23.0/desktop/plasma"

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
    die "The chroot installer must run as root."

[[ -d /sys/firmware/efi ]] || \
    die "UEFI firmware interface is unavailable."

[[ -d /efi ]] || \
    die "/efi does not exist."

[[ -d /var/db/repos ]] || \
    die "/var/db/repos does not exist."

# ------------------------------------------------------------
# Portage configuration
# ------------------------------------------------------------

msg "CONFIGURING PORTAGE"

mkdir -p \
    /etc/portage \
    /etc/portage/package.use \
    /etc/portage/package.license \
    /etc/portage/repos.conf

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

USE="elogind X wayland pipewire sound-server"

L10N="en-US"
LINGUAS="en"

ACCEPT_LICENSE="-* @FREE @BINARY-REDISTRIBUTABLE"
EOF

# ------------------------------------------------------------
# Kernel installation configuration
# ------------------------------------------------------------

cat > /etc/portage/package.use/installkernel <<'EOF'
sys-kernel/installkernel dracut grub -systemd
EOF

# ------------------------------------------------------------
# Firmware license
# ------------------------------------------------------------

cat > /etc/portage/package.license/firmware <<'EOF'
sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE
EOF

# ------------------------------------------------------------
# Desktop package USE flags
# ------------------------------------------------------------

cat > /etc/portage/package.use/desktop <<'EOF'
kde-plasma/plasma-meta sddm
net-misc/networkmanager elogind
media-video/pipewire sound-server pipewire-alsa pipewire-pulse elogind
media-video/wireplumber elogind
EOF

# ------------------------------------------------------------
# Ensure repository configuration exists
# ------------------------------------------------------------

if [[ ! -f /etc/portage/repos.conf/gentoo.conf ]]; then
    cat > /etc/portage/repos.conf/gentoo.conf <<'EOF'
[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
sync-rsync-verify-metamanifest = yes
sync-rsync-verify-jobs = 1
EOF
fi

# ------------------------------------------------------------
# Synchronize Gentoo repository
# ------------------------------------------------------------

msg "SYNCHRONIZING GENTOO REPOSITORY"

if command -v emerge-webrsync >/dev/null 2>&1; then
    emerge-webrsync
else
    emerge --sync
fi

if [[ ! -d /var/db/repos/gentoo/profiles ]]; then
    emerge --sync
fi

[[ -d /var/db/repos/gentoo/profiles ]] || \
    die "Gentoo repository could not be installed."

# ------------------------------------------------------------
# Select AMD64 23.0 Plasma OpenRC profile
# ------------------------------------------------------------

msg "SELECTING AMD64 23.0 PLASMA OPENRC PROFILE"

PROFILE_INDEX="$(
    eselect profile list |
    sed -n \
        's/^[[:space:]]*\[\([0-9][0-9]*\)\][[:space:]]*default\/linux\/amd64\/23\.0\/desktop\/plasma[[:space:]]*.*$/\1/p' |
    head -n 1
)"

if [[ -z "${PROFILE_INDEX}" ]]; then
    echo
    echo "Available AMD64 Plasma profiles:"
    eselect profile list |
        grep -E 'default/linux/amd64/23\.0/desktop/plasma' ||
        true
    echo
    die "Could not locate the AMD64 23.0 Plasma profile."
fi

echo
echo "Selected profile index:"
echo "  ${PROFILE_INDEX}"
echo
echo "Selected profile:"
echo "  ${PROFILE_TARGET}"

eselect profile set "${PROFILE_INDEX}"

SELECTED_PROFILE="$(readlink -f /etc/portage/make.profile)"

echo
echo "Active profile:"
echo "  ${SELECTED_PROFILE}"

[[ "${SELECTED_PROFILE}" == *"/${PROFILE_TARGET}" ]] || \
    die "The requested Plasma profile was not selected."

[[ "${SELECTED_PROFILE}" != *"/systemd"* ]] || \
    die "The systemd Plasma profile was selected. OpenRC is required."

[[ "${SELECTED_PROFILE}" != *"/nomultilib"* ]] || \
    die "The selected profile is no-multilib."

# ------------------------------------------------------------
# Verify multilib
# ------------------------------------------------------------

msg "VERIFYING AMD64 MULTILIB"

ABI_X86_CURRENT="$(
    portageq envvar ABI_X86 2>/dev/null || true
)"

MULTILIB_ABIS_CURRENT="$(
    portageq envvar MULTILIB_ABIS 2>/dev/null || true
)"

echo
echo "ABI_X86:"
echo "  ${ABI_X86_CURRENT}"

echo
echo "MULTILIB_ABIS:"
echo "  ${MULTILIB_ABIS_CURRENT}"

if ! printf '%s\n' "${ABI_X86_CURRENT}" | grep -Eq '(^|[[:space:]])64([[:space:]]|$)'; then
    die "ABI_X86 does not contain 64."
fi

if ! printf '%s\n' "${ABI_X86_CURRENT}" | grep -Eq '(^|[[:space:]])32([[:space:]]|$)'; then
    die "ABI_X86 does not contain 32."
fi

if ! printf '%s\n' "${MULTILIB_ABIS_CURRENT}" | grep -Eq '(^|[[:space:]])x86([[:space:]]|$)'; then
    die "MULTILIB_ABIS does not contain x86."
fi

# ------------------------------------------------------------
# Update base system after profile selection
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
pt_BR.UTF-8 UTF-8
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

rc-update del dhcpcd default 2>/dev/null || true
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
CHECKVT=7
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

    echo zstd > /sys/block/zram0/comp_algorithm

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

grub-install \
    --target=x86_64-efi \
    --efi-directory=/efi \
    --bootloader-id=Gentoo \
    --recheck

# ------------------------------------------------------------
# User account
# ------------------------------------------------------------

msg "CREATING USER ACCOUNT"

if id "${USERNAME}" >/dev/null 2>&1; then

    usermod \
        --shell /bin/bash \
        --groups wheel,audio,video,input,plugdev \
        "${USERNAME}"

else

    useradd \
        --create-home \
        --shell /bin/bash \
        --groups wheel,audio,video,input,plugdev \
        "${USERNAME}"

fi

echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

echo "root:${USER_PASSWORD}" | chpasswd

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
# Regenerate kernel initramfs
# ------------------------------------------------------------

msg "REGENERATING KERNEL INITRAMFS"

KERNEL_VERSION="$(
    find /lib/modules \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -printf '%f\n' |
    sort -V |
    tail -n 1
)"

[[ -n "${KERNEL_VERSION}" ]] || \
    die "Could not determine the installed kernel version."

if command -v kernel-install >/dev/null 2>&1; then
    kernel-install \
        add \
        "${KERNEL_VERSION}" \
        "/usr/src/linux-${KERNEL_VERSION}/arch/x86/boot/bzImage" \
        2>/dev/null || true
fi

# ------------------------------------------------------------
# Generate GRUB configuration
# ------------------------------------------------------------

msg "GENERATING GRUB CONFIGURATION"

grub-mkconfig \
    -o /boot/grub/grub.cfg

[[ -s /boot/grub/grub.cfg ]] || \
    die "GRUB configuration was not generated."

# ------------------------------------------------------------
# Verify kernel and initramfs
# ------------------------------------------------------------

msg "VERIFYING KERNEL AND INITRAMFS"

KERNEL_COUNT="$(
    find /boot \
        -maxdepth 1 \
        -type f \
        -name 'vmlinuz-*' |
    wc -l
)"

INITRAMFS_COUNT="$(
    find /boot \
        -maxdepth 1 \
        -type f \
        -name 'initramfs-*' |
    wc -l
)"

echo
echo "Kernel images:"
find /boot \
    -maxdepth 1 \
    -type f \
    -name 'vmlinuz-*' \
    -print

echo
echo "Initramfs images:"
find /boot \
    -maxdepth 1 \
    -type f \
    -name 'initramfs-*' \
    -print

[[ "${KERNEL_COUNT}" -gt 0 ]] || \
    die "No kernel image was found in /boot."

[[ "${INITRAMFS_COUNT}" -gt 0 ]] || \
    die "No initramfs was found in /boot."

# ------------------------------------------------------------
# Verify GRUB
# ------------------------------------------------------------

msg "VERIFYING GRUB"

[[ -s /boot/grub/grub.cfg ]] || \
    die "GRUB configuration is missing."

grep -Eq 'linux|vmlinuz' /boot/grub/grub.cfg || \
    die "GRUB configuration does not contain a Linux entry."

# ------------------------------------------------------------
# Verify EFI installation
# ------------------------------------------------------------

msg "VERIFYING EFI BOOTLOADER"

[[ -d /efi/EFI/Gentoo ]] || \
    die "Gentoo EFI bootloader directory was not created."

find /efi/EFI/Gentoo \
    -maxdepth 2 \
    -type f \
    -print

# ------------------------------------------------------------
# Verify services
# ------------------------------------------------------------

msg "VERIFYING OPENRC SERVICES"

rc-update show

rc-update show | grep -q 'NetworkManager' || \
    die "NetworkManager is not enabled."

rc-update show | grep -q 'dbus' || \
    die "D-Bus is not enabled."

rc-update show | grep -q 'elogind' || \
    die "elogind is not enabled."

rc-update show | grep -q 'display-manager' || \
    die "display-manager is not enabled."

rc-update show | grep -q 'zram-swap' || \
    die "zram-swap is not enabled."

# ------------------------------------------------------------
# Verify installed packages
# ------------------------------------------------------------

msg "VERIFYING INSTALLED SOFTWARE"

command -v sudo >/dev/null || \
    die "sudo is missing."

command -v sddm >/dev/null || \
    die "sddm is missing."

command -v NetworkManager >/dev/null || \
    die "NetworkManager is missing."

command -v zramctl >/dev/null || \
    die "zramctl is missing."

command -v grub-install >/dev/null || \
    die "grub-install is missing."

command -v grub-mkconfig >/dev/null || \
    die "grub-mkconfig is missing."

command -v swapon >/dev/null || \
    die "swapon is missing."

# ------------------------------------------------------------
# Verify profile
# ------------------------------------------------------------

msg "VERIFYING FINAL PROFILE"

FINAL_PROFILE="$(readlink -f /etc/portage/make.profile)"

echo
echo "Profile:"
echo "  ${FINAL_PROFILE}"

[[ "${FINAL_PROFILE}" == *"/${PROFILE_TARGET}" ]] || \
    die "Final profile is not the requested Plasma OpenRC profile."

[[ "${FINAL_PROFILE}" != *"/systemd"* ]] || \
    die "Final profile is a systemd profile."

[[ "${FINAL_PROFILE}" != *"/nomultilib"* ]] || \
    die "Final profile is a no-multilib profile."

# ------------------------------------------------------------
# Verify multilib
# ------------------------------------------------------------

msg "VERIFYING FINAL MULTILIB CONFIGURATION"

FINAL_ABI_X86="$(
    portageq envvar ABI_X86 2>/dev/null || true
)"

FINAL_MULTILIB_ABIS="$(
    portageq envvar MULTILIB_ABIS 2>/dev/null || true
)"

echo
echo "ABI_X86:"
echo "  ${FINAL_ABI_X86}"

echo
echo "MULTILIB_ABIS:"
echo "  ${FINAL_MULTILIB_ABIS}"

printf '%s\n' "${FINAL_ABI_X86}" |
    grep -Eq '(^|[[:space:]])64([[:space:]]|$)' ||
    die "Final ABI_X86 does not contain 64."

printf '%s\n' "${FINAL_ABI_X86}" |
    grep -Eq '(^|[[:space:]])32([[:space:]]|$)' ||
    die "Final ABI_X86 does not contain 32."

printf '%s\n' "${FINAL_MULTILIB_ABIS}" |
    grep -Eq '(^|[[:space:]])x86([[:space:]]|$)' ||
    die "Final MULTILIB_ABIS does not contain x86."

# ------------------------------------------------------------
# Final account verification
# ------------------------------------------------------------

msg "VERIFYING USER ACCOUNT"

id "${USERNAME}"

id -nG "${USERNAME}" |
    tr ' ' '\n' |
    grep -qx 'wheel' ||
    die "User is not a member of wheel."

# ------------------------------------------------------------
# Final ZRAM verification
# ------------------------------------------------------------

msg "VERIFYING ZRAM CONFIGURATION"

[[ -f /etc/init.d/zram-swap ]] || \
    die "zram-swap service file is missing."

echo
echo "ZRAM service:"
rc-update show | grep zram-swap || true

# ------------------------------------------------------------
# Final report
# ------------------------------------------------------------

msg "FINAL INSTALLATION REPORT"

echo
echo "Hostname      : ${HOSTNAME}"
echo "Username      : ${USERNAME}"
echo "Profile       : ${FINAL_PROFILE}"
echo "Desktop       : KDE Plasma 6"
echo "Display       : SDDM"
echo "Init          : OpenRC"
echo "Network       : NetworkManager"
echo "Audio         : PipeWire + WirePlumber"
echo "Kernel        : gentoo-kernel-bin"
echo "Initramfs     : dracut"
echo "GPU           : AMD Radeon RX 7600"
echo "Architecture  : amd64 multilib"
echo "ABI_X86       : ${FINAL_ABI_X86}"
echo "MULTILIB_ABIS : ${FINAL_MULTILIB_ABIS}"
echo "Swap          : 8 GiB zram"
echo

echo "Kernel:"
ls -lh /boot/vmlinuz-*

echo
echo "Initramfs:"
ls -lh /boot/initramfs-*

echo
echo "GRUB:"
ls -lh /boot/grub/grub.cfg

echo
echo "EFI:"
find /efi/EFI \
    -maxdepth 3 \
    -type f \
    -print

echo
echo "Filesystem:"
df -h /

echo
echo "ZRAM:"
zramctl 2>/dev/null || true

echo
echo "Enabled services:"
rc-update show

echo
echo "============================================================"
echo "              INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "The Gentoo installation completed successfully."
echo
echo "Hostname  : ${HOSTNAME}"
echo "User      : ${USERNAME}"
echo "Desktop   : KDE Plasma 6"
echo "Login     : SDDM"
echo "Init      : OpenRC"
echo "Kernel    : gentoo-kernel-bin"
echo "Initramfs : dracut"
echo "GPU       : AMD Radeon RX 7600"
echo "Multilib  : amd64 64-bit + 32-bit"
echo "Swap      : 8 GiB zram"
echo
echo "The initial root password is the same password entered"
echo "for the user account."
echo
echo "============================================================"

# ------------------------------------------------------------
# Remove sensitive data
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

chroot "${TARGET}" /bin/bash -c '
    source /etc/profile
    export HOME=/root
    export TERM="${TERM:-xterm}"
    /root/install-inside-gentoo.sh
'

# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------

msg "FINAL CLEANUP"

rm -f "${TARGET}/root/install-inside-gentoo.sh"

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

exit 0
