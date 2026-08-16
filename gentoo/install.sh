#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Gentoo installer
#
# Hardware:
#   AMD Ryzen 7 5700X
#   AMD Radeon RX 7600
#   Kingston KC3000 512 GB
#   16 GB RAM
#
# Target:
#   /dev/nvme0n1
#
# Configuration:
#   UEFI
#   GPT
#   1 GiB EFI
#   ext4 /
#   amd64 nomultilib
#   OpenRC
#   KDE Plasma 6
#   gentoo-kernel-bin
#   AMD firmware
#   NetworkManager
#   PipeWire + WirePlumber
#   SDDM
#   zram swap
#
# IMPORTANT:
#   /dev/nvme0n1 WILL BE ERASED.
# ============================================================

DISK="/dev/nvme0n1"
EFI="${DISK}p1"
ROOT="${DISK}p2"

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

TARGET="/mnt/gentoo"

# ------------------------------------------------------------
# Functions
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
    echo " INSTALAÇÃO INTERROMPIDA"
    echo "============================================================"
    echo
    echo "O sistema instalado pode estar incompleto."
    echo "Não reinicie automaticamente."
}

trap cleanup_on_error ERR

# ------------------------------------------------------------
# Root / UEFI checks
# ------------------------------------------------------------

[[ "$EUID" -eq 0 ]] || die "Execute como root."

[[ -d /sys/firmware/efi ]] || \
    die "A LiveGUI não parece estar inicializada em UEFI."

[[ -b "$DISK" ]] || \
    die "$DISK não existe."

DISK_TYPE="$(lsblk -dn -o TYPE "$DISK" | tr -d ' ')"

[[ "$DISK_TYPE" == "disk" ]] || \
    die "$DISK não parece ser um disco físico."

MODEL="$(lsblk -dn -o MODEL "$DISK" | sed 's/^[[:space:]]*//')"
SIZE="$(lsblk -dn -o SIZE "$DISK")"

# ------------------------------------------------------------
# Safety confirmation
# ------------------------------------------------------------

clear

echo "============================================================"
echo "              GENTOO AUTOMATED INSTALLER"
echo "============================================================"
echo
echo "HARDWARE DETECTADO"
echo
echo "Disco alvo : $DISK"
echo "Modelo     : $MODEL"
echo "Tamanho    : $SIZE"
echo
echo "PARTICIONAMENTO NOVO"
echo
echo "  $EFI   1 GiB       EFI System Partition"
echo "  $ROOT  restante    ext4 /"
echo
echo "CONFIGURAÇÃO"
echo
echo "  CPU       : Ryzen 7 5700X"
echo "  GPU       : Radeon RX 7600"
echo "  Init      : OpenRC"
echo "  Desktop   : KDE Plasma 6"
echo "  Kernel    : gentoo-kernel-bin"
echo "  Multilib  : NÃO"
echo "  Swap      : zram"
echo "  Hostname  : $HOSTNAME"
echo "  Usuário   : $USERNAME"
echo "  Locale    : $LOCALE"
echo "  Teclado   : $KEYMAP"
echo "  Timezone  : $TIMEZONE"
echo
echo "============================================================"
echo
echo "ATENÇÃO: TODO O CONTEÚDO DE $DISK SERÁ APAGADO."
echo
echo "O seu pendrive Ventoy (/dev/sda) NÃO será apagado."
echo
echo "Discos atualmente presentes:"
echo
lsblk -o NAME,SIZE,MODEL,FSTYPE,MOUNTPOINTS
echo
echo "============================================================"
echo

read -r -p 'Digite APAGAR para continuar: ' CONFIRM

[[ "$CONFIRM" == "APAGAR" ]] || \
    die "Instalação cancelada."

# ------------------------------------------------------------
# Password
# ------------------------------------------------------------

echo
echo "Defina a senha inicial do usuário '$USERNAME'."
echo "Você pode usar: 100tempo"
echo

read -r -s -p "Senha: " USER_PASSWORD
echo
read -r -s -p "Confirme: " USER_PASSWORD_CONFIRM
echo

[[ "$USER_PASSWORD" == "$USER_PASSWORD_CONFIRM" ]] || \
    die "As senhas não coincidem."

[[ -n "$USER_PASSWORD" ]] || \
    die "A senha não pode ser vazia."

# ------------------------------------------------------------
# Network
# ------------------------------------------------------------

msg "VERIFICANDO INTERNET"

if ! ping -c 3 -W 5 distfiles.gentoo.org >/dev/null 2>&1; then
    die "Sem acesso à internet."
fi

echo "Internet OK."

