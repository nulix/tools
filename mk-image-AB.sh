#!/bin/sh
set -e

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(dirname "$0")
RED="\\e[31m"
BLUE="\\e[34m"
WHITE="\\e[37m"
NC="\\e[0m"

# defaults
IMAGE_FILE="nulix-os"
BOOT_FILES_ARCHIVE="kernel-artifacts-*.tar.gz"
BOOT_FILES_ARCHIVE_PATH="${SCRIPT_DIR}/../nulix-bsp/${BOOT_FILES_ARCHIVE}"
ROOTFS_ARCHIVE="nulix-rootfs-*.tar.gz"
ROOTFS_ARCHIVE_PATH="${SCRIPT_DIR}/../nulix-rootfs/${ROOTFS_ARCHIVE}"
BOOT_PART="p1"
ROOTFS_PART="p5"

LOG_INF() {
  echo -e "${BLUE}INFO:${NC} ${SCRIPT_NAME}: ${@}"
}

LOG_DBG() {
  echo -e "${WHITE}DEBUG:${NC} ${SCRIPT_NAME}: ${@}"
}

LOG_ERR() {
  echo -e "${RED}ERROR:${NC} ${SCRIPT_NAME}: ${@}"
}

init() {
  LOG_INF "--- NULIX OS image wizard ---"

  if ! ls ${BOOT_FILES_ARCHIVE_PATH} > /dev/null; then
    LOG_ERR "boot files archive not found!"
    exit 1
  fi

  if ! ls ${ROOTFS_ARCHIVE_PATH} > /dev/null; then
    LOG_ERR "rootfs archive not found!"
    exit 1
  fi

  BOOT_FILES_ARCHIVE=$(basename $(ls ${BOOT_FILES_ARCHIVE_PATH} | sort -Vr | head -1))
  BOOT_FILES_ARCHIVE_PATH="${SCRIPT_DIR}/../nulix-bsp/${BOOT_FILES_ARCHIVE}"
  ROOTFS_ARCHIVE=$(basename $(ls ${ROOTFS_ARCHIVE_PATH} | sort -Vr | head -1))
  ROOTFS_ARCHIVE_PATH="${SCRIPT_DIR}/../nulix-rootfs/${ROOTFS_ARCHIVE}"
  ROOTFS_VER=$(echo $ROOTFS_ARCHIVE | cut -d "-" -f3 | sed "s/.tar.gz//")
  IMAGE_FILE=${IMAGE_FILE}-${ROOTFS_VER}.img
  LOG_INF "using rootfs: $ROOTFS_ARCHIVE_PATH"
  LOG_INF "using boot files: $BOOT_FILES_ARCHIVE_PATH"
  LOG_INF "resulting image: $IMAGE_FILE"
}

mk_image() {
  LOG_INF "creating partitioned image file ${IMAGE_FILE}"

  # blank image
  dd if=/dev/zero of=${IMAGE_FILE} bs=1M count=1536

  # prepare partitions
  (
    echo o;
    echo n; echo p; echo 1; echo; echo +100M; echo t; echo c;
    echo n; echo p; echo 2; echo; echo +100M; echo t; echo 2; echo c;
    echo n; echo e; echo 3; echo; echo;
    echo n; echo l; echo; echo +500M;
    echo n; echo l; echo; echo +500M;
    echo n; echo l; echo; echo;
    echo p; echo w;
  ) | fdisk ${IMAGE_FILE} || true
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
  tar xf ${ROOTFS_ARCHIVE_PATH} -C rootfs
  sync
}

setup_apps() {
  LOG_INF "setting up apps"

  mount ${DATA_PART} rootfs/data
  cp ${SCRIPT_DIR}/../nulix-rootfs/webserver-app*.tar.gz rootfs/data
  sync

  mount --bind /dev rootfs/dev
  mount --bind /proc rootfs/proc

  # import apps in chroot
  chroot rootfs /bin/sh <<"EOF"
  mkdir -p /data/docker
  mkdir -p /var/lib/docker
  mount --bind /data/docker /var/lib/docker

  mkdir -p /sys/fs/cgroup
  mount -t cgroup2 none /sys/fs/cgroup

  dockerd 2> /dev/null &
  sleep 3

  docker load -i data/webserver-app*.tar.gz
  docker run -d -p 8080:80 --restart unless-stopped --name webserver webserver:1.0.0
  sleep 1

  docker images
  docker ps

  kill $(pidof dockerd)
  sleep 2

  rm /data/*app*.tar.gz
  umount /sys/fs/cgroup
  umount /var/lib/docker
EOF

  umount rootfs/dev
  umount rootfs/proc
  umount rootfs/data
}

unmount_image() {
  LOG_INF "unmounting image"
  umount -l boot rootfs
  losetup -d ${LOOP_DEV}
  rm -rf boot rootfs
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
mk_image
mount_image
mkfs
setup_boot_files
setup_rootfs_files
#setup_apps
unmount_image
compress_image
