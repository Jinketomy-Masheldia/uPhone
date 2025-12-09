#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ROOT="$(cd "$(dirname "$0")" && pwd)"
ROOTFS_DIR="$ROOT/resources/rootfs/jammy"
TAR_OUT="$ROOT/resources/rootfs/rootfs.tar.gz"
DEFAULT_MIRROR="http://ports.ubuntu.com/ubuntu-ports/"
LZMA_DIR="$ROOT/resources/sandcastle/linux-sandcastle"
LZMA_SRC="$LZMA_DIR/Linux.lzma"

mkdir -p "$ROOTFS_DIR"
rm "$LZMA_DIR/Linux" || true

echo -e "${BLUE}[+] Extracting Linux kernel from Linux.lzma...${NC}"


if [[ ! -f "$LZMA_SRC" ]]; then
    echo -e "${RED}[!] Linux.lzma not found at: $LZMA_SRC${NC}"
    exit 1
fi

echo -e "${BLUE}[+] Decompressing LZMA...${NC}"
cd "$LZMA_DIR"

xz --format=lzma --decompress --keep "Linux.lzma" 2>/dev/null || {
    echo -e "${RED}[!] Failed to decompress Linux.lzma${NC}"
    exit 1
}

if [[ ! -f "$LZMA_DIR/Linux" ]]; then
    echo -e "${RED}[!] Decompression failed: 'Linux' file not created.${NC}"
    exit 1
fi

echo -e "${GREEN}[✓] LZMA decompression complete.${NC}"
echo -e "${BLUE}[+] Running binwalk to extract kernel...${NC}"

# Check binwalk
if ! command -v binwalk >/dev/null 2>&1; then
    echo -e "${RED}[!] binwalk not installed. Please install binwalk.${NC}"
    exit 1
fi

binwalk -e "$LZMA_DIR/Linux" >/dev/null 2>&1 || {
    echo -e "${RED}[!] binwalk extraction failed.${NC}"
    exit 1
}

EXTRACT_DIR=$(find "$LZMA_DIR" -maxdepth 1 -type d -name "_Linux.extracted" | head -n 1)

if [[ -z "$EXTRACT_DIR" ]]; then
    echo -e "${RED}[!] Extracted kernel directory not found.${NC}"
    exit 1
fi

echo -e "${GREEN}[✓] Kernel extracted to: $EXTRACT_DIR${NC}"

echo -e "${BLUE}[+] Locating cpio archive 1134EF8...${NC}"

CPIO_FILE="$EXTRACT_DIR/1134EF8"

if [[ ! -f "$CPIO_FILE" ]]; then
    echo -e "${RED}[!] Required file 1134EF8 not found at: $CPIO_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}[✓] Found 1134EF8 (cpio archive).${NC}"

OUT_DIR="$LZMA_DIR/initramfs"
mkdir -p "$OUT_DIR"

echo -e "${BLUE}[+] Extracting 1134EF8 into: $OUT_DIR ...${NC}"

cd "$OUT_DIR" && cpio -idmv < "$CPIO_FILE" >/dev/null 2>&1 || true

echo -e "${GREEN}[✓] initramfs extracted successfully to $OUT_DIR${NC}"




# Check debootstrap
if ! command -v debootstrap >/dev/null 2>&1; then
    echo -e "${RED}[!] debootstrap not found. Install it first.${NC}"
    exit 1
fi



TARGET_ARCH="arm64"
HOST_ARCH=$(dpkg --print-architecture)
QEMU_BINARY=$(command -v qemu-aarch64-static || true)

if [ "$HOST_ARCH" != "$TARGET_ARCH" ] && [ ! -f "$QEMU_BINARY" ]; then
    echo -e "${RED}[!] Host is not ARM64. Install qemu-user-static first!${NC}"
    exit 1
fi

echo -e "${BLUE}[+] Starting debootstrap for Ubuntu Jammy ($TARGET_ARCH)...${NC}"
sudo debootstrap --arch="$TARGET_ARCH" jammy "$ROOTFS_DIR" "$DEFAULT_MIRROR"

# Copy qemu if needed
if [ "$HOST_ARCH" != "$TARGET_ARCH" ]; then
    sudo cp "$QEMU_BINARY" "$ROOTFS_DIR/usr/bin/"
fi

# Configure APT sources
cat <<EOF | sudo tee "$ROOTFS_DIR/etc/apt/sources.list"
deb http://ports.ubuntu.com/ubuntu-ports jammy main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports jammy-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports jammy-backports main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports jammy-security main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports jammy-proposed main restricted universe multiverse
EOF

echo -e "${BLUE}[+] Applying driver fixes to rootfs...${NC}"

# Paths
DRIVER_FIX_DIR="$ROOT/resources/ios/driver-fix"
INITRAMFS_DIR="$ROOT/resources/sandcastle/linux-sandcastle/initramfs"
SYSTEMD_DIR="$ROOTFS_DIR/etc/systemd/system"
USR_BIN_DIR="$ROOTFS_DIR/usr/bin"
USR_LOCAL_BIN_DIR="$ROOTFS_DIR/usr/local/bin"
HW_DIR="$ROOTFS_DIR/etc/hw"

# Ensure directories exist
sudo mkdir -p "$SYSTEMD_DIR" "$USR_BIN_DIR" "$USR_LOCAL_BIN_DIR" "$HW_DIR"

