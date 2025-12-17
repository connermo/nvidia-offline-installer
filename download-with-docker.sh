#!/bin/bash

##############################################################################
# 使用 Docker 容器下载 NVIDIA 离线安装包
# 优势：
#   - 在干净的 Ubuntu 22.04 环境中下载
#   - 确保依赖关系正确
#   - 不污染宿主机环境
#   - 可验证包的完整性
##############################################################################

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置
NVIDIA_DRIVER_VERSION="550.127.05"
CUDA_VERSION="12.9"
CUDA_VERSION_FULL="12-9"
DOWNLOAD_DIR="$(pwd)/packages"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}使用 Docker 下载 NVIDIA 离线安装包${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "NVIDIA 驱动版本: $NVIDIA_DRIVER_VERSION"
echo "CUDA 版本: $CUDA_VERSION"
echo "下载目录: $DOWNLOAD_DIR"
echo ""

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo -e "${RED}错误: 未检测到 Docker${NC}"
    echo "请先安装 Docker: https://docs.docker.com/engine/install/"
    exit 1
fi

# 检查 Docker 是否运行
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}错误: Docker 未运行${NC}"
    echo "请启动 Docker 服务"
    exit 1
fi

echo -e "${BLUE}[1/4] 创建下载目录...${NC}"
mkdir -p "$DOWNLOAD_DIR"/{nvidia-driver,cuda,container-toolkit}
echo -e "${GREEN}✓${NC} 目录已创建"
echo ""

# 选择下载场景
echo -e "${YELLOW}请选择下载场景:${NC}"
echo "1) 仅 Container Toolkit（驱动和 CUDA 已安装）"
echo "2) 驱动 + CUDA（新系统安装）"
echo "3) 完整安装（所有组件）"
echo ""
read -p "请选择 [1-3]: " choice
echo ""

DOWNLOAD_SCRIPT=""
case $choice in
    1)
        echo -e "${BLUE}场景 A: 仅下载 Container Toolkit${NC}"
        DOWNLOAD_SCRIPT="download-packages.sh"
        ;;
    2)
        echo -e "${BLUE}场景 B: 下载驱动 + CUDA${NC}"
        DOWNLOAD_SCRIPT="download-driver-cuda.sh"
        ;;
    3)
        echo -e "${BLUE}场景 C: 下载所有组件${NC}"
        DOWNLOAD_SCRIPT="download-all-packages.sh"
        ;;
    *)
        echo -e "${RED}无效选择${NC}"
        exit 1
        ;;
esac
echo ""

echo -e "${BLUE}[2/4] 构建 Docker 镜像...${NC}"
docker build -t nvidia-offline-downloader:ubuntu22.04 -f Dockerfile.download . || {
    echo -e "${RED}错误: Docker 镜像构建失败${NC}"
    exit 1
}
echo -e "${GREEN}✓${NC} Docker 镜像构建完成"
echo ""

echo -e "${BLUE}[3/4] 在 Docker 容器中下载安装包...${NC}"
echo "这可能需要较长时间，请耐心等待..."
echo ""

# 检查下载脚本是否存在
if [ ! -f "$(pwd)/$DOWNLOAD_SCRIPT" ]; then
    echo -e "${RED}错误: 未找到下载脚本 $DOWNLOAD_SCRIPT${NC}"
    exit 1
fi

# 运行 Docker 容器进行下载
docker run --rm \
    -v "$(pwd):/workspace" \
    -w /workspace \
    -e NVIDIA_DRIVER_VERSION="$NVIDIA_DRIVER_VERSION" \
    -e CUDA_VERSION="$CUDA_VERSION" \
    -e CUDA_VERSION_FULL="$CUDA_VERSION_FULL" \
    nvidia-offline-downloader:ubuntu22.04 \
    bash -c "
        # 确保脚本可执行
        chmod +x $DOWNLOAD_SCRIPT

        # 运行下载脚本（自动跳过交互式提示）
        echo 'y' | bash $DOWNLOAD_SCRIPT || bash $DOWNLOAD_SCRIPT
    "

echo ""
echo -e "${GREEN}✓${NC} 下载完成"
echo ""

echo -e "${BLUE}[4/4] 检查下载结果...${NC}"
echo ""

# 统计下载的文件
DRIVER_COUNT=$(find "$DOWNLOAD_DIR/nvidia-driver" -name "*.deb" -o -name "*.run" 2>/dev/null | wc -l)
CUDA_COUNT=$(find "$DOWNLOAD_DIR/cuda" -name "*.deb" 2>/dev/null | wc -l)
TOOLKIT_COUNT=$(find "$DOWNLOAD_DIR/container-toolkit" -name "*.deb" 2>/dev/null | wc -l)

echo "下载统计:"
echo "  NVIDIA 驱动文件: $DRIVER_COUNT"
echo "  CUDA 包: $CUDA_COUNT"
echo "  Container Toolkit 包: $TOOLKIT_COUNT"
echo ""

# 计算总大小
TOTAL_SIZE=$(du -sh "$DOWNLOAD_DIR" | cut -f1)
echo "总下载大小: $TOTAL_SIZE"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}下载完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "安装包位置: $DOWNLOAD_DIR"
echo ""
echo "后续步骤:"
echo "1. 将 packages 目录复制到目标机器"
echo "2. 根据场景选择对应的安装脚本:"
echo "   - 场景 A: ./install-offline.sh"
echo "   - 场景 B: ./install-driver-cuda.sh"
echo "   - 场景 C: ./install-all-offline.sh"
echo ""

# 询问是否在容器中验证
read -p "是否在 Docker 容器中验证安装包? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}在容器中验证安装包...${NC}"
    docker run --rm \
        -v "$DOWNLOAD_DIR:/packages:ro" \
        nvidia-offline-downloader:ubuntu22.04 \
        bash -c "
            echo '验证 .deb 包完整性...'
            cd /packages
            ERROR=0
            for dir in nvidia-driver cuda container-toolkit; do
                if [ -d \"\$dir\" ]; then
                    echo \"检查 \$dir 目录...\"
                    find \"\$dir\" -name '*.deb' | while read deb; do
                        if ! dpkg -I \"\$deb\" > /dev/null 2>&1; then
                            echo \"  ✗ 损坏: \$deb\"
                            ERROR=1
                        fi
                    done
                fi
            done
            if [ \$ERROR -eq 0 ]; then
                echo '✓ 所有包验证通过'
            else
                echo '⚠ 发现损坏的包'
                exit 1
            fi
        "
    echo -e "${GREEN}✓${NC} 验证完成"
fi

echo ""
echo -e "${GREEN}全部完成！${NC}"
