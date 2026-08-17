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

STAGE_BASE="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc"

GENTOO_REPO="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc"

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

cleanup_on_error() {
    local rc=$?

    echo
    echo "============================================================"
    echo "              INSTALLATION STOPPED"
    echo "============================================================"
    echo
    echo "The installer stopped because a command failed."
    echo
    echo "Target root:"
    echo "  ${TARGET}"
    echo
    echo "The system has NOT been rebooted."
    echo

    exit "${rc}"
}

trap cleanup_on_error ERR

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

command -v tar >/dev/null 2>&1 || \
    die "tar is not available."

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
echo "  Profile     : ${PROFILE_TARGET}"
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

if ! wget \
    --quiet \
    --timeout=15 \
    --tries=3 \
    --spider \
    "https://distfiles.gentoo.org/"; then

    die "Internet connection to distfiles.gentoo.org is not working."
fi

echo "Internet connection OK."

# ------------------------------------------------------------
# Disable existing swap
# ------------------------------------------------------------

msg "DISABLING LIVE SYSTEM SWAP"

swapoff -a 2>/dev/null || true

# ------------------------------------------------------------
# Unmount previous installer mounts
# ------------------------------------------------------------

msg "UNMOUNTING PREVIOUS INSTALLATION MOUNTS"

umount -R "${TARGET}" 2>/dev/null || true

umount "${EFI}" 2>/dev/null || true
umount "${ROOT}" 2>/dev/null || true

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

udevadm settle

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
# Mount target filesystem
# ------------------------------------------------------------

msg "MOUNTING TARGET FILESYSTEM"

mkdir -p "${TARGET}"

mount "${ROOT}" "${TARGET}"

mkdir -p "${TARGET}/efi"

mount "${EFI}" "${TARGET}/efi"

mountpoint -q "${TARGET}" || \
    die "${TARGET} is not mounted."

mountpoint -q "${TARGET}/efi" || \
    die "${TARGET}/efi is not mounted."

# ------------------------------------------------------------
# Download latest Stage 3
# ------------------------------------------------------------

msg "FINDING LATEST AMD64 OPENRC STAGE 3"

STAGE_INDEX="${STAGE_BASE}/latest-stage3-amd64-openrc.txt"

STAGE_FILE="$(
    wget \
        -qO- \
        "${STAGE_INDEX}" |
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

cd "${TARGET}"

wget \
    --continue \
    "${STAGE_BASE}/${STAGE_FILE}"

wget \
    --continue \
    "${STAGE_BASE}/${STAGE_FILE}.sha256"

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

cd "${TARGET}"

tar \
    xpf "${STAGE_FILE}" \
    --xattrs-include='*.*' \
    --numeric-owner

rm -f \
    "${TARGET}/${STAGE_FILE}" \
    "${TARGET}/${STAGE_FILE}.sha256"

# ------------------------------------------------------------
# Verify extracted Gentoo system
# ------------------------------------------------------------

msg "VERIFYING EXTRACTED GENTOO SYSTEM"

[[ -d "${TARGET}/etc" ]] || \
    die "Stage 3 extraction failed: /etc is missing."

[[ -x "${TARGET}/bin/bash" ]] || \
    die "Stage 3 extraction failed: /bin/bash is missing."

[[ -x "${TARGET}/usr/bin/emerge" ]] || \
    die "Stage 3 extraction failed: emerge is missing."

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
# Configure repository BEFORE entering chroot
# ------------------------------------------------------------

msg "CONFIGURING GENTOO REPOSITORY"

mkdir -p \
    "${TARGET}/etc/portage/repos.conf" \
    "${TARGET}/var/db/repos/gentoo"

