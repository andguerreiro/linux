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

PROFILE="default/linux/amd64/23.0/desktop/plasma"

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
        echo " INSTALLATION FAILED"
        echo "============================================================"
        echo
        echo "The target filesystem has NOT been reformatted again."
        echo "Mounted filesystems will be unmounted before exiting."
        echo
    fi

    sync 2>/dev/null || true

    if mountpoint -q "${TARGET}/dev" 2>/dev/null; then
        umount -R "${TARGET}/dev" 2>/dev/null || true
    fi

    if mountpoint -q "${TARGET}/sys" 2>/dev/null; then
        umount -R "${TARGET}/sys" 2>/dev/null || true
    fi

    if mountpoint -q "${TARGET}/run" 2>/dev/null; then
        umount -R "${TARGET}/run" 2>/dev/null || true
    fi

    if mountpoint -q "${TARGET}/proc" 2>/dev/null; then
        umount "${TARGET}/proc" 2>/dev/null || true
    fi

    if mountpoint -q "${TARGET}/efi" 2>/dev/null; then
        umount "${TARGET}/efi" 2>/dev/null || true
    fi

    if mountpoint -q "${TARGET}" 2>/dev/null; then
        umount "${TARGET}" 2>/dev/null || true
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

[[ -d /sys/firmware/efi/efivars ]] || \
    die "UEFI variables are not available."

[[ -b "${DISK}" ]] || \
    die "${DISK} does not exist."

command -v lsblk >/dev/null 2>&1 || \
    die "lsblk is not available."

command -v blkid >/dev/null 2>&1 || \
    die "blkid is not available."

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
# Safety confirmation
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
echo "  Profile     : ${PROFILE}"
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

read -r -p "Type ERASE to continue: " CONFIRM

[[ "${CONFIRM}" == "ERASE" ]] || \
    die "Installation cancelled."

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

[[ "${USERNAME}" =~ ^[a-z_][a-z0-9_-]*$ ]] || \
    die "Invalid username: ${USERNAME}"

[[ "${HOSTNAME}" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]] || \
    die "Invalid hostname: ${HOSTNAME}"

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
    die "Internet connection to distfiles.gentoo.org is not working."

echo "Internet connection OK."

# ------------------------------------------------------------
# Disable existing swap
# ------------------------------------------------------------

msg "DISABLING LIVE SYSTEM SWAP"

swapoff -a 2>/dev/null || true

# ------------------------------------------------------------
# Unmount only the target
# ------------------------------------------------------------

msg "UNMOUNTING OLD TARGET"

if mountpoint -q "${TARGET}" 2>/dev/null; then
    umount -R "${TARGET}" 2>/dev/null || true
fi

# ------------------------------------------------------------
# Ensure target is not mounted
# ------------------------------------------------------------

mountpoint -q "${TARGET}" && \
    die "${TARGET} is still mounted."

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

udevadm settle

sleep 2

[[ -b "${EFI}" ]] || \
    die "EFI partition was not created."

[[ -b "${ROOT}" ]] || \
    die "Root partition was not created."

# ------------------------------------------------------------
# Verify partition layout
# ------------------------------------------------------------

msg "VERIFYING PARTITION LAYOUT"

EFI_TYPE="$(blkid -o value -s TYPE "${EFI}" 2>/dev/null || true)"
ROOT_TYPE="$(blkid -o value -s TYPE "${ROOT}" 2>/dev/null || true)"

[[ -z "${EFI_TYPE}" ]] || \
    die "EFI partition is unexpectedly formatted before installation."

[[ -z "${ROOT_TYPE}" ]] || \
    die "Root partition is unexpectedly formatted before installation."

lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTTYPE,PARTLABEL "${DISK}"

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
# Mount target filesystem
# ------------------------------------------------------------

msg "MOUNTING TARGET FILESYSTEM"

mkdir -p "${TARGET}"

mount \
    "${ROOT}" \
    "${TARGET}"

