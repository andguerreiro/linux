#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ============================================================
# Gentoo Automated Installer
#
# Target:
#   AMD Ryzen 7 5700X
#   AMD Radeon RX 7600
#   Kingston KC3000 512 GB NVMe
#   16 GB RAM
#
# Layout:
#   UEFI
#   GPT
#   1 GiB EFI System Partition
#   Remaining space: ext4 /
#
# Software:
#   amd64 multilib
#   OpenRC
#   KDE Plasma 6
#   SDDM
#   NetworkManager
#   PipeWire + WirePlumber
#   gentoo-kernel-bin
#   Dracut initramfs
#   GRUB UEFI
#   8 GiB zram swap
#
# WARNING:
#   THE TARGET DISK WILL BE COMPLETELY REPARTITIONED.
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

# Ryzen 7 5700X = Zen 3
CFLAGS="-O2 -pipe -march=znver3"
CXXFLAGS="${CFLAGS}"

MAKEOPTS="-j8"

# Gentoo Stage 3
GENTOO_MIRROR_HOST="distfiles.gentoo.org"

STAGE_PATH="/releases/amd64/autobuilds/current-stage3-amd64-openrc"

STAGE_LATEST_FILE="latest-stage3-amd64-openrc.txt"

# Gentoo 23.0 merged-usr Plasma/OpenRC profile.
PROFILE_TARGET="default/linux/amd64/23.0/desktop/plasma"

# 8 GiB
ZRAM_SIZE_BYTES=$((8 * 1024 * 1024 * 1024))

# EFI bootloader ID
GRUB_BOOTLOADER_ID="Gentoo"

# Installation lock
LOCK_FILE="/run/gentoo-installer.lock"

# Temporary secret file inside target
SECRET_FILE="${TARGET}/root/.gentoo-install-secrets"

# ------------------------------------------------------------
# Runtime state
# ------------------------------------------------------------

INSTALL_STARTED=0
INSTALL_FINISHED=0

USER_PASSWORD=""
USER_PASSWORD_CONFIRM=""

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
    echo
    exit 1
}

warn() {
    echo
    echo "WARNING: $*" >&2
    echo
}

cleanup() {
    local status=$?

    # Never leave the password file behind.
    if [[ -f "${SECRET_FILE}" ]]; then
        if command -v shred >/dev/null 2>&1; then
            shred -u "${SECRET_FILE}" 2>/dev/null || rm -f "${SECRET_FILE}"
        else
            rm -f "${SECRET_FILE}"
        fi
    fi

    if [[ "${status}" -ne 0 && "${INSTALL_STARTED}" -eq 1 ]]; then
        echo
        echo "============================================================"
        echo "              INSTALLATION STOPPED"
        echo "============================================================"
        echo
        echo "Exit status: ${status}"
        echo
        echo "The machine has NOT been rebooted."
        echo
        echo "Target:"
        echo "  ${TARGET}"
        echo
        echo "If you need to inspect the failed installation:"
        echo
        echo "  chroot ${TARGET} /bin/bash"
        echo
    fi

    rm -f "${LOCK_FILE}" 2>/dev/null || true

    exit "${status}"
}

trap cleanup EXIT


# ------------------------------------------------------------
# Basic environment checks
# ------------------------------------------------------------

msg "CHECKING INSTALLATION ENVIRONMENT"

[[ "${EUID}" -eq 0 ]] ||
    die "This installer must be run as root."

[[ -d /sys/firmware/efi ]] ||
    die "The LiveGUI was not booted in UEFI mode."

[[ -b "${DISK}" ]] ||
    die "${DISK} does not exist."

[[ "${DISK}" =~ ^/dev/nvme[0-9]+n[0-9]+$ ]] ||
    die "Target disk must be an NVMe namespace such as /dev/nvme0n1."

for command in \
    awk \
    blkid \
    chroot \
    findmnt \
    grep \
    lsblk \
    mkfs.ext4 \
    mkfs.fat \
    mount \
    partprobe \
    sgdisk \
    sha256sum \
    swapoff \
    umount \
    wget \
    wipefs \
    udevadm
do
    command -v "${command}" >/dev/null 2>&1 ||
        die "Required command is missing: ${command}"
done

# Prevent multiple installers from running simultaneously.

if command -v flock >/dev/null 2>&1; then
    exec 9>"${LOCK_FILE}"
    flock -n 9 ||
        die "Another instance of this installer is already running."
fi


# ------------------------------------------------------------
# Detect target disk
# ------------------------------------------------------------

DISK_TYPE="$(lsblk -dn -o TYPE "${DISK}" | tr -d ' ')"
MODEL="$(lsblk -dn -o MODEL "${DISK}" | sed 's/^[[:space:]]*//')"
SIZE="$(lsblk -dn -o SIZE "${DISK}")"
SERIAL="$(lsblk -dn -o SERIAL "${DISK}" | sed 's/^[[:space:]]*//')"

