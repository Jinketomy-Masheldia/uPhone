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
KERNEL_SRC="$ROOT/resources/kernel-src/linux-sandcastle"
IOS_DIR="$ROOT/resources/ios"
CHROOT_SCRIPT="/root/build_kernel.sh"

echo -e "${BLUE}[+] Copying kernel source and config into rootfs...${NC}"
sudo rm -rf "$ROOTFS_DIR/root/linux-sandcastle"
sudo cp -r "$KERNEL_SRC" "$ROOTFS_DIR/root/"
sudo cp "$IOS_DIR/kernel.config" "$ROOTFS_DIR/root/"

echo -e "${BLUE}[+] Creating kernel build script inside rootfs...${NC}"
cat <<'EOF' | sudo tee "$ROOTFS_DIR/root/build_kernel.sh"
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "[*] Updating package lists..."
apt update

echo "[*] Installing kernel build dependencies..."
apt install -y \
    gcc-9 g++-9 make libc6-dev \
    bc \
    bison \
    flex \
    libssl-dev \
    libelf-dev \
    libncurses5-dev \
    libncursesw5-dev \
    dwarves \
    libudev-dev \
    libpci-dev \
    libiberty-dev \
    python3 \
    python3-distutils \
    zstd \
    cpio \
    initramfs-tools \
    lzma

echo "[*] Setting gcc-9/g++-9 as default..."
update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 100
update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-9 100
update-alternatives --set gcc /usr/bin/gcc-9
update-alternatives --set g++ /usr/bin/g++-9

KERNEL_DIR="/root/linux-sandcastle"
cd "$KERNEL_DIR"

echo "[*] Preparing kernel config..."
make hx_h9p_defconfig
cp /root/kernel.config .config

echo "[*] Building kernel Image..."
make -j$(nproc) Image

echo "[*] Building device tree blobs..."
make dtbs

echo "[*] Packing DTBs..."
bash dtbpack.sh

echo "[✓] Kernel build completed."
EOF

sudo chmod +x "$ROOTFS_DIR/root/build_kernel.sh"

echo -e "${BLUE}[+] Entering chroot to build kernel...${NC}"
sudo chroot "$ROOTFS_DIR" /bin/bash /root/build_kernel.sh

echo -e "${BLUE}[+] Compressing kernel with LZMA...${NC}"
sudo lzma -z --stdout "$ROOTFS_DIR/root/linux-sandcastle/arch/arm64/boot/Image" > "$IOS_DIR/Image.lzma"
echo -e "${BLUE}[+] Copying dtbpack file back to resources/ios...${NC}"
sudo cp "$ROOTFS_DIR/root/linux-sandcastle/dtbpack" "$IOS_DIR/"

echo -e "${GREEN}[✓] Kernel Image.lzma and dtbpack are ready in $IOS_DIR${NC}"