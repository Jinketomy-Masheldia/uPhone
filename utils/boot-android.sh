#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_SANDCASTLE_DIR="$ROOT/resources/sandcastle/android-sandcastle/"
HOST_TOOL="$ROOT/resources/host/load-linux"

echo -e "${BLUE}[+] Please connect your PongoOS device to the computer.${NC}"
read -rp "Press ENTER when ready..."

if [[ ! -f "$HOST_TOOL" ]]; then
    echo -e "${RED}[!] load-linux tool not found at $HOST_TOOL${NC}"
    exit 1
fi

if [[ ! -f "$ANDROID_SANDCASTLE_DIR/Android.lzma" || ! -f "$ANDROID_SANDCASTLE_DIR/dtbpack" ]]; then
    echo -e "${RED}[!] Kernel files not found in $ANDROID_SANDCASTLE_DIR${NC}"
    exit 1
fi

echo -e "${BLUE}[+] Loading Linux kernel and DTB onto device...${NC}"
sudo "$HOST_TOOL" "$ANDROID_SANDCASTLE_DIR/Android.lzma" "$ANDROID_SANDCASTLE_DIR/dtbpack"

echo -e "${GREEN}[✓] Boot process initiated.${NC}"
