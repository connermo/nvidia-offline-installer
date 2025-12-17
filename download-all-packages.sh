#!/bin/bash

##############################################################################
# NVIDIA 完整环境离线安装包下载脚本
# 适用于: Ubuntu 22.04
# 包含: NVIDIA 驱动 + CUDA + Container Toolkit
# 用途: 在联网环境下载所有必要的安装包
##############################################################################

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置 - 可根据需要修改
NVIDIA_DRIVER_VERSION="550.127.05"
CUDA_VERSION="12.9"
CUDA_VERSION_FULL="12-9"  # 用于包名
UBUNTU_VERSION="22.04"
UBUNTU_CODENAME="jammy"

# 目录配置
BASE_DIR="./packages"
DRIVER_DIR="$BASE_DIR/nvidia-driver"
CUDA_DIR="$BASE_DIR/cuda"
TOOLKIT_DIR="$BASE_DIR/container-toolkit"
REPO_LIST_DIR="./repo-lists"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}NVIDIA 完整环境离线包下载${NC}"
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
echo -e "${YELLOW}[1/7] 创建目录结构...${NC}"
mkdir -p "$DRIVER_DIR"
mkdir -p "$CUDA_DIR"
mkdir -p "$TOOLKIT_DIR"
mkdir -p "$REPO_LIST_DIR"
echo -e "${GREEN}✓${NC} 目录创建完成"
echo ""

# ========================================
# 下载 NVIDIA 驱动
# ========================================
echo -e "${YELLOW}[2/7] 下载 NVIDIA 驱动 $NVIDIA_DRIVER_VERSION...${NC}"

# 检测系统架构
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    DRIVER_ARCH="amd64"
else
    echo -e "${RED}错误: 不支持的架构 $ARCH${NC}"
    exit 1
fi

# 驱动下载 URL
DRIVER_FILENAME="NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run"
DRIVER_URL="https://download.nvidia.com/XFree86/Linux-x86_64/${NVIDIA_DRIVER_VERSION}/${DRIVER_FILENAME}"

echo "下载驱动安装包: $DRIVER_FILENAME"
echo "下载地址: $DRIVER_URL"
cd "$DRIVER_DIR"

if [ ! -f "$DRIVER_FILENAME" ]; then
    echo "开始下载..."
    if wget --show-progress --timeout=60 "$DRIVER_URL"; then
        echo -e "${GREEN}✓${NC} 驱动下载成功"
        chmod +x "$DRIVER_FILENAME"
    else
        echo ""
        echo -e "${RED}错误: 驱动下载失败${NC}"
        echo ""
        echo -e "${YELLOW}手动下载选项:${NC}"
        echo ""
        echo "方法 1: 使用浏览器下载"
        echo "  URL: $DRIVER_URL"
        echo ""
        echo "方法 2: 从 NVIDIA 官网下载"
        echo "  访问: https://www.nvidia.com/Download/index.aspx"
        echo "  选择对应的产品和版本 $NVIDIA_DRIVER_VERSION"
        echo ""
        echo "下载后将文件放置到: $(pwd)/"
        echo "文件名必须是: $DRIVER_FILENAME"
        echo ""

        read -p "是否已手动下载驱动? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "跳过驱动下载，继续其他组件..."
        else
            if [ ! -f "$DRIVER_FILENAME" ]; then
                echo -e "${RED}错误: 未找到驱动文件 $DRIVER_FILENAME${NC}"
                cd - > /dev/null
                exit 1
            fi
            chmod +x "$DRIVER_FILENAME"
        fi
    fi
else
    echo -e "${GREEN}✓${NC} 驱动已存在，跳过下载"
fi

cd - > /dev/null

# 下载驱动依赖包
echo "下载驱动依赖包..."
cd "$DRIVER_DIR"
apt-get update > /dev/null 2>&1

# 基础依赖
DRIVER_DEPS="build-essential dkms pkg-config libglvnd-dev"
for dep in $DRIVER_DEPS; do
    echo "  下载 $dep..."
    apt-get download $dep 2>/dev/null || true
    # 下载依赖的依赖
    apt-cache depends $dep | grep "Depends:" | awk '{print $2}' | while read subdep; do
        apt-get download $subdep 2>/dev/null || true
    done
done

cd - > /dev/null
echo -e "${GREEN}✓${NC} NVIDIA 驱动下载完成"
echo ""

# ========================================
# 下载 CUDA Toolkit
# ========================================
echo -e "${YELLOW}[3/7] 下载 CUDA Toolkit $CUDA_VERSION...${NC}"

# 添加 CUDA 仓库
echo "配置 CUDA 仓库..."
CUDA_REPO_PIN="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin"
CUDA_REPO_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64"