mkdir -p "${TARGET}/efi"

mount \
    "${EFI}" \
    "${TARGET}/efi"

mountpoint -q "${TARGET}" || \
    die "Gentoo root filesystem is not mounted."

mountpoint -q "${TARGET}/efi" || \
    die "EFI filesystem is not mounted."

# ------------------------------------------------------------
# Download Stage 3
# ------------------------------------------------------------

msg "FINDING LATEST AMD64 OPENRC STAGE 3"

STAGE_BASE="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc"

STAGE_INDEX="${STAGE_BASE}/latest-stage3-amd64-openrc.txt"

STAGE_FILE="$(
    wget \
        -qO- \
        "${STAGE_INDEX}" |
    awk '
        !/^#/ &&
        $0 ~ /stage3-amd64-openrc-[0-9T]+\.tar\.xz$/ {
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
    --continue \
    --show-progress \
    "${STAGE_BASE}/${STAGE_FILE}"

wget \
    --continue \
    --show-progress \
    "${STAGE_BASE}/${STAGE_FILE}.sha256"

# ------------------------------------------------------------
# Verify Stage 3 checksum
# ------------------------------------------------------------

msg "VERIFYING STAGE 3 CHECKSUM"

STAGE_CHECKSUM="$(awk '{print $1}' "${STAGE_FILE}.sha256")"

[[ "${STAGE_CHECKSUM}" =~ ^[0-9a-fA-F]{64}$ ]] || \
    die "Invalid SHA256 checksum file."

echo "${STAGE_CHECKSUM}  ${STAGE_FILE}" | sha256sum -c -

# ------------------------------------------------------------
# Extract Stage 3
# ------------------------------------------------------------

msg "EXTRACTING STAGE 3"

tar \
    xpvf \
    "${STAGE_FILE}" \
    --xattrs-include='*.*' \
    --numeric-owner

rm -f \
    "${STAGE_FILE}" \
    "${STAGE_FILE}.sha256"

# ------------------------------------------------------------
# DNS
# ------------------------------------------------------------

msg "CONFIGURING DNS"

rm -f "${TARGET}/etc/resolv.conf"

cp \
    --dereference \
    /etc/resolv.conf \
    "${TARGET}/etc/resolv.conf"

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

mkdir -p \
    "${TARGET}/proc" \
    "${TARGET}/sys" \
    "${TARGET}/dev" \
    "${TARGET}/run"

mount \
    --types proc \
    /proc \
    "${TARGET}/proc"

mount \
    --rbind \
    /sys \
    "${TARGET}/sys"

mount \
    --make-rslave \
    "${TARGET}/sys"

mount \
    --rbind \
    /dev \
    "${TARGET}/dev"

mount \
    --make-rslave \
    "${TARGET}/dev"

mount \
    --rbind \
    /run \
    "${TARGET}/run"

mount \
    --make-rslave \
    "${TARGET}/run"

# ------------------------------------------------------------
# DNS after Stage 3 extraction
# ------------------------------------------------------------

rm -f "${TARGET}/etc/resolv.conf"

cp \
    --dereference \
    /etc/resolv.conf \
    "${TARGET}/etc/resolv.conf"

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
export GENTOO_PROFILE="${PROFILE}"

# ------------------------------------------------------------
# Create chroot installer
# ------------------------------------------------------------

msg "PREPARING CHROOT INSTALLER"

cat > "${TARGET}/root/install-inside-gentoo.sh" <<'CHROOT_SCRIPT'
#!/usr/bin/env bash

set -Eeuo pipefail
set -o errtrace

# ============================================================
# Gentoo Chroot Installer
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
PROFILE="${GENTOO_PROFILE}"

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
# Root check
# ------------------------------------------------------------

[[ "${EUID}" -eq 0 ]] || \
    die "The chroot installer must run as root."

# ------------------------------------------------------------
# UEFI checks
# ------------------------------------------------------------

[[ -d /sys/firmware/efi ]] || \
    die "UEFI firmware interface is unavailable."

[[ -d /sys/firmware/efi/efivars ]] || \
    die "UEFI variables are unavailable."

# ------------------------------------------------------------
# Required filesystems
# ------------------------------------------------------------

mountpoint -q /efi || \
    die "/efi is not mounted."

mountpoint -q /proc || \
    die "/proc is not mounted."

mountpoint -q /sys || \
    die "/sys is not mounted."

mountpoint -q /dev || \
    die "/dev is not mounted."

# ------------------------------------------------------------
# Validate installation variables
# ------------------------------------------------------------

[[ -n "${HOSTNAME}" ]] || \
    die "Hostname is empty."

[[ -n "${USERNAME}" ]] || \
    die "Username is empty."

[[ -n "${USER_PASSWORD}" ]] || \
    die "User password is empty."

[[ -n "${TIMEZONE}" ]] || \
    die "Timezone is empty."

[[ -n "${CFLAGS}" ]] || \
    die "CFLAGS is empty."

[[ -n "${MAKEOPTS}" ]] || \
    die "MAKEOPTS is empty."

# ------------------------------------------------------------
# Portage directories
# ------------------------------------------------------------

msg "CONFIGURING PORTAGE"

mkdir -p \
    /etc/portage/package.use \
    /etc/portage/package.license

# ------------------------------------------------------------
# Portage configuration
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
# Firmware license
# ------------------------------------------------------------

cat > /etc/portage/package.license/firmware <<'EOF'
sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE
EOF

# ------------------------------------------------------------
# Installkernel configuration
# ------------------------------------------------------------

msg "CONFIGURING INSTALLKERNEL"

cat > /etc/portage/package.use/installkernel <<'EOF'
sys-kernel/installkernel dracut grub
EOF

# ------------------------------------------------------------
# Desktop USE flags
# ------------------------------------------------------------

msg "CONFIGURING DESKTOP USE FLAGS"

cat > /etc/portage/package.use/desktop <<'EOF'
net-misc/networkmanager elogind
media-video/pipewire sound-server pipewire-alsa pipewire-pulse elogind
media-video/wireplumber elogind
x11-misc/sddm elogind
EOF

# ------------------------------------------------------------
# Verify repository
# ------------------------------------------------------------

msg "VERIFYING GENTOO REPOSITORY"

[[ -d /var/db/repos/gentoo ]] || \
    die "Gentoo repository does not exist."

# ------------------------------------------------------------
# Synchronize repository
# ------------------------------------------------------------

msg "SYNCHRONIZING GENTOO REPOSITORY"

emerge \
    --sync

# ------------------------------------------------------------
# Verify required profile
# ------------------------------------------------------------

msg "SELECTING AMD64 23.0 PLASMA PROFILE"

PROFILE_INDEX="$(
    eselect profile list |
    sed -n \
        's/^[[:space:]]*\[\([0-9][0-9]*\)\][[:space:]]*default\/linux\/amd64\/23\.0\/desktop\/plasma[[:space:]]*(stable).*/\1/p' |
    head -n 1
)"

