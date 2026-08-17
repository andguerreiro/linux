#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Gentoo Automated Installer
#
# Target:
#   AMD Ryzen 7 5700X
#   AMD Radeon RX 7600
#   Kingston KC3000 512 GB NVMe
#   16 GiB RAM
#
# Installation:
#   UEFI
#   GPT
#   1 GiB EFI System Partition
#   Remaining space: ext4 root
#   amd64 multilib
#   OpenRC
#   KDE Plasma
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


# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

DISK="/dev/nvme0n1"
EFI="${DISK}p1"
ROOT="${DISK}p2"

TARGET="/mnt/gentoo"

EXPECTED_MODEL="KINGSTON SKC3000S512G"
EXPECTED_SERIAL="KINGSTON_SKC3000S512G_50026B7686C15573_1"

HOSTNAME="gentoo"
USERNAME="and"

TIMEZONE="America/Sao_Paulo"
LOCALE="en_US.UTF-8"
KEYMAP="us"

# Ryzen 7 5700X = Zen 3
CFLAGS="-O2 -pipe -march=znver3"
CXXFLAGS="${CFLAGS}"

# 8 cores / 16 threads, 16 GiB RAM.
# Keep parallelism conservative during installation.
MAKEOPTS="-j8"

# Current Gentoo KDE desktop profile.
PROFILE="default/linux/amd64/23.0/desktop/kde"

# Stage 3 flavor.
STAGE_VARIANT="desktop-openrc"

DISTFILES_HOST="distfiles.gentoo.org"
STAGE_BASE="https://${DISTFILES_HOST}/releases/amd64/autobuilds/current-stage3-amd64-${STAGE_VARIANT}"

STAGE_LATEST="latest-stage3-amd64-${STAGE_VARIANT}.txt"


# ------------------------------------------------------------
# Temporary state
# ------------------------------------------------------------

VARS_FILE=""

cleanup_parent() {
    if [[ -n "${VARS_FILE}" && -f "${VARS_FILE}" ]]; then
        rm -f "${VARS_FILE}"
    fi

    unset USER_PASSWORD USER_PASSWORD_CONFIRM
    unset ROOT_PASSWORD ROOT_PASSWORD_CONFIRM
}

trap cleanup_parent EXIT


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
    die "This installer must be run as root."

[[ -d /sys/firmware/efi ]] || \
    die "The LiveGUI was not booted in UEFI mode."

[[ -b "${DISK}" ]] || \
    die "${DISK} does not exist."

for cmd in \
    lsblk \
    blkid \
    sgdisk \
    wipefs \
    partprobe \
    mkfs.fat \
    mkfs.ext4 \
    mount \
    umount \
    wget \
    sha256sum \
    tar \
    chroot \
    udevadm
do
    command -v "${cmd}" >/dev/null 2>&1 || \
        die "Required command not found: ${cmd}"
done


# ------------------------------------------------------------
# Detect target disk
# ------------------------------------------------------------

DISK_TYPE="$(lsblk -dn -o TYPE "${DISK}" | tr -d ' ')"
MODEL="$(lsblk -dn -o MODEL "${DISK}" | sed 's/^[[:space:]]*//')"
SIZE="$(lsblk -dn -o SIZE "${DISK}")"

SERIAL="$(
    udevadm info \
        --query=property \
        --name="${DISK}" 2>/dev/null |
    awk -F= '/^ID_SERIAL=/{print $2; exit}'
)"

[[ "${DISK_TYPE}" == "disk" ]] || \
    die "${DISK} does not appear to be a physical disk."

[[ "${MODEL}" == "${EXPECTED_MODEL}" ]] || \
    die "Unexpected disk model: '${MODEL}'. Expected '${EXPECTED_MODEL}'."

[[ "${SERIAL}" == "${EXPECTED_SERIAL}" ]] || \
    die "Unexpected disk serial. Refusing to continue."


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
echo "  Serial : ${SERIAL}"
echo "  Size   : ${SIZE}"
echo
echo "EXPECTED TARGET:"
echo
echo "  ${EXPECTED_MODEL}"
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
echo "  Profile     : ${PROFILE}"
echo "  Init        : OpenRC"
echo "  Desktop     : KDE Plasma"
echo "  Login       : SDDM"
echo "  Network     : NetworkManager"
echo "  Audio       : PipeWire + WirePlumber"
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

