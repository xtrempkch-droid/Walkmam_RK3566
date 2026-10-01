#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 8 ]]; then
    echo "Usage: $0 <image-file> <uboot-dir> <kernel-dir> <rootfs-dir> <device> <variant> <dtb-file> <dtb-name>" >&2
    exit 2
fi

IMAGE_FILE=$1
UBOOT_DIR=$2
KERNEL_DIR=$3
ROOTFS_DIR=$4
DEVICE=$5
VARIANT=$6
DTB_FILE=$7
DTB_NAME=$8
IMAGE_SIZE_MB=4096
BOOT_MOUNT=
ROOT_MOUNT=
LOOP_DEV=
MOUNT_DIR=

for file in \
    "$UBOOT_DIR/idbloader.img" \
    "$UBOOT_DIR/u-boot.itb" \
    "$KERNEL_DIR/arch/arm64/boot/Image" \
    "$DTB_FILE"; do
    if [[ ! -f $file ]]; then
        echo "Required image input not found: $file" >&2
        exit 1
    fi
done
if [[ ! -d $ROOTFS_DIR ]]; then
    echo "Root filesystem directory not found: $ROOTFS_DIR" >&2
    exit 1
fi
if [[ ! $DTB_NAME =~ ^[a-zA-Z0-9._-]+\.dtb$ ]]; then
    echo "Invalid DTB destination filename: $DTB_NAME" >&2
    exit 2
fi
if [[ -e $IMAGE_FILE || -e $IMAGE_FILE.gz ]]; then
    echo "Refusing to overwrite existing image: $IMAGE_FILE[.gz]" >&2
    exit 1
fi
if [[ $EUID -ne 0 ]]; then
    exec sudo -- "$0" "$@"
fi

cleanup() {
    local exit_code=$?
    set +e
    if [[ -n $BOOT_MOUNT ]]; then
        umount "$BOOT_MOUNT" 2>/dev/null
    fi
    if [[ -n $ROOT_MOUNT ]]; then
        umount "$ROOT_MOUNT" 2>/dev/null
    fi
    if [[ -n $LOOP_DEV ]]; then
        losetup -d "$LOOP_DEV" 2>/dev/null
    fi
    if [[ -n $MOUNT_DIR ]]; then
        rmdir "$MOUNT_DIR/boot" "$MOUNT_DIR/rootfs" "$MOUNT_DIR" 2>/dev/null
    fi
    exit "$exit_code"
}
trap cleanup EXIT

MOUNT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/walkmam-image.XXXXXX")
BOOT_MOUNT="$MOUNT_DIR/boot"
ROOT_MOUNT="$MOUNT_DIR/rootfs"
mkdir "$BOOT_MOUNT" "$ROOT_MOUNT"

echo "Creating ${IMAGE_SIZE_MB}MB SD card image: $IMAGE_FILE"
dd if=/dev/zero of="$IMAGE_FILE" bs=1M count="$IMAGE_SIZE_MB" status=progress
parted -s "$IMAGE_FILE" mklabel msdos
parted -s "$IMAGE_FILE" mkpart primary fat32 16MiB 144MiB
parted -s "$IMAGE_FILE" mkpart primary ext4 144MiB 100%

LOOP_DEV=$(losetup --find --partscan --show "$IMAGE_FILE")
BOOT_DEV="${LOOP_DEV}p1"
ROOT_DEV="${LOOP_DEV}p2"
for _ in {1..20}; do
    [[ -b $BOOT_DEV && -b $ROOT_DEV ]] && break
    sleep 0.25
done
if [[ ! -b $BOOT_DEV || ! -b $ROOT_DEV ]]; then
    echo "Partition devices were not created for $LOOP_DEV." >&2
    exit 1
fi

mkfs.vfat -F 32 -n BOOT "$BOOT_DEV"
mkfs.ext4 -F -L ROOTFS "$ROOT_DEV"
dd if="$UBOOT_DIR/idbloader.img" of="$LOOP_DEV" seek=64 conv=notrunc,fsync
dd if="$UBOOT_DIR/u-boot.itb" of="$LOOP_DEV" seek=16384 conv=notrunc,fsync

