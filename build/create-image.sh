#!/bin/bash

# Script para criar imagem SD bootável
# Uso: ./create-image.sh <image-file> <uboot-dir> <kernel-dir> <rootfs-dir> <device> <variant>

set -e

IMAGE_FILE="$1"
UBOOT_DIR="$2"
KERNEL_DIR="$3"
ROOTFS_DIR="$4"
DEVICE="$5"
VARIANT="$6"

if [ -z "$IMAGE_FILE" ] || [ -z "$UBOOT_DIR" ]; then
    echo "Usage: $0 <image-file> <uboot-dir> <kernel-dir> <rootfs-dir> <device> <variant>"
    exit 1
fi

IMAGE_SIZE_MB=4096

echo "Creating SD card image: $IMAGE_FILE"
echo "Size: ${IMAGE_SIZE_MB}MB"
echo "Device: $DEVICE"
echo "Variant: $VARIANT"

sudo bash << EOF
set -e

# Create empty image
dd if=/dev/zero of="${IMAGE_FILE}" bs=1M count=${IMAGE_SIZE_MB} status=progress

# Create partition table
parted -s "${IMAGE_FILE}" mklabel msdos
parted -s "${IMAGE_FILE}" mkpart primary fat32 16MiB 144MiB
parted -s "${IMAGE_FILE}" mkpart primary ext4 144MiB 100%

# Setup loop device
LOOP_DEV=\$(losetup -fP --show "${IMAGE_FILE}")
BOOT_DEV="\${LOOP_DEV}p1"
ROOT_DEV="\${LOOP_DEV}p2"

echo "Loop device: \$LOOP_DEV"

# Format partitions
mkfs.vfat -F 32 -n "BOOT" \${BOOT_DEV}
mkfs.ext4 -F -L "ROOTFS" \${ROOT_DEV}

# Mount partitions
mkdir -p /mnt/boot-temp /mnt/rootfs-temp
mount \${BOOT_DEV} /mnt/boot-temp
mount \${ROOT_DEV} /mnt/rootfs-temp

# Write U-Boot bootloader
dd if="${UBOOT_DIR}/idbloader.img" of=\${LOOP_DEV} seek=64 conv=notrunc,fsync
dd if="${UBOOT_DIR}/u-boot.itb" of=\${LOOP_DEV} seek=16384 conv=notrunc,fsync

# Copy kernel and device trees
cp "${KERNEL_DIR}/arch/arm64/boot/Image" /mnt/boot-temp/
mkdir -p /mnt/boot-temp/dtbs
cp "${KERNEL_DIR}/arch/arm64/boot/dts/rockchip/rk3566-powkiddy-"*.dtb /mnt/boot-temp/dtbs/ 2>/dev/null || true

# Select correct DTB based on device
case "$DEVICE" in
    powkiddy-x55)
        DTB_FILE="dtbs/rk3566-powkiddy-x55.dtb"
        ;;
    powkiddy-x35s|powkiddy-x35h)
        DTB_FILE="dtbs/rk3566-powkiddy-x35s.dtb"
        ;;
    *)
        DTB_FILE="dtbs/rk3566-powkiddy-x55.dtb"
        ;;
esac

# Create boot configuration
mkdir -p /mnt/boot-temp/extlinux
cat > /mnt/boot-temp/extlinux/extlinux.conf << BOOTCFG
LABEL Walkmam ($DEVICE - $VARIANT)
    KERNEL /Image
    FDT /\${DTB_FILE}
    APPEND quiet rootwait earlycon=uart8250,mmio32,0xfe660000 console=ttyS2,1500000n8 console=tty1 root=/dev/mmcblk1p2 rw
BOOTCFG

# Copy rootfs
echo "Copying rootfs (this may take a few minutes)..."
cp -a "${ROOTFS_DIR}"/* /mnt/rootfs-temp/

# Unmount and cleanup
umount /mnt/boot-temp
umount /mnt/rootfs-temp
losetup -d \${LOOP_DEV}

# Compress image
echo "Compressing image..."
gzip -f "${IMAGE_FILE}"

ls -lh "${IMAGE_FILE}.gz"
EOF

echo "Image created successfully: ${IMAGE_FILE}.gz"