[[ "${DISK_TYPE}" == "disk" ]] ||
    die "${DISK} is not a block device of type disk."

# ------------------------------------------------------------
# Make sure the live system is NOT running from target disk
# ------------------------------------------------------------

LIVE_ROOT_SOURCE="$(findmnt -no SOURCE / 2>/dev/null || true)"

if [[ -n "${LIVE_ROOT_SOURCE}" ]]; then
    if [[ "${LIVE_ROOT_SOURCE}" == "${DISK}" ||
          "${LIVE_ROOT_SOURCE}" == "${EFI}" ||
          "${LIVE_ROOT_SOURCE}" == "${ROOT}" ]]; then
        die "The live system root is located on ${DISK}. Refusing to erase it."
    fi
fi

# ------------------------------------------------------------
# Check for mounted target partitions
# ------------------------------------------------------------

TARGET_MOUNTS="$(
    lsblk -nrpo NAME,MOUNTPOINTS "${DISK}" |
    awk 'NF > 1 && $2 != "" { print }'
)"

if [[ -n "${TARGET_MOUNTS}" ]]; then
    warn "The target disk currently has mounted filesystems:"
    echo
    echo "${TARGET_MOUNTS}"
    echo
    echo "The installer will attempt to unmount them."
fi

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
echo "  Model  : ${MODEL:-unknown}"
echo "  Serial : ${SERIAL:-unknown}"
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

read -r -p "Type exactly 'ERASE ${DISK}' to continue: " CONFIRMATION

[[ "${CONFIRMATION}" == "ERASE ${DISK}" ]] ||
    die "Destructive-operation confirmation failed."


# ------------------------------------------------------------
# Password
# ------------------------------------------------------------

msg "CONFIGURING INITIAL PASSWORD"

echo
echo "Set the initial password for '${USERNAME}'."
echo "The same password will initially be assigned to root."
echo

read -r -s -p "Password: " USER_PASSWORD
echo

read -r -s -p "Confirm password: " USER_PASSWORD_CONFIRM
echo

[[ "${USER_PASSWORD}" == "${USER_PASSWORD_CONFIRM}" ]] ||
    die "Passwords do not match."

[[ -n "${USER_PASSWORD}" ]] ||
    die "Password cannot be empty."

# Do not allow newline characters in password input.
[[ "${USER_PASSWORD}" != *$'\n'* ]] ||
    die "Password contains an unsupported newline character."

unset USER_PASSWORD_CONFIRM


# ------------------------------------------------------------
# Network check
# ------------------------------------------------------------

msg "CHECKING INTERNET CONNECTION"

wget \
    --quiet \
    --spider \
    --timeout=15 \
    --tries=3 \
    "https://${GENTOO_MIRROR_HOST}/" ||
    die "Internet connection to Gentoo infrastructure is unavailable."

echo "Internet connection OK."


# ------------------------------------------------------------
# Disable live-system swap
# ------------------------------------------------------------

msg "DISABLING LIVE SYSTEM SWAP"

swapoff -a 2>/dev/null || true


# ------------------------------------------------------------
# Unmount existing target
# ------------------------------------------------------------

msg "UNMOUNTING EXISTING TARGET"

if mountpoint -q "${TARGET}" 2>/dev/null; then
    umount -R "${TARGET}" 2>/dev/null || true
fi

# Try all existing partitions explicitly.
for partition in "${DISK}"p*; do
    [[ -e "${partition}" ]] || continue
    umount "${partition}" 2>/dev/null || true
done

udevadm settle 2>/dev/null || true


# ------------------------------------------------------------
# Wipe target disk
# ------------------------------------------------------------

INSTALL_STARTED=1

msg "WIPING TARGET DISK"

# Remove filesystem signatures.
wipefs --all --force "${DISK}"

# Destroy GPT and MBR structures.
sgdisk --zap-all "${DISK}"

sync

partprobe "${DISK}" 2>/dev/null || true

udevadm settle 2>/dev/null || true

sleep 2


# ------------------------------------------------------------
# Create GPT
# ------------------------------------------------------------

msg "CREATING GPT PARTITION TABLE"

sgdisk \
    --clear \
    --set-alignment=2048 \
    --new=1:0:+1G \
    --typecode=1:ef00 \
    --change-name=1:"EFI System Partition" \
    --new=2:0:0 \
    --typecode=2:8300 \
    --change-name=2:"Gentoo Root" \
    "${DISK}"

sgdisk --verify "${DISK}"

partprobe "${DISK}"

udevadm settle 2>/dev/null || true

sleep 2

[[ -b "${EFI}" ]] ||
    die "EFI partition ${EFI} was not created."

[[ -b "${ROOT}" ]] ||
    die "Root partition ${ROOT} was not created."


# ------------------------------------------------------------
# Verify partition types
# ------------------------------------------------------------

msg "VERIFYING PARTITION TABLE"