lsblk -o NAME,SIZE,MODEL,FSTYPE,TYPE,MOUNTPOINTS

echo
echo "============================================================"
echo

read -r -p "Type ERASE to continue: " CONFIRM

[[ "${CONFIRM}" == "ERASE" ]] || \
    die "Installation cancelled."


# ------------------------------------------------------------
# Passwords
# ------------------------------------------------------------

echo
echo "Set the password for user '${USERNAME}'."
echo

read -r -s -p "User password: " USER_PASSWORD
echo

read -r -s -p "Confirm user password: " USER_PASSWORD_CONFIRM
echo

[[ "${USER_PASSWORD}" == "${USER_PASSWORD_CONFIRM}" ]] || \
    die "User passwords do not match."

[[ -n "${USER_PASSWORD}" ]] || \
    die "User password cannot be empty."

echo
echo "Set a separate root password."
echo

read -r -s -p "Root password: " ROOT_PASSWORD
echo

read -r -s -p "Confirm root password: " ROOT_PASSWORD_CONFIRM
echo

[[ "${ROOT_PASSWORD}" == "${ROOT_PASSWORD_CONFIRM}" ]] || \
    die "Root passwords do not match."

[[ -n "${ROOT_PASSWORD}" ]] || \
    die "Root password cannot be empty."


# ------------------------------------------------------------
# Network check
# ------------------------------------------------------------

msg "CHECKING INTERNET CONNECTION"

wget \
    --spider \
    --timeout=10 \
    --tries=3 \
    "https://${DISTFILES_HOST}/" \
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

umount "${DISK}"p* 2>/dev/null || true

if mountpoint -q "${TARGET}/efi" 2>/dev/null; then
    umount -R "${TARGET}/efi" 2>/dev/null || true
fi

if mountpoint -q "${TARGET}" 2>/dev/null; then
    umount -R "${TARGET}" 2>/dev/null || true
fi


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
    --new=1:0:+1G \
    --typecode=1:ef00 \
    --change-name=1:"EFI System Partition" \
    --new=2:0:0 \
    --typecode=2:8300 \
    --change-name=2:"Gentoo Root" \
    "${DISK}"

partprobe "${DISK}"
sleep 3

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


# ------------------------------------------------------------
# Obtain latest Stage 3
# ------------------------------------------------------------

msg "FINDING LATEST AMD64 DESKTOP OPENRC STAGE 3"

LATEST_URL="${STAGE_BASE}/${STAGE_LATEST}"

echo
echo "Reading:"
echo "  ${LATEST_URL}"
echo

LATEST_CONTENT="$(
    wget \
        -qO- \
        --timeout=20 \
        --tries=3 \
        "${LATEST_URL}"
)"

[[ -n "${LATEST_CONTENT}" ]] || \
    die "Could not download the Stage 3 index."


# The current Gentoo index is clearsigned and contains lines such as:
#
# stage3-amd64-desktop-openrc-20260816T170110Z.tar.xz 123456789
#
# Therefore we parse the FIRST FIELD instead of requiring the line
# to end in .tar.xz.

STAGE_FILE="$(
    printf '%s\n' "${LATEST_CONTENT}" |
    awk '
        $1 ~ /^stage3-amd64-desktop-openrc-[0-9TZ]+\.tar\.xz$/ {
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
# Extract expected size from signed index
# ------------------------------------------------------------

EXPECTED_STAGE_SIZE="$(
    printf '%s\n' "${LATEST_CONTENT}" |
    awk -v file="${STAGE_FILE}" '$1 == file {print $2; exit}'
)"

[[ "${EXPECTED_STAGE_SIZE}" =~ ^[0-9]+$ ]] || \
    die "Could not determine the expected Stage 3 size."


# ------------------------------------------------------------
# Download Stage 3 and checksum
# ------------------------------------------------------------

cd "${TARGET}"

msg "DOWNLOADING STAGE 3"

wget \
    -c \
    --timeout=30 \
    --tries=5 \
    "${STAGE_BASE}/${STAGE_FILE}"

wget \
    -c \
    --timeout=30 \
    --tries=5 \
    "${STAGE_BASE}/${STAGE_FILE}.sha256"


