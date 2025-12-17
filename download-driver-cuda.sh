#!/bin/bash

##############################################################################
# NVIDIA 驱动 + CUDA Toolkit 离线安装包下载脚本
# 适用于: Ubuntu 22.04
# 用途: 在联网环境下载驱动和 CUDA 的所有安装包
##############################################################################

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置 - 可根据需要修改
NVIDIA_DRIVER_VERSION="575.51.03"
CUDA_VERSION="12.9"
CUDA_VERSION_FULL="12-9"  # 用于包名
UBUNTU_VERSION="22.04"
UBUNTU_CODENAME="jammy"

# 目录配置
BASE_DIR="./driver-cuda-packages"
DRIVER_DIR="$BASE_DIR/nvidia-driver"
CUDA_DIR="$BASE_DIR/cuda"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}NVIDIA 驱动 + CUDA 离线包下载${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}下载配置:${NC}"
echo "  NVIDIA 驱动版本: $NVIDIA_DRIVER_VERSION"
echo "  CUDA 版本: $CUDA_VERSION"
echo "  操作系统: Ubuntu $UBUNTU_VERSION"
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用 root 权限运行此脚本${NC}"
    echo "使用: sudo $0"
    exit 1
fi

# 创建目录结构
echo -e "${YELLOW}[1/5] 创建目录结构...${NC}"
mkdir -p "$DRIVER_DIR"
mkdir -p "$CUDA_DIR"
echo -e "${GREEN}✓${NC} 目录创建完成"
echo ""

# ========================================
# 下载 NVIDIA 驱动
# ========================================
echo -e "${YELLOW}[2/5] 下载 NVIDIA 驱动 $NVIDIA_DRIVER_VERSION...${NC}"

# 检测系统架构
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    DRIVER_ARCH="amd64"
else
    echo -e "${RED}错误: 不支持的架构 $ARCH${NC}"
    exit 1
fi

# 驱动下载 URL - 多个镜像源
DRIVER_FILENAME="NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run"
DRIVER_URLS=(
    "https://us.download.nvidia.com/XFree86/Linux-x86_64/${NVIDIA_DRIVER_VERSION}/${DRIVER_FILENAME}"
    "https://download.nvidia.com/XFree86/Linux-x86_64/${NVIDIA_DRIVER_VERSION}/${DRIVER_FILENAME}"
    "https://cn.download.nvidia.com/XFree86/Linux-x86_64/${NVIDIA_DRIVER_VERSION}/${DRIVER_FILENAME}"
)

echo "下载驱动安装包: $DRIVER_FILENAME"
cd "$DRIVER_DIR"

if [ ! -f "$DRIVER_FILENAME" ]; then
    DOWNLOAD_SUCCESS=false

    # 尝试所有下载源
    for url in "${DRIVER_URLS[@]}"; do
        echo "尝试下载: $url"
        if wget -q --show-progress --timeout=30 "$url"; then
            echo -e "${GREEN}✓${NC} 驱动下载成功"
            DOWNLOAD_SUCCESS=true
            break
        else
            echo -e "${YELLOW}⚠${NC} 此下载源失败，尝试下一个..."
        fi
    done

    # 如果所有源都失败
    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        echo ""
        echo -e "${RED}错误: 所有下载源均失败${NC}"
        echo ""
        echo -e "${YELLOW}请手动下载驱动:${NC}"
        echo ""
        echo "方法 1: 从 NVIDIA 官网下载"
        echo "  访问: https://www.nvidia.com/Download/index.aspx"
        echo "  或直接: https://www.nvidia.com/download/driverResults.aspx/$(echo $NVIDIA_DRIVER_VERSION | sed 's/\.//g')/en-us"
        echo ""
        echo "方法 2: 尝试以下直接链接"
        for url in "${DRIVER_URLS[@]}"; do
            echo "  $url"
        done
        echo ""
        echo "下载后将文件放置到: $(pwd)/"
        echo "文件名必须是: $DRIVER_FILENAME"
        echo ""

        read -p "是否已手动下载驱动? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "跳过驱动下载，继续其他组件..."
            cd - > /dev/null
        else
            if [ ! -f "$DRIVER_FILENAME" ]; then
                echo -e "${RED}错误: 未找到驱动文件 $DRIVER_FILENAME${NC}"
                echo "当前目录: $(pwd)"
                echo "请确保文件名完全匹配"
                cd - > /dev/null
                exit 1
            fi
        fi
    fi

    chmod +x "$DRIVER_FILENAME" 2>/dev/null || true
