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

mkdir -p "$RES/sandcastle"
mkdir -p "$RES/kernel-src"
mkdir -p "$RES/host"

# Functions
prompt_redownload() {
    local file="$1"
    read -r -p "$(echo -e "${YELLOW}File '$file' exists. Delete and re-download? [y/N]:${NC} ")" ans
    case "$ans" in
        [Yy]* ) 
            echo -e "${RED}[!] Removing $file${NC}"
            rm -rf "$file"
            return 0
            ;;
        * ) 
            echo -e "${GREEN}[=] Keeping existing $file${NC}"
            return 1
            ;;
    esac
}

download_file() {
    local url="$1"
    local out="$2"

    if [ -f "$out" ]; then
        if ! prompt_redownload "$out"; then
            return
        fi
    fi

    echo -e "${BLUE}[+] Downloading:${NC} $url"
    curl -L --fail --retry 3 --retry-delay 2 "$url" -o "$out"
}

download_github() {
    local repo="$1"
    local branch="$2"
    local outdir="$3"

    if [ -d "$outdir" ]; then
        if ! prompt_redownload "$outdir"; then
            return
        fi
    fi

    echo -e "${BLUE}[+] Cloning GitHub repo:${NC} $repo (branch=$branch)"
    git clone --depth=1 --branch "$branch" "https://github.com/$repo.git" "$outdir"
}

unzip_file() {
    local zipfile="$1"
    local dest="$2"

    if ! command -v unzip >/dev/null 2>&1; then
        echo -e "${RED}[!] unzip command not found. Please install unzip.${NC}"
        exit 1
    fi

    if [ ! -f "$zipfile" ]; then
        echo -e "${RED}[!] ZIP file not found: $zipfile${NC}"
        exit 1
    fi

    rm -rf "$dest"
    mkdir -p "$dest"
    echo -e "${BLUE}[+] Unzipping:${NC} $zipfile -> $dest"

    tmpdir=$(mktemp -d)
    unzip -q -o "$zipfile" -d "$tmpdir" || {
        echo -e "${RED}[!] Failed to unzip $zipfile${NC}"
        rm -rf "$tmpdir"
        exit 1
    }

    # Flatten top-level directory if it exists
    topdir=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    if [ -d "$topdir" ]; then
        mv "$topdir"/* "$dest"/
    else
        mv "$tmpdir"/* "$dest"/
    fi
    rm -rf "$tmpdir"
}

# Start download
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}   Downloading resources for uPhone project${NC}"
echo -e "${GREEN}================================================================${NC}"

download_github "corellium/linux-sandcastle" "sandcastle-5.4" "$RES/kernel-src/linux-sandcastle"
download_github "corellium/projectsandcastle" "master" "$RES/sandcastle/projectsandcastle"
# download_github "verygenericname/SSHRD_Script" "main" "$RES/host/SSHRD_Script"

ANDROID_ZIP="$RES/sandcastle/android-sandcastle.zip"
LINUX_ZIP="$RES/sandcastle/linux-sandcastle.zip"
NAND_GZ="$RES/ios/nand.gz"

download_file "https://assets.checkra.in/downloads/sandcastle/dff60656db1bdc6a250d3766813aa55c5e18510694bc64feaabff88876162f3f/android-sandcastle.zip" "$ANDROID_ZIP"
download_file "https://assets.checkra.in/downloads/sandcastle/0175ae56bcba314268d786d1239535bca245a7b126d62a767e12de48fd20f470/linux-sandcastle.zip" "$LINUX_ZIP"
download_file "http://assets.checkra.in/downloads/sandcastle/88b1089d97fe72ab77af8253ab7c312f8e789d49209234239be2408c3ad89a34/nand.gz" "$NAND_GZ"

unzip_file "$ANDROID_ZIP" "$RES/sandcastle/android-sandcastle"
unzip_file "$LINUX_ZIP" "$RES/sandcastle/linux-sandcastle"


echo -e "\n\n${RED}[!] WARNING: checkra1n will NOT be downloaded automatically!${NC}"
echo -e "${YELLOW}[!] Please download ${GREEN}checkra1n 0.11.0 beta version${NC}"
echo -e "${YELLOW}[!] Place it at: ${GREEN}$RES/host/ch${NC}"
echo -e "${YELLOW}[!] Press ENTER after placing the file to continue...${NC}"
read -r

while true; do
    CH_PATH="$RES/host/ch"

    if [ ! -f "$CH_PATH" ]; then
        echo -e "${RED}[!] File not found: $CH_PATH${NC}"
        echo -e "${YELLOW}[!] Please download checkra1n 0.11.0 beta and press ENTER...${NC}"
        read -r
        continue
    fi

    chmod +x "$CH_PATH" || true

    echo -e "${BLUE}[+] Checking checkra1n version...${NC}"
    VERSION_OUTPUT="$($CH_PATH --version 2>&1 || true)"


    echo -e "${BLUE}[=] Output:${NC} $VERSION_OUTPUT"

    if echo "$VERSION_OUTPUT" | grep -q "beta 0.11.0"; then
        echo -e "${GREEN}[✓] Correct checkra1n version detected (beta 0.11.0)${NC}"
        break
    fi

    echo -e "${RED}[!] Incorrect version of checkra1n${NC}"
    echo -e "${YELLOW}[!] Expected version containing: ${GREEN}beta 0.11.0${NC}"
    echo -e "${YELLOW}[!] Please re-download the correct file and press ENTER...${NC}"
    read -r
done

echo -e "\n${BLUE}[+] Ready to compile load-linux${NC}"
echo -e "${YELLOW}[!] Press ENTER to start compiling...${NC}"
read -r

SRC="$RES/sandcastle/projectsandcastle/loader/load-linux.c"
OUT="$RES/host/load-linux"

mkdir -p "$RES/host"

while true; do
    echo -e "${BLUE}[+] Compiling load-linux...${NC}"

    if cc "$SRC" -lusb-1.0 -o "$OUT" 2>&1; then
        chmod +x "$OUT"
        echo -e "${GREEN}[✓] load-linux compiled successfully:${NC} $OUT"
        break
    else
        echo -e "${RED}[!] Compile failed${NC}"
        echo -e "${YELLOW}[!] Please check that libusb-1.0-dev is installed.${NC}"
        echo -e "${YELLOW}[!] Press ENTER to try compiling again...${NC}"
        read -r
    fi
done

echo -e "\n${GREEN}[✓] All files prepared successfully. Ready to use!${NC}"