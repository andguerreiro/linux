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

# 16 GiB RAM
MAKEOPTS="-j8"

# Gentoo profile
PROFILE="default/linux/amd64/23.0/desktop/plasma"

# Stage 3
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

command -v blkid >/dev/null 2>&1 || \
    die "blkid is not available."

command -v lsblk >/dev/null 2>&1 || \
    die "lsblk is not available."

command -v wipefs >/dev/null 2>&1 || \
    die "wipefs is not available."

command -v partprobe >/dev/null 2>&1 || \
    die "partprobe is not available."

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

# ------------------------------------------------------------
# Network check
# ------------------------------------------------------------

msg "CHECKING INTERNET CONNECTION"

wget \
    --quiet \
    --spider \
    "${STAGE_BASE}/latest-stage3-amd64-openrc.txt" || \
    die "Internet connection is not working."

echo "Internet connection OK."

# ------------------------------------------------------------
# Disable existing swap
# ------------------------------------------------------------

msg "DISABLING LIVE SYSTEM SWAP"

swapoff -a 2>/dev/null || true

# ------------------------------------------------------------
# Unmount old target
# ------------------------------------------------------------

msg "UNMOUNTING OLD TARGET FILESYSTEMS"

if mountpoint -q "${TARGET}/efi"; then
    umount "${TARGET}/efi" 2>/dev/null || \
        umount -l "${TARGET}/efi" 2>/dev/null || true
fi

if mountpoint -q "${TARGET}"; then
    umount "${TARGET}" 2>/dev/null || \
        umount -l "${TARGET}" 2>/dev/null || true
fi

umount "${DISK}"* 2>/dev/null || true

# ------------------------------------------------------------
# Verify target is no longer mounted
# ------------------------------------------------------------

mountpoint -q "${TARGET}" && \
    die "${TARGET} is still mounted."

mountpoint -q "${TARGET}/efi" && \
    die "${TARGET}/efi is still mounted."

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

udevadm settle 2>/dev/null || true

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

mountpoint -q "${TARGET}" || \
    die "Gentoo root filesystem could not be mounted."

mountpoint -q "${TARGET}/efi" || \
    die "EFI filesystem could not be mounted."

# ------------------------------------------------------------
# Download Stage 3
# ------------------------------------------------------------

msg "FINDING LATEST AMD64 OPENRC STAGE 3"