# ------------------------------------------------------------
# Date/time
# ------------------------------------------------------------

msg "VERIFICANDO DATA/HORA"

date

# ------------------------------------------------------------
# Stop swap and unmount target
# ------------------------------------------------------------

msg "PREPARANDO DISCO"

swapoff -a 2>/dev/null || true

umount "${DISK}"* 2>/dev/null || true

# ------------------------------------------------------------
# Destroy existing partition table
# ------------------------------------------------------------

msg "APAGANDO PARTIÇÕES EXISTENTES"

wipefs -a "$DISK"
sgdisk --zap-all "$DISK"

# ------------------------------------------------------------
# Create GPT
# ------------------------------------------------------------

msg "CRIANDO GPT"

sgdisk \
    --clear \
    --new=1:0:+1G \
    --typecode=1:ef00 \
    --change-name=1:"EFI System Partition" \
    --new=2:0:0 \
    --typecode=2:8300 \
    --change-name=2:"Gentoo Root" \
    "$DISK"

partprobe "$DISK"
sleep 3

# ------------------------------------------------------------
# Verify partitions
# ------------------------------------------------------------

msg "VERIFICANDO PARTICIONAMENTO"

lsblk "$DISK"

[[ -b "$EFI" ]] || die "Partição EFI não apareceu."
[[ -b "$ROOT" ]] || die "Partição root não apareceu."

# ------------------------------------------------------------
# Format
# ------------------------------------------------------------

msg "FORMATANDO EFI"

mkfs.fat -F 32 -n EFI "$EFI"

msg "FORMATANDO ROOT EXT4"

mkfs.ext4 -F -L gentoo-root "$ROOT"

# ------------------------------------------------------------
# Mount
# ------------------------------------------------------------

msg "MONTANDO GENTOO"

mkdir -p "$TARGET"

mount "$ROOT" "$TARGET"

mkdir -p "$TARGET/efi"

mount "$EFI" "$TARGET/efi"

# ------------------------------------------------------------
# Download Stage 3 nomultilib OpenRC
# ------------------------------------------------------------

msg "DESCOBRINDO STAGE 3 NOMULTILIB OPENRC"

STAGE_BASE="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-nomultilib-openrc"

STAGE_FILE="$(
    wget -qO- \
    "${STAGE_BASE}/latest-stage3-amd64-nomultilib-openrc.txt" |
    awk '!/^#/ && /stage3-amd64-nomultilib-openrc-.*\.tar\.xz$/ {
        print $1
        exit
    }'
)"

[[ -n "$STAGE_FILE" ]] || \
    die "Não consegui descobrir o Stage 3."

echo
echo "Stage 3:"
echo "  $STAGE_FILE"
echo

cd "$TARGET"

wget -c \
    "${STAGE_BASE}/${STAGE_FILE}"

wget -c \
    "${STAGE_BASE}/${STAGE_FILE}.sha256"

# ------------------------------------------------------------
# Verify Stage 3
# ------------------------------------------------------------

msg "VERIFICANDO CHECKSUM DO STAGE 3"

sha256sum -c "${STAGE_FILE}.sha256"

# ------------------------------------------------------------
# Extract Stage 3
# ------------------------------------------------------------

msg "EXTRAINDO STAGE 3"

tar xpvf "$STAGE_FILE" \
    --xattrs-include='*.*' \
    --numeric-owner

rm -f \
    "$STAGE_FILE" \
    "${STAGE_FILE}.sha256"

# ------------------------------------------------------------
# DNS
# ------------------------------------------------------------

msg "CONFIGURANDO DNS"

cp --dereference \
    /etc/resolv.conf \
    "$TARGET/etc/resolv.conf"

# ------------------------------------------------------------
# fstab
# ------------------------------------------------------------

msg "GERANDO FSTAB"

ROOT_UUID="$(blkid -s UUID -o value "$ROOT")"
EFI_UUID="$(blkid -s UUID -o value "$EFI")"

cat > "$TARGET/etc/fstab" <<EOF
# Gentoo root
UUID=${ROOT_UUID}    /       ext4    noatime,errors=remount-ro    0 1

# EFI System Partition
UUID=${EFI_UUID}     /efi    vfat    umask=0077                0 2
EOF

# ------------------------------------------------------------
# Mount virtual filesystems
# ------------------------------------------------------------

msg "MONTANDO FILESYSTEMS VIRTUAIS"

mount --types proc /proc "$TARGET/proc"

mount --rbind /sys "$TARGET/sys"
mount --make-rslave "$TARGET/sys"

mount --rbind /dev "$TARGET/dev"
mount --make-rslave "$TARGET/dev"

