#!/bin/bash

##############################################################################
# NVIDIA Container Toolkit 离线安装包下载脚本
# 适用于: Ubuntu 22.04
# 用途: 在联网环境下载所有必要的安装包
##############################################################################

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置
UBUNTU_VERSION="22.04"
UBUNTU_CODENAME="jammy"
PACKAGES_DIR="./packages"
REPO_LIST_DIR="./repo-lists"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}NVIDIA Container Toolkit 离线包下载${NC}"
echo -e "${GREEN}========================================${NC}"

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用 root 权限运行此脚本${NC}"
    echo "使用: sudo $0"
    exit 1
fi

# 创建目录结构
echo -e "${YELLOW}[1/6] 创建目录结构...${NC}"
mkdir -p "$PACKAGES_DIR"
mkdir -p "$REPO_LIST_DIR"

# 备份现有源列表
echo -e "${YELLOW}[2/6] 备份现有软件源配置...${NC}"
if [ -f /etc/apt/sources.list.d/nvidia-container-toolkit.list ]; then
    cp /etc/apt/sources.list.d/nvidia-container-toolkit.list "$REPO_LIST_DIR/nvidia-container-toolkit.list.backup" || true
fi

# 添加 NVIDIA Container Toolkit 仓库
echo -e "${YELLOW}[3/6] 配置 NVIDIA Container Toolkit 仓库...${NC}"
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

cat > /etc/apt/sources.list.d/nvidia-container-toolkit.list <<EOF
deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/\$(ARCH) /
EOF

# 更新软件源
echo -e "${YELLOW}[4/6] 更新软件源...${NC}"
apt-get update

# 下载 NVIDIA Container Toolkit 及其依赖
echo -e "${YELLOW}[5/6] 下载 NVIDIA Container Toolkit 及所有依赖包...${NC}"
cd "$PACKAGES_DIR"

# 使用 apt-get download 下载包及依赖
echo "下载 nvidia-container-toolkit..."
apt-get download nvidia-container-toolkit 2>/dev/null || true

echo "下载 libnvidia-container1..."
apt-get download libnvidia-container1 2>/dev/null || true

echo "下载 libnvidia-container-tools..."
apt-get download libnvidia-container-tools 2>/dev/null || true

echo "下载 nvidia-container-toolkit-base..."
apt-get download nvidia-container-toolkit-base 2>/dev/null || true

# 使用 apt-rdepends 获取所有递归依赖
echo "分析依赖关系..."
if ! command -v apt-rdepends &> /dev/null; then
    apt-get install -y apt-rdepends
fi

# 下载所有递归依赖
for pkg in nvidia-container-toolkit libnvidia-container1 libnvidia-container-tools nvidia-container-toolkit-base; do
    echo "下载 $pkg 的依赖..."
    apt-rdepends $pkg 2>/dev/null | grep -v "^ " | grep -v "^$pkg$" | sort -u | while read dep; do
        if [ ! -z "$dep" ] && [ "$dep" != "Depends:" ] && [ "$dep" != "PreDepends:" ]; then
            apt-get download "$dep" 2>/dev/null || echo "警告: 无法下载 $dep (可能已存在或不需要)"
        fi
    done
done

cd ..

# 保存包列表
echo -e "${YELLOW}[6/6] 生成包清单...${NC}"
ls -lh "$PACKAGES_DIR"/*.deb > "$PACKAGES_DIR/package-list.txt" 2>/dev/null || true
echo "总计: $(ls -1 $PACKAGES_DIR/*.deb 2>/dev/null | wc -l) 个安装包"

# 计算总大小
TOTAL_SIZE=$(du -sh "$PACKAGES_DIR" | cut -f1)
echo -e "${GREEN}下载完成！总大小: $TOTAL_SIZE${NC}"

# 创建校验和
echo -e "${YELLOW}生成 SHA256 校验和...${NC}"
cd "$PACKAGES_DIR"
sha256sum *.deb > SHA256SUMS
cd ..

# 保存 GPG 密钥
echo -e "${YELLOW}保存 GPG 密钥...${NC}"
cp /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg "$PACKAGES_DIR/" 2>/dev/null || true

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}下载完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}下载位置:${NC} $PACKAGES_DIR/"
echo -e "${BLUE}总大小:${NC} $TOTAL_SIZE"
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}后续步骤指引${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 生成日期戳（避免在 echo 中使用 % 符号）
DATE_STAMP=$(date +%Y%m%d)

echo -e "${CYAN}步骤 1: 打包压缩${NC}"
echo "在当前机器上执行:"
echo ""
echo -e "  ${GREEN}tar -czf nvidia-toolkit-${DATE_STAMP}.tar.gz packages/ install-offline.sh${NC}"
echo ""

echo -e "${CYAN}步骤 2: 传输到目标机器${NC}"
echo "使用 SCP 或其他方式传输:"
echo ""
echo -e "  ${GREEN}scp nvidia-toolkit-${DATE_STAMP}.tar.gz user@target-host:/tmp/${NC}"
echo ""

echo -e "${CYAN}步骤 3: 在目标机器上解压并安装${NC}"
echo ""
echo -e "  ${GREEN}cd /tmp${NC}"
echo -e "  ${GREEN}tar -xzf nvidia-toolkit-${DATE_STAMP}.tar.gz${NC}"
echo -e "  ${GREEN}chmod +x install-offline.sh${NC}"
echo -e "  ${GREEN}sudo ./install-offline.sh${NC}"
echo ""

echo -e "${CYAN}步骤 4: 验证安装${NC}"
echo ""
echo -e "  ${GREEN}docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi${NC}"
echo ""

echo -e "${BLUE}提示: Container Toolkit 安装无需重启${NC}"
echo ""