STAGE_FILE="$(
    wget \
        -qO- \
        "${STAGE_BASE}/latest-stage3-amd64-openrc.txt" |
    awk '
        !/^#/ &&
        $1 ~ /stage3-amd64-openrc-.*\.tar\.xz$/ {
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

[[ -s "${STAGE_FILE}" ]] || \
    die "Stage 3 archive was not downloaded."

[[ -s "${STAGE_FILE}.sha256" ]] || \
    die "Stage 3 checksum file was not downloaded."

# ------------------------------------------------------------
# Verify Stage 3 checksum
# ------------------------------------------------------------

msg "VERIFYING STAGE 3 CHECKSUM"

(
    cd "${TARGET}"
    sha256sum -c "${STAGE_FILE}.sha256"
)

# ------------------------------------------------------------
# Extract Stage 3
# ------------------------------------------------------------

msg "EXTRACTING STAGE 3"

tar \
    xpvf "${TARGET}/${STAGE_FILE}" \
    -C "${TARGET}" \
    --xattrs-include='*.*' \
    --numeric-owner

rm -f \
    "${TARGET}/${STAGE_FILE}" \
    "${TARGET}/${STAGE_FILE}.sha256"

# ------------------------------------------------------------
# Verify Stage 3 extraction
# ------------------------------------------------------------

[[ -x "${TARGET}/bin/bash" ]] || \
    die "Stage 3 extraction failed."

[[ -x "${TARGET}/usr/bin/emerge" ]] || \
    die "Stage 3 does not contain emerge."

[[ -d "${TARGET}/var/db/repos" ]] || \
    mkdir -p "${TARGET}/var/db/repos"

# ------------------------------------------------------------
# DNS
# ------------------------------------------------------------

msg "CONFIGURING DNS"

if [[ -e /etc/resolv.conf ]]; then
    cp \
        --dereference \
        /etc/resolv.conf \
        "${TARGET}/etc/resolv.conf"
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

mount --rbind /sys "${TARGET}/sys"
mount --make-rslave "${TARGET}/sys"

mount --rbind /dev "${TARGET}/dev"
mount --make-rslave "${TARGET}/dev"

mount --rbind /run "${TARGET}/run"
mount --make-rslave "${TARGET}/run"

# ------------------------------------------------------------
# DNS after Stage 3 extraction
# ------------------------------------------------------------

if [[ -e /etc/resolv.conf ]]; then
    cp \
        --dereference \
        /etc/resolv.conf \
        "${TARGET}/etc/resolv.conf"
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
export GENTOO_ROOT_UUID="${ROOT_UUID}"
export GENTOO_EFI_UUID="${EFI_UUID}"

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

ROOT_UUID="${GENTOO_ROOT_UUID}"
EFI_UUID="${GENTOO_EFI_UUID}"

PROFILE="default/linux/amd64/23.0/desktop/plasma"

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

# ============================================================
# Basic checks
# ============================================================

[[ "${EUID}" -eq 0 ]] || \
    die "This installer must run as root."

[[ -d /sys/firmware/efi ]] || \
    die "UEFI firmware interface is unavailable."

[[ -d /efi ]] || \
    die "/efi does not exist."

mountpoint -q /efi || \
    die "/efi is not mounted."

[[ -n "${HOSTNAME}" ]] || \
    die "Hostname is empty."

[[ -n "${USERNAME}" ]] || \
    die "Username is empty."

[[ -n "${USER_PASSWORD}" ]] || \
    die "User password is empty."

# ============================================================
# Configure Portage
# ============================================================

msg "CONFIGURING PORTAGE"

mkdir -p \
    /etc/portage \
    /etc/portage/package.use \
    /etc/portage/package.license \
    /etc/portage/repos.conf

cat > /etc/portage/make.conf <<EOF
COMMON_FLAGS="${CFLAGS}"

CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="${CXXFLAGS}"
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

# ============================================================
# Kernel and initramfs configuration
# ============================================================

msg "CONFIGURING KERNEL AND INITRAMFS"

cat > /etc/portage/package.use/kernel <<'EOF'
sys-kernel/installkernel dracut
EOF

# ============================================================
# Firmware license
# ============================================================

cat > /etc/portage/package.license/firmware <<'EOF'
sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE
EOF

# ============================================================
# KDE and desktop USE flags
# ============================================================

msg "CONFIGURING DESKTOP USE FLAGS"

cat > /etc/portage/package.use/desktop <<'EOF'
kde-plasma/plasma-meta sddm wayland X xwayland
net-misc/networkmanager elogind wifi
media-video/pipewire sound-server pipewire-alsa pipewire-pulse elogind
media-video/wireplumber elogind
EOF

# ============================================================
# Synchronize Gentoo repository
# ============================================================

msg "SYNCHRONIZING GENTOO REPOSITORY"

emerge --sync

[[ -d /var/db/repos/gentoo/profiles ]] || \
    die "Gentoo profile repository is unavailable."

# ============================================================
# Select Plasma OpenRC profile
# ============================================================

msg "SELECTING AMD64 23.0 PLASMA OPENRC PROFILE"

PROFILE_DIR="/var/db/repos/gentoo/profiles/${PROFILE}"

[[ -d "${PROFILE_DIR}" ]] || {
    echo
    echo "Requested profile was not found:"
    echo "  ${PROFILE_DIR}"
    echo
    echo "Available AMD64 23.0 Plasma profiles:"
    find \
        /var/db/repos/gentoo/profiles/default/linux/amd64/23.0 \
        -maxdepth 3 \
        -type d \
        -path '*/desktop/plasma*' \
        -print \
        2>/dev/null || true
    echo
    die "The requested Plasma profile is unavailable."
}

rm -f /etc/portage/make.profile

ln -s \
    "../../var/db/repos/gentoo/profiles/${PROFILE}" \
    /etc/portage/make.profile

CURRENT_PROFILE="$(readlink -f /etc/portage/make.profile)"

echo
echo "Selected profile:"
echo "  ${CURRENT_PROFILE}"

[[ "${CURRENT_PROFILE}" == "${PROFILE_DIR}" ]] || \
    die "Profile selection failed."

[[ "${CURRENT_PROFILE}" != *"/systemd"* ]] || \
    die "The selected profile is a systemd profile."

[[ "${CURRENT_PROFILE}" != *"/no-multilib"* ]] || \
    die "The selected profile is a no-multilib profile."

# ============================================================
# Verify multilib
# ============================================================

msg "VERIFYING MULTILIB"

ABI_X86_CURRENT="$(
    emerge --info |
    sed -n 's/^ABI_X86="\([^"]*\)".*/\1/p'
)"

echo "ABI_X86=${ABI_X86_CURRENT}"

echo "${ABI_X86_CURRENT}" | grep -qw "64" || \
    die "ABI_X86=64 is not enabled."