if [[ -z "${PROFILE_INDEX}" ]]; then
    echo
    echo "Available amd64 23.0 profiles:"
    eselect profile list | grep -E 'default/linux/amd64/23\.0' || true
    echo
    die "The required amd64 23.0 Plasma OpenRC profile was not found."
fi

echo "Profile index: ${PROFILE_INDEX}"

eselect profile set "${PROFILE_INDEX}"

CURRENT_PROFILE="$(readlink -f /etc/portage/make.profile)"

echo
echo "Selected profile:"
echo "  ${CURRENT_PROFILE}"

[[ "${CURRENT_PROFILE}" == */default/linux/amd64/23.0/desktop/plasma ]] || \
    die "The selected profile is not the required Plasma OpenRC profile."

[[ "${CURRENT_PROFILE}" != *"/systemd" ]] || \
    die "The selected profile is a systemd profile."

[[ "${CURRENT_PROFILE}" != *"/no-multilib"* ]] || \
    die "The selected profile is a no-multilib profile."

# ------------------------------------------------------------
# Verify multilib configuration
# ------------------------------------------------------------

msg "VERIFYING AMD64 MULTILIB"

grep -q '^ABI_X86="64 32"$' /etc/portage/make.conf || \
    die "ABI_X86 is not configured for amd64 multilib."

