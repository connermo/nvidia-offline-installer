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
mkdir -p "$DOWNLOAD_DIR"
echo -e "${GREEN}✓${NC} 目录已创建: $DOWNLOAD_DIR (所有包统一下载到此目录)"
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
TARGET_KERNEL_VERSION=""

case $choice in
    1)
        echo -e "${BLUE}场景 A: 仅下载 Container Toolkit${NC}"
        DOWNLOAD_SCRIPT="download-packages.sh"
        ;;
    2)
        echo -e "${BLUE}场景 B: 下载驱动 + CUDA${NC}"
        DOWNLOAD_SCRIPT="download-driver-cuda.sh"

        # 询问目标内核版本
        echo ""
        echo -e "${YELLOW}注意: linux-headers 必须与目标机器的内核版本完全匹配${NC}"
        echo "如果不确定，可以留空，稍后在目标机器上安装"
        echo ""
        read -p "目标机器内核版本（如 6.8.0-31-generic，留空跳过）: " TARGET_KERNEL_VERSION
        echo ""
        ;;
    3)
        echo -e "${BLUE}场景 C: 下载所有组件${NC}"
        DOWNLOAD_SCRIPT="download-all-packages.sh"

        # 询问目标内核版本
        echo ""
        echo -e "${YELLOW}注意: linux-headers 必须与目标机器的内核版本完全匹配${NC}"
        echo "如果不确定，可以留空，稍后在目标机器上安装"
        echo ""
        read -p "目标机器内核版本（如 6.8.0-31-generic，留空跳过）: " TARGET_KERNEL_VERSION
        echo ""
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

# 创建日志目录和文件
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="./download-logs"
mkdir -p "$LOG_DIR"
DOCKER_LOG="$LOG_DIR/docker_download_${TIMESTAMP}.log"

echo "日志文件: $DOCKER_LOG"
echo ""

# 运行 Docker 容器进行下载，捕获所有输出
if docker run --rm \
    -v "$(pwd):/workspace" \
    -w /workspace \
    -e NVIDIA_DRIVER_VERSION="$NVIDIA_DRIVER_VERSION" \
    -e CUDA_VERSION="$CUDA_VERSION" \
    -e CUDA_VERSION_FULL="$CUDA_VERSION_FULL" \
    -e TARGET_KERNEL_VERSION="$TARGET_KERNEL_VERSION" \
    nvidia-offline-downloader:ubuntu22.04 \
    bash -c "
        # 更新 apt 包索引（重要！避免404错误）
        echo '========================================'
        echo '更新 apt 包索引...'
        echo '========================================'
        apt-get update || {
            echo '警告: apt-get update 失败，但继续尝试下载'
        }
        echo ''

        # 确保脚本可执行
        chmod +x $DOWNLOAD_SCRIPT

        # 运行下载脚本（自动跳过交互式提示）
        # 传递空字符串到脚本以跳过交互式提示
        echo '' | bash $DOWNLOAD_SCRIPT || bash $DOWNLOAD_SCRIPT
    " 2>&1 | tee "$DOCKER_LOG"; then
    DOWNLOAD_SUCCESS=true
else
    DOWNLOAD_SUCCESS=false
fi

echo ""
echo -e "${GREEN}✓${NC} 下载完成"
echo ""

echo -e "${BLUE}[4/4] 分析下载结果...${NC}"
echo ""

# 分析日志中的失败信息
FAILED_PACKAGES_FILE="$LOG_DIR/failed_packages_${TIMESTAMP}.txt"

# 提取失败的包
echo "分析下载日志..."
grep -E "(失败|Failed|Unable to locate|404|E: Package)" "$DOCKER_LOG" 2>/dev/null | \
    grep -oE "\b[a-z0-9][a-z0-9+._-]+\b" | \
    grep -v "^E$\|^Package$\|^failed$\|^Failed$" | \
    sort -u > "$FAILED_PACKAGES_FILE" 2>/dev/null || true

# 统计结果
SUCCESS_COUNT=$(grep -c "✓\|成功" "$DOCKER_LOG" 2>/dev/null || echo "0")
FAILED_MENTION=$(grep -c "失败\|失败\|Failed\|failed" "$DOCKER_LOG" 2>/dev/null || echo "0")

# 统计下载的文件（统一目录）
TOTAL_DEB_COUNT=$(find "$DOWNLOAD_DIR" -maxdepth 1 -name "*.deb" 2>/dev/null | wc -l | tr -d ' ')
TOTAL_RUN_COUNT=$(find "$DOWNLOAD_DIR" -maxdepth 1 -name "*.run" 2>/dev/null | wc -l | tr -d ' ')

echo ""
echo "下载统计:"
echo "  成功标记: $SUCCESS_COUNT"
echo "  失败提及: $FAILED_MENTION"
echo ""
echo "  .deb 包数量: $TOTAL_DEB_COUNT"
echo "  .run 文件数量: $TOTAL_RUN_COUNT"
echo "  总文件数: $((TOTAL_DEB_COUNT + TOTAL_RUN_COUNT))"
echo ""