echo "${ABI_X86_CURRENT}" | grep -qw "32" || \
    die "ABI_X86=32 is not enabled."

# ============================================================
# Install installkernel and dracut
# ============================================================

msg "INSTALLING KERNEL INSTALLATION TOOLS"

emerge \
    --ask=n \
    sys-kernel/installkernel \
    sys-kernel/dracut

# ============================================================
# Configure dracut
# ============================================================

msg "CONFIGURING DRACUT"

mkdir -p /etc/dracut.conf.d

cat > /etc/dracut.conf.d/10-gentoo.conf <<EOF
hostonly="yes"
add_dracutmodules+=" udev base rootfs-block kernel-modules "
EOF

# ============================================================
# Update base system
# ============================================================

msg "UPDATING BASE SYSTEM"

emerge \
    --ask=n \
    --verbose \
    --update \
    --deep \
    --newuse \
    --with-bdeps=y \
    @world

# ============================================================
# Locale
# ============================================================

msg "CONFIGURING LOCALE"

cat > /etc/locale.gen <<'EOF'
en_US.UTF-8 UTF-8
EOF

locale-gen

eselect locale set en_US.utf8

# ============================================================
# Timezone
# ============================================================

msg "CONFIGURING TIMEZONE"

[[ -e "/usr/share/zoneinfo/${TIMEZONE}" ]] || \
    die "Invalid timezone: ${TIMEZONE}"

ln -sf \
    "/usr/share/zoneinfo/${TIMEZONE}" \
    /etc/localtime

echo "${TIMEZONE}" > /etc/timezone

# ============================================================
# Keyboard
# ============================================================

msg "CONFIGURING KEYBOARD"

cat > /etc/conf.d/keymaps <<EOF
keymap="${KEYMAP}"
EOF

# ============================================================
# Hostname
# ============================================================

msg "CONFIGURING HOSTNAME"

echo "${HOSTNAME}" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1       localhost
::1             localhost
127.0.1.1       ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# ============================================================
# Install kernel and firmware
# ============================================================

msg "INSTALLING KERNEL AND FIRMWARE"

emerge \
    --ask=n \
    sys-kernel/gentoo-kernel-bin \
    sys-kernel/linux-firmware

# ============================================================
# Install KDE Plasma
# ============================================================

msg "INSTALLING KDE PLASMA"

emerge \
    --ask=n \
    kde-plasma/plasma-meta

# ============================================================
# Install KDE applications
# ============================================================

msg "INSTALLING KDE APPLICATIONS"

emerge \
    --ask=n \
    kde-apps/dolphin \
    kde-apps/konsole \
    kde-apps/ark

# ============================================================
# Install system utilities
# ============================================================

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

# ============================================================
# NetworkManager
# ============================================================

msg "CONFIGURING NETWORKMANAGER"

emerge \
    --ask=n \
    net-misc/networkmanager

rc-update add NetworkManager default

# ============================================================
# D-Bus
# ============================================================

msg "CONFIGURING D-BUS"

emerge \
    --ask=n \
    sys-apps/dbus

rc-update add dbus default

# ============================================================
# elogind
# ============================================================

msg "CONFIGURING ELOGIND"

emerge \
    --ask=n \
    sys-auth/elogind

rc-update add elogind boot

# ============================================================
# SDDM
# ============================================================

msg "CONFIGURING SDDM"

emerge \
    --ask=n \
    x11-misc/sddm \
    gui-libs/display-manager-init

cat > /etc/conf.d/display-manager <<'EOF'
DISPLAYMANAGER="sddm"
EOF

rc-update add display-manager default

# ============================================================
# PipeWire and WirePlumber
# ============================================================

msg "CONFIGURING PIPEWIRE AUDIO"

emerge \
    --ask=n \
    media-video/pipewire \
    media-video/wireplumber

# PipeWire and WirePlumber run as user-session services.
# No system-wide OpenRC service is required.

# ============================================================
# AMD GPU
# ============================================================

msg "CONFIGURING AMD GPU"

mkdir -p /etc/modprobe.d

cat > /etc/modprobe.d/amdgpu.conf <<'EOF'
# AMD Radeon RX 7600
options amdgpu dc=1
EOF

# ============================================================
# ZRAM
# ============================================================

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

# ============================================================
# GRUB
# ============================================================

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

# ============================================================
# Generate GRUB configuration
# ============================================================

msg "GENERATING GRUB CONFIGURATION"

grub-mkconfig \
    -o /boot/grub/grub.cfg

[[ -s /boot/grub/grub.cfg ]] || \
    die "GRUB configuration was not generated."

# ============================================================
# User account
# ============================================================

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