cat > "${TARGET}/etc/portage/repos.conf/gentoo.conf" <<'EOF'
[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
sync-rsync-verify-metamanifest = yes
sync-rsync-verify-max-age = 24
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

mount -t proc proc "${TARGET}/proc"

mount --rbind /sys "${TARGET}/sys"
mount --make-rslave "${TARGET}/sys"

mount --rbind /dev "${TARGET}/dev"
mount --make-rslave "${TARGET}/dev"

mount --rbind /run "${TARGET}/run"
mount --make-rslave "${TARGET}/run"

# ------------------------------------------------------------
# Copy DNS again after virtual filesystem preparation
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

# ------------------------------------------------------------
# Create chroot installer
# ------------------------------------------------------------

msg "PREPARING CHROOT INSTALLER"

cat > "${TARGET}/root/install-inside-gentoo.sh" <<'CHROOT_SCRIPT'
#!/usr/bin/env bash

set -Eeuo pipefail
set -o errtrace

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

[[ -x /usr/bin/emerge ]] || \
    die "emerge is not available inside the Gentoo system."

[[ -d /var/db/repos/gentoo ]] || \
    die "The Gentoo repository directory does not exist."

[[ -f /etc/portage/repos.conf/gentoo.conf ]] || \
    die "The Gentoo repository configuration does not exist."

[[ -d /efi ]] || \
    die "/efi does not exist."

# ------------------------------------------------------------
# Configure Portage
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

L10N="en-US"
LINGUAS="en"

ACCEPT_LICENSE="-* @FREE @BINARY-REDISTRIBUTABLE"
EOF

# ------------------------------------------------------------
# Configure Gentoo repository
# ------------------------------------------------------------

msg "VERIFYING GENTOO REPOSITORY CONFIGURATION"

cat > /etc/portage/repos.conf/gentoo.conf <<'EOF'
[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
sync-rsync-verify-metamanifest = yes
sync-rsync-verify-max-age = 24
EOF

# ------------------------------------------------------------
# Synchronize Gentoo repository
# ------------------------------------------------------------

msg "SYNCHRONIZING GENTOO REPOSITORY"

emerge --sync

[[ -d /var/db/repos/gentoo/profiles ]] || \
    die "Gentoo repository synchronization did not create the profiles directory."

# ------------------------------------------------------------
# Select Plasma multilib profile
# ------------------------------------------------------------

msg "SELECTING AMD64 23.0 PLASMA MULTILIB PROFILE"

PROFILE_INDEX="$(
    eselect profile list |
    awk -v target="${PROFILE_TARGET}" '
        $0 ~ target && $0 !~ /no-multilib/ && $0 !~ /systemd/ {
            match($0, /^\[[[:space:]]*[0-9]+\]/)
            if (RSTART > 0) {
                token=substr($0, RSTART, RLENGTH)
                gsub(/[^0-9]/, "", token)
                print token
                exit
            }
        }
    '
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

eselect profile set "${PROFILE_INDEX}"

# ------------------------------------------------------------
# Verify selected profile
# ------------------------------------------------------------

CURRENT_PROFILE="$(readlink -f /etc/portage/make.profile)"

echo
echo "Current profile:"
echo "  ${CURRENT_PROFILE}"
echo

[[ "${CURRENT_PROFILE}" == */default/linux/amd64/23.0/desktop/plasma ]] || \
    die "The selected profile is not the expected AMD64 23.0 Plasma profile."

[[ "${CURRENT_PROFILE}" != *"/no-multilib/"* ]] || \
    die "The selected profile is a no-multilib profile."

[[ "${CURRENT_PROFILE}" != *"/systemd"* ]] || \
    die "The selected profile is a systemd profile."

# ------------------------------------------------------------
# Explicitly configure multilib
# ------------------------------------------------------------

msg "CONFIGURING AMD64 MULTILIB"

cat > /etc/portage/package.use/multilib <<'EOF'
*/* abi_x86_64 abi_x86_32
EOF

if ! grep -q '^ABI_X86="64 32"$' /etc/portage/make.conf; then
    die "ABI_X86 configuration is missing."
fi

ABI_X86_CURRENT="$(
    emerge --info |
    sed -n 's/^ABI_X86="\([^"]*\)".*/\1/p'
)"

echo "ABI_X86=${ABI_X86_CURRENT}"

if [[ -z "${ABI_X86_CURRENT}" ]]; then
    die "Portage returned an empty ABI_X86 value."
fi

echo "${ABI_X86_CURRENT}" | grep -qw "64" || \
    die "ABI_X86=64 is not enabled."

echo "${ABI_X86_CURRENT}" | grep -qw "32" || \
    die "ABI_X86=32 is not enabled."

# ------------------------------------------------------------
# Firmware licensing
# ------------------------------------------------------------

msg "CONFIGURING FIRMWARE LICENSE"

cat > /etc/portage/package.license/firmware <<'EOF'
sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE
EOF

# ------------------------------------------------------------
# Desktop USE flags
# ------------------------------------------------------------

msg "CONFIGURING DESKTOP USE FLAGS"

cat > /etc/portage/package.use/desktop <<'EOF'
kde-plasma/plasma-meta wayland X
net-misc/networkmanager elogind wifi
media-video/pipewire sound-server pipewire-alsa pipewire-pulse
media-video/wireplumber
x11-misc/sddm wayland
sys-auth/elogind pam
sys-apps/dbus elogind
EOF

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
# Install dracut and installkernel
# ------------------------------------------------------------

msg "INSTALLING DRACUT AND INSTALLKERNEL"

emerge \
    --ask=n \
    sys-kernel/dracut \
    sys-kernel/installkernel

cat > /etc/portage/package.use/installkernel <<'EOF'
sys-kernel/installkernel dracut grub
EOF

# ------------------------------------------------------------
# Install kernel and firmware
# ------------------------------------------------------------

msg "INSTALLING KERNEL AND FIRMWARE"

emerge \
    --ask=n \
    sys-kernel/gentoo-kernel-bin \
    sys-kernel/linux-firmware

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
# PipeWire and WirePlumber
# ------------------------------------------------------------

msg "CONFIGURING PIPEWIRE AUDIO"

emerge \
    --ask=n \
    media-video/pipewire \
    media-video/wireplumber

# PipeWire and WirePlumber are started by the user session.
# No system-wide OpenRC service is required.

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
# Final system update
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
# Regenerate initramfs
# ------------------------------------------------------------

msg "REGENERATING INITRAMFS"

if command -v dracut >/dev/null 2>&1; then

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
        die "Could not determine installed kernel version."

    dracut \
        --force \
        "/boot/initramfs-${KERNEL_VERSION}.img" \
        "${KERNEL_VERSION}"

fi

# ------------------------------------------------------------
# Regenerate GRUB
# ------------------------------------------------------------

msg "REGENERATING GRUB CONFIGURATION"

grub-mkconfig \
    -o /boot/grub/grub.cfg

# ------------------------------------------------------------
# Verify kernel
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
    die "No kernel image was found in /boot."

[[ "${INITRAMFS_COUNT}" -gt 0 ]] || \
    die "No initramfs was found in /boot."

# ------------------------------------------------------------
# Verify GRUB
# ------------------------------------------------------------

msg "VERIFYING GRUB"

[[ -s /boot/grub/grub.cfg ]] || \
    die "GRUB configuration was not generated."

grep -q "linux" /boot/grub/grub.cfg || \
    die "GRUB configuration does not contain a Linux entry."

find /efi/EFI \
    -maxdepth 3 \
    -type f \
    -iname '*.efi' |
    grep -q . ||
    die "No EFI bootloader file was found."

# ------------------------------------------------------------
# Verify services
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
# Verify installed commands
# ------------------------------------------------------------

msg "VERIFYING INSTALLED SOFTWARE"

command -v emerge >/dev/null || \
    die "emerge is missing."

command -v grub-install >/dev/null || \
    die "grub-install is missing."

command -v grub-mkconfig >/dev/null || \
    die "grub-mkconfig is missing."

command -v sddm >/dev/null || \
    die "sddm is missing."

command -v sudo >/dev/null || \
    die "sudo is missing."

command -v NetworkManager >/dev/null || \
    die "NetworkManager is missing."

command -v dracut >/dev/null || \
    die "dracut is missing."

command -v zramctl >/dev/null || \
    die "zramctl is missing."

command -v swapon >/dev/null || \
    die "swapon is missing."

# ------------------------------------------------------------
# Verify multilib
# ------------------------------------------------------------

msg "VERIFYING MULTILIB CONFIGURATION"

FINAL_PROFILE="$(readlink -f /etc/portage/make.profile)"

echo
echo "Profile:"
echo "  ${FINAL_PROFILE}"

[[ "${FINAL_PROFILE}" == */default/linux/amd64/23.0/desktop/plasma ]] || \
    die "Final profile is not the expected Plasma multilib profile."

ABI_X86_FINAL="$(
    emerge --info |
    sed -n 's/^ABI_X86="\([^"]*\)".*/\1/p'
)"

echo
echo "ABI_X86=${ABI_X86_FINAL}"

echo "${ABI_X86_FINAL}" | grep -qw "64" || \
    die "Final ABI_X86 does not contain 64."

echo "${ABI_X86_FINAL}" | grep -qw "32" || \
    die "Final ABI_X86 does not contain 32."

# ------------------------------------------------------------
# Verify user
# ------------------------------------------------------------

msg "VERIFYING USER ACCOUNT"

id "${USERNAME}" >/dev/null || \
    die "The user account was not created."

id -nG "${USERNAME}" | grep -qw wheel || \
    die "The user is not a member of the wheel group."

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
echo "EFI:"
find /efi/EFI \
    -maxdepth 3 \
    -type f \
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
echo "ZRAM:"
zramctl 2>/dev/null || true

echo
echo "============================================================"
echo "              INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Hostname      : ${HOSTNAME}"
echo "User          : ${USERNAME}"
echo "Profile       : ${PROFILE_TARGET}"
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

unset USER_PASSWORD
unset USER_PASSWORD_CONFIRM

exit 0
