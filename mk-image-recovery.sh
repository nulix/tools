#!/bin/sh
set -e

# dependencies
. globals.sh

# defaults
IMAGE_FILE="nulix-os"
RECOVERY_INITRAMFS="initramfs-recovery"
RECOVERY_INITRAMFS_PATH="${SCRIPT_DIR}/../nulix-rootfs/${RECOVERY_INITRAMFS}"
RAUC_RECOVERY_OS_BUNDLE="ota-update-os-rpi.raucb"
RAUC_RECOVERY_OS_BUNDLE_PATH="${SCRIPT_DIR}/../nulix-rootfs/${RAUC_RECOVERY_OS_BUNDLE}"
BOOT_PART="p1"
ROOTFS_PART="p2"
RECOVERY_PART="p3"

LOG_INF "--- NULIX OS image wizard ---"

init_os_img() {
  if ! which parted &> /dev/null; then
    LOG_ERR "parted is not installed!"
    exit 1
  fi

  if [ -z "${RECOVERY_INITRAMFS_PATH}" ]; then
    LOG_ERR "recovery initramfs not set!"
    exit 1
  fi

  if ! ls ${RECOVERY_INITRAMFS_PATH} > /dev/null; then
    LOG_ERR "recovery initramfs not found!"
    exit 1
  fi

  if [ -z "${RAUC_RECOVERY_OS_BUNDLE_PATH}" ]; then
    LOG_ERR "rauc recovery OS bundle not set!"
    exit 1
  fi

  if ! ls ${RAUC_RECOVERY_OS_BUNDLE_PATH} > /dev/null; then
    LOG_ERR "rauc recovery OS bundle not found!"
    exit 1
  fi

  IMAGE_FILE=${IMAGE_FILE}-${ROOTFS_VER}.img

  LOG_INF "using recovery initramfs: $RECOVERY_INITRAMFS_PATH"
  LOG_INF "using rauc recovery OS bundle: $RAUC_RECOVERY_OS_BUNDLE_PATH"
  LOG_INF "resulting image: $IMAGE_FILE"
}

mk_image() {
  LOG_INF "creating partitioned image file ${IMAGE_FILE}"

  # blank image
  dd if=/dev/zero of=${IMAGE_FILE} bs=1M count=1024

  # prepare partitions
  parted -s ${IMAGE_FILE} mklabel msdos \
    mkpart primary fat32 0% 100MiB \
    mkpart primary ext4 100MiB 600MiB \
    mkpart primary ext4 600MiB 800MiB \
    mkpart primary ext4 800MiB 100% \
    print
}

mount_image() {
  LOG_INF "attaching ${IMAGE_FILE} to loop device"

  losetup -fP ${IMAGE_FILE}
  losetup -a
  LOOP_DEV=$(losetup -a | cut -d ":" -f1)
}

mkfs() {
  LOG_INF "formatting partitions"

  DATA_PART=$(ls ${LOOP_DEV}* | tail -n1)

  mkfs.vfat -n boot ${LOOP_DEV}${BOOT_PART}
  mkfs.ext4 -L rootfs ${LOOP_DEV}${ROOTFS_PART}
  mkfs.ext4 -L recovery ${LOOP_DEV}${RECOVERY_PART}
  mkfs.ext4 -L data ${DATA_PART}
}

setup_boot_files() {
  mkdir boot

  LOG_INF "setting up boot files"
  mount ${LOOP_DEV}${BOOT_PART} boot
  tar xzf ${BOOT_FILES_ARCHIVE_PATH} -C boot
  sync
}

setup_rootfs_files() {
  mkdir rootfs

  LOG_INF "setting up rootfs files"
  mount ${LOOP_DEV}${ROOTFS_PART} rootfs
  tar xzf ${ROOTFS_ARCHIVE_PATH} -C rootfs
  sync
}

setup_recovery_files() {
  mkdir recovery

  LOG_INF "setting up recovery files"
  mount ${LOOP_DEV}${RECOVERY_PART} recovery
  cp -v ${RECOVERY_INITRAMFS_PATH} recovery
  cp -v boot/Image recovery
  #cp -v ${RAUC_RECOVERY_OS_BUNDLE_PATH} recovery
  sync
}

setup_apps() {
  LOG_INF "setting up apps"

  cp /etc/resolv.conf rootfs/etc
  mount ${DATA_PART} rootfs/data
  mount --bind /dev rootfs/dev
  mount --bind /proc rootfs/proc

  # import apps in chroot
  chroot rootfs /bin/sh <<"EOF"
  mkdir -p /data/docker
  mount --bind /data/docker /var/lib/docker

  mkdir -p /sys/fs/cgroup
  mount -t cgroup2 none /sys/fs/cgroup

  dockerd 2> /dev/null &
  sleep 3

  cd /var/apps
  docker compose up -d
  sleep 1

  docker images
  docker ps

  kill $(pidof dockerd)
  sleep 2

  umount /sys/fs/cgroup
  umount /var/lib/docker
  rm /etc/resolv.conf
EOF

  umount rootfs/dev
  umount rootfs/proc
  umount rootfs/data
}

unmount_image() {
  LOG_INF "unmounting image"
  umount -l boot rootfs recovery
  losetup -d ${LOOP_DEV}
  rm -rf boot rootfs recovery
}

compress_image() {
  LOG_INF "compressing image"
  rm -f ${IMAGE_FILE}.bz2
  bzip2 ${IMAGE_FILE}
  mv ${IMAGE_FILE}.bz2 ${SCRIPT_DIR}/..

  LOG_INF "Done! Write the image using one of the following commands:"
  echo " $ bzcat /path/to/${IMAGE_FILE}.bz2 | sudo dd of=/dev/sdX bs=1M conv=fsync status=progress"
  echo " $ bmaptool copy /path/to/${IMAGE_FILE}.bz2 /dev/sdX"
}

init
init_os_img
mk_image
mount_image
mkfs
setup_boot_files
setup_rootfs_files
setup_recovery_files
setup_apps
unmount_image
compress_image