mount --rbind /run "$TARGET/run"
mount --make-rslave "$TARGET/run"

cp --dereference \
    /etc/resolv.conf \
    "$TARGET/etc/resolv.conf"

# ------------------------------------------------------------
# Pass variables safely into chroot
# ------------------------------------------------------------

export GENTOO_HOSTNAME="$HOSTNAME"
export GENTOO_USERNAME="$USERNAME"
export GENTOO_PASSWORD="$USER_PASSWORD"
export GENTOO_TIMEZONE="$TIMEZONE"
export GENTOO_LOCALE="$LOCALE"
export GENTOO_KEYMAP="$KEYMAP"
export GENTOO_CFLAGS="$CFLAGS"
export GENTOO_CXXFLAGS="$CXXFLAGS"
export GENTOO_MAKEOPTS="$MAKEOPTS"

# ------------------------------------------------------------
# Create chroot installer
# ------------------------------------------------------------

msg "PREPARANDO INSTALADOR DENTRO DO GENTOO"

cat > "$TARGET/root/install-inside-gentoo.sh" <<'CHROOT'
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

# ------------------------------------------------------------
# Portage configuration
# ------------------------------------------------------------

msg "CONFIGURANDO PORTAGE"

mkdir -p /etc/portage

cat > /etc/portage/make.conf <<EOF
COMMON_FLAGS="${CFLAGS}"

CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="${CXXFLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"

MAKEOPTS="${MAKEOPTS}"

VIDEO_CARDS="amdgpu radeonsi"
INPUT_DEVICES="libinput"

GRUB_PLATFORMS="efi-64"

L10N="en-US"
LINGUAS="en"

# No multilib:
ABI_X86="64"
EOF

# ------------------------------------------------------------
# Confirm no-multilib profile
# ------------------------------------------------------------

msg "VERIFICANDO PROFILE"

eselect profile list

PROFILE="$(eselect profile list | awk '
    /no-multilib/ && !/systemd/ && !/hardened/ {
        line=$0
        sub(/^[^]]*\] /, "", line)
        print line
        exit
    }
')"

if [[ -n "$PROFILE" ]]; then
    echo "Profile detectado: $PROFILE"
else
    echo
    echo "O Stage 3 já deve estar usando o profile no-multilib."
    echo "Profile atual:"
    readlink -f /etc/portage/make.profile || true
fi

# ------------------------------------------------------------
# Repository synchronization
# ------------------------------------------------------------

msg "SINCRONIZANDO REPOSITÓRIO GENTOO"

emerge --sync

# ------------------------------------------------------------
# Confirm profile after sync
# ------------------------------------------------------------

msg "PROFILE APÓS SINCRONIZAÇÃO"

eselect profile list

CURRENT_PROFILE="$(readlink -f /etc/portage/make.profile)"

echo
echo "Profile atual:"
echo "  $CURRENT_PROFILE"
echo

if [[ "$CURRENT_PROFILE" != *"/no-multilib"* ]]; then
    echo "O profile atual não é no-multilib."
    echo
    echo "Profiles disponíveis:"
    eselect profile list
    echo
    echo "Tentando selecionar automaticamente o primeiro profile"
    echo "amd64 23.0 no-multilib que não seja systemd/hardened."

    NOMULTILIB_PROFILE="$(
        eselect profile list |
        awk '
            /no-multilib/ && !/systemd/ && !/hardened/ {
                line=$0
                sub(/^[^]]*\] /, "", line)
                print line
                exit
            }
        '
    )"

    [[ -n "$NOMULTILIB_PROFILE" ]] || \
        die "Não consegui encontrar um profile no-multilib."

    echo "Selecionando: $NOMULTILIB_PROFILE"

    eselect profile set "$NOMULTILIB_PROFILE"
fi

# ------------------------------------------------------------
# Update system
# ------------------------------------------------------------

msg "ATUALIZANDO BASE DO SISTEMA"

emerge --ask=n \
    --verbose \
    --update \
    --deep \
    --newuse \
    @world

# ------------------------------------------------------------
# Locale
# ------------------------------------------------------------

msg "CONFIGURANDO LOCALE"

cat > /etc/locale.gen <<EOF
en_US.UTF-8 UTF-8
EOF

locale-gen

eselect locale set en_US.utf8

# ------------------------------------------------------------
# Timezone
# ------------------------------------------------------------

msg "CONFIGURANDO TIMEZONE"

ln -sf \
    "/usr/share/zoneinfo/${TIMEZONE}" \
    /etc/localtime