ABI_X86_CURRENT="$(
    emerge --info |
    sed -n 's/^ABI_X86="\([^"]*\)".*/\1/p'
)"

echo "ABI_X86=${ABI_X86_CURRENT}"

echo "${ABI_X86_CURRENT}" | grep -qw "64" || \
    die "ABI_X86=64 is not enabled."

echo "${ABI_X86_CURRENT}" | grep -qw "32" || \
    die "ABI_X86=32 is not enabled."

# ------------------------------------------------------------
# Install installkernel and GRUB
# ------------------------------------------------------------

msg "INSTALLING INSTALLKERNEL AND GRUB"

emerge \
    --ask=n \
    sys-kernel/installkernel \
    sys-boot/grub

command -v installkernel >/dev/null 2>&1 || \
    die "installkernel was not installed."

command -v grub-install >/dev/null 2>&1 || \
    die "grub-install was not installed."

command -v grub-mkconfig >/dev/null 2>&1 || \
    die "grub-mkconfig was not installed."

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

cat > /etc/locale.gen <<EOF
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
    "../usr/share/zoneinfo/${TIMEZONE}" \
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
# Install firmware
# ------------------------------------------------------------

msg "INSTALLING LINUX FIRMWARE"

emerge \
    --ask=n \
    sys-kernel/linux-firmware

# ------------------------------------------------------------
# Install kernel
# ------------------------------------------------------------

msg "INSTALLING GENTOO DISTRIBUTION KERNEL"

emerge \
    --ask=n \
    sys-kernel/gentoo-kernel-bin

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

[[ "${KERNEL_COUNT}" -gt 0 ]] || \
    die "No kernel image was installed."

[[ "${INITRAMFS_COUNT}" -gt 0 ]] || \
    die "No initramfs was generated."

echo
echo "Kernel images:"
ls -lh /boot/vmlinuz-*

echo
echo "Initramfs images:"
ls -lh /boot/initramfs-*

# ------------------------------------------------------------
# Install KDE Plasma
# ------------------------------------------------------------

msg "INSTALLING KDE PLASMA"

emerge \
    --ask=n \
    kde-plasma/plasma-meta

# ------------------------------------------------------------
# Install KDE applications
# ------------------------------------------------------------

msg "INSTALLING KDE APPLICATIONS"

emerge \
    --ask=n \
    kde-apps/dolphin \
    kde-apps/konsole \
    kde-apps/ark

# ------------------------------------------------------------
# Install system utilities
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

if rc-update show | grep -qE '(^|[[:space:]])dhcpcd([[:space:]]|$)'; then
    rc-update del dhcpcd default || true
fi

for service in net.eth0 net.enp0s3 net.enp1s0; do
    if [[ -e "/etc/init.d/${service}" ]]; then
        rc-update del "${service}" default || true
    fi
done

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
# PipeWire and WirePlumber
# ------------------------------------------------------------

msg "CONFIGURING PIPEWIRE AUDIO"

emerge \
    --ask=n \
    media-video/pipewire \
    media-video/wireplumber

# PipeWire and WirePlumber run as user services.
# No system-wide OpenRC PipeWire service is enabled.

# ------------------------------------------------------------
# AMD GPU configuration
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

cat > /etc/init.d/zram-swap <<'EOF'
#!/sbin/openrc-run

description="8 GiB compressed zram swap"

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

    if grep -qw "zstd" /sys/block/zram0/comp_algorithm; then
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

    if swapon --show=NAME | grep -qx "/dev/zram0"; then
        eend 0
        return 0
    fi

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
# User account
# ------------------------------------------------------------