# 下载 CUDA repo pin
wget -q $CUDA_REPO_PIN -O /etc/apt/preferences.d/cuda-repository-pin-600 || true

# 添加 CUDA GPG key
if [ ! -f /usr/share/keyrings/cuda-archive-keyring.gpg ]; then
    wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
    dpkg -i cuda-keyring_1.1-1_all.deb 2>/dev/null || true
    rm -f cuda-keyring_1.1-1_all.deb
fi

# 更新软件源
apt-get update > /dev/null 2>&1

# 下载 CUDA 包
echo "下载 CUDA $CUDA_VERSION 核心包..."
cd "$CUDA_DIR"

# CUDA 核心包
CUDA_PACKAGES=(
    "cuda-toolkit-${CUDA_VERSION_FULL}"
    "cuda-runtime-${CUDA_VERSION_FULL}"
    "cuda-drivers"
    "cuda-cudart-${CUDA_VERSION_FULL}"
    "cuda-libraries-${CUDA_VERSION_FULL}"
    "cuda-nvcc-${CUDA_VERSION_FULL}"
)

for pkg in "${CUDA_PACKAGES[@]}"; do
    echo "  下载 $pkg..."
    apt-get download $pkg 2>/dev/null || {
        echo -e "    ${YELLOW}警告: $pkg 下载失败，继续...${NC}"
    }
done

# 下载 CUDA 元数据包
echo "下载 CUDA 依赖包..."
apt-get download \
    cuda-${CUDA_VERSION_FULL} \
    2>/dev/null || true

# 使用 apt-rdepends 下载所有依赖
if ! command -v apt-rdepends &> /dev/null; then
    apt-get install -y apt-rdepends > /dev/null 2>&1
fi

echo "分析并下载 CUDA 依赖关系..."
for pkg in cuda-toolkit-${CUDA_VERSION_FULL} cuda-runtime-${CUDA_VERSION_FULL}; do
    apt-rdepends $pkg 2>/dev/null | grep -v "^ " | grep -v "^$pkg$" | sort -u | while read dep; do
        if [ ! -z "$dep" ] && [ "$dep" != "Depends:" ] && [ "$dep" != "PreDepends:" ]; then
            apt-get download "$dep" 2>/dev/null || true
        fi
    done
done

# 保存 CUDA repo 配置
cp /etc/apt/preferences.d/cuda-repository-pin-600 . 2>/dev/null || true
cp /usr/share/keyrings/cuda-archive-keyring.gpg . 2>/dev/null || true

cd - > /dev/null
echo -e "${GREEN}✓${NC} CUDA Toolkit 下载完成"
echo ""

# ========================================
# 下载 NVIDIA Container Toolkit
# ========================================
echo -e "${YELLOW}[4/7] 下载 NVIDIA Container Toolkit...${NC}"

# 添加 NVIDIA Container Toolkit 仓库
echo "配置 Container Toolkit 仓库..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

cat > /etc/apt/sources.list.d/nvidia-container-toolkit.list <<EOF
deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/\$(ARCH) /
EOF

# 更新软件源
apt-get update > /dev/null 2>&1

# 下载 Container Toolkit 包
echo "下载 Container Toolkit 包..."
cd "$TOOLKIT_DIR"

TOOLKIT_PACKAGES=(
    "nvidia-container-toolkit"
    "libnvidia-container1"
    "libnvidia-container-tools"
    "nvidia-container-toolkit-base"
)

for pkg in "${TOOLKIT_PACKAGES[@]}"; do
    echo "  下载 $pkg..."
    apt-get download $pkg 2>/dev/null || true
done

# 下载依赖
echo "下载 Container Toolkit 依赖..."
for pkg in "${TOOLKIT_PACKAGES[@]}"; do
    apt-rdepends $pkg 2>/dev/null | grep -v "^ " | grep -v "^$pkg$" | sort -u | while read dep; do
        if [ ! -z "$dep" ] && [ "$dep" != "Depends:" ] && [ "$dep" != "PreDepends:" ]; then
            apt-get download "$dep" 2>/dev/null || true
        fi
    done
done

# 保存 GPG 密钥
cp /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg . 2>/dev/null || true

cd - > /dev/null
echo -e "${GREEN}✓${NC} Container Toolkit 下载完成"
echo ""

# ========================================
# 生成安装信息和校验和
# ========================================
echo -e "${YELLOW}[5/7] 生成包清单和校验和...${NC}"

