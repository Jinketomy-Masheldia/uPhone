#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Paths
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RES="$ROOT/resources"
BACKUP_DIR="$RES/backup"
PARTITION="/dev/block/nvme0n1p2"
MNT="/mnt/tmp"

# Time-stamped filename
TS="$(date +"%Y-%m-%d-%H-%M-%S")"
BACKUP_FILE="backup-${TS}.tar.gz"

mkdir -p "$BACKUP_DIR"

echo -e "${BLUE}[+] Starting ADB root...${NC}"
adb root >/dev/null 2>&1
adb wait-for-device

echo -e "${BLUE}[+] Creating mount point on device: $MNT${NC}"
adb shell "mkdir -p $MNT"

echo -e "${BLUE}[+] Mounting EXT4 partition: $PARTITION${NC}"
if ! adb shell "mount -t ext4 $PARTITION $MNT"; then
    echo -e "${RED}[!] Failed to mount EXT4 partition.${NC}"
    exit 1
fi

echo -e "${BLUE}[+] Packing existing system into tar.gz (this may take a while)...${NC}"
adb shell "cd $MNT && tar -czf /sdcard/$BACKUP_FILE ." || {
    echo -e "${RED}[!] Failed to create backup archive.${NC}"
    exit 1
}

echo -e "${BLUE}[+] Pulling backup file to PC...${NC}"
adb pull "/sdcard/$BACKUP_FILE" "$BACKUP_DIR/" >/dev/null || {
    echo -e "${RED}[!] Failed to pull backup file.${NC}"
    exit 1
}

echo -e "${BLUE}[+] Cleaning up backup file from device...${NC}"
adb shell "rm /sdcard/$BACKUP_FILE" || true

echo -e "${GREEN}[✓] Backup completed successfully.${NC}"
echo -e "${GREEN}[✓] Saved to: $BACKUP_DIR/$BACKUP_FILE${NC}"