EFI_TYPE="$(sgdisk -i 1 "${DISK}" | awk -F: '/Partition GUID code/ {gsub(/ /,"",$2); print $2}')"
ROOT_TYPE="$(sgdisk -i 2 "${DISK}" | awk -F: '/Partition GUID code/ {gsub(/ /,"",$2); print $2}')"

echo
echo "EFI type : ${EFI_TYPE}"
echo "Root type: ${ROOT_TYPE}"
echo

[[ "${EFI_TYPE}" == "EF00" ]] ||
    die "Partition 1 is not an EFI System Partition."

[[ "${ROOT_TYPE}" == "8300" ]] ||
    die "Partition 2 is not a Linux filesystem partition."


# ------------------------------------------------------------
# Format EFI
# ------------------------------------------------------------

msg "FORMATTING EFI SYSTEM PARTITION"

mkfs.fat \
    -F 32 \
    -n EFI \
    "${EFI}"


# ------------------------------------------------------------
# Format root
# ------------------------------------------------------------

msg "FORMATTING ROOT FILESYSTEM"

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

mountpoint -q "${TARGET}" ||
    die "Root filesystem is not mounted."

mountpoint -q "${TARGET}/efi" ||
    die "EFI filesystem is not mounted."


# ------------------------------------------------------------
# Verify filesystems
# ------------------------------------------------------------

ROOT_FSTYPE="$(blkid -s TYPE -o value "${ROOT}")"
EFI_FSTYPE="$(blkid -s TYPE -o value "${EFI}")"

[[ "${ROOT_FSTYPE}" == "ext4" ]] ||
    die "Root filesystem is not ext4."

[[ "${EFI_FSTYPE}" == "vfat" ]] ||
    die "EFI filesystem is not vfat."


# ------------------------------------------------------------
# Generate UUIDs
# ------------------------------------------------------------

ROOT_UUID="$(blkid -s UUID -o value "${ROOT}")"
EFI_UUID="$(blkid -s UUID -o value "${EFI}")"

[[ -n "${ROOT_UUID}" ]] ||
    die "Could not determine root filesystem UUID."

[[ -n "${EFI_UUID}" ]] ||
    die "Could not determine EFI filesystem UUID."


# ------------------------------------------------------------
# Prepare Stage 3 download directory
# ------------------------------------------------------------

msg "PREPARING STAGE 3 DOWNLOAD"

mkdir -p "${TARGET}/var/tmp/gentoo-stage3"

chmod 700 "${TARGET}/var/tmp/gentoo-stage3"

cd "${TARGET}/var/tmp/gentoo-stage3"


# ------------------------------------------------------------
# Determine latest Stage 3
# ------------------------------------------------------------

msg "FINDING LATEST AMD64 OPENRC STAGE 3"

STAGE_BASE="https://${GENTOO_MIRROR_HOST}${STAGE_PATH}"

STAGE_FILE="$(
    wget \
        -qO- \
        "${STAGE_BASE}/${STAGE_LATEST_FILE}" |
    awk '
        $1 ~ /^stage3-amd64-openrc-[0-9TZ]+\.tar\.xz$/ {
            print $1
            exit
        }
    '
)"

[[ -n "${STAGE_FILE}" ]] ||
    die "Could not determine the current Stage 3 archive."

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
    --continue \
    "${STAGE_BASE}/${STAGE_FILE}"

wget \
    --progress=bar:force \
    --tries=5 \
    --timeout=30 \
    --continue \
    "${STAGE_BASE}/${STAGE_FILE}.sha256"


# ------------------------------------------------------------
# Verify Stage 3 checksum
# ------------------------------------------------------------

msg "VERIFYING STAGE 3 CHECKSUM"

sha256sum \
    -c \
    "${STAGE_FILE}.sha256"


# ------------------------------------------------------------
# Extract Stage 3
# ------------------------------------------------------------

msg "EXTRACTING STAGE 3"

cd "${TARGET}"

tar \
    --extract \
    --preserve-permissions \
    --xattrs \
    --xattrs-include='*.*' \
    --numeric-owner \
    --file="/var/tmp/gentoo-stage3/${STAGE_FILE}"


# ------------------------------------------------------------
# Remove downloaded Stage 3
# ------------------------------------------------------------

rm -f \
    "/var/tmp/gentoo-stage3/${STAGE_FILE}" \
    "/var/tmp/gentoo-stage3/${STAGE_FILE}.sha256"


# ------------------------------------------------------------
# Prepare target directories
# ------------------------------------------------------------

mkdir -p \
    "${TARGET}/proc" \
    "${TARGET}/sys" \
    "${TARGET}/dev" \
    "${TARGET}/run" \
    "${TARGET}/efi" \
    "${TARGET}/etc/portage" \
    "${TARGET}/etc/portage/package.use" \
    "${TARGET}/etc/portage/package.license" \
    "${TARGET}/etc/portage/repos.conf" \
    "${TARGET}/var/db/repos"


# ------------------------------------------------------------
# DNS
# ------------------------------------------------------------

msg "CONFIGURING DNS"