# 计算总大小
TOTAL_SIZE=$(du -sh "$DOWNLOAD_DIR" | cut -f1)
echo "总下载大小: $TOTAL_SIZE"
echo ""

# 分析失败的包
if [ -s "$FAILED_PACKAGES_FILE" ]; then
    FAILED_PKG_COUNT=$(wc -l < "$FAILED_PACKAGES_FILE" | tr -d ' ')
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}检测到 $FAILED_PKG_COUNT 个可能失败的包${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # 分类显示前15个
    echo "失败包预览（前15个）:"
    head -15 "$FAILED_PACKAGES_FILE" | while read pkg; do
        if [[ "$pkg" == *"-doc"* ]] || [[ "$pkg" == *"-examples"* ]]; then
            echo -e "  ${BLUE}◇${NC} $pkg ${BLUE}(文档/示例 - 可选)${NC}"
        elif [[ "$pkg" == *"-dev"* ]]; then
            echo -e "  ${BLUE}◇${NC} $pkg ${BLUE}(开发包 - 编译时需要)${NC}"
        elif [[ "$pkg" == *"cuda"* ]] || [[ "$pkg" == *"nvidia"* ]]; then
            echo -e "  ${YELLOW}?${NC} $pkg ${YELLOW}(需要检查)${NC}"
        elif [[ "$pkg" =~ ^(awk|c-compiler|c-shell|x11-common)$ ]]; then
            echo -e "  ${GREEN}○${NC} $pkg ${GREEN}(虚拟包 - 可忽略)${NC}"
        else
            echo -e "  ${CYAN}·${NC} $pkg"
        fi
    done

    if [ $FAILED_PKG_COUNT -gt 15 ]; then
        echo -e "  ${CYAN}... 还有 $((FAILED_PKG_COUNT - 15)) 个${NC}"
    fi
    echo ""

    echo -e "${BLUE}详细分析${NC}:"
    echo "使用以下命令进行详细分析:"
    echo -e "  ${CYAN}./analyze-failures.sh $FAILED_PACKAGES_FILE${NC}"
    echo ""

    # 快速判断是否有关键包失败
    CRITICAL_COUNT=$(grep -E "nvidia-driver|cuda-toolkit|cuda-runtime|nvidia-container-toolkit|libnvidia" "$FAILED_PACKAGES_FILE" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$CRITICAL_COUNT" -gt 0 ]; then
        echo -e "${RED}⚠️  警告: 检测到 $CRITICAL_COUNT 个可能的关键包失败！${NC}"
        echo ""
        echo "建议操作:"
        echo "  1. 查看完整日志: cat $DOCKER_LOG"
        echo "  2. 运行详细分析: ./analyze-failures.sh $FAILED_PACKAGES_FILE"
        echo "  3. 如确认为关键包，重新构建 Docker 镜像后再试"
        echo ""
    else
        echo -e "${GREEN}✓${NC} 未检测到关键包失败"
        echo -e "${GREEN}失败的包大多是虚拟包或可选包，可以继续安装${NC}"
        echo ""
    fi
else
    echo -e "${GREEN}✓ 未检测到明显的失败包${NC}"
    echo ""
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}下载完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "安装包位置: $DOWNLOAD_DIR"
echo ""
echo -e "${CYAN}说明:${NC}"
echo "  所有下载的包都统一保存在 packages/ 目录中"
echo "  三种下载场景的包会自动合并，公共依赖自动去重"
echo "  可以多次运行不同场景，包会累积到同一目录"
echo ""
echo "日志文件:"
echo "  完整日志: $DOCKER_LOG"
if [ -s "$FAILED_PACKAGES_FILE" ]; then
    echo "  失败包列表: $FAILED_PACKAGES_FILE"
fi
echo ""
echo "后续步骤:"
echo "1. 如有失败包，运行分析: ./analyze-failures.sh $FAILED_PACKAGES_FILE"
echo "2. 将 packages 目录复制到目标机器"
echo "3. 根据场景选择对应的安装脚本:"
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
            TOTAL=0
            VALID=0

            for deb in *.deb; do
                if [ -f \"\$deb\" ]; then
                    TOTAL=\$((TOTAL + 1))
                    if dpkg -I \"\$deb\" > /dev/null 2>&1; then
                        VALID=\$((VALID + 1))
                    else
                        echo \"  ✗ 损坏: \$deb\"
                        ERROR=1
                    fi
                fi
            done

            echo \"检查了 \$TOTAL 个 .deb 包\"
            if [ \$ERROR -eq 0 ]; then
                echo \"✓ 所有包验证通过 (\$VALID/\$TOTAL)\"
            else
                echo \"⚠ 发现损坏的包\"
                exit 1
            fi
        "
    echo -e "${GREEN}✓${NC} 验证完成"
fi

echo ""
echo -e "${GREEN}全部完成！${NC}"
