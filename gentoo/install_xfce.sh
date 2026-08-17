#!/usr/bin/env bash
set -Eeuo pipefail

# Configuration
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
MAKEOPTS="-j16"

STAGE_BASE="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc"

msg() {
    echo
    echo "============================================================"
    echo " $*"
    echo "============================================================"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

[[ "${EUID}" -eq 0 ]] || die "Must be run as root."
[[ -d /sys/firmware/efi ]] || die "Live system not booted in UEFI mode."

clear
echo "============================================================"
echo "          GENTOO FAST INSTALLER (XFCE + LIGHTDM)"
echo "============================================================"
echo "Target: ${DISK} (ALL DATA WILL BE ERASED)"
echo "User:   ${USERNAME}"
echo "============================================================"
echo

msg "CONFIGURING INITIAL PASSWORD"
read -r -s -p "Password: " USER_PASSWORD
echo
read -r -s -p "Confirm password: " USER_PASSWORD_CONFIRM
echo
[[ "${USER_PASSWORD}" == "${USER_PASSWORD_CONFIRM}" ]] || die "Passwords do not match."

msg "CHECKING INTERNET"
wget -q --spider --timeout=15 "https://distfiles.gentoo.org/" || die "No internet connection."

msg "PREPARING DISK"
swapoff -a 2>/dev/null || true
umount -R "${TARGET}" 2>/dev/null || true
umount "${DISK}"* 2>/dev/null || true

wipefs -af "${DISK}"
sgdisk --zap-all "${DISK}"

msg "CREATING PARTITIONS"
sgdisk \
    --clear \
    --new=1:2048:+1G --typecode=1:ef00 --change-name=1:"EFI System Partition" \
    --new=2:0:0       --typecode=2:8300 --change-name=2:"Gentoo Root" \
    "${DISK}"

partprobe "${DISK}" || true
blockdev --rereadpt "${DISK}" 2>/dev/null || true
udevadm settle 2>/dev/null || true
sleep 3

[[ -b "${EFI}" ]] || die "EFI partition missing."
[[ -b "${ROOT}" ]] || die "Root partition missing."

msg "FORMATTING FILESYSTEMS"
mkfs.fat -F 32 -n EFI "${EFI}"
mkfs.ext4 -F -L gentoo-root "${ROOT}"

msg "MOUNTING TARGET"
mkdir -p "${TARGET}"
mount "${ROOT}" "${TARGET}"
mkdir -p "${TARGET}/efi"
mount "${EFI}" "${TARGET}/efi"

msg "DOWNLOADING AND EXTRACTING STAGE 3"
mkdir -p "${TARGET}/var/tmp"
cd "${TARGET}/var/tmp"

STAGE_FILE="$(wget -qO- "${STAGE_BASE}/latest-stage3-amd64-openrc.txt" | awk '!/^#/ && $1 ~ /^stage3-amd64-openrc-.*\.tar\.xz$/ {print $1; exit}')"
[[ -n "${STAGE_FILE}" ]] || die "Failed to locate Stage 3 tarball."

wget --progress=bar:force -c "${STAGE_BASE}/${STAGE_FILE}"
wget --progress=bar:force -c "${STAGE_BASE}/${STAGE_FILE}.sha256"
sha256sum -c "${STAGE_FILE}.sha256"

cd "${TARGET}"
tar xpf "/mnt/gentoo/var/tmp/${STAGE_FILE}" --xattrs-include='*.*' --numeric-owner
rm -f "/mnt/gentoo/var/tmp/${STAGE_FILE}"*

msg "CONFIGURING BASE SYSTEM DATA"
mkdir -p "${TARGET}/proc" "${TARGET}/sys" "${TARGET}/dev" "${TARGET}/run" "${TARGET}/etc/portage/repos.conf" "${TARGET}/var/db/repos"

if [[ -e /etc/resolv.conf ]]; then
    cp --dereference /etc/resolv.conf "${TARGET}/etc/resolv.conf"
else
    cat > "${TARGET}/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
fi

ROOT_UUID="$(blkid -s UUID -o value "${ROOT}")"
EFI_UUID="$(blkid -s UUID -o value "${EFI}")"

cat > "${TARGET}/etc/fstab" <<EOF
UUID=${ROOT_UUID}    /        ext4    noatime,errors=remount-ro    0 1
UUID=${EFI_UUID}     /efi     vfat    umask=0077                  0 2
EOF

mount --types proc /proc "${TARGET}/proc"
mount --rbind /sys "${TARGET}/sys" && mount --make-rslave "${TARGET}/sys"
mount --rbind /dev "${TARGET}/dev" && mount --make-rslave "${TARGET}/dev"
mount --rbind /run "${TARGET}/run" && mount --make-rslave "${TARGET}/run"

if [[ -L "${TARGET}/dev/shm" ]]; then
    rm -f "${TARGET}/dev/shm"
    mkdir -p "${TARGET}/dev/shm"
fi
chmod 1777 "${TARGET}/dev/shm"

cat > "${TARGET}/etc/portage/repos.conf/gentoo.conf" <<'EOF'
[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
sync-rsync-verify-metamanifest = yes
sync-rsync-verify-jobs = 1
EOF

export GENTOO_HOSTNAME="${HOSTNAME}"
export GENTOO_USERNAME="${USERNAME}"
export GENTOO_PASSWORD="${USER_PASSWORD}"
export GENTOO_TIMEZONE="${TIMEZONE}"
export GENTOO_LOCALE="${LOCALE}"
export GENTOO_KEYMAP="${KEYMAP}"
export GENTOO_CFLAGS="${CFLAGS}"
export GENTOO_CXXFLAGS="${CXXFLAGS}"
export GENTOO_MAKEOPTS="${MAKEOPTS}"

msg "GENERATING CHROOT SCRIPT"
cat > "${TARGET}/root/install-inside.sh" <<'CHROOT_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

HOSTNAME="${GENTOO_HOSTNAME}"
USERNAME="${GENTOO_USERNAME}"
USER_PASSWORD="${GENTOO_PASSWORD}"
TIMEZONE="${GENTOO_TIMEZONE}"
LOCALE="${GENTOO_LOCALE}"
KEYMAP="${GENTOO_KEYMAP}"
CFLAGS="${GENTOO_CFLAGS}"
CXXFLAGS="${GENTOO_CXXFLAGS}"
MAKEOPTS="${GENTOO_MAKEOPTS}"

echo "============================================================"
echo " CONFIGURING PORTAGE & ENVIRONMENT INSIDE CHROOT"
echo "============================================================"

mkdir -p /etc/portage/package.use /etc/portage/package.license /etc/portage/binrepos.conf

# Configure Official Gentoo Binary Repository
cat > /etc/portage/binrepos.conf/gentoo.conf <<'EOF'
[gentoobinhost]
priority = 1
sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64
EOF

# Video USE flag fix
cat > /etc/portage/package.use/video <<'EOF'
x11-libs/libdrm video_cards_radeon
EOF

# Portage configuration
cat > /etc/portage/make.conf <<EOF
COMMON_FLAGS="${CFLAGS}"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"
MAKEOPTS="${MAKEOPTS}"
EMERGE_DEFAULT_OPTS="--getbinpkg=y --binpkg-respect-use=n --binpkg-changed-deps=n"
ABI_X86="64 32"
VIDEO_CARDS="amdgpu radeonsi radeon"
INPUT_DEVICES="libinput"
GRUB_PLATFORMS="efi-64"
USE="elogind X wayland pipewire sound-server -systemd -gpm"
L10N="en-US"
LINGUAS="en"
ACCEPT_LICENSE="-* @FREE @BINARY-REDISTRIBUTABLE"
EOF

cat > /etc/portage/package.use/installkernel <<'EOF'
sys-kernel/installkernel dracut grub -systemd
EOF

cat > /etc/portage/package.license/firmware <<'EOF'
sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE
EOF

# Added -truetype to pillow to break docutils -> pillow -> harfbuzz -> glib cycle
cat > /etc/portage/package.use/desktop <<'EOF'
x11-misc/lightdm gtk
net-misc/networkmanager elogind
media-video/pipewire sound-server pipewire-alsa pipewire-pulse elogind
media-video/wireplumber elogind
dev-python/pillow -truetype
EOF

# Reliable Portage tree sync
emerge --sync || emerge-webrsync

# Select standard desktop profile (matches merged-usr Stage 3)
eselect profile set "default/linux/amd64/23.0/desktop"

echo "Updating base system..."
emerge --ask=n --update --deep --newuse --with-bdeps=y @world

echo "Configuring System Settings..."
cat > /etc/locale.gen <<'EOF'
en_US.UTF-8 UTF-8
pt_BR.UTF-8 UTF-8
EOF
locale-gen
eselect locale set en_US.utf8

ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
echo "${TIMEZONE}" > /etc/timezone
echo "keymap=\"${KEYMAP}\"" > /etc/conf.d/keymaps
echo "${HOSTNAME}" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1       localhost
::1             localhost
127.0.1.1       ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

echo "Installing Kernel, Firmware, XFCE, and LightDM..."
emerge --ask=n --usepkg \
    sys-kernel/gentoo-kernel-bin \
    sys-kernel/linux-firmware \
    xfce-base/xfce4-meta \
    xfce-extra/xfce4-terminal \
    x11-misc/lightdm \
    x11-misc/lightdm-gtk-greeter \
    app-admin/sudo app-editors/nano app-portage/gentoolkit \
    sys-apps/pciutils sys-apps/usbutils sys-process/htop \
    net-misc/networkmanager sys-apps/dbus sys-auth/elogind \
    gui-libs/display-manager-init \
    media-video/pipewire media-video/wireplumber \
    sys-boot/grub sys-boot/efibootmgr sys-apps/util-linux

echo "Configuring Services..."
rc-update del dhcpcd default 2>/dev/null || true
rc-update add NetworkManager default
rc-update add dbus default
rc-update add elogind boot

cat > /etc/conf.d/display-manager <<'EOF'
CHECKVT=7
DISPLAYMANAGER="lightdm"
EOF
rc-update add display-manager default

# ZRAM Setup
cat > /etc/init.d/zram-swap <<'EOF'
#!/sbin/openrc-run
description="Compressed zram swap"
depend() { need localmount; after bootmisc; }
start_pre() {
    modprobe zram num_devices=1
    zramctl --reset /dev/zram0 2>/dev/null || true
    echo zstd > /sys/block/zram0/comp_algorithm
    echo 8589934592 > /sys/block/zram0/disksize
    mkswap -L zram0 /dev/zram0 >/dev/null
}
start() { ebegin "Enabling zram"; swapon --priority 100 /dev/zram0; eend $?; }
stop() { ebegin "Disabling zram"; swapoff /dev/zram0 2>/dev/null || true; zramctl --reset /dev/zram0 2>/dev/null || true; eend 0; }
EOF
chmod +x /etc/init.d/zram-swap
rc-update add zram-swap default

echo "Installing Bootloader..."
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=Gentoo --recheck

echo "Creating User Accounts..."
if ! id "${USERNAME}" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G wheel,audio,video,input,plugdev "${USERNAME}"
fi
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
echo "root:${USER_PASSWORD}" | chpasswd

mkdir -p /etc/sudoers.d
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

echo "Building Initramfs and GRUB Config..."
KERNEL_VERSION="$(find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tail -n 1)"
dracut --force /boot/initramfs-"${KERNEL_VERSION}".img "${KERNEL_VERSION}"
grub-mkconfig -o /boot/grub/grub.cfg

rm -f /root/install-inside.sh
CHROOT_SCRIPT

chmod 700 "${TARGET}/root/install-inside.sh"

msg "RUNNING CHROOT INSTALLATION PROCESS"
chroot "${TARGET}" /bin/bash -c '
    source /etc/profile
    export HOME=/root
    export TERM="${TERM:-xterm}"
    /root/install-inside.sh
'

msg "CLEANING UP"
sync
umount -R "${TARGET}" || true

echo
echo "============================================================"
echo "          GENTOO INSTALLATION COMPLETE!"
echo "============================================================"
echo " You may now reboot your system."
echo "============================================================"