printf '%s\n' "${USERNAME}:${USER_PASSWORD}" | chpasswd

printf '%s\n' "root:${USER_PASSWORD}" | chpasswd

# ============================================================
# Sudo
# ============================================================

msg "CONFIGURING SUDO"

mkdir -p /etc/sudoers.d

cat > /etc/sudoers.d/wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF

chmod 440 /etc/sudoers.d/wheel

visudo -c

# ============================================================
# Final world update
# ============================================================

msg "RUNNING FINAL SYSTEM UPDATE"

emerge \
    --ask=n \
    --update \
    --deep \
    --newuse \
    --with-bdeps=y \
    @world

# ============================================================
# Regenerate GRUB after final update
# ============================================================

msg "REGENERATING GRUB CONFIGURATION"

grub-mkconfig \
    -o /boot/grub/grub.cfg

[[ -s /boot/grub/grub.cfg ]] || \
    die "GRUB configuration was not generated."

# ============================================================
# Verify kernel and initramfs
# ============================================================

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

# ============================================================
# Verify GRUB
# ============================================================

msg "VERIFYING GRUB"

[[ -f /boot/grub/grub.cfg ]] || \
    die "GRUB configuration is missing."

grep -q "linux" /boot/grub/grub.cfg || \
    die "GRUB configuration does not contain a Linux entry."

# ============================================================
# Verify services
# ============================================================

msg "VERIFYING OPENRC SERVICES"

rc-update show | grep -q "NetworkManager" || \
    die "NetworkManager is not enabled."

rc-update show | grep -q "dbus" || \
    die "D-Bus is not enabled."

rc-update show | grep -q "elogind" || \
    die "elogind is not enabled."

rc-update show | grep -q "display-manager" || \
    die "display-manager is not enabled."

rc-update show | grep -q "zram-swap" || \
    die "zram-swap is not enabled."

# ============================================================
# Verify profile
# ============================================================

msg "VERIFYING PROFILE"

FINAL_PROFILE="$(readlink -f /etc/portage/make.profile)"

echo
echo "Profile:"
echo "  ${FINAL_PROFILE}"

[[ "${FINAL_PROFILE}" == "/var/db/repos/gentoo/profiles/${PROFILE}" ]] || \
    die "The final profile is incorrect."

[[ "${FINAL_PROFILE}" != *"/systemd"* ]] || \
    die "The final profile is a systemd profile."

[[ "${FINAL_PROFILE}" != *"/no-multilib"* ]] || \
    die "The final profile is a no-multilib profile."

# ============================================================
# Verify multilib
# ============================================================

msg "VERIFYING MULTILIB CONFIGURATION"

ABI_X86_FINAL="$(
    emerge --info |
    sed -n 's/^ABI_X86="\([^"]*\)".*/\1/p'
)"

echo "ABI_X86=${ABI_X86_FINAL}"

echo "${ABI_X86_FINAL}" | grep -qw "64" || \
    die "Final ABI_X86 does not contain 64."

echo "${ABI_X86_FINAL}" | grep -qw "32" || \
    die "Final ABI_X86 does not contain 32."

# ============================================================
# Final command checks
# ============================================================

msg "VERIFYING INSTALLED COMPONENTS"

command -v grub-install >/dev/null || \
    die "grub-install is missing."

command -v grub-mkconfig >/dev/null || \
    die "grub-mkconfig is missing."

command -v sudo >/dev/null || \
    die "sudo is missing."

command -v sddm >/dev/null || \
    die "sddm is missing."

command -v NetworkManager >/dev/null || \
    die "NetworkManager is missing."

command -v zramctl >/dev/null || \
    die "zramctl is missing."

command -v dracut >/dev/null || \
    die "dracut is missing."

command -v installkernel >/dev/null || \
    die "installkernel is missing."

id "${USERNAME}" >/dev/null || \
    die "The user account was not created."

[[ -f /etc/init.d/zram-swap ]] || \
    die "zram-swap service is missing."

[[ -s /boot/grub/grub.cfg ]] || \
    die "GRUB configuration is missing."

# ============================================================
# Final report
# ============================================================

msg "FINAL INSTALLATION CHECK"

echo
echo "Kernel:"
ls -lh /boot/vmlinuz-*

echo
echo "Initramfs:"
ls -lh /boot/initramfs-*

echo
echo "EFI files:"
find \
    /efi/EFI \
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
echo "The initial password was the password entered during setup."
echo
echo "You can change it later with:"
echo
echo "    passwd"
echo
echo "============================================================"

# ============================================================
# Cleanup sensitive variables
# ============================================================

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

unset USER_PASSWORD
unset USER_PASSWORD_CONFIRM

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
