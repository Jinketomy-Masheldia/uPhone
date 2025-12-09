#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST_TOOL="$ROOT/resources/host/ch"

echo -e "${BLUE}[+] Make sure your iPhone has successfully booted into iOS.${NC}"
echo -e "${YELLOW}[!] Once booted, you can close this script.${NC}"
read -rp "Press ENTER to continue..."

if [[ ! -f "$HOST_TOOL" ]]; then
    echo -e "${RED}[!] ch not found at $HOST_TOOL${NC}"
    exit 1
fi

echo -e "${BLUE}[+] Running ch with '-V' option...${NC}"
sudo "$HOST_TOOL" -V