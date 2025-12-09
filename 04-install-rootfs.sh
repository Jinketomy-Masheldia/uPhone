#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Paths
ROOT="$(cd "$(dirname "$0")" && pwd)"
RES="$ROOT/resources"
ROOTFS="$RES/rootfs/rootfs.tar.gz"

PARTITION="/dev/block/nvme0n1p2"
MNT="/mnt/tmp"

echo -e "${BLUE}[+] Checking rootfs file...${NC}"
if [[ ! -f "$ROOTFS" ]]; then
    echo -e "${RED}[!] rootfs.tar.gz not found at: $ROOTFS${NC}"
    exit 1
fi
echo -e "${GREEN}[✓] RootFS found.${NC}"

echo -e "${BLUE}[+] Starting ADB root...${NC}"
adb root >/dev/null 2>&1
adb wait-for-device

echo -e "${BLUE}[+] Formatting Linux partition: $PARTITION${NC}"
adb shell "mkfs.ext4 $PARTITION" || {
    echo -e "${RED}[!] mkfs.ext4 failed.${NC}"
    exit 1
}

echo -e "${BLUE}[+] Creating mount point: $MNT${NC}"
adb shell "mkdir -p $MNT"

echo -e "${BLUE}[+] Mounting EXT4 partition...${NC}"
adb shell "mount -t ext4 $PARTITION $MNT" || {
    echo -e "${RED}[!] Failed to mount EXT4 partition.${NC}"
    exit 1
}

echo -e "${BLUE}[+] Pushing RootFS (this may take a few minutes)...${NC}"
adb push "$ROOTFS" "$MNT/" || {
    echo -e "${RED}[!] Failed to push rootfs.tar.gz${NC}"
    exit 1
}

echo -e "${BLUE}[+] Extracting RootFS...${NC}"
adb shell "cd $MNT && tar -xzf rootfs.tar.gz" || {
    echo -e "${RED}[!] Failed to extract RootFS${NC}"
    exit 1
}

adb shell "mv $MNT/jammy/* $MNT/"
adb shell "rmdir $MNT/jammy"
echo -e "${BLUE}[+] Removing rootfs.tar.gz from device...${NC}"
adb shell "rm $MNT/rootfs.tar.gz" || true

echo -e "${GREEN}[✓] RootFS installation complete.${NC}"
