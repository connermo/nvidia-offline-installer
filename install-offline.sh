#!/bin/bash

##############################################################################
# NVIDIA Container Toolkit 离线安装脚本
# 适用于: Ubuntu 22.04
# 前置条件:
#   - NVIDIA 驱动已安装 (建议 575.51.03)
#   - CUDA 已安装 (建议 12.9)
#   - Docker 已安装并运行
##############################################################################

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PACKAGES_DIR="./packages"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}NVIDIA Container Toolkit 离线安装${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用 root 权限运行此脚本${NC}"
    echo "使用: sudo $0"
    exit 1
fi

# 检查包目录是否存在
if [ ! -d "$PACKAGES_DIR" ]; then
    echo -e "${RED}错误: 找不到安装包目录 '$PACKAGES_DIR'${NC}"
    echo "请确保已解压离线安装包并在正确的目录下运行此脚本"
    exit 1
fi

# 检查是否有 .deb 文件
if [ ! "$(ls -A $PACKAGES_DIR/*.deb 2>/dev/null)" ]; then
    echo -e "${RED}错误: 在 '$PACKAGES_DIR' 中找不到 .deb 安装包${NC}"
    exit 1
fi

# 验证前置条件
echo -e "${BLUE}[1/8] 验证系统环境...${NC}"

# 检查 NVIDIA 驱动
if ! command -v nvidia-smi &> /dev/null; then
    echo -e "${RED}错误: 未检测到 NVIDIA 驱动${NC}"
    echo "请先安装 NVIDIA 驱动"
    exit 1
fi

echo -e "${GREEN}✓${NC} NVIDIA 驱动已安装"
nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1 | xargs echo "  驱动版本:"

# 检查 CUDA
if [ -d /usr/local/cuda ]; then
    echo -e "${GREEN}✓${NC} CUDA 已安装"
    if [ -f /usr/local/cuda/version.txt ]; then
        cat /usr/local/cuda/version.txt | xargs echo "  CUDA 版本:"
    elif command -v nvcc &> /dev/null; then
        nvcc --version | grep "release" | awk '{print $5}' | sed 's/,//' | xargs echo "  CUDA 版本:"
    fi
else
    echo -e "${YELLOW}警告: 未检测到 CUDA 安装 (可选)${NC}"
fi

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}错误: 未检测到 Docker${NC}"
    echo "请先安装 Docker"
    exit 1
fi

echo -e "${GREEN}✓${NC} Docker 已安装"
docker --version | xargs echo "  Docker 版本:"

# 检查 Docker 是否运行
if ! docker info &> /dev/null; then
    echo -e "${RED}错误: Docker 未运行${NC}"
    echo "请启动 Docker 服务: sudo systemctl start docker"
    exit 1
fi
echo -e "${GREEN}✓${NC} Docker 服务正在运行"

echo ""

# 验证校验和 (如果存在)
if [ -f "$PACKAGES_DIR/SHA256SUMS" ]; then
    echo -e "${BLUE}[2/8] 验证安装包完整性...${NC}"
    cd "$PACKAGES_DIR"
    if sha256sum -c SHA256SUMS --quiet 2>/dev/null; then
        echo -e "${GREEN}✓${NC} 所有安装包校验成功"
    else
        echo -e "${YELLOW}警告: 部分安装包校验失败，但继续安装...${NC}"
    fi
    cd ..
else
    echo -e "${YELLOW}[2/8] 跳过完整性验证 (未找到 SHA256SUMS)${NC}"
fi

echo ""

# 清理可能存在的旧配置
echo -e "${BLUE}[3/8] 清理旧配置...${NC}"
if [ -f /etc/apt/sources.list.d/nvidia-container-toolkit.list ]; then
    echo "移除旧的软件源配置..."
    rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list
fi

# 卸载旧版本 (如果存在)
if dpkg -l | grep -q nvidia-container-toolkit; then
    echo -e "${YELLOW}检测到已安装的版本，准备升级...${NC}"
    OLD_VERSION=$(dpkg -l | grep nvidia-container-toolkit | awk '{print $3}')
    echo "  当前版本: $OLD_VERSION"
fi

echo ""

# 安装依赖包
echo -e "${BLUE}[4/8] 安装依赖包...${NC}"
cd "$PACKAGES_DIR"

# 首先安装基础依赖
echo "安装基础依赖..."
dpkg -i *.deb 2>/dev/null || true

# 修复依赖关系
echo -e "${BLUE}[5/8] 修复依赖关系...${NC}"
apt-get install -f -y --fix-missing 2>/dev/null || true

# 强制安装 NVIDIA Container Toolkit 相关包
echo -e "${BLUE}[6/8] 安装 NVIDIA Container Toolkit...${NC}"
dpkg -i --force-depends \
    libnvidia-container1_*.deb \
    libnvidia-container-tools_*.deb \
    nvidia-container-toolkit-base_*.deb \
    nvidia-container-toolkit_*.deb 2>/dev/null || true

# 再次修复依赖
apt-get install -f -y 2>/dev/null || true

cd ..

echo ""

# 配置 Docker runtime
echo -e "${BLUE}[7/8] 配置 Docker runtime...${NC}"
if command -v nvidia-ctk &> /dev/null; then
    echo "配置 Docker 使用 NVIDIA runtime..."
    nvidia-ctk runtime configure --runtime=docker
    echo -e "${GREEN}✓${NC} Docker runtime 配置完成"
else
    echo -e "${RED}错误: nvidia-ctk 命令不可用${NC}"
    exit 1
fi

# 重启 Docker
echo "重启 Docker 服务..."
systemctl restart docker

# 等待 Docker 启动
sleep 3

if ! docker info &> /dev/null; then
    echo -e "${RED}错误: Docker 重启后无法连接${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Docker 服务已重启"

echo ""

# 验证安装
echo -e "${BLUE}[8/8] 验证安装...${NC}"

# 检查安装的版本
if dpkg -l | grep -q nvidia-container-toolkit; then
    INSTALLED_VERSION=$(dpkg -l | grep nvidia-container-toolkit | head -1 | awk '{print $3}')
    echo -e "${GREEN}✓${NC} NVIDIA Container Toolkit 已安装"
    echo "  版本: $INSTALLED_VERSION"
else
    echo -e "${RED}错误: NVIDIA Container Toolkit 安装失败${NC}"
    exit 1
fi

# 测试 NVIDIA runtime
echo ""
echo "测试 NVIDIA Container Runtime..."
if docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi &> /dev/null; then
    echo -e "${GREEN}✓${NC} NVIDIA Container Runtime 测试成功！"
else
    echo -e "${YELLOW}警告: 无法运行测试容器${NC}"
    echo "这可能是因为:"
    echo "  1. 网络原因无法拉取测试镜像"
    echo "  2. 需要手动验证"
    echo ""
    echo "手动验证命令:"
    echo "  docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}安装完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}后续步骤:${NC}"
echo "1. 验证安装:"
echo "   docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi"
echo ""
echo "2. 在 docker-compose 中使用:"
echo "   services:"
echo "     your-service:"
echo "       deploy:"
echo "         resources:"
echo "           reservations:"
echo "             devices:"
echo "               - driver: nvidia"
echo "                 count: all"
echo "                 capabilities: [gpu]"
echo ""
echo "3. 在 docker run 中使用:"
echo "   docker run --gpus all your-image"
echo ""