# 生成驱动信息
echo "NVIDIA 驱动信息" > "$DRIVER_DIR/INFO.txt"
echo "================" >> "$DRIVER_DIR/INFO.txt"
echo "版本: $NVIDIA_DRIVER_VERSION" >> "$DRIVER_DIR/INFO.txt"
echo "下载日期: $(date)" >> "$DRIVER_DIR/INFO.txt"
echo "" >> "$DRIVER_DIR/INFO.txt"
ls -lh "$DRIVER_DIR"/*.run 2>/dev/null >> "$DRIVER_DIR/INFO.txt" || echo "无 .run 文件" >> "$DRIVER_DIR/INFO.txt"
ls -lh "$DRIVER_DIR"/*.deb 2>/dev/null | head -20 >> "$DRIVER_DIR/INFO.txt" || true

# CUDA 校验和
cd "$CUDA_DIR"
if ls *.deb 1> /dev/null 2>&1; then
    sha256sum *.deb > SHA256SUMS
    ls -lh *.deb > package-list.txt
    echo "CUDA 包数量: $(ls -1 *.deb | wc -l)" > INFO.txt
    echo "CUDA 版本: $CUDA_VERSION" >> INFO.txt
fi
cd - > /dev/null

# Container Toolkit 校验和
cd "$TOOLKIT_DIR"
if ls *.deb 1> /dev/null 2>&1; then
    sha256sum *.deb > SHA256SUMS
    ls -lh *.deb > package-list.txt
    echo "Container Toolkit 包数量: $(ls -1 *.deb | wc -l)" > INFO.txt
fi
cd - > /dev/null

echo -e "${GREEN}✓${NC} 清单生成完成"
echo ""

# ========================================
# 统计信息
# ========================================
echo -e "${YELLOW}[6/7] 统计下载信息...${NC}"

DRIVER_COUNT=$(ls -1 "$DRIVER_DIR"/*.run 2>/dev/null | wc -l)
DRIVER_DEB_COUNT=$(ls -1 "$DRIVER_DIR"/*.deb 2>/dev/null | wc -l)
CUDA_COUNT=$(ls -1 "$CUDA_DIR"/*.deb 2>/dev/null | wc -l)
TOOLKIT_COUNT=$(ls -1 "$TOOLKIT_DIR"/*.deb 2>/dev/null | wc -l)

echo "统计信息:"
echo "  驱动安装包: $DRIVER_COUNT 个 .run 文件"
echo "  驱动依赖包: $DRIVER_DEB_COUNT 个 .deb 文件"
echo "  CUDA 包: $CUDA_COUNT 个 .deb 文件"
echo "  Container Toolkit 包: $TOOLKIT_COUNT 个 .deb 文件"
echo ""

# 计算总大小
TOTAL_SIZE=$(du -sh "$BASE_DIR" | cut -f1)
echo "总下载大小: $TOTAL_SIZE"
echo ""

# ========================================
# 生成安装配置文件
# ========================================
echo -e "${YELLOW}[7/7] 生成安装配置...${NC}"

cat > "$BASE_DIR/install-config.conf" <<EOF
# NVIDIA 完整环境安装配置
# 自动生成于: $(date)

NVIDIA_DRIVER_VERSION=$NVIDIA_DRIVER_VERSION
CUDA_VERSION=$CUDA_VERSION
CUDA_VERSION_FULL=$CUDA_VERSION_FULL
UBUNTU_VERSION=$UBUNTU_VERSION
DOWNLOAD_DATE=$(date +%Y-%m-%d)
TOTAL_SIZE=$TOTAL_SIZE
EOF

echo -e "${GREEN}✓${NC} 配置文件已生成: $BASE_DIR/install-config.conf"
echo ""

# 完成
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}下载完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}下载内容:${NC}"
echo "  📦 NVIDIA 驱动 $NVIDIA_DRIVER_VERSION"
echo "  📦 CUDA Toolkit $CUDA_VERSION"
echo "  📦 NVIDIA Container Toolkit"
echo "  📦 所有必要的依赖包"
echo ""
echo -e "${BLUE}下载位置:${NC}"
echo "  驱动: $DRIVER_DIR/"
echo "  CUDA: $CUDA_DIR/"
echo "  Container Toolkit: $TOOLKIT_DIR/"
echo ""
echo -e "${YELLOW}下一步操作:${NC}"
echo "1. 打包所有文件:"
echo "   tar -czf nvidia-full-offline-install.tar.gz packages/ install-all-offline.sh *.md *.txt"
echo ""
echo "2. 将压缩包传输到目标离线服务器"
echo ""
echo "3. 在目标服务器上解压并安装:"
echo "   tar -xzf nvidia-full-offline-install.tar.gz"
echo "   sudo ./install-all-offline.sh"
echo ""
