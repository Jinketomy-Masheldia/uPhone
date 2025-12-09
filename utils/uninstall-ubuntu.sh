#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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
    echo -e "${GREEN}[✓] /dev/disk0s2 detected!.${NC}"
else
    echo -e "${RED}[!] /dev/disk0s2 not found.${NC}"
    ssh_run "/sbin/resize_apfs /dev/disk0s1 0" && echo -e "${GREEN}[✓] Storage space restored successfully.${NC}" || echo -e "${RED}[!] Failed to restore storage space.${NC}"
    echo -e "${RED}[!] If the storage size displayed on the device does not update immediately, please reboot the phone and try this tool again.${NC}"
    exit 1
fi


copy_tool "$HOST_GDISK"
copy_tool "$HOST_RESIZE"

# Run gdisk
ssh_run "/sbin/gdisk /dev/disk0 <<EOF
d
2
d
n



AF0A
w
y
EOF
" && echo -e "${GREEN}[✓] Partitioning completed.${NC}" || echo -e "${RED}[!] Partitioning failed.${NC}"

ssh_run "/sbin/resize_apfs /dev/disk0s1 0" && echo -e "${GREEN}[✓] Storage space restored successfully.${NC}" || echo -e "${RED}[!] Failed to restore storage space.${NC}"

echo -e "${RED}[!] If the storage size displayed on the device does not update immediately, please reboot the phone and try this tool again.${NC}"