rm -f "${TARGET}/etc/resolv.conf"

if [[ -e /etc/resolv.conf ]]; then
    cp -L \
        /etc/resolv.conf \
        "${TARGET}/etc/resolv.conf"
else
    cat > "${TARGET}/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
fi


# ------------------------------------------------------------
# fstab
# ------------------------------------------------------------

msg "GENERATING FSTAB"

cat > "${TARGET}/etc/fstab" <<EOF
# Gentoo root filesystem
UUID=${ROOT_UUID}    /       ext4    noatime,errors=remount-ro    0 1

# EFI System Partition
UUID=${EFI_UUID}     /efi    vfat    umask=0077                  0 2
EOF

chmod 644 "${TARGET}/etc/fstab"


# ------------------------------------------------------------
# Gentoo repository configuration
# ------------------------------------------------------------

msg "CONFIGURING GENTOO REPOSITORY"

cat > "${TARGET}/etc/portage/repos.conf/gentoo.conf" <<'EOF'
[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
sync-rsync-verify-metamanifest = yes
sync-rsync-verify-jobs = 1
EOF


# ------------------------------------------------------------
# Mount virtual filesystems
# ------------------------------------------------------------

msg "MOUNTING VIRTUAL FILESYSTEMS"

mountpoint -q "${TARGET}/proc" ||
    mount \
        --types proc \
        proc \
        "${TARGET}/proc"

mountpoint -q "${TARGET}/sys" ||
    mount \
        --rbind \
        /sys \
        "${TARGET}/sys"

mount --make-rslave "${TARGET}/sys"

mountpoint -q "${TARGET}/dev" ||
    mount \
        --rbind \
        /dev \
        "${TARGET}/dev"

mount --make-rslave "${TARGET}/dev"

mountpoint -q "${TARGET}/run" ||
    mount \
        --rbind \
        /run \
        "${TARGET}/run"

mount --make-rslave "${TARGET}/run"


# ------------------------------------------------------------
# Ensure /dev/shm is usable
# ------------------------------------------------------------

if [[ -L "${TARGET}/dev/shm" ]]; then
    rm -f "${TARGET}/dev/shm"
    mkdir -p "${TARGET}/dev/shm"
fi

chmod 1777 "${TARGET}/dev/shm"


# ------------------------------------------------------------
# Store sensitive installation data
# ------------------------------------------------------------

msg "PREPARING SECURE INSTALLATION SECRETS"

cat > "${SECRET_FILE}" <<EOF
USER_PASSWORD=$(printf '%q' "${USER_PASSWORD}")
EOF

chmod 600 "${SECRET_FILE}"

unset USER_PASSWORD


# ------------------------------------------------------------
# Create chroot installer
# ------------------------------------------------------------

msg "PREPARING CHROOT INSTALLER"

cat > "${TARGET}/root/install-inside-gentoo.sh" <<'CHROOT_SCRIPT'
#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

# ============================================================
# Gentoo Installation Inside Chroot
# ============================================================

HOSTNAME="gentoo"
USERNAME="and"

TIMEZONE="America/Sao_Paulo"
LOCALE="en_US.UTF-8"
KEYMAP="us"

CFLAGS="-O2 -pipe -march=znver3"
CXXFLAGS="${CFLAGS}"

MAKEOPTS="-j8"

PROFILE_TARGET="default/linux/amd64/23.0/desktop/plasma"

SECRET_FILE="/root/.gentoo-install-secrets"

# ------------------------------------------------------------
# Helpers
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
    echo
    exit 1
}

# ------------------------------------------------------------
# Load secret
# ------------------------------------------------------------

[[ -f "${SECRET_FILE}" ]] ||
    die "Installation secret file is missing."

# shellcheck disable=SC1091
source "${SECRET_FILE}"

[[ -n "${USER_PASSWORD:-}" ]] ||
    die "Installation password was not loaded."

unset SECRET_FILE


# ------------------------------------------------------------
# Basic chroot checks
# ------------------------------------------------------------

[[ "${EUID}" -eq 0 ]] ||
    die "Chroot installer must run as root."

[[ -d /sys/firmware/efi ]] ||
    die "UEFI firmware interface is unavailable."

mountpoint -q /efi ||
    die "/efi is not mounted."

[[ -d /var/db/repos ]] ||
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

# AMD64 multilib
ABI_X86="64 32"

# AMD Radeon graphics
VIDEO_CARDS="amdgpu radeonsi"

# Generic input stack
INPUT_DEVICES="libinput"

# UEFI GRUB
GRUB_PLATFORMS="efi-64"

# Desktop / session infrastructure
USE="X wayland elogind"

L10N="en-US"
LINGUAS="en"

# Allow normal Free software plus redistributable firmware.
ACCEPT_LICENSE="@FREE @BINARY-REDISTRIBUTABLE"
EOF


# ------------------------------------------------------------
# Distribution kernel + Dracut
# ------------------------------------------------------------