else
    echo -e "${GREEN}✓${NC} 驱动已存在，跳过下载"
fi

cd - > /dev/null

# 下载驱动依赖包
echo "下载驱动依赖包..."
cd "$DRIVER_DIR"
apt-get update > /dev/null 2>&1

# 基础依赖
DRIVER_DEPS="build-essential dkms pkg-config libglvnd-dev linux-headers-$(uname -r)"
for dep in $DRIVER_DEPS; do
    echo "  下载 $dep..."
    apt-get download $dep 2>/dev/null || {
        echo -e "    ${YELLOW}警告: $dep 下载失败${NC}"
    }
done

# 下载常见依赖的依赖
for dep in $DRIVER_DEPS; do
    apt-cache depends $dep 2>/dev/null | grep "Depends:" | awk '{print $2}' | while read subdep; do
        if [ ! -z "$subdep" ]; then
            apt-get download "$subdep" 2>/dev/null || true
        fi
    done
done

cd - > /dev/null
echo -e "${GREEN}✓${NC} NVIDIA 驱动下载完成"
echo ""

# ========================================
# 下载 CUDA Toolkit
# ========================================
echo -e "${YELLOW}[3/5] 下载 CUDA Toolkit $CUDA_VERSION...${NC}"

# 添加 CUDA 仓库
echo "配置 CUDA 仓库..."

# 下载并安装 CUDA keyring
CUDA_KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb"
wget -q $CUDA_KEYRING_URL -O /tmp/cuda-keyring.deb || {
    echo -e "${YELLOW}警告: 无法下载 CUDA keyring，尝试继续...${NC}"
}

if [ -f /tmp/cuda-keyring.deb ]; then
    dpkg -i /tmp/cuda-keyring.deb 2>/dev/null || true
    cp /tmp/cuda-keyring.deb "$CUDA_DIR/" 2>/dev/null || true
    rm -f /tmp/cuda-keyring.deb
fi

# 更新软件源
apt-get update > /dev/null 2>&1

# 下载 CUDA 包
echo "下载 CUDA $CUDA_VERSION 核心包（这可能需要较长时间）..."
cd "$CUDA_DIR"

# CUDA 核心包列表
CUDA_PACKAGES=(
    "cuda-toolkit-${CUDA_VERSION_FULL}"
    "cuda-runtime-${CUDA_VERSION_FULL}"
    "cuda-drivers"
)

for pkg in "${CUDA_PACKAGES[@]}"; do
    echo "  下载 $pkg..."
    apt-get download $pkg 2>/dev/null || {
        echo -e "    ${YELLOW}警告: $pkg 下载失败，继续...${NC}"
    }
done

# 下载 CUDA 依赖
if command -v apt-rdepends &> /dev/null; then
    USE_RDEPENDS=true
else
    echo "安装 apt-rdepends 以分析依赖..."
    apt-get install -y apt-rdepends > /dev/null 2>&1
    USE_RDEPENDS=true
fi

if [ "$USE_RDEPENDS" = true ]; then
    echo "分析并下载 CUDA 依赖关系（这可能需要一些时间）..."
    for pkg in cuda-toolkit-${CUDA_VERSION_FULL} cuda-runtime-${CUDA_VERSION_FULL}; do
        apt-rdepends $pkg 2>/dev/null | grep -v "^ " | sort -u | while read dep; do
            if [ ! -z "$dep" ] && [ "$dep" != "Depends:" ] && [ "$dep" != "PreDepends:" ] && [ "$dep" != "$pkg" ]; then
                apt-get download "$dep" 2>/dev/null || true
            fi
        done
    done
fi

# 保存密钥文件
if [ -f /usr/share/keyrings/cuda-archive-keyring.gpg ]; then
    cp /usr/share/keyrings/cuda-archive-keyring.gpg . 2>/dev/null || true
fi