msg "CREATING USER ACCOUNT"

for group in wheel audio video input; do
    if ! getent group "${group}" >/dev/null 2>&1; then
        groupadd "${group}"
    fi
done

if getent group plugdev >/dev/null 2>&1; then
    USER_GROUPS="wheel,audio,video,input,plugdev"
else
    USER_GROUPS="wheel,audio,video,input"
fi

if id "${USERNAME}" >/dev/null 2>&1; then
    usermod \
        --shell /bin/bash \
        --groups "${USER_GROUPS}" \
        "${USERNAME}"
else
    useradd \
        --create-home \
        --shell /bin/bash \
        --groups "${USER_GROUPS}" \
        "${USERNAME}"
fi

printf '%s\n' "${USERNAME}:${USER_PASSWORD}" | chpasswd

printf '%s\n' "root:${USER_PASSWORD}" | chpasswd

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
# GRUB UEFI installation
# ------------------------------------------------------------

msg "INSTALLING GRUB UEFI"

mountpoint -q /efi || \
    die "/efi is not mounted."

[[ -d /sys/firmware/efi/efivars ]] || \
    die "UEFI variables are unavailable."

grub-install \
    --target=x86_64-efi \
    --efi-directory=/efi \
    --bootloader-id=Gentoo \
    --recheck

# ------------------------------------------------------------
# Generate GRUB configuration
# ------------------------------------------------------------

msg "GENERATING GRUB CONFIGURATION"

grub-mkconfig \
    --output=/boot/grub/grub.cfg

[[ -s /boot/grub/grub.cfg ]] || \
    die "GRUB configuration was not generated."

grep -q "linux" /boot/grub/grub.cfg || \
    die "GRUB configuration does not contain a Linux entry."

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
# Regenerate GRUB after final update
# ------------------------------------------------------------

msg "REGENERATING GRUB CONFIGURATION"

grub-mkconfig \
    --output=/boot/grub/grub.cfg

[[ -s /boot/grub/grub.cfg ]] || \
    die "Final GRUB configuration was not generated."

# ------------------------------------------------------------
# Verify kernel and initramfs
# ------------------------------------------------------------

msg "FINAL KERNEL VERIFICATION"

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

[[ "${KERNEL_COUNT}" -gt 0 ]] || \
    die "No kernel image was found in /boot."

[[ "${INITRAMFS_COUNT}" -gt 0 ]] || \
    die "No initramfs image was found in /boot."

# ------------------------------------------------------------
# Verify OpenRC services
# ------------------------------------------------------------

msg "VERIFYING OPENRC SERVICES"

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
# Verify profile
# ------------------------------------------------------------

msg "VERIFYING FINAL PROFILE"

FINAL_PROFILE="$(readlink -f /etc/portage/make.profile)"

echo
echo "Final profile:"
echo "  ${FINAL_PROFILE}"

[[ "${FINAL_PROFILE}" == */default/linux/amd64/23.0/desktop/plasma ]] || \
    die "Final profile is not the required amd64 Plasma OpenRC profile."

[[ "${FINAL_PROFILE}" != *"/systemd" ]] || \
    die "Final profile unexpectedly uses systemd."

[[ "${FINAL_PROFILE}" != *"/no-multilib"* ]] || \
    die "Final profile unexpectedly uses no-multilib."

# ------------------------------------------------------------
# Verify multilib
# ------------------------------------------------------------

msg "VERIFYING FINAL MULTILIB CONFIGURATION"

ABI_X86_FINAL="$(
    emerge --info |
    sed -n 's/^ABI_X86="\([^"]*\)".*/\1/p'
)"

echo "ABI_X86=${ABI_X86_FINAL}"

echo "${ABI_X86_FINAL}" | grep -qw "64" || \
    die "Final ABI_X86 does not contain 64."

