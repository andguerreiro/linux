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
#   Remaining space: ext4 root filesystem
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
# Confirmed hardware from LiveGUI:
#
#   /dev/sda
#     DataTraveler 3.0
#     Ventoy USB
#
#   /dev/nvme0n1
#     KINGSTON SKC3000S512G
#
# ============================================================

set -Eeuo pipefail

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

# Ryzen 7 5700X has 16 threads and the machine has 16 GiB RAM.
# -j8 is a conservative setting for this installation.
MAKEOPTS="-j8"

# Gentoo amd64 Plasma profile without systemd.
# This is the multilib profile.
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
    echo
    echo "============================================================"
    echo " INSTALLATION FAILED"
    echo "============================================================"
    echo
    echo "The target system may be partially installed."
    echo
    echo "Mounted target filesystems:"
    mount | grep "${TARGET}" || true
    echo
}

trap cleanup_on_error ERR

# ------------------------------------------------------------
# Basic checks
# ------------------------------------------------------------

[[ "${EUID}" -eq 0 ]] || \
    die "This installer must be run as root."

[[ -d /sys/firmware/efi ]] || \
    die "The LiveGUI was not booted in UEFI mode."

[[ -d /sys/firmware/efi/efivars ]] || \
    die "EFI variables are not available."

[[ -b "${DISK}" ]] || \
    die "${DISK} does not exist."

command -v lsblk >/dev/null 2>&1 || \
    die "lsblk is not available."

command -v sgdisk >/dev/null 2>&1 || \
    die "sgdisk is not available."

command -v wipefs >/dev/null 2>&1 || \
    die "wipefs is not available."

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

command -v partprobe >/dev/null 2>&1 || \
    die "partprobe is not available."

command -v udevadm >/dev/null 2>&1 || \
    die "udevadm is not available."

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
echo "EXPECTED TARGET:"
echo
echo "  KINGSTON SKC3000S512G"
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
# User password
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

# ------------------------------------------------------------
# Root password
# ------------------------------------------------------------

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

wget -q --spider https://distfiles.gentoo.org/ || \
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

umount "${DISK}"* 2>/dev/null || true

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

sleep 2

[[ -b "${EFI}" ]] || \
    die "EFI partition was not created."

[[ -b "${ROOT}" ]] || \
    die "Root partition was not created."

# ------------------------------------------------------------
# Format filesystems
# ------------------------------------------------------------

msg "FORMATTING EFI PARTITION"

mkfs.fat -F 32 -n EFI "${EFI}"

msg "FORMATTING ROOT PARTITION"

mkfs.ext4 -F -L gentoo-root "${ROOT}"

# ------------------------------------------------------------
# Mount target
# ------------------------------------------------------------

msg "MOUNTING TARGET FILESYSTEM"

mkdir -p "${TARGET}"

mount "${ROOT}" "${TARGET}"

mkdir -p "${TARGET}/efi"

mount "${EFI}" "${TARGET}/efi"

# ------------------------------------------------------------
# Find latest Stage 3
# ------------------------------------------------------------

msg "FINDING LATEST AMD64 OPENRC STAGE 3"

STAGE_BASE="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc"

STAGE_FILE="$(
    wget -qO- \
        "${STAGE_BASE}/latest-stage3-amd64-openrc.txt" |
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

wget -c "${STAGE_BASE}/${STAGE_FILE}"
wget -c "${STAGE_BASE}/${STAGE_FILE}.sha256"

# ------------------------------------------------------------
# Verify Stage 3 checksum
# ------------------------------------------------------------

msg "VERIFYING STAGE 3 CHECKSUM"

sha256sum -c "${STAGE_FILE}.sha256"

# ------------------------------------------------------------
# Extract Stage 3
# ------------------------------------------------------------

msg "EXTRACTING STAGE 3"

tar xpvf "${STAGE_FILE}" \
    --xattrs-include='*.*' \
    --numeric-owner

rm -f \
    "${STAGE_FILE}" \
    "${STAGE_FILE}.sha256"

# ------------------------------------------------------------
# DNS
# ------------------------------------------------------------

msg "CONFIGURING DNS"

cp --dereference \
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
UUID=${EFI_UUID}     /efi    vfat    umask=0077                0 2
EOF

# ------------------------------------------------------------
# Mount virtual filesystems
# ------------------------------------------------------------

msg "MOUNTING VIRTUAL FILESYSTEMS"