cd - > /dev/null
echo -e "${GREEN}✓${NC} CUDA Toolkit 下载完成"
echo ""

# ========================================
# 生成安装信息和校验和
# ========================================
echo -e "${YELLOW}[4/5] 生成包清单和校验和...${NC}"

# 生成驱动信息
cat > "$DRIVER_DIR/INFO.txt" <<EOF
NVIDIA 驱动信息
================
版本: $NVIDIA_DRIVER_VERSION
下载日期: $(date)
文件列表:
EOF

ls -lh "$DRIVER_DIR"/*.run 2>/dev/null >> "$DRIVER_DIR/INFO.txt" || echo "  无 .run 文件" >> "$DRIVER_DIR/INFO.txt"
echo "" >> "$DRIVER_DIR/INFO.txt"
echo "依赖包:" >> "$DRIVER_DIR/INFO.txt"
ls -lh "$DRIVER_DIR"/*.deb 2>/dev/null | head -20 >> "$DRIVER_DIR/INFO.txt" || echo "  无依赖包" >> "$DRIVER_DIR/INFO.txt"

# 驱动校验和
cd "$DRIVER_DIR"
if ls *.run 1> /dev/null 2>&1; then
    sha256sum *.run > SHA256SUMS-driver 2>/dev/null || true
fi
if ls *.deb 1> /dev/null 2>&1; then
    sha256sum *.deb > SHA256SUMS-deps 2>/dev/null || true
fi
cd - > /dev/null

# CUDA 校验和和信息
cd "$CUDA_DIR"
if ls *.deb 1> /dev/null 2>&1; then
    sha256sum *.deb > SHA256SUMS
    ls -lh *.deb > package-list.txt

    cat > INFO.txt <<EOF
CUDA Toolkit 信息
=================
版本: $CUDA_VERSION
下载日期: $(date)
包数量: $(ls -1 *.deb | wc -l)
EOF
fi
cd - > /dev/null

echo -e "${GREEN}✓${NC} 清单生成完成"
echo ""

# ========================================
# 生成安装配置文件
# ========================================
echo -e "${YELLOW}[5/5] 生成安装配置...${NC}"

cat > "$BASE_DIR/install-config.conf" <<EOF
# NVIDIA 驱动 + CUDA 安装配置
# 自动生成于: $(date)

NVIDIA_DRIVER_VERSION=$NVIDIA_DRIVER_VERSION
CUDA_VERSION=$CUDA_VERSION
CUDA_VERSION_FULL=$CUDA_VERSION_FULL
UBUNTU_VERSION=$UBUNTU_VERSION
DOWNLOAD_DATE=$(date +%Y-%m-%d)
EOF

echo -e "${GREEN}✓${NC} 配置文件已生成"
echo ""

# 统计信息
DRIVER_COUNT=$(ls -1 "$DRIVER_DIR"/*.run 2>/dev/null | wc -l)
DRIVER_DEB_COUNT=$(ls -1 "$DRIVER_DIR"/*.deb 2>/dev/null | wc -l)
CUDA_COUNT=$(ls -1 "$CUDA_DIR"/*.deb 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh "$BASE_DIR" | cut -f1)

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}下载完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}下载统计:${NC}"
echo "  驱动安装包: $DRIVER_COUNT 个 .run 文件"
echo "  驱动依赖包: $DRIVER_DEB_COUNT 个 .deb 文件"
echo "  CUDA 包: $CUDA_COUNT 个 .deb 文件"
echo "  总大小: $TOTAL_SIZE"
echo ""
echo -e "${BLUE}下载位置:${NC}"
echo "  $BASE_DIR/"
echo "  ├── nvidia-driver/  (驱动文件)"
echo "  └── cuda/           (CUDA 包)"
echo ""
echo -e "${YELLOW}下一步操作:${NC}"
echo "1. 打包所有文件:"
echo "   tar -czf nvidia-driver-cuda-offline.tar.gz driver-cuda-packages/ install-driver-cuda.sh"
echo ""
echo "2. 将压缩包传输到目标离线服务器"
echo ""
echo "3. 在目标服务器上解压并安装:"
echo "   tar -xzf nvidia-driver-cuda-offline.tar.gz"
echo "   sudo ./install-driver-cuda.sh"
echo ""