mount "$BOOT_DEV" "$BOOT_MOUNT"
mount "$ROOT_DEV" "$ROOT_MOUNT"
cp "$KERNEL_DIR/arch/arm64/boot/Image" "$BOOT_MOUNT/Image"
mkdir -p "$BOOT_MOUNT/dtbs" "$BOOT_MOUNT/extlinux"
for dtb in "$KERNEL_DIR"/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-*.dtb; do
    [[ -f $dtb ]] && cp "$dtb" "$BOOT_MOUNT/dtbs/"
done
cp "$DTB_FILE" "$BOOT_MOUNT/dtbs/$DTB_NAME"

X35S_DTB="$KERNEL_DIR/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-x35s.dtb"
if [[ $DEVICE == powkiddy-x35s && $(basename -- "$DTB_FILE") == rocknix-official-x35s.dtb ]]; then
    cp "$DTB_FILE" "$BOOT_MOUNT/dtbs/rk3566-powkiddy-x35s-rocknix.dtb"
    cat > "$BOOT_MOUNT/extlinux/extlinux.conf.x35s-rocknix" << 'BOOTCFG'
LABEL Mainline (X35S - DTB ROCKNIX)
    KERNEL /Image
    FDT /dtbs/rk3566-powkiddy-x35s-rocknix.dtb
    APPEND quiet rootwait earlycon=uart8250,mmio32,0xfe660000 console=ttyS2,1500000n8 console=tty1 root=/dev/mmcblk1p2 rw
BOOTCFG
fi
if [[ $DEVICE == powkiddy-x35s && -f $X35S_DTB ]]; then
    cp "$X35S_DTB" "$BOOT_MOUNT/dtbs/rk3566-powkiddy-x35s-nosso.dtb"
    cat > "$BOOT_MOUNT/extlinux/extlinux.conf.x35s-nosso" << 'BOOTCFG'
LABEL Mainline (X35S - nosso .dtb)
    KERNEL /Image
    FDT /dtbs/rk3566-powkiddy-x35s-nosso.dtb
    APPEND quiet rootwait earlycon=uart8250,mmio32,0xfe660000 console=ttyS2,1500000n8 console=tty1 root=/dev/mmcblk1p2 rw
BOOTCFG
fi

if [[ -f $BOOT_MOUNT/dtbs/rk3566-powkiddy-x55.dtb ]]; then
    cat > "$BOOT_MOUNT/extlinux/extlinux.conf.x55" << 'BOOTCFG'
LABEL Mainline (Powkiddy X55)
    KERNEL /Image
    FDT /dtbs/rk3566-powkiddy-x55.dtb
    APPEND quiet rootwait earlycon=uart8250,mmio32,0xfe660000 console=ttyS2,1500000n8 console=tty1 root=/dev/mmcblk1p2 rw
BOOTCFG
fi

cat > "$BOOT_MOUNT/extlinux/extlinux.conf" << BOOTCFG
LABEL Walkmam ($DEVICE - $VARIANT)
    KERNEL /Image
    FDT /dtbs/$DTB_NAME
    APPEND quiet rootwait earlycon=uart8250,mmio32,0xfe660000 console=ttyS2,1500000n8 console=tty1 root=/dev/mmcblk1p2 rw
BOOTCFG

cp -a "$ROOTFS_DIR"/. "$ROOT_MOUNT"/
umount "$BOOT_MOUNT"
BOOT_MOUNT=
umount "$ROOT_MOUNT"
ROOT_MOUNT=
losetup -d "$LOOP_DEV"
LOOP_DEV=
rmdir "$MOUNT_DIR/boot" "$MOUNT_DIR/rootfs" "$MOUNT_DIR"
MOUNT_DIR=
trap - EXIT

gzip -f -- "$IMAGE_FILE"
echo "Created image: $IMAGE_FILE.gz"
