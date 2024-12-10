#!/bin/sh
set -e

# INSPIRED WITH:
# https://github.com/uptane/meta-updater/blob/master/classes/image_types_ota.bbclass

# dependencies
. globals.sh

# defaults
OSTREE_REPO="ostree_repo"
OSTREE_REPO_PATH="${SCRIPT_DIR}/../out/${OSTREE_REPO}"
OSTREE_MANIFEST="ostree_manifest"
OSTREE_MANIFEST_PATH="${SCRIPT_DIR}/../out/${OSTREE_MANIFEST}"
OTA_SYSROOT="ota-sysroot"
OSTREE_BRANCHNAME="main"
OSTREE_OSNAME="nulix"
IMAGE_FILE="nulix-os"
BOOT_PART="p1"
OTA_SYSROOT_PART="p2"

LOG_INF "--- NULIX OS image wizard ---"

init_os_img() {
  if ! which parted &> /dev/null; then
    LOG_ERR "parted is not installed!"
    exit 1
  fi

  if ! which ostree &> /dev/null; then
    LOG_ERR "ostree is not installed!"
    exit 1
  fi

  if [ -z "${OSTREE_REPO_PATH}" ]; then
    LOG_ERR "local ostree repo not set!"
    exit 1
  fi

  if ! ls ${OSTREE_REPO_PATH} > /dev/null; then
    LOG_ERR "local ostree repo not found!"
    exit 1
  fi

  if [ -z "${OSTREE_MANIFEST_PATH}" ]; then
    LOG_ERR "local ostree repo commit not set!"
    exit 1
  fi

  if ! ls ${OSTREE_MANIFEST_PATH} > /dev/null; then
    LOG_ERR "local ostree repo commit not found!"
    exit 1
  fi

  OSTREE_REPO="${OSTREE_REPO_PATH}"
  IMAGE_FILE=${IMAGE_FILE}-${ROOTFS_VER}.img

  LOG_INF "using OSTree repo: $OSTREE_REPO_PATH"
  LOG_INF "using OSTree repo commit: $OSTREE_MANIFEST_PATH"
  LOG_INF "resulting image: $IMAGE_FILE"
}

mk_image() {
  LOG_INF "creating partitioned image file ${IMAGE_FILE}"

  # blank image
  dd if=/dev/zero of=${IMAGE_FILE} bs=1M count=1024

  # prepare partitions
  parted -s ${IMAGE_FILE} mklabel msdos \
    mkpart primary fat32 0% 100MiB \
    mkpart primary ext4 100MiB 100% \
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

  mkfs.vfat -n boot ${LOOP_DEV}${BOOT_PART}
  mkfs.ext4 -L otaroot -i 4096 -t ext4 ${LOOP_DEV}${OTA_SYSROOT_PART}
}

setup_boot_files() {
  mkdir boot

  LOG_INF "setting up boot files"
  mount ${LOOP_DEV}${BOOT_PART} boot
  tar xzf ${BOOT_FILES_ARCHIVE_PATH} -C boot
  # dtb is needed for successful boot on rpi
  tar xzf ${KERNEL_ARTIFACTS_ARCHIVE_PATH} -C boot
  sync
}

