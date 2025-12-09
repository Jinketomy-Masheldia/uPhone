#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ROOT="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$ROOT/resources/ios"

HOST_GDISK="$IOS_DIR/gdisk"
HOST_RESIZE="$IOS_DIR/resize_apfs"
ANDROID_INSTALLER="$ROOT/resources/sandcastle/android-sandcastle/isetup"
NAND_IMAGE="$ROOT/resources/ios/nand.gz"

SSH_PORT=2222
SSH_USER="root"
SSH_HOST="127.0.0.1"
SSH_PASS="alpine"

SCP_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -O -oHostKeyAlgorithms=+ssh-rsa -oPubkeyAcceptedAlgorithms=+ssh-rsa -P ${SSH_PORT}"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -oHostKeyAlgorithms=+ssh-rsa -oPubkeyAcceptedAlgorithms=+ssh-rsa -p ${SSH_PORT}"

if ! command -v sshpass >/dev/null 2>&1; then
    echo -e "${RED}[!] sshpass is required but not installed.${NC}"
    echo -e "${YELLOW}[!] Install it please.${NC}"
    exit 1
fi

cleanup() {
    if [[ "${IPROXY_PID:-}" != "" ]]; then
        kill "$IPROXY_PID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

ssh_run() {
    sshpass -p "$SSH_PASS" ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" "$@" 2>/dev/null
}

echo -e "${BLUE}[+] Starting iproxy 2222 → 44...${NC}"
iproxy 2222 44 >/dev/null 2>&1 &
IPROXY_PID=$!

echo -e "${BLUE}[+] Waiting for SSH...${NC}"
for i in {1..30}; do
    if ssh_run "echo ok" >/dev/null 2>&1; then
        echo -e "${GREEN}[✓] SSH connected (password = alpine).${NC}"
        break
    fi
    sleep 1
done

copy_tool() {
    local src="$1"
    local name
    name="$(basename "$src")"

    if [[ -f "$src" ]]; then
        echo -e "${BLUE}[+] Copying ${name} to device:/sbin/${name}${NC}"
        sshpass -p "$SSH_PASS" scp -p $SCP_OPTS "$src" "$SSH_USER@$SSH_HOST:/sbin/${name}" && \
            ssh_run chmod +x "/sbin/${name}" && \
            echo -e "${GREEN}[✓] ${name} copied${NC}" || \
            echo -e "${RED}[!] Failed to copy ${name}${NC}"
    else
        echo -e "${YELLOW}[!] Local file missing, skipped: $src${NC}"
    fi
}

if ssh_run "[ -b /dev/disk0s2 ]"; then
    echo -e "${RED}[!] /dev/disk0s2 detected! Script will not run to prevent data loss.${NC}"
    exit 1
else
    echo -e "${GREEN}[✓] /dev/disk0s2 not found. Safe to proceed.${NC}"
fi


copy_tool "$HOST_GDISK"
copy_tool "$HOST_RESIZE"
copy_tool "$ANDROID_INSTALLER"

# List APFS snapshots
echo -e "${BLUE}[+] Listing APFS snapshots on device...${NC}"
SNAPSHOTS=$(ssh_run snappy -f / -l | grep -v '^Will' || true)

if [[ -z "$SNAPSHOTS" ]]; then
    echo -e "${YELLOW}[!] No snapshots found.${NC}"
    echo -e "${BLUE}[+] Skipping snapshot deletion, continuing...${NC}"
else
    echo -e "${GREEN}[✓] Snapshots found:${NC}"
    echo "$SNAPSHOTS"

    while true; do
        echo -e "${RED}[!] WARNING: You are about to delete ALL APFS snapshots.${NC}"
        echo -e "${YELLOW}[!] This cannot be undone. You will be UNABLE to restore rootfs!${NC}"
        echo -e "${YELLOW}[!] Type ${RED}DELETE${YELLOW} to delete snapshots, Ctrl+C to cancel.${NC}"
        read -r input

        if [[ "$input" == "DELETE" ]]; then
            for snap in $SNAPSHOTS; do
                echo -e "${BLUE}[-] Removing snapshot: ${snap}${NC}"
                ssh_run snappy -f / -d "$snap" || echo -e "${RED}[!] Failed to delete $snap${NC}"
            done
            echo -e "${GREEN}[✓] All snapshots deleted.${NC}"
            break
        fi
    done
fi

echo -e "${BLUE}[+] Uploading nand.gz to device:/tmp/nand.gz\nThis may take a few minutes, please be patient.
${NC}"
if [[ -f "$NAND_IMAGE" ]]; then
    sshpass -p "$SSH_PASS" scp -p $SCP_OPTS "$NAND_IMAGE" "$SSH_USER@$SSH_HOST:/tmp/nand.gz"
    echo -e "${GREEN}[✓] nand.gz uploaded to /tmp/nand.gz${NC}"
else
    echo -e "${RED}[!] nand.gz not found at $NAND_IMAGE${NC}"
    exit 1
fi
echo -e "${BLUE}[+] Preparing Android APFS volume on device...${NC}"

ssh_run "
DISK=0
for i in /dev/disk0s1s*; do
    LABEL=\$(/System/Library/Filesystems/apfs.fs/apfs.util -p \$i 2>/dev/null || echo)
    if [ \"\$LABEL\" = \"Android\" ]; then
        DISK=\$i
        break
    fi
done

if [ ! -b \$DISK ]; then
    echo 'No Android volume found, creating...'
    newfs_apfs -A -v Android -e /dev/disk0s1
fi

# Rescan disks
DISK=0
for i in /dev/disk0s1s*; do
    LABEL=\$(/System/Library/Filesystems/apfs.fs/apfs.util -p \$i 2>/dev/null || echo)
    if [ \"\$LABEL\" = \"Android\" ]; then
        DISK=\$i
        break
    fi
done

if [ -b \$DISK ]; then
    mkdir -p /tmp/mnt
    echo \"Mounting \$DISK...\"
    mount -t apfs \$DISK /tmp/mnt || { echo 'Failed to mount disk'; exit 1; }
    rm -rf /tmp/mnt/nand*
    echo 'Copying nand.gz to /tmp/mnt...'
    cp /tmp/nand.gz /tmp/mnt/nand.gz || { echo 'Failed to copy nand.gz'; umount /tmp/mnt; exit 1; }
    echo 'Decompressing nand.gz...'
    gunzip -d /tmp/mnt/nand.gz || { echo 'Failed to decompress nand.gz'; umount /tmp/mnt; exit 1; }
    sync
    umount /tmp/mnt
    echo 'Android APFS volume ready.'
else
    echo 'Error: Android volume not found after creation attempt.'
    exit 1
fi
"

# Resize APFS
echo -e "\n${BLUE}[+] Ready to resize APFS partition on /dev/disk0s1${NC}"
echo -e "${YELLOW}[!] Enter target size in GB (e.g., 64 for 64GB). Recommended: 64G.${NC}"
echo -e "${YELLOW}[!] Warning: Input <16 may be unsafe. Script will not validate input.${NC}"

while true; do
    read -rp "Enter target size in GB for APFS (recommended 64, must be >=16): " TARGET_GB
 
    TARGET_GB=${TARGET_GB:-64}

    if [[ "$TARGET_GB" =~ ^[0-9]+$ ]]; then
        if (( TARGET_GB < 16 )); then
            echo -e "${RED}[!] Warning: Size <16GB is unsafe.${NC}"
            read -rp "Press ENTER to continue anyway or Ctrl+C to cancel..."
        fi
        break
    else
        echo -e "${YELLOW}[!] Invalid input. Please enter a number.${NC}"
    fi
done

if [[ "$TARGET_GB" =~ ^[0-9]+$ ]]; then
    if (( TARGET_GB < 16 )); then
        echo -e "${RED}[!] Last Warning: You chose a very small size (<16GB). Are you sure? Ctrl+C to cancel.${NC}"
        read -r -p "Press ENTER to continue anyway..."
    fi

    TARGET_BYTES=$(( TARGET_GB * 1024 * 1024 * 1024 ))
    echo -e "${BLUE}[+] Resizing APFS to ${TARGET_GB}GB (${TARGET_BYTES} bytes)...${NC}"

    ssh_run "/sbin/resize_apfs /dev/disk0s1 $TARGET_BYTES" && \
        echo -e "${GREEN}[✓] resize_apfs completed.${NC}" || \
        echo -e "${RED}[!] resize_apfs failed. Check device and try again.${NC}"
else
    echo -e "${RED}[!] Invalid input. Must be a number in GB.${NC}"
fi

echo -e "${BLUE}[+] Starting partitioning with gdisk...${NC}"
echo -e "${YELLOW}[!] Using target size: ${TARGET_GB}GB for APFS.${NC}"

APFS_SIZE="+${TARGET_GB}G"

# Run gdisk
ssh_run "/sbin/gdisk /dev/disk0 <<EOF
d
n


$APFS_SIZE
AF0A
n



8300
w
y
EOF
" && echo -e "${GREEN}[✓] Partitioning completed.${NC}" || echo -e "${RED}[!] Partitioning failed.${NC}"