cat > /etc/portage/package.use/kernel <<'EOF'
sys-kernel/installkernel dracut grub -systemd
sys-kernel/gentoo-kernel-bin initramfs
sys-kernel/linux-firmware redistributable
EOF


# ------------------------------------------------------------
# Desktop / session configuration
# ------------------------------------------------------------

cat > /etc/portage/package.use/desktop <<'EOF'
kde-plasma/plasma-meta sddm

net-misc/networkmanager elogind

media-video/pipewire elogind pipewire-alsa sound-server
media-video/wireplumber elogind

sys-auth/pambase elogind

sys-auth/polkit elogind
EOF


# ------------------------------------------------------------
# Dracut configuration
# ------------------------------------------------------------

mkdir -p /etc/dracut.conf.d

cat > /etc/dracut.conf.d/10-gentoo-root.conf <<'EOF'
# Root filesystem is specified by /etc/fstab and the generated GRUB entry.
use_fstab="yes"

# Keep the initramfs suitable for this installed machine.
hostonly="yes"

# Include filesystem and block-device support needed by the installation.
add_dracutmodules+=" base systemd-initrd "
EOF


# ------------------------------------------------------------
# Repository sync
# ------------------------------------------------------------

msg "SYNCHRONIZING GENTOO REPOSITORY"

if command -v emerge-webrsync >/dev/null 2>&1; then
    emerge-webrsync
else
    emerge --sync
fi

# Bring the snapshot to the current repository state when possible.
emerge --sync


[[ -d /var/db/repos/gentoo/profiles ]] ||
    die "Gentoo repository is unavailable."


# ------------------------------------------------------------
# Select Plasma OpenRC profile
# ------------------------------------------------------------

msg "SELECTING AMD64 PLASMA OPENRC PROFILE"

PROFILE_INDEX="$(
    eselect profile list |
    awk -v target="${PROFILE_TARGET}" '
        index($0, target) &&
        $0 !~ /\/systemd([[:space:]]|$)/ {
            match($0, /\[[0-9]+\]/)
            if (RSTART) {
                value=substr($0, RSTART + 1, RLENGTH - 2)
                print value
                exit
            }
        }
    '
)"

if [[ -z "${PROFILE_INDEX}" ]]; then
    echo
    echo "Available Plasma profiles:"
    eselect profile list |
        grep -E 'default/linux/amd64/23\.0/desktop/plasma' ||
        true
    echo
    die "Could not find ${PROFILE_TARGET}."
fi

echo
echo "Profile index: ${PROFILE_INDEX}"
echo "Profile path : ${PROFILE_TARGET}"
echo

eselect profile set "${PROFILE_INDEX}"

SELECTED_PROFILE="$(readlink -f /etc/portage/make.profile)"

echo
echo "Selected profile:"
echo "  ${SELECTED_PROFILE}"
echo

[[ "${SELECTED_PROFILE}" == *"/${PROFILE_TARGET}" ]] ||
    die "Incorrect Plasma profile selected."

[[ "${SELECTED_PROFILE}" != *"/systemd"* ]] ||
    die "A systemd profile was selected."

[[ "${SELECTED_PROFILE}" != *"/nomultilib"* ]] ||
    die "A no-multilib profile was selected."


# ------------------------------------------------------------
# Verify multilib before large installation
# ------------------------------------------------------------

msg "VERIFYING MULTILIB CONFIGURATION"

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
echo

printf '%s\n' "${ABI_X86_CURRENT}" |
    grep -Eq '(^|[[:space:]])64([[:space:]]|$)' ||
    die "ABI_X86 does not contain 64."

printf '%s\n' "${ABI_X86_CURRENT}" |
    grep -Eq '(^|[[:space:]])32([[:space:]]|$)' ||
    die "ABI_X86 does not contain 32."

printf '%s\n' "${MULTILIB_ABIS_CURRENT}" |
    grep -Eq '(^|[[:space:]])x86([[:space:]]|$)' ||
    die "MULTILIB_ABIS does not contain x86."


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
pt_BR.UTF-8 UTF-8
EOF

locale-gen

eselect locale set en_US.utf8


# ------------------------------------------------------------
# Timezone
# ------------------------------------------------------------

msg "CONFIGURING TIMEZONE"

[[ -e "/usr/share/zoneinfo/${TIMEZONE}" ]] ||
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
# Install kernel + firmware + initramfs generator
# ------------------------------------------------------------

msg "INSTALLING KERNEL, DRACUT AND FIRMWARE"

emerge \
    --ask=n \
    sys-kernel/installkernel \
    sys-kernel/dracut \
    sys-kernel/gentoo-kernel-bin \
    sys-kernel/linux-firmware


# ------------------------------------------------------------
# Verify kernel
# ------------------------------------------------------------

msg "VERIFYING KERNEL INSTALLATION"

KERNEL_IMAGES=(
    /boot/vmlinuz-*
)

KERNEL_FOUND=0