# ------------------------------------------------------------
# Verify archive size
# ------------------------------------------------------------

msg "VERIFYING STAGE 3 FILE SIZE"

ACTUAL_STAGE_SIZE="$(stat -c '%s' "${STAGE_FILE}")"

echo
echo "Expected size : ${EXPECTED_STAGE_SIZE}"
echo "Actual size   : ${ACTUAL_STAGE_SIZE}"
echo

[[ "${ACTUAL_STAGE_SIZE}" == "${EXPECTED_STAGE_SIZE}" ]] || \
    die "Downloaded Stage 3 size does not match the signed index."


# ------------------------------------------------------------
# Verify checksum
# ------------------------------------------------------------

msg "VERIFYING STAGE 3 SHA256 CHECKSUM"

sha256sum \
    --check \
    "${STAGE_FILE}.sha256"


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

cp \
    --dereference \
    /etc/resolv.conf \
    "${TARGET}/etc/resolv.conf"


# ------------------------------------------------------------
# Ensure Gentoo repository configuration exists
# ------------------------------------------------------------

msg "PREPARING GENTOO REPOSITORY CONFIGURATION"

mkdir -p "${TARGET}/etc/portage/repos.conf"

if [[ -f "${TARGET}/usr/share/portage/config/repos.conf" ]]; then
    cp \
        "${TARGET}/usr/share/portage/config/repos.conf" \
        "${TARGET}/etc/portage/repos.conf/gentoo.conf"
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
UUID=${EFI_UUID}     /efi    vfat    umask=0077                0 2
EOF


# ------------------------------------------------------------
# Mount virtual filesystems
# ------------------------------------------------------------

msg "MOUNTING VIRTUAL FILESYSTEMS"

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

cp \
    --dereference \
    /etc/resolv.conf \
    "${TARGET}/etc/resolv.conf"


# ------------------------------------------------------------
# Transfer sensitive installation variables
# ------------------------------------------------------------

msg "PREPARING CHROOT INSTALLER VARIABLES"

VARS_FILE="${TARGET}/root/.gentoo-installer-vars"

umask 077

{
    printf 'GENTOO_HOSTNAME=%q\n' "${HOSTNAME}"
    printf 'GENTOO_USERNAME=%q\n' "${USERNAME}"
    printf 'GENTOO_USER_PASSWORD=%q\n' "${USER_PASSWORD}"
    printf 'GENTOO_ROOT_PASSWORD=%q\n' "${ROOT_PASSWORD}"
    printf 'GENTOO_TIMEZONE=%q\n' "${TIMEZONE}"
    printf 'GENTOO_LOCALE=%q\n' "${LOCALE}"
    printf 'GENTOO_KEYMAP=%q\n' "${KEYMAP}"
    printf 'GENTOO_CFLAGS=%q\n' "${CFLAGS}"
    printf 'GENTOO_CXXFLAGS=%q\n' "${CXXFLAGS}"
    printf 'GENTOO_MAKEOPTS=%q\n' "${MAKEOPTS}"
    printf 'GENTOO_PROFILE=%q\n' "${PROFILE}"
} > "${VARS_FILE}"

chmod 600 "${VARS_FILE}"


# ------------------------------------------------------------
# Create chroot installer
# ------------------------------------------------------------

msg "PREPARING CHROOT INSTALLER"

cat > "${TARGET}/root/install-inside-gentoo.sh" <<'CHROOT_SCRIPT'
#!/usr/bin/env bash

set -Eeuo pipefail

# ------------------------------------------------------------
# Load installation variables
# ------------------------------------------------------------

VARS_FILE="/root/.gentoo-installer-vars"

[[ -f "${VARS_FILE}" ]] || \
    exit 1

# shellcheck disable=SC1090
source "${VARS_FILE}"

HOSTNAME="${GENTOO_HOSTNAME}"
USERNAME="${GENTOO_USERNAME}"

USER_PASSWORD="${GENTOO_USER_PASSWORD}"
ROOT_PASSWORD="${GENTOO_ROOT_PASSWORD}"

TIMEZONE="${GENTOO_TIMEZONE}"
LOCALE="${GENTOO_LOCALE}"
KEYMAP="${GENTOO_KEYMAP}"