setup_ota_sysroot_files() {
  mkdir ${OTA_SYSROOT}

  LOG_INF "setting up OTA sysroot files"
  mount ${LOOP_DEV}${OTA_SYSROOT_PART} ${OTA_SYSROOT}

  ostree admin --sysroot=${OTA_SYSROOT} init-fs --modern ${OTA_SYSROOT}
  ostree admin --sysroot=${OTA_SYSROOT} os-init ${OSTREE_OSNAME}

  # Preparation required to steer ostree bootloader detection
  mkdir -p ${OTA_SYSROOT}/boot/loader.0
  ln -s loader.0 ${OTA_SYSROOT}/boot/loader
  touch ${OTA_SYSROOT}/boot/loader/uEnv.txt

  # Apply generic configurations to the deployed repository; they are
  # specified as a series of "key:value ..." pairs.
  for cfg in ${OSTREE_OTA_REPO_CONFIG}; do
    ostree config --repo=${OTA_SYSROOT}/ostree/repo set \
           "$(echo "${cfg}" | cut -d ":" -f1)" \
           "$(echo "${cfg}" | cut -d ":" -f2-)"
  done

  ostree_target_hash=$(cat ${OSTREE_MANIFEST_PATH})

  # Use OSTree hash to avoid any potential race conditions between
  # multiple builds accessing the same ${OSTREE_REPO}.
  ostree --repo=${OTA_SYSROOT}/ostree/repo pull-local --remote=${OSTREE_OSNAME} ${OSTREE_REPO} ${ostree_target_hash}
  kargs_list=""
  for arg in $(printf '%s' "${OSTREE_KERNEL_ARGS}"); do
    kargs_list="${kargs_list} --karg-append=${arg}"
  done

  # Create the same reference on the device we use in the archive OSTree
  # repo in ${OSTREE_REPO}. This reference will show up when showing the
  # deployment on the device:
  # ostree admin status
  # If a remote with the name ${OSTREE_OSNAME} is configured, this also
  # will allow to use:
  # ostree admin upgrade
  ostree --repo=${OTA_SYSROOT}/ostree/repo refs --create=${OSTREE_OSNAME}:${OSTREE_BRANCHNAME} ${ostree_target_hash}
  ostree admin --sysroot=${OTA_SYSROOT} deploy ${kargs_list} --os=${OSTREE_OSNAME} ${OSTREE_OSNAME}:${OSTREE_BRANCHNAME}

  if [ "${OSTREE_SYSROOT_READONLY}" = "1" ]; then
    ostree config --repo=${OTA_SYSROOT}/ostree/repo set sysroot.readonly true
  fi

  # Create /var/sota if it doesn't exist yet
  mkdir -p ${OTA_SYSROOT}/ostree/deploy/${OSTREE_OSNAME}/var/sota
  # Ensure the permissions are correctly set
  chmod 700 ${OTA_SYSROOT}/ostree/deploy/${OSTREE_OSNAME}/var/sota

  mkdir -p ${OTA_SYSROOT}/ostree/deploy/${OSTREE_OSNAME}/var/rootdirs

  # Ensure that /var/local exists (AGL symlinks /usr/local to /var/local)
  install -d ${OTA_SYSROOT}/ostree/deploy/${OSTREE_OSNAME}/var/local
  # Set package version for the first deployment
  target_version=${ostree_target_hash}
	mkdir -p ${OTA_SYSROOT}/ostree/deploy/${OSTREE_OSNAME}/var/sota/import
	echo "{\"${ostree_target_hash}\":\"${GARAGE_TARGET_NAME}-${target_version}\"}" \
    > ${OTA_SYSROOT}/ostree/deploy/${OSTREE_OSNAME}/var/sota/import/installed_versions
}

setup_apps() {
  LOG_INF "setting up apps"

  ROOTFS="$OTA_SYSROOT/ostree/deploy/nulix/deploy"
  DEPLOY_DIR="$(ls $ROOTFS | head -1)"
  ROOTFS="$ROOTFS/$DEPLOY_DIR"

  cp /etc/resolv.conf ${ROOTFS}/etc

  mount --bind /dev ${ROOTFS}/dev
  mount --bind /proc ${ROOTFS}/proc

  # import apps in chroot
  chroot ${ROOTFS} /bin/sh <<"EOF"
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

  umount ${ROOTFS}/dev
  umount ${ROOTFS}/proc
}

unmount_image() {
  LOG_INF "unmounting image"
  umount -l boot ${OTA_SYSROOT}
  losetup -d ${LOOP_DEV}
  rm -rf boot ${OTA_SYSROOT}
}

compress_image() {
  LOG_INF "compressing image"
  rm -f ${SCRIPT_DIR}/../out/${IMAGE_FILE}.bz2
  bzip2 ${IMAGE_FILE}
  mv ${IMAGE_FILE}.bz2 ${SCRIPT_DIR}/../out

  LOG_INF "Done! Write the image using one of the following commands:"
  echo " $ bzcat /path/to/${IMAGE_FILE}.bz2 | sudo dd of=/dev/sdX bs=4M iflag=fullblock oflag=direct status=progress"
}

init
init_os_img
mk_image
mount_image
mkfs
setup_boot_files
setup_ota_sysroot_files
# setup_apps
unmount_image
compress_image