echo "${ABI_X86_FINAL}" | grep -qw "32" || \
    die "Final ABI_X86 does not contain 32."

# ------------------------------------------------------------
# Verify installed software
# ------------------------------------------------------------

msg "VERIFYING INSTALLED SOFTWARE"

command -v grub-install >/dev/null 2>&1 || \
    die "grub-install is missing."

command -v grub-mkconfig >/dev/null 2>&1 || \
    die "grub-mkconfig is missing."

command -v installkernel >/dev/null 2>&1 || \
    die "installkernel is missing."

command -v sudo >/dev/null 2>&1 || \
    die "sudo is missing."

command -v NetworkManager >/dev/null 2>&1 || \
    die "NetworkManager is missing."

command -v zramctl >/dev/null 2>&1 || \
    die "zramctl is missing."

command -v sddm >/dev/null 2>&1 || \
    die "sddm is missing."

command -v pipewire >/dev/null 2>&1 || \
    die "PipeWire is missing."

command -v wireplumber >/dev/null 2>&1 || \
    die "WirePlumber is missing."

# ------------------------------------------------------------
# Verify user
# ------------------------------------------------------------

msg "VERIFYING USER ACCOUNT"

id "${USERNAME}" >/dev/null 2>&1 || \
    die "The user account was not created."

id -nG "${USERNAME}" | grep -qw "wheel" || \
    die "The user is not a member of wheel."

# ------------------------------------------------------------
# Verify filesystem
# ------------------------------------------------------------

msg "VERIFYING FILESYSTEMS"

mountpoint -q /efi || \
    die "/efi is not mounted."

[[ -s /etc/fstab ]] || \
    die "/etc/fstab is missing."

grep -q "UUID=${ROOT_UUID}" /etc/fstab 2>/dev/null || true

# ------------------------------------------------------------
# Final report
# ------------------------------------------------------------

msg "FINAL INSTALLATION CHECK"

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
echo "EFI files:"
find /efi/EFI \
    -maxdepth 3 \
    -type f \
    -print \
    2>/dev/null || true

echo
echo "Enabled services:"
rc-update show

echo
echo "User:"
id "${USERNAME}"

echo
echo "Root filesystem:"
df -h /

echo
echo "ZRAM configuration:"
zramctl 2>/dev/null || true

echo
echo "Portage profile:"
readlink -f /etc/portage/make.profile

echo
echo "Portage ABI:"
emerge --info | grep '^ABI_X86=' || true

echo
echo "============================================================"
echo "              INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Hostname      : ${HOSTNAME}"
echo "User          : ${USERNAME}"
echo "Profile       : ${PROFILE}"
echo "Desktop       : KDE Plasma 6"
echo "Login         : SDDM"
echo "Init          : OpenRC"
echo "Network       : NetworkManager"
echo "Audio         : PipeWire + WirePlumber"
echo "Kernel        : gentoo-kernel-bin"
echo "Initramfs     : dracut"
echo "GPU           : AMD Radeon RX 7600"
echo "Architecture  : amd64 multilib"
echo "ABI_X86       : 64 32"
echo "Swap          : 8 GiB zram"
echo
echo "The initial password is the password entered during setup."
echo
echo "============================================================"

# ------------------------------------------------------------
# Remove installer
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
# Remove chroot installer
# ------------------------------------------------------------

rm -f "${TARGET}/root/install-inside-gentoo.sh"

# ------------------------------------------------------------
# Final cleanup
# ------------------------------------------------------------

msg "FINAL CLEANUP"

sync

umount -R "${TARGET}"

sync

trap - EXIT

echo
echo "============================================================"
echo "          GENTOO INSTALLATION FINISHED"
echo "============================================================"
echo
echo "The system has been installed on:"
echo
echo "    ${DISK}"
echo
echo "The target filesystems have been unmounted."
echo
echo "Next step:"
echo
echo "    reboot"
echo
echo "Remove the LiveGUI USB drive when the machine restarts."
echo
echo "============================================================"

exit 0