CFLAGS="${GENTOO_CFLAGS}"
CXXFLAGS="${GENTOO_CXXFLAGS}"
MAKEOPTS="${GENTOO_MAKEOPTS}"
PROFILE="${GENTOO_PROFILE}"


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
    exit 1
}


# ------------------------------------------------------------
# Verify chroot
# ------------------------------------------------------------

[[ "${EUID}" -eq 0 ]] || \
    die "Chroot installer must run as root."

[[ -d /sys ]] || \
    die "/sys is not mounted."

[[ -d /dev ]] || \
    die "/dev is not mounted."

[[ -d /run ]] || \
    die "/run is not mounted."


# ------------------------------------------------------------
# Portage configuration
# ------------------------------------------------------------

msg "CONFIGURING PORTAGE"

mkdir -p /etc/portage/package.use
mkdir -p /etc/portage/package.license
mkdir -p /etc/portage/repos.conf

cat > /etc/portage/make.conf <<EOF
COMMON_FLAGS="${CFLAGS}"

CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

MAKEOPTS="${MAKEOPTS}"

VIDEO_CARDS="amdgpu radeonsi"

INPUT_DEVICES="libinput"

GRUB_PLATFORMS="efi-64"

L10N="en-US"
LINGUAS="en"

ACCEPT_LICENSE="-* @FREE @BINARY-REDISTRIBUTABLE"
EOF


# ------------------------------------------------------------
# Kernel / initramfs configuration
# ------------------------------------------------------------

msg "CONFIGURING KERNEL INSTALLATION"

cat > /etc/portage/package.use/installkernel <<EOF
sys-kernel/installkernel dracut grub
EOF


# ------------------------------------------------------------
# PipeWire configuration
# ------------------------------------------------------------

cat > /etc/portage/package.use/pipewire <<EOF
media-video/pipewire sound-server pipewire-alsa elogind
media-video/wireplumber elogind
EOF


# ------------------------------------------------------------
# NetworkManager configuration
# ------------------------------------------------------------

cat > /etc/portage/package.use/networkmanager <<EOF
net-misc/networkmanager wifi elogind
EOF


# ------------------------------------------------------------
# KDE / SDDM configuration
# ------------------------------------------------------------

cat > /etc/portage/package.use/kde <<EOF
kde-plasma/plasma-meta sddm
EOF


# ------------------------------------------------------------
# Firmware licensing
# ------------------------------------------------------------

cat > /etc/portage/package.license/firmware <<EOF
sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE
EOF


# ------------------------------------------------------------
# Synchronize Gentoo repository
# ------------------------------------------------------------

msg "SYNCHRONIZING GENTOO REPOSITORY"

emerge --sync


# ------------------------------------------------------------
# Select current KDE desktop profile
# ------------------------------------------------------------

msg "SELECTING GENTOO KDE DESKTOP PROFILE"

PROFILE_INDEX="$(
    eselect profile list |
    awk -v wanted="${PROFILE}" '
        index($0, wanted) {
            gsub(/[\[\]]/, "", $1)
            print $1
            exit
        }
    '
)"

[[ "${PROFILE_INDEX}" =~ ^[0-9]+$ ]] || \
    die "Could not find profile: ${PROFILE}"

eselect profile set "${PROFILE_INDEX}"

CURRENT_PROFILE="$(readlink -f /etc/portage/make.profile)"

echo
echo "Selected profile:"
echo "  ${CURRENT_PROFILE}"
echo

[[ "${CURRENT_PROFILE}" == *"/amd64/23.0/desktop/kde" ]] || \
    die "Unexpected Gentoo profile."


# ------------------------------------------------------------
# Verify multilib
# ------------------------------------------------------------

msg "VERIFYING MULTILIB PROFILE"

ABI_X86_VALUE="$(
    emerge --info |
    awk -F= '/^ABI_X86=/{print $2}'
)"

echo
echo "ABI_X86=${ABI_X86_VALUE}"
echo

echo "${ABI_X86_VALUE}" | grep -qw "32" || \
    die "Multilib ABI_X86=32 is not enabled."

echo "Multilib is enabled."


# ------------------------------------------------------------
# Initial world update
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

ln -sf \
    "/usr/share/zoneinfo/${TIMEZONE}" \
    /etc/localtime

