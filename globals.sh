#!/bin/sh
set -e

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(dirname "$0")
RED="\\e[31m"
BLUE="\\e[34m"
WHITE="\\e[37m"
NC="\\e[0m"

# defaults
BOOT_FILES_ARCHIVE="boot-artifacts-*.tar.gz"
BOOT_FILES_ARCHIVE_PATH="${SCRIPT_DIR}/../out/${BOOT_FILES_ARCHIVE}"
KERNEL_ARTIFACTS_ARCHIVE="kernel-artifacts-*.tar.gz"
KERNEL_ARTIFACTS_ARCHIVE_PATH="${SCRIPT_DIR}/../out/${KERNEL_ARTIFACTS_ARCHIVE}"
ROOTFS_ARCHIVE="nulix-rootfs-*.tar.gz"
ROOTFS_ARCHIVE_PATH="${SCRIPT_DIR}/../out/${ROOTFS_ARCHIVE}"

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
  if [ -z "${BOOT_FILES_ARCHIVE_PATH}" ]; then
    LOG_ERR "boot files archive not set!"
    exit 1
  fi

  if ! ls ${BOOT_FILES_ARCHIVE_PATH} > /dev/null; then
    LOG_ERR "boot files archive not found!"
    exit 1
  fi

  if [ -z "${KERNEL_ARTIFACTS_ARCHIVE_PATH}" ]; then
    LOG_ERR "kernel artifacts archive not set!"
    exit 1
  fi

  if ! ls ${KERNEL_ARTIFACTS_ARCHIVE_PATH} > /dev/null; then
    LOG_ERR "kernel artifacts archive not found!"
    exit 1
  fi

  if [ -z "${ROOTFS_ARCHIVE_PATH}" ]; then
    LOG_ERR "rootfs archive not set!"
    exit 1
  fi

  if ! ls ${ROOTFS_ARCHIVE_PATH} > /dev/null; then
    LOG_ERR "rootfs archive not found!"
    exit 1
  fi

  BOOT_FILES_ARCHIVE=$(basename $(ls ${BOOT_FILES_ARCHIVE_PATH} | sort -Vr | head -1))
  BOOT_FILES_ARCHIVE_PATH="${SCRIPT_DIR}/../out/${BOOT_FILES_ARCHIVE}"
  KERNEL_ARTIFACTS_ARCHIVE=$(basename $(ls ${KERNEL_ARTIFACTS_ARCHIVE_PATH} | sort -Vr | head -1))
  KERNEL_ARTIFACTS_ARCHIVE_PATH="${SCRIPT_DIR}/../out/${KERNEL_ARTIFACTS_ARCHIVE}"
  ROOTFS_ARCHIVE=$(basename $(ls ${ROOTFS_ARCHIVE_PATH} | sort -Vr | head -1))
  ROOTFS_ARCHIVE_PATH="${SCRIPT_DIR}/../out/${ROOTFS_ARCHIVE}"
  ROOTFS_VER=$(echo $ROOTFS_ARCHIVE | cut -d "-" -f3 | sed "s/.tar.gz//")

  LOG_INF "using boot files: $BOOT_FILES_ARCHIVE_PATH"
  LOG_INF "using kernel artifacts: $KERNEL_ARTIFACTS_ARCHIVE_PATH"
  LOG_INF "using rootfs: $ROOTFS_ARCHIVE_PATH"
}