mount --types proc /proc "${TARGET}/proc"

mount --rbind /sys "${TARGET}/sys"
mount --make-rslave "${TARGET}/sys"

mount --rbind /dev "${TARGET}/dev"
mount --make-rslave "${TARGET}/dev"

mount --rbind /run "${TARGET}/run"
mount --make-rslave "${TARGET}/run"

cp --dereference \
    /etc/resolv.conf \
    "${TARGET}/etc/resolv.conf"

# ------------------------------------------------------------
# Export installation variables
# ------------------------------------------------------------

export GENTOO_HOSTNAME="${HOSTNAME}"
export GENTOO_USERNAME="${USERNAME}"
export GENTOO_PASSWORD="${USER_PASSWORD}"
export GENTOO_ROOT_PASSWORD="${ROOT_PASSWORD}"
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

HOSTNAME="${GENTOO_HOSTNAME}"
USERNAME="${GENTOO_USERNAME}"

USER_PASSWORD="${GENTOO_PASSWORD}"
ROOT_PASSWORD="${GENTOO_ROOT_PASSWORD}"

TIMEZONE="${GENTOO_TIMEZONE}"
LOCALE="${GENTOO_LOCALE}"
KEYMAP="${GENTOO_KEYMAP}"

CFLAGS="${GENTOO_CFLAGS}"
CXXFLAGS="${GENTOO_CXXFLAGS}"
MAKEOPTS="${GENTOO_MAKEOPTS}"
PROFILE="${GENTOO_PROFILE}"

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
# Basic chroot checks
# ------------------------------------------------------------

[[ "${EUID}" -eq 0 ]] || \
    die "Chroot installer must run as root."

[[ -d /sys/firmware/efi ]] || \
    die "EFI firmware directory is not visible inside chroot."

[[ -d /sys/firmware/efi/efivars ]] || \
    die "EFI variables are not visible inside chroot."

command -v eselect >/dev/null 2>&1 || \
    die "eselect is not available."

command -v emerge >/dev/null 2>&1 || \
    die "emerge is not available."

# ------------------------------------------------------------
# Portage configuration
# ------------------------------------------------------------

msg "CONFIGURING PORTAGE"

mkdir -p /etc/portage/package.use
mkdir -p /etc/portage/package.license

# Modern Gentoo allows /etc/portage/make.conf to be a directory.
# Preserve the original Stage 3 configuration instead of replacing it.
if [[ -f /etc/portage/make.conf ]]; then
    mv /etc/portage/make.conf /etc/portage/make.conf/00-stage3
elif [[ ! -d /etc/portage/make.conf ]]; then
    mkdir -p /etc/portage/make.conf
fi

cat > /etc/portage/make.conf/99-gentoo-installer <<EOF
# ============================================================
# Local Gentoo installer configuration
# ============================================================

COMMON_FLAGS="${CFLAGS}"

CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="${CXXFLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

MAKEOPTS="${MAKEOPTS}"

# Distribution kernel support.
USE="dist-kernel"

# UEFI GRUB support.
GRUB_PLATFORMS="efi-64"

# English userland/build messages.
LINGUAS="en"

# Firmware licenses required for linux-firmware.
ACCEPT_LICENSE="-* @FREE @BINARY-REDISTRIBUTABLE"
EOF

# ------------------------------------------------------------
# USE_EXPAND configuration
# ------------------------------------------------------------

msg "CONFIGURING HARDWARE AND LOCALIZATION USE FLAGS"

cat > /etc/portage/package.use/00-local <<EOF
# AMD graphics
*/* VIDEO_CARDS: amdgpu radeonsi

# Generic Linux input stack
*/* INPUT_DEVICES: libinput