echo "${TIMEZONE}" > /etc/timezone


# ------------------------------------------------------------
# Console keyboard
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
# Basic utilities
# ------------------------------------------------------------

msg "INSTALLING SYSTEM UTILITIES"

emerge \
    --ask=n \
    app-admin/sudo \
    app-editors/nano \
    app-portage/gentoolkit \
    app-portage/eix


# ------------------------------------------------------------
# NetworkManager
# ------------------------------------------------------------

msg "INSTALLING NETWORKMANAGER"

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

cat > /etc/conf.d/display-manager <<EOF
DISPLAYMANAGER="sddm"
EOF

rc-update add display-manager default


# ------------------------------------------------------------
# PipeWire + WirePlumber
# ------------------------------------------------------------

msg "INSTALLING PIPEWIRE AND WIREPLUMBER"

emerge \
    --ask=n \
    media-video/pipewire \
    media-video/wireplumber

if command -v gentoo-pipewire-launcher >/dev/null 2>&1; then
    echo
    echo "gentoo-pipewire-launcher installed successfully."
    echo "PipeWire will be started for the graphical user session."
fi


# ------------------------------------------------------------
# AMD GPU
# ------------------------------------------------------------

msg "CONFIGURING AMD GPU"

# No custom amdgpu module parameters are required.
#
# VIDEO_CARDS="amdgpu radeonsi" in make.conf causes the relevant
# userspace graphics stack to be built.
#
# gentoo-kernel-bin provides the kernel-side AMDGPU support and
# linux-firmware provides the required firmware.


# ------------------------------------------------------------
# ZRAM
# ------------------------------------------------------------

msg "CONFIGURING 8 GiB ZRAM SWAP"

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

    zramctl \
        --algorithm zstd \
        --size 8G \
        /dev/zram0

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

if ! id "${USERNAME}" >/dev/null 2>&1; then
    useradd \
        --create-home \
        --shell /bin/bash \
        --groups wheel,audio,video,input \
        "${USERNAME}"
else
    usermod \
        --shell /bin/bash \
        --groups wheel,audio,video,input \
        "${USERNAME}"
fi

echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

echo "root:${ROOT_PASSWORD}" | chpasswd


# ------------------------------------------------------------
# Sudo
# ------------------------------------------------------------

msg "CONFIGURING SUDO"

mkdir -p /etc/sudoers.d

cat > /etc/sudoers.d/wheel <<EOF
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
# Rebuild initramfs if necessary
# ------------------------------------------------------------

msg "VERIFYING KERNEL AND INITRAMFS"

echo
echo "Kernel images:"
ls -lh /boot/vmlinuz-* 2>/dev/null || true

echo
echo "Initramfs images:"
ls -lh /boot/initramfs-* 2>/dev/null || true

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
    die "No initramfs was found in /boot."


# ------------------------------------------------------------
# Regenerate GRUB
# ------------------------------------------------------------

msg "REGENERATING GRUB CONFIGURATION"

grub-mkconfig \
    -o /boot/grub/grub.cfg

[[ -f /boot/grub/grub.cfg ]] || \
    die "GRUB configuration was not generated."

grep -q "linux" /boot/grub/grub.cfg || \
    die "GRUB configuration does not contain a Linux entry."


# ------------------------------------------------------------
# Verify services
# ------------------------------------------------------------

msg "VERIFYING OPENRC SERVICES"

echo
echo "Enabled services:"
echo

rc-update show

echo
echo "Checking required services:"
echo

for service in \
    NetworkManager \
    dbus \
    elogind \
    display-manager \
    zram-swap
do
    if rc-update show default | grep -qE "[[:space:]]${service}$"; then
        echo "  OK: ${service}"
    else
        echo "  WARNING: ${service} not found in default runlevel"
    fi
done


# ------------------------------------------------------------
# Verify profile and multilib
# ------------------------------------------------------------

msg "VERIFYING FINAL PROFILE"

echo
echo "Profile:"
readlink -f /etc/portage/make.profile

echo

grep -q \
    '/amd64/23.0/desktop/kde' \
    <(readlink -f /etc/portage/make.profile) || \
    die "Final profile is not amd64 23.0 desktop/kde."


