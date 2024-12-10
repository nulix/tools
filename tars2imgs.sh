#!/bin/sh
set -e

# dependencies
. globals.sh

LOG_INF "--- NULIX tar.gz to ext4 converter wizard ---"

init_imgs() {
  BOOT_FILES_IMAGE_FILE=$(echo $BOOT_FILES_ARCHIVE | sed "s/.tar.gz/.vfat/")
  ROOTFS_IMAGE_FILE=$(echo $ROOTFS_ARCHIVE | sed "s/.tar.gz/.ext4/")

  LOG_INF "resulting boot files image: $BOOT_FILES_IMAGE_FILE"
  LOG_INF "resulting rootfs image: $ROOTFS_IMAGE_FILE"
}

mk_imgs() {
  # blank boot files image
  LOG_INF "creating boot files image file: ${BOOT_FILES_IMAGE_FILE}"
  dd if=/dev/zero of=${BOOT_FILES_IMAGE_FILE} bs=1M count=100

  # blank rootfs image
  LOG_INF "creating rootfs image file: ${ROOTFS_IMAGE_FILE}"
  dd if=/dev/zero of=${ROOTFS_IMAGE_FILE} bs=1M count=500
}

mkfs() {
  LOG_INF "creating filesystem on the ${BOOT_FILES_IMAGE_FILE} image"
  mkfs.vfat -n boot ${BOOT_FILES_IMAGE_FILE}

  LOG_INF "creating filesystem on the ${ROOTFS_IMAGE_FILE} image"
  mkfs.ext4 -L rootfs ${ROOTFS_IMAGE_FILE}
}

mount_imgs() {
  LOG_INF "mounting ${BOOT_FILES_IMAGE_FILE} image"
  mkdir boot
  mount ${BOOT_FILES_IMAGE_FILE} boot -o loop

  LOG_INF "mounting ${ROOTFS_IMAGE_FILE} image"
  mkdir rootfs
  mount ${ROOTFS_IMAGE_FILE} rootfs -o loop
}

extract_boot_files() {
  LOG_INF "extracting ${BOOT_FILES_ARCHIVE_PATH}"
  tar xzf ${BOOT_FILES_ARCHIVE_PATH} -C boot
  sync
}

extract_rootfs_files() {
  LOG_INF "extracting ${ROOTFS_ARCHIVE_PATH}"
  tar xzf ${ROOTFS_ARCHIVE_PATH} -C rootfs
  sync
}

unmount_imgs() {
  LOG_INF "unmounting image"
  umount -l boot rootfs
  rm -rf boot rootfs
}

compress_imgs() {
  LOG_INF "compressing ${BOOT_FILES_IMAGE_FILE} image"
  gzip ${BOOT_FILES_IMAGE_FILE}

  LOG_INF "compressing ${ROOTFS_IMAGE_FILE} image"
  gzip ${ROOTFS_IMAGE_FILE}
}

init
init_imgs
mk_imgs
mkfs
mount_imgs
extract_boot_files
extract_rootfs_files
unmount_imgs
compress_imgs