# English localization
*/* L10N: en-US

# KDE Plasma
kde-plasma/plasma-meta sddm pulseaudio

# NetworkManager
net-misc/networkmanager elogind wifi

# PipeWire
media-video/pipewire sound-server pipewire-alsa pulseaudio elogind

# WirePlumber
media-video/wireplumber elogind

# Distribution kernel installation
sys-kernel/installkernel dracut grub
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
# Select correct profile
# ------------------------------------------------------------

msg "SELECTING GENTOO AMD64 PLASMA OPENRC PROFILE"

PROFILE_NUMBER="$(
    eselect profile list |
    awk -v wanted="${PROFILE}" '
        index($0, wanted) {
            match($0, /\[[0-9]+\]/)
            if (RSTART > 0) {
                print substr($0, RSTART + 1, RLENGTH - 2)
                exit
            }
        }
    '
)"

[[ -n "${PROFILE_NUMBER}" ]] || \
    die "Could not find profile: ${PROFILE}"

echo
echo "Profile:"
echo "  ${PROFILE}"
echo
echo "Profile number:"
echo "  ${PROFILE_NUMBER}"
echo

eselect profile set "${PROFILE_NUMBER}"

CURRENT_PROFILE="$(readlink -f /etc/portage/make.profile)"

echo
echo "Current profile:"
echo "  ${CURRENT_PROFILE}"
echo

[[ "${CURRENT_PROFILE}" == *"/amd64/23.0/desktop/plasma" ]] || \
    die "The installed system is not using amd64/23.0/desktop/plasma."

[[ "${CURRENT_PROFILE}" != *"no-multilib"* ]] || \
    die "The installed system is using a no-multilib profile."

[[ "${CURRENT_PROFILE}" != *"/systemd" ]] || \
    die "The installed system is using a systemd profile."

# ------------------------------------------------------------
# Verify multilib
# ------------------------------------------------------------

msg "VERIFYING MULTILIB"

ABI_X86_VALUE="$(
    emerge --info |
    awk -F= '/^ABI_X86=/{print $2}'
)"

echo
echo "ABI_X86=${ABI_X86_VALUE}"
echo

echo "${ABI_X86_VALUE}" |
    grep -Eq '(^|[[:space:]"'\''])32([[:space:]"'\'']|$)' || \
    die "ABI_X86 does not contain 32-bit support."

echo "Multilib is enabled."

# ------------------------------------------------------------
# Verify Portage configuration
# ------------------------------------------------------------

msg "VERIFYING PORTAGE CONFIGURATION"

echo
echo "CFLAGS:"
emerge --info | grep '^CFLAGS=' || true

echo
echo "MAKEOPTS:"
emerge --info | grep '^MAKEOPTS=' || true

echo
echo "VIDEO_CARDS:"
emerge --info | grep '^VIDEO_CARDS=' || true

echo
echo "INPUT_DEVICES:"
emerge --info | grep '^INPUT_DEVICES=' || true

echo
echo "L10N:"
emerge --info | grep '^L10N=' || true

echo
echo "USE flags relevant to installation:"
emerge --info | grep '^USE=' || true

# ------------------------------------------------------------
# Update base system after profile selection
# ------------------------------------------------------------

msg "UPDATING BASE SYSTEM AFTER PROFILE SELECTION"

emerge --ask=n \
    --verbose \
    --update \
    --deep \
    --newuse \
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

cat > /etc/conf.d/hostname <<EOF
hostname="${HOSTNAME}"
EOF

cat > /etc/hosts <<EOF
127.0.0.1       localhost
::1             localhost
127.0.1.1       ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# ------------------------------------------------------------
# Install GRUB BEFORE THE DISTRIBUTION KERNEL
# ------------------------------------------------------------

msg "INSTALLING GRUB AND EFIBOOTMGR"

emerge --ask=n \
    sys-boot/grub \
    sys-boot/efibootmgr

# ------------------------------------------------------------
# Install GRUB into EFI System Partition
# ------------------------------------------------------------

msg "INSTALLING GRUB UEFI BOOTLOADER"

grub-install \
    --target=x86_64-efi \
    --efi-directory=/efi \
    --bootloader-id=Gentoo \
    --recheck

# Verify that the firmware entry was created.
if command -v efibootmgr >/dev/null 2>&1; then
    echo
    echo "EFI boot entries:"
    efibootmgr

    efibootmgr |
        grep -q "Gentoo" || \
        die "GRUB was installed but no Gentoo EFI boot entry was found."
fi

# ------------------------------------------------------------
# Install distribution kernel and firmware
# ------------------------------------------------------------

msg "INSTALLING DISTRIBUTION KERNEL AND FIRMWARE"

emerge --ask=n \
    sys-kernel/gentoo-kernel-bin \
    sys-kernel/linux-firmware

# Explicitly run the kernel package configuration step.
# This follows the Handbook's documented method for regenerating
# the initramfs of a distribution kernel when necessary.
msg "CONFIGURING DISTRIBUTION KERNEL"

emerge --ask=n \
    --config \
    sys-kernel/gentoo-kernel-bin

# ------------------------------------------------------------
# Install KDE Plasma
# ------------------------------------------------------------

msg "INSTALLING KDE PLASMA"

emerge --ask=n \
    kde-plasma/plasma-meta

# ------------------------------------------------------------
# Install KDE applications
# ------------------------------------------------------------

msg "INSTALLING KDE APPLICATIONS"

emerge --ask=n \
    kde-apps/dolphin \
    kde-apps/konsole \
    kde-apps/ark

# ------------------------------------------------------------
# Install basic utilities
# ------------------------------------------------------------

msg "INSTALLING BASIC UTILITIES"

emerge --ask=n \
    app-admin/sudo \
    app-editors/nano \
    sys-process/htop

# ------------------------------------------------------------
# NetworkManager
# ------------------------------------------------------------

msg "CONFIGURING NETWORKMANAGER"

emerge --ask=n \
    net-misc/networkmanager

# Remove competing network management services.
rc-update del dhcpcd default 2>/dev/null || true
rc-update del dhcpcd boot 2>/dev/null || true

for service in \
    net.eth0 \
    net.enp1s0 \
    net.enp2s0 \
    net.enp3s0 \
    net.wlan0 \
    net.wlp2s0
do
    rc-update del "${service}" default 2>/dev/null || true
    rc-update del "${service}" boot 2>/dev/null || true
done

rc-update add NetworkManager default

# ------------------------------------------------------------
# D-Bus
# ------------------------------------------------------------

msg "CONFIGURING D-BUS"

emerge --ask=n \
    sys-apps/dbus

rc-update add dbus default

# ------------------------------------------------------------
# elogind
# ------------------------------------------------------------

msg "CONFIGURING ELOGIND"

emerge --ask=n \
    sys-auth/elogind

rc-update add elogind boot

# ------------------------------------------------------------
# SDDM
# ------------------------------------------------------------

msg "CONFIGURING SDDM"

emerge --ask=n \
    x11-misc/sddm \
    gui-libs/display-manager-init

cat > /etc/conf.d/display-manager <<EOF
CHECKVT=7
DISPLAYMANAGER="sddm"
EOF

rc-update add display-manager default

# ------------------------------------------------------------
# PipeWire and WirePlumber
# ------------------------------------------------------------

msg "CONFIGURING PIPEWIRE AUDIO"

emerge --ask=n \
    media-video/pipewire \
    media-video/wireplumber

# PipeWire and WirePlumber are user-session services.
# With elogind + KDE they are started through the user's session.
#
# The pipewire package is built with:
#   sound-server
#   pipewire-alsa
#   pulseaudio
#   elogind
#
# No system-wide OpenRC PipeWire service is enabled.

# ------------------------------------------------------------
# AMD GPU
# ------------------------------------------------------------

msg "CONFIGURING AMD GPU"

# No forced amdgpu module options are needed.
# The RX 7600 uses the normal amdgpu defaults.

rm -f /etc/modprobe.d/amdgpu.conf 2>/dev/null || true

# ------------------------------------------------------------
# ZRAM
# ------------------------------------------------------------

msg "CONFIGURING 8 GIB ZRAM SWAP"

emerge --ask=n \
    sys-apps/util-linux

cat > /etc/init.d/zram-swap <<'EOF'
#!/sbin/openrc-run

description="Compressed zram swap"

depend() {
    need localmount
    after bootmisc
}

start_pre() {
    modprobe zram

    if [ ! -b /dev/zram0 ]; then
        return 1
    fi

    zramctl --reset /dev/zram0 2>/dev/null || true

    zramctl \
        --algorithm zstd \
        --size 8G \
        /dev/zram0

    mkswap -L zram0 /dev/zram0 >/dev/null
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

    swapoff /dev/zram0 2>/dev/null || true
    zramctl --reset /dev/zram0 2>/dev/null || true

    eend 0
}
EOF

chmod +x /etc/init.d/zram-swap

rc-update add zram-swap default

# ------------------------------------------------------------
# Chrony
# ------------------------------------------------------------

msg "CONFIGURING TIME SYNCHRONIZATION"

emerge --ask=n \
    net-misc/chrony

rc-update add chronyd default

# ------------------------------------------------------------
# User account
# ------------------------------------------------------------

msg "CREATING USER ACCOUNT"

if ! id "${USERNAME}" >/dev/null 2>&1; then
    useradd \
        --create-home \
        --shell /bin/bash \
        --groups wheel,audio,video,input,plugdev \
        "${USERNAME}"
else
    usermod \
        --append \
        --groups wheel,audio,video,input,plugdev \
        "${USERNAME}"
fi

echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

# Separate root password.
echo "root:${ROOT_PASSWORD}" | chpasswd

# ------------------------------------------------------------
# SDDM permissions
# ------------------------------------------------------------

if id sddm >/dev/null 2>&1; then
    usermod \
        --append \
        --groups video \
        sddm || true
fi

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

emerge --ask=n \
    --update \
    --deep \
    --newuse \
    @world

# ------------------------------------------------------------
# Regenerate distribution kernel/initramfs
# ------------------------------------------------------------

msg "REGENERATING DISTRIBUTION KERNEL INITRAMFS"

emerge --ask=n \
    --config \
    sys-kernel/gentoo-kernel-bin

# ------------------------------------------------------------
# Generate GRUB configuration
# ------------------------------------------------------------

msg "GENERATING GRUB CONFIGURATION"

grub-mkconfig \
    -o /boot/grub/grub.cfg

# ------------------------------------------------------------
# Verify kernel
# ------------------------------------------------------------

msg "VERIFYING KERNEL"

echo
echo "Kernel images:"
ls -lh /boot/vmlinuz-* 2>/dev/null || true

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
# Verify initramfs
# ------------------------------------------------------------

msg "VERIFYING INITRAMFS"

echo
echo "Initramfs images:"
ls -lh /boot/initramfs-* 2>/dev/null || true

INITRAMFS_COUNT="$(
    find /boot \
        -maxdepth 1 \
        -type f \
        -name 'initramfs-*' |
    wc -l
)"

[[ "${INITRAMFS_COUNT}" -gt 0 ]] || \
    die "No initramfs was found in /boot."

# ------------------------------------------------------------
# Verify GRUB
# ------------------------------------------------------------

msg "VERIFYING GRUB"

[[ -f /boot/grub/grub.cfg ]] || \
    die "GRUB configuration was not generated."

grep -Eq 'linux|vmlinuz' /boot/grub/grub.cfg || \
    die "GRUB configuration does not contain a Linux entry."

# ------------------------------------------------------------
# Verify EFI files
# ------------------------------------------------------------

msg "VERIFYING EFI INSTALLATION"

[[ -d /efi/EFI ]] || \
    die "EFI directory does not exist."

find /efi/EFI \
    -maxdepth 3 \
    -type f \
    -print

# ------------------------------------------------------------
# Verify EFI firmware entry
# ------------------------------------------------------------

msg "VERIFYING EFI BOOT ENTRY"

efibootmgr

efibootmgr |
    grep -q "Gentoo" || \
    die "No Gentoo EFI boot entry was found."

# ------------------------------------------------------------
# Verify OpenRC services
# ------------------------------------------------------------

msg "VERIFYING OPENRC SERVICES"

echo
echo "Enabled services:"
echo

rc-update show

# Explicit checks.
rc-update show default | grep -q "NetworkManager" || \
    die "NetworkManager is not enabled in default runlevel."

rc-update show default | grep -q "dbus" || \
    die "D-Bus is not enabled in default runlevel."

rc-update show boot | grep -q "elogind" || \
    die "elogind is not enabled in boot runlevel."

rc-update show default | grep -q "display-manager" || \
    die "display-manager is not enabled in default runlevel."

rc-update show default | grep -q "zram-swap" || \
    die "zram-swap is not enabled in default runlevel."

rc-update show default | grep -q "chronyd" || \
    die "chronyd is not enabled in default runlevel."

# ------------------------------------------------------------
# Verify multilib
# ------------------------------------------------------------

msg "VERIFYING MULTILIB"

echo
echo "Profile:"
readlink -f /etc/portage/make.profile

echo
echo "ABI_X86:"
emerge --info | grep '^ABI_X86=' || true

ABI_X86_FINAL="$(
    emerge --info |
    awk -F= '/^ABI_X86=/{print $2}'
)"

echo "${ABI_X86_FINAL}" |
    grep -Eq '(^|[[:space:]"'\''])32([[:space:]"'\'']|$)' || \
    die "Final ABI_X86 does not contain 32-bit support."

# ------------------------------------------------------------
# Verify important packages
# ------------------------------------------------------------

msg "VERIFYING IMPORTANT PACKAGES"

for package in \
    sys-kernel/gentoo-kernel-bin \
    sys-kernel/linux-firmware \
    sys-kernel/dracut \
    sys-kernel/installkernel \
    sys-boot/grub \
    sys-boot/efibootmgr \
    kde-plasma/plasma-meta \
    x11-misc/sddm \
    gui-libs/display-manager-init \
    net-misc/networkmanager \
    sys-apps/dbus \
    sys-auth/elogind \
    media-video/pipewire \
    media-video/wireplumber \
    net-misc/chrony
do
    has_version "${package}" || \
        die "Required package is not installed: ${package}"
done

# ------------------------------------------------------------
# Verify user
# ------------------------------------------------------------

msg "VERIFYING USER ACCOUNT"

id "${USERNAME}"

echo
echo "Groups:"
id -nG "${USERNAME}"

# ------------------------------------------------------------
# Verify filesystem
# ------------------------------------------------------------

msg "VERIFYING FILESYSTEMS"

echo
echo "Root:"
df -h /

echo
echo "EFI:"
df -h /efi

echo
echo "fstab:"
cat /etc/fstab

# ------------------------------------------------------------
# Verify zram configuration
# ------------------------------------------------------------

msg "VERIFYING ZRAM CONFIGURATION"

echo
zramctl 2>/dev/null || true

echo
grep -E 'zram|swap' /etc/init.d/zram-swap || true

# ------------------------------------------------------------
# Verify Portage configuration
# ------------------------------------------------------------

msg "FINAL PORTAGE CONFIGURATION"

echo
echo "Profile:"
readlink -f /etc/portage/make.profile

echo
echo "ABI_X86:"
emerge --info | grep '^ABI_X86=' || true

echo
echo "VIDEO_CARDS:"
emerge --info | grep '^VIDEO_CARDS=' || true

echo
echo "INPUT_DEVICES:"
emerge --info | grep '^INPUT_DEVICES=' || true

echo
echo "L10N:"
emerge --info | grep '^L10N=' || true

echo
echo "GRUB_PLATFORMS:"
emerge --info | grep '^GRUB_PLATFORMS=' || true

echo
echo "USE:"
emerge --info | grep '^USE=' || true

# ------------------------------------------------------------
# Final summary
# ------------------------------------------------------------

msg "FINAL INSTALLATION CHECK"

echo
echo "============================================================"
echo "              INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Hostname     : ${HOSTNAME}"
echo "User         : ${USERNAME}"
echo "Desktop      : KDE Plasma"
echo "Login        : SDDM"
echo "Init         : OpenRC"
echo "Network      : NetworkManager"
echo "Audio        : PipeWire + WirePlumber"
echo "Kernel       : gentoo-kernel-bin"
echo "Initramfs    : dracut"
echo "Bootloader   : GRUB UEFI"
echo "GPU          : AMD Radeon RX 7600"
echo "Architecture : amd64 multilib"
echo "Swap         : 8 GiB zram"
echo "Root FS      : ext4"
echo "EFI          : 1 GiB FAT32"
echo "Profile      : ${PROFILE}"
echo
echo "The user and root passwords were configured separately."
echo
echo "After first boot, you can change the user password with:"
echo
echo "    passwd"
echo
echo "============================================================"

# ------------------------------------------------------------
# Remove sensitive information
# ------------------------------------------------------------

unset USER_PASSWORD
unset ROOT_PASSWORD
unset GENTOO_PASSWORD
unset GENTOO_ROOT_PASSWORD

rm -f /root/install-inside-gentoo.sh

exit 0
CHROOT_SCRIPT

chmod +x "${TARGET}/root/install-inside-gentoo.sh"

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
# Remove sensitive variables from LiveGUI shell
# ------------------------------------------------------------

unset USER_PASSWORD
unset USER_PASSWORD_CONFIRM
unset ROOT_PASSWORD
unset ROOT_PASSWORD_CONFIRM
unset GENTOO_PASSWORD
unset GENTOO_ROOT_PASSWORD

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
echo "Target:"
echo
echo "    KINGSTON SKC3000S512G"
echo
echo "Next steps:"
echo
echo "    umount -R ${TARGET}"
echo "    sync"
echo "    reboot"
echo
echo "Remove the LiveGUI/Ventoy USB drive when the machine restarts."
echo
echo "============================================================"