echo
echo "ABI_X86:"
emerge --info | grep '^ABI_X86=' || true

ABI_X86_FINAL="$(
    emerge --info |
    awk -F= '/^ABI_X86=/{print $2}'
)"

echo "${ABI_X86_FINAL}" | grep -qw "32" || \
    die "Final system is not multilib."


# ------------------------------------------------------------
# Verify important packages
# ------------------------------------------------------------

msg "VERIFYING IMPORTANT PACKAGES"

for package in \
    sys-kernel/gentoo-kernel-bin \
    sys-kernel/linux-firmware \
    kde-plasma/plasma-meta \
    x11-misc/sddm \
    net-misc/networkmanager \
    media-video/pipewire \
    media-video/wireplumber \
    sys-auth/elogind \
    sys-boot/grub
do
    if emerge -q "${package}"; then
        echo "  OK: ${package}"
    else
        echo "  WARNING: ${package} not found"
    fi
done


# ------------------------------------------------------------
# Verify zram configuration
# ------------------------------------------------------------

msg "VERIFYING ZRAM CONFIGURATION"

[[ -x /etc/init.d/zram-swap ]] || \
    die "zram-swap init script is missing."

grep -q 'size 8G' /etc/init.d/zram-swap || \
    die "zram-swap configuration does not contain 8G."


# ------------------------------------------------------------
# Final filesystem check
# ------------------------------------------------------------

msg "FINAL FILESYSTEM CHECK"

echo
echo "Filesystem:"
df -h /

echo
echo "EFI:"
df -h /efi

echo
echo "EFI files:"
find /efi/EFI \
    -maxdepth 3 \
    -type f \
    2>/dev/null || true


# ------------------------------------------------------------
# User check
# ------------------------------------------------------------

msg "FINAL USER CHECK"

id "${USERNAME}"


# ------------------------------------------------------------
# Remove sensitive information
# ------------------------------------------------------------

msg "REMOVING INSTALLATION SECRETS"

unset USER_PASSWORD
unset ROOT_PASSWORD

unset GENTOO_USER_PASSWORD
unset GENTOO_ROOT_PASSWORD

rm -f /root/.gentoo-installer-vars
rm -f /root/install-inside-gentoo.sh


# ------------------------------------------------------------
# Final message
# ------------------------------------------------------------

echo
echo "============================================================"
echo "              INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Hostname     : ${HOSTNAME}"
echo "User         : ${USERNAME}"
echo "Profile      : ${PROFILE}"
echo "Desktop      : KDE Plasma"
echo "Login        : SDDM"
echo "Init         : OpenRC"
echo "Network      : NetworkManager"
echo "Audio        : PipeWire + WirePlumber"
echo "Kernel       : gentoo-kernel-bin"
echo "Initramfs    : dracut"
echo "GPU          : AMD Radeon RX 7600"
echo "Architecture : amd64 multilib"
echo "Swap         : 8 GiB zram"
echo
echo "============================================================"

exit 0
CHROOT_SCRIPT

chmod 700 "${TARGET}/root/install-inside-gentoo.sh"


# ------------------------------------------------------------
# Run chroot installer
# ------------------------------------------------------------

msg "STARTING GENTOO INSTALLATION"

chroot "${TARGET}" /bin/bash -c '
    source /etc/profile
    export PS1="(gentoo) ${PS1:-\u@\h \w\$ }"
    /root/install-inside-gentoo.sh
'


# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------

msg "FINAL CLEANUP"

rm -f "${TARGET}/root/install-inside-gentoo.sh"
rm -f "${TARGET}/root/.gentoo-installer-vars"

sync


# ------------------------------------------------------------
# Unmount target
# ------------------------------------------------------------

msg "UNMOUNTING GENTOO"

umount -R "${TARGET}"

sync


# ------------------------------------------------------------
# Finished
# ------------------------------------------------------------

echo
echo "============================================================"
echo "          GENTOO INSTALLATION FINISHED"
echo "============================================================"
echo
echo "Installed on:"
echo
echo "    ${DISK}"
echo
echo "Target:"
echo
echo "    ${MODEL}"
echo
echo "Next step:"
echo
echo "    reboot"
echo
echo "Remove the LiveGUI USB drive when the machine restarts."
echo
echo "============================================================"