echo "${TIMEZONE}" > /etc/timezone

# ------------------------------------------------------------
# Keyboard
# ------------------------------------------------------------

msg "CONFIGURANDO TECLADO"

cat > /etc/conf.d/keymaps <<EOF
keymap="${KEYMAP}"
EOF

# ------------------------------------------------------------
# Hostname
# ------------------------------------------------------------

msg "CONFIGURANDO HOSTNAME"

echo "$HOSTNAME" > /etc/hostname

cat > /etc/hosts <<EOF
127.0.0.1       localhost
::1             localhost
127.0.1.1       ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# ------------------------------------------------------------
# Package USE flags
# ------------------------------------------------------------

msg "CONFIGURANDO USE FLAGS DO DESKTOP"

mkdir -p /etc/portage/package.use

cat > /etc/portage/package.use/desktop <<EOF
# KDE Plasma
kde-plasma/plasma-meta display-manager sddm xwayland gtk kwallet discover

# SDDM
x11-misc/sddm elogind

# NetworkManager
net-misc/networkmanager elogind

# PipeWire
media-video/pipewire sound-server pipewire-alsa pipewire-pulse

# WirePlumber
media-video/wireplumber elogind

# X/Wayland
x11-base/xorg-server elogind

# AMD firmware
sys-kernel/linux-firmware redistributable
EOF

# ------------------------------------------------------------
# Install base desktop stack
# ------------------------------------------------------------

msg "INSTALANDO KERNEL + FIRMWARE"

emerge --ask=n \
    sys-kernel/gentoo-kernel-bin \
    sys-kernel/linux-firmware \
    sys-firmware/amd-microcode

msg "INSTALANDO REDE"

emerge --ask=n \
    net-misc/networkmanager

msg "INSTALANDO SESSÃO GRÁFICA"

emerge --ask=n \
    sys-auth/elogind \
    sys-auth/polkit \
    sys-apps/dbus

msg "INSTALANDO KDE PLASMA"

emerge --ask=n \
    kde-plasma/plasma-meta \
    x11-misc/sddm \
    gui-libs/display-manager-init

msg "INSTALANDO ÁUDIO"

emerge --ask=n \
    media-video/pipewire \
    media-sound/wireplumber

# ------------------------------------------------------------
# Useful KDE applications
# ------------------------------------------------------------

msg "INSTALANDO APLICATIVOS KDE BÁSICOS"

emerge --ask=n \
    kde-apps/dolphin \
    kde-apps/konsole \
    kde-apps/ark

# ------------------------------------------------------------
# System utilities
# ------------------------------------------------------------

msg "INSTALANDO UTILITÁRIOS"

emerge --ask=n \
    app-admin/sudo \
    app-portage/gentoolkit \
    app-portage/eix \
    app-editors/nano \
    sys-apps/util-linux

# ------------------------------------------------------------
# AMD GPU
# ------------------------------------------------------------

msg "CONFIGURANDO AMDGPU"

mkdir -p /etc/modprobe.d

cat > /etc/modprobe.d/amdgpu.conf <<EOF
# AMD Radeon RX 7600
options amdgpu dc=1
EOF

# ------------------------------------------------------------
# NetworkManager
# ------------------------------------------------------------

msg "ATIVANDO NETWORKMANAGER"

rc-update add NetworkManager default

# ------------------------------------------------------------
# D-Bus
# ------------------------------------------------------------

msg "ATIVANDO DBUS"

rc-update add dbus default

# ------------------------------------------------------------
# elogind
# ------------------------------------------------------------

msg "ATIVANDO ELOGIND"

rc-update add elogind boot

# ------------------------------------------------------------
# Display manager
# ------------------------------------------------------------

msg "CONFIGURANDO SDDM"

cat > /etc/conf.d/display-manager <<EOF
DISPLAYMANAGER="sddm"
EOF

rc-update add display-manager default

# ------------------------------------------------------------
# zram OpenRC service
# ------------------------------------------------------------

msg "CONFIGURANDO ZRAM"

cat > /etc/init.d/zram-swap <<'EOF'
#!/sbin/openrc-run

description="Compressed zram swap"

depend() {
    need localmount
    after bootmisc
}

start_pre() {
    modprobe zram num_devices=1

    if ! zramctl /dev/zram0 >/dev/null 2>&1; then
        return 1
    fi

    # 8 GiB maximum compressed swap
    zramctl --algorithm zstd --size 8G /dev/zram0

    mkswap -L zram0 /dev/zram0 >/dev/null
}

start() {
    ebegin "Enabling zram swap"
    swapon --priority 100 /dev/zram0
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
# GRUB
# ------------------------------------------------------------

msg "INSTALANDO GRUB UEFI"

emerge --ask=n sys-boot/grub

grub-install \
    --target=x86_64-efi \
    --efi-directory=/efi \
    --bootloader-id=Gentoo \
    --recheck

grub-mkconfig -o /boot/grub/grub.cfg

# ------------------------------------------------------------
# User
# ------------------------------------------------------------

msg "CRIANDO USUÁRIO ${USERNAME}"

if id "$USERNAME" >/dev/null 2>&1; then
    echo "Usuário já existe."
else
    useradd \
        --create-home \
        --shell /bin/bash \
        --groups wheel,audio,video,input \
        "$USERNAME"
fi

echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

# Root também recebe a senha inicial.
echo "root:${USER_PASSWORD}" | chpasswd

# ------------------------------------------------------------
# sudo
# ------------------------------------------------------------

msg "CONFIGURANDO SUDO"

mkdir -p /etc/sudoers.d

cat > /etc/sudoers.d/wheel <<EOF
%wheel ALL=(ALL:ALL) ALL
EOF

chmod 440 /etc/sudoers.d/wheel

visudo -c

# ------------------------------------------------------------
# Make sure /boot has kernel
# ------------------------------------------------------------

msg "VERIFICANDO KERNEL"

ls -lh /boot

KERNEL_FOUND=0

for f in /boot/vmlinuz-*; do
    if [[ -e "$f" ]]; then
        KERNEL_FOUND=1
        break
    fi
done

[[ "$KERNEL_FOUND" -eq 1 ]] || \
    die "Nenhum kernel foi encontrado em /boot."

# ------------------------------------------------------------
# Rebuild world after configuration
# ------------------------------------------------------------

msg "ATUALIZAÇÃO FINAL"

emerge --ask=n \
    --update \
    --deep \
    --newuse \
    @world

# ------------------------------------------------------------
# Regenerate GRUB after final kernel installation
# ------------------------------------------------------------

msg "REGENERANDO GRUB"

grub-mkconfig -o /boot/grub/grub.cfg

# ------------------------------------------------------------
# Final checks
# ------------------------------------------------------------

msg "VERIFICAÇÃO FINAL"

echo
echo "Profile:"
readlink -f /etc/portage/make.profile

echo
echo "Kernel:"
ls -lh /boot/vmlinuz-* 2>/dev/null || true

echo
echo "EFI:"
find /efi/EFI -maxdepth 2 -type f 2>/dev/null || true

echo
echo "Serviços OpenRC:"
rc-update show

echo
echo "Usuário:"
id "$USERNAME"

echo
echo "Filesystem:"
df -h /

echo
echo "ZRAM service:"
rc-service zram-swap status || true

echo
echo "============================================================"
echo " GENTOO INSTALADO"
echo "============================================================"
echo
echo "Hostname : $HOSTNAME"
echo "Usuário  : $USERNAME"
echo "Desktop  : KDE Plasma"
echo "Init     : OpenRC"
echo "Kernel   : gentoo-kernel-bin"
echo "GPU      : AMDGPU / Radeon RX 7600"
echo "Multilib : desativado"
echo "Swap     : zram 8 GiB"
echo
echo "A senha inicial foi definida durante a execução."
echo
echo "Você pode alterá-la depois com:"
echo
echo "  passwd"
echo
echo "============================================================"

# ------------------------------------------------------------
# Remove sensitive installer
# ------------------------------------------------------------

unset USER_PASSWORD

rm -f /root/install-inside-gentoo.sh

exit 0
CHROOT

chmod +x "$TARGET/root/install-inside-gentoo.sh"

# ------------------------------------------------------------
# Run chroot installer
# ------------------------------------------------------------

msg "INICIANDO INSTALAÇÃO DENTRO DO GENTOO"

chroot "$TARGET" /bin/bash -c '
    source /etc/profile
    export PS1="(gentoo) ${PS1:-\\u@\\h \\w\\$ }"
    /root/install-inside-gentoo.sh
'

# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------

msg "LIMPANDO"

rm -f "$TARGET/root/install-inside-gentoo.sh"

sync

echo
echo "============================================================"
echo "           INSTALAÇÃO CONCLUÍDA COM SUCESSO"
echo "============================================================"
echo
echo "O Gentoo foi instalado em:"
echo
echo "  $DISK"
echo
echo "Agora execute:"
echo
echo "  umount -R $TARGET"
echo "  sync"
echo "  reboot"
echo
echo "Quando o computador reiniciar, retire o pendrive."
echo
echo "============================================================"