# 1. Copy systemd service files
for svc in autofix-network.service hx-touchd.service; do
    if [[ -f "$DRIVER_FIX_DIR/$svc" ]]; then
        sudo cp "$DRIVER_FIX_DIR/$svc" "$SYSTEMD_DIR/"
        sudo chmod 644 "$SYSTEMD_DIR/$svc"
    fi
done

# 2. Copy binaries from initramfs
for bin in syscfg hx-touchd hcdpack; do
    if [[ -f "$INITRAMFS_DIR/usr/bin/$bin" ]]; then
        sudo cp "$INITRAMFS_DIR/usr/bin/$bin" "$USR_BIN_DIR/"
        sudo chmod 755 "$USR_BIN_DIR/$bin"
    fi
done

# 3. Copy firmware list
if [[ -f "$INITRAMFS_DIR/etc/hw/hx-touch.fwlist" ]]; then
    sudo cp "$INITRAMFS_DIR/etc/hw/hx-touch.fwlist" "$HW_DIR/"
    sudo chmod 644 "$HW_DIR/hx-touch.fwlist"
fi

# 4. Copy network scripts and USB start script
for script in wlan0-up startusbnet; do
    if [[ -f "$INITRAMFS_DIR/etc/network/$script" ]]; then
        sudo cp "$INITRAMFS_DIR/etc/network/$script" "$USR_LOCAL_BIN_DIR/"
        sudo chmod 755 "$USR_LOCAL_BIN_DIR/$script"
    elif [[ -f "$DRIVER_FIX_DIR/$script" ]]; then
        sudo cp "$DRIVER_FIX_DIR/$script" "$USR_LOCAL_BIN_DIR/"
        sudo chmod 755 "$USR_LOCAL_BIN_DIR/$script"
    fi
done
if [[ -f "$DRIVER_FIX_DIR/autofix-network.sh" ]]; then
    sudo cp "$DRIVER_FIX_DIR/autofix-network.sh" "$USR_LOCAL_BIN_DIR/"
    sudo chmod 755 "$USR_LOCAL_BIN_DIR/autofix-network.sh"
fi

# Modify wlan0-up script inside rootfs
WLAN_SCRIPT="$USR_LOCAL_BIN_DIR/wlan0-up"

if [[ -f "$WLAN_SCRIPT" ]]; then
    echo -e "${BLUE}[+] Modifying wlan0-up script...${NC}"
    
    # 1. Change first line to /bin/bash
    sudo sed -i '1s@.*@#!/bin/bash@' "$WLAN_SCRIPT"

    # 2. Change second line to mount APFS partition
    sudo sed -i '2s@.*@mount -t apfs /dev/nvme0n1p1 /hostfs@' "$WLAN_SCRIPT"

    # 3. Comment out line 53
    sudo sed -i '53s@^@# @' "$WLAN_SCRIPT"

    # 4. Change line 72 to echo 0
    sudo sed -i '72s@.*@echo 0@' "$WLAN_SCRIPT"

    echo -e "${GREEN}[✓] wlan0-up script modified successfully.${NC}"
else
    echo -e "${YELLOW}[!] wlan0-up script not found, skipping modification.${NC}"
fi


echo -e "${GREEN}[✓] Driver fixes applied successfully.${NC}"


# Inform user for adduser
echo -e "\n${YELLOW}[!] Next, you will configure the rootfs.${NC}"
echo -e "${YELLOW}[!] Press ENTER to continue (you will be prompted for user and password inside chroot).${NC}"
read -r

# Temporary chroot script
CHROOT_SCRIPT=$(mktemp)
cat <<'EOF' > "$CHROOT_SCRIPT"
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
echo "nameserver 114.114.114.114" > /etc/resolv.conf
mkdir -p /hostfs

# Update and install packages
export https_proxy=http://127.0.0.1:7897 http_proxy=http://127.0.0.1:7897 all_proxy=socks5://127.0.0.1:7897
apt update
apt upgrade -y
apt install -y vim network-manager openssh-server sudo locales tzdata
apt install -y ubuntu-desktop
apt clean

# Enable custom services
systemctl enable autofix-network.service || true
systemctl enable hx-touchd.service || true
systemctl start autofix-network.service || true
systemctl start hx-touchd.service || true

# Configure locales
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8
export LANG=en_US.UTF-8

# Configure timezone (UTC default)
echo "Etc/UTC" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata

# Add user
echo -e "\n*** You will now add a user. Remember the password! ***"
read -p "Enter new username: " NEWUSER
adduser "$NEWUSER"
adduser "$NEWUSER" sudo

echo -e "\n[✓] Rootfs configuration done."
EOF

# Copy script into rootfs
sudo cp "$CHROOT_SCRIPT" "$ROOTFS_DIR/root/chroot_config.sh"
sudo chmod +x "$ROOTFS_DIR/root/chroot_config.sh"

# Execute chroot
sudo chroot "$ROOTFS_DIR" /bin/bash /root/chroot_config.sh  || true

# Cleanup
sudo rm "$ROOTFS_DIR/root/chroot_config.sh"
if [ "$HOST_ARCH" != "$TARGET_ARCH" ]; then
    sudo rm "$ROOTFS_DIR/usr/bin/$(basename $QEMU_BINARY)"
fi

# Package rootfs
echo -e "${BLUE}[+] Packaging rootfs into tar.gz...${NC}"
cd "$ROOT/resources/rootfs"
sudo tar -czf rootfs.tar.gz jammy

echo -e "${GREEN}[✓] Rootfs prepared and packaged at ${NC}$TAR_OUT"