for kernel in "${KERNEL_IMAGES[@]}"; do
    [[ -f "${kernel}" ]] || continue
    KERNEL_FOUND=1
    echo "Kernel: ${kernel}"
done

[[ "${KERNEL_FOUND}" -eq 1 ]] ||
    die "No kernel image was installed."


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
rc-update del net.eth0 default 2>/dev/null || true

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
# PipeWire / WirePlumber
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

    if [[ ! -b /dev/zram0 ]]; then
        eerror "/dev/zram0 was not created"
        return 1
    fi

    # Reset any stale zram configuration.
    zramctl --reset /dev/zram0 2>/dev/null || true

    # Prefer zstd; fall back to the kernel-selected compressor if unavailable.
    if grep -qw zstd /sys/block/zram0/comp_algorithm; then
        echo zstd > /sys/block/zram0/comp_algorithm
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

chmod 755 /etc/init.d/zram-swap

rc-update add zram-swap default


# ------------------------------------------------------------
# GRUB
# ------------------------------------------------------------

msg "INSTALLING GRUB UEFI"

emerge \
    --ask=n \
    sys-boot/grub \
    sys-boot/efibootmgr

mountpoint -q /efi ||
    die "/efi is not mounted."

[[ -d /sys/firmware/efi ]] ||
    die "UEFI firmware interface is unavailable."

# Make sure EFI variables are writable when possible.
if [[ -d /sys/firmware/efi/efivars ]]; then
    mountpoint -q /sys/firmware/efi/efivars || true
fi

grub-install \
    --target=x86_64-efi \
    --efi-directory=/efi \
    --bootloader-id=Gentoo \
    --recheck


# ------------------------------------------------------------
# User account
# ------------------------------------------------------------

msg "CREATING USER ACCOUNT"

getent group wheel >/dev/null ||
    groupadd wheel

if id "${USERNAME}" >/dev/null 2>&1; then
    usermod \
        --shell /bin/bash \
        "${USERNAME}"
else
    useradd \
        --create-home \
        --shell /bin/bash \
        "${USERNAME}"
fi

# Add groups only if they exist.
for group in wheel audio video input plugdev; do
    if getent group "${group}" >/dev/null 2>&1; then
        usermod \
            --append \
            --groups "${group}" \
            "${USERNAME}"
    fi
done

echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

# Initial root password intentionally matches user password.
echo "root:${USER_PASSWORD}" | chpasswd

unset USER_PASSWORD


# ------------------------------------------------------------
# Sudo
# ------------------------------------------------------------

msg "CONFIGURING SUDO"

mkdir -p /etc/sudoers.d

cat > /etc/sudoers.d/10-wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF

chmod 440 /etc/sudoers.d/10-wheel

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
# Regenerate initramfs explicitly with Dracut
# ------------------------------------------------------------

msg "REGENERATING INITRAMFS WITH DRACUT"

if command -v dracut >/dev/null 2>&1; then

    mapfile -t KERNEL_VERSIONS < <(
        find /lib/modules \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -printf '%f\n' |
        sort -V
    )

    [[ "${#KERNEL_VERSIONS[@]}" -gt 0 ]] ||
        die "Could not determine installed kernel versions."

    for kernel_version in "${KERNEL_VERSIONS[@]}"; do

        echo
        echo "Generating initramfs for:"
        echo "  ${kernel_version}"
        echo

        dracut \
            --force \
            --kver "${kernel_version}"

    done

else
    die "Dracut is not installed."
fi


# ------------------------------------------------------------
# Verify initramfs
# ------------------------------------------------------------

msg "VERIFYING INITRAMFS"

INITRAMFS_FOUND=0

for initramfs in /boot/initramfs-*; do
    [[ -f "${initramfs}" ]] || continue
    INITRAMFS_FOUND=1
    echo "Initramfs: ${initramfs}"
done

[[ "${INITRAMFS_FOUND}" -eq 1 ]] ||
    die "No initramfs was generated."


# ------------------------------------------------------------
# Generate GRUB configuration
# ------------------------------------------------------------

msg "GENERATING GRUB CONFIGURATION"

mkdir -p /boot/grub

grub-mkconfig \
    -o /boot/grub/grub.cfg

[[ -s /boot/grub/grub.cfg ]] ||
    die "GRUB configuration was not generated."


# ------------------------------------------------------------
# Verify GRUB configuration
# ------------------------------------------------------------

msg "VERIFYING GRUB CONFIGURATION"

grep -Eq \
    'linux|vmlinuz' \
    /boot/grub/grub.cfg ||
    die "GRUB configuration does not contain a Linux kernel entry."


# ------------------------------------------------------------
# Verify EFI installation
# ------------------------------------------------------------

msg "VERIFYING EFI BOOTLOADER"

[[ -d /efi/EFI/Gentoo ]] ||
    die "EFI/Gentoo directory was not created."

EFI_FILES_FOUND=0

while IFS= read -r -d '' file; do
    EFI_FILES_FOUND=1
    echo "${file}"
done < <(
    find /efi/EFI/Gentoo \
        -maxdepth 2 \
        -type f \
        -print0
)

[[ "${EFI_FILES_FOUND}" -eq 1 ]] ||
    die "No EFI bootloader files were installed."


# ------------------------------------------------------------
# Verify services
# ------------------------------------------------------------

msg "VERIFYING OPENRC SERVICES"

rc-update show

for service in \
    NetworkManager \
    dbus \
    elogind \
    display-manager \
    zram-swap
do

    rc-update show |
        grep -Eq \
            "(^|[[:space:]])${service}([[:space:]]|$)" ||
        die "OpenRC service is not enabled: ${service}"

done


# ------------------------------------------------------------
# Verify installed commands
# ------------------------------------------------------------

msg "VERIFYING INSTALLED SOFTWARE"

for command in \
    sudo \
    sddm \
    NetworkManager \
    zramctl \
    grub-install \
    grub-mkconfig \
    swapon \
    dracut
do

    command -v "${command}" >/dev/null 2>&1 ||
        die "Required command is missing: ${command}"

done


# ------------------------------------------------------------
# Verify kernel
# ------------------------------------------------------------

msg "VERIFYING INSTALLED KERNEL"

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

[[ "${KERNEL_COUNT}" -gt 0 ]] ||
    die "No kernel image exists."

[[ "${INITRAMFS_COUNT}" -gt 0 ]] ||
    die "No initramfs exists."


# ------------------------------------------------------------
# Verify profile
# ------------------------------------------------------------

msg "VERIFYING FINAL PROFILE"

FINAL_PROFILE="$(readlink -f /etc/portage/make.profile)"

echo
echo "Final profile:"
echo "  ${FINAL_PROFILE}"
echo

[[ "${FINAL_PROFILE}" == *"/${PROFILE_TARGET}" ]] ||
    die "Final profile is incorrect."

[[ "${FINAL_PROFILE}" != *"/systemd"* ]] ||
    die "Final profile uses systemd."

[[ "${FINAL_PROFILE}" != *"/nomultilib"* ]] ||
    die "Final profile disables multilib."


# ------------------------------------------------------------
# Verify final multilib
# ------------------------------------------------------------

msg "VERIFYING FINAL MULTILIB"

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
echo

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
# Verify user
# ------------------------------------------------------------

msg "VERIFYING USER ACCOUNT"

id "${USERNAME}"

id -nG "${USERNAME}" |
    tr ' ' '\n' |
    grep -qx wheel ||
    die "User is not a member of wheel."


# ------------------------------------------------------------
# Verify zram service
# ------------------------------------------------------------

msg "VERIFYING ZRAM CONFIGURATION"

[[ -x /etc/init.d/zram-swap ]] ||
    die "zram-swap init script is missing."

grep -q '8589934592' /etc/init.d/zram-swap ||
    die "zram configuration does not specify 8 GiB."


# ------------------------------------------------------------
# Verify fstab
# ------------------------------------------------------------

msg "VERIFYING FSTAB"

grep -Eq \
    "^UUID=${ROOT_UUID}[[:space:]]+/[[:space:]]+ext4" \
    /etc/fstab ||
    die "Root filesystem entry is missing from fstab."

grep -Eq \
    "^UUID=${EFI_UUID}[[:space:]]+/efi[[:space:]]+vfat" \
    /etc/fstab ||
    die "EFI filesystem entry is missing from fstab."


# ------------------------------------------------------------
# Verify GPU configuration
# ------------------------------------------------------------

msg "VERIFYING AMD GPU CONFIGURATION"

grep -q \
    'amdgpu' \
    /etc/portage/make.conf ||
    die "amdgpu is missing from VIDEO_CARDS."

grep -q \
    'radeonsi' \
    /etc/portage/make.conf ||
    die "radeonsi is missing from VIDEO_CARDS."

[[ -f /etc/modprobe.d/amdgpu.conf ]] ||
    die "AMD GPU modprobe configuration is missing."


# ------------------------------------------------------------
# Verify GRUB platform configuration
# ------------------------------------------------------------

msg "VERIFYING GRUB PLATFORM"

grep -q \
    'GRUB_PLATFORMS="efi-64"' \
    /etc/portage/make.conf ||
    die "GRUB EFI platform is not configured."


# ------------------------------------------------------------
# Verify OpenRC
# ------------------------------------------------------------

msg "VERIFYING INIT SYSTEM"

[[ -x /sbin/openrc ]] ||
    die "OpenRC executable is missing."

if [[ -L /sbin/init ]]; then
    INIT_TARGET="$(readlink -f /sbin/init)"
    echo
    echo "/sbin/init -> ${INIT_TARGET}"
fi


# ------------------------------------------------------------
# Verify no systemd profile
# ------------------------------------------------------------

if [[ -e /etc/systemd/system.conf ]]; then
    echo
    echo "Note: systemd-related files may exist as dependencies."
    echo "The active init system remains OpenRC."
fi


# ------------------------------------------------------------
# Final report
# ------------------------------------------------------------

msg "FINAL INSTALLATION REPORT"

echo
echo "Hostname       : ${HOSTNAME}"
echo "Username       : ${USERNAME}"
echo "Profile        : ${FINAL_PROFILE}"
echo "Init           : OpenRC"
echo "Desktop        : KDE Plasma 6"
echo "Display        : SDDM"
echo "Network        : NetworkManager"
echo "Audio          : PipeWire + WirePlumber"
echo "Kernel         : gentoo-kernel-bin"
echo "Initramfs      : Dracut"
echo "GPU            : AMD Radeon RX 7600"
echo "Architecture   : amd64 multilib"
echo "ABI_X86        : ${FINAL_ABI_X86}"
echo "MULTILIB_ABIS  : ${FINAL_MULTILIB_ABIS}"
echo "Swap           : 8 GiB zram"
echo

echo "Kernel images:"
find /boot \
    -maxdepth 1 \
    -type f \
    -name 'vmlinuz-*' \
    -print |
    sort -V

echo

echo "Initramfs images:"
find /boot \
    -maxdepth 1 \
    -type f \
    -name 'initramfs-*' \
    -print |
    sort -V

echo

echo "GRUB configuration:"
ls -lh /boot/grub/grub.cfg

echo

echo "EFI bootloader:"
find /efi/EFI/Gentoo \
    -maxdepth 2 \
    -type f \
    -print

echo

echo "Filesystem:"
df -h /

echo

echo "ZRAM:"
zramctl 2>/dev/null || true

echo

echo "Enabled OpenRC services:"
rc-update show

echo
echo "============================================================"
echo "              INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Gentoo has been installed successfully."
echo
echo "Hostname : ${HOSTNAME}"
echo "User     : ${USERNAME}"
echo "Desktop  : KDE Plasma 6"
echo "Login    : SDDM"
echo "Init     : OpenRC"
echo "Kernel   : gentoo-kernel-bin"
echo "Boot     : GRUB UEFI"
echo "Audio    : PipeWire + WirePlumber"
echo "GPU      : AMD Radeon RX 7600"
echo "Multilib : amd64 64-bit + x86 32-bit"
echo "Swap     : 8 GiB zram"
echo
echo "============================================================"

# ------------------------------------------------------------
# Remove sensitive material
# ------------------------------------------------------------

unset USER_PASSWORD

rm -f /root/.gentoo-install-secrets
rm -f /root/install-inside-gentoo.sh

exit 0
CHROOT_SCRIPT

chmod 700 "${TARGET}/root/install-inside-gentoo.sh"


# ------------------------------------------------------------
# Enter chroot
# ------------------------------------------------------------

msg "STARTING GENTOO INSTALLATION"

chroot "${TARGET}" /bin/bash -c '
    source /etc/profile
    export HOME=/root
    export TERM="${TERM:-xterm}"
    /root/install-inside-gentoo.sh
'


# ------------------------------------------------------------
# Remove chroot installer and secret
# ------------------------------------------------------------

msg "FINAL CLEANUP"

rm -f \
    "${TARGET}/root/install-inside-gentoo.sh" \
    "${SECRET_FILE}"

sync


# ------------------------------------------------------------
# Final verification from installer environment
# ------------------------------------------------------------

msg "FINAL TARGET VERIFICATION"

mountpoint -q "${TARGET}" ||
    die "Target root filesystem is no longer mounted."

mountpoint -q "${TARGET}/efi" ||
    die "EFI filesystem is no longer mounted."

[[ -s "${TARGET}/boot/grub/grub.cfg" ]] ||
    die "Final GRUB configuration is missing."

find "${TARGET}/boot" \
    -maxdepth 1 \
    -type f \
    -name 'vmlinuz-*' |
    grep -q . ||
    die "Final kernel image is missing."

find "${TARGET}/boot" \
    -maxdepth 1 \
    -type f \
    -name 'initramfs-*' |
    grep -q . ||
    die "Final initramfs is missing."

[[ -d "${TARGET}/efi/EFI/Gentoo" ]] ||
    die "Final Gentoo EFI directory is missing."


# ------------------------------------------------------------
# Finish
# ------------------------------------------------------------

INSTALL_FINISHED=1

echo
echo "============================================================"
echo "          GENTOO INSTALLATION FINISHED"
echo "============================================================"
echo
echo "Installed to:"
echo
echo "    ${DISK}"
echo
echo "Partition layout:"
echo
echo "    ${EFI}   1 GiB EFI System Partition"
echo "    ${ROOT}  remaining space, ext4"
echo
echo "The system has NOT been rebooted automatically."
echo
echo "Recommended next steps:"
echo
echo "    sync"
echo "    umount -R ${TARGET}"
echo "    sync"
echo "    reboot"
echo
echo "Remove the LiveGUI USB when the machine restarts."
echo
echo "============================================================"

exit 0
