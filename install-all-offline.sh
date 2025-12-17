#!/bin/bash

##############################################################################
# NVIDIA 完整环境离线安装脚本
# 适用于: Ubuntu 22.04
# 包含: NVIDIA 驱动 + CUDA Toolkit + Container Toolkit
#
# 安装顺序:
#   1. NVIDIA 驱动
#   2. CUDA Toolkit
#   3. NVIDIA Container Toolkit
#   4. 配置和验证
##############################################################################

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 目录配置
BASE_DIR="./packages"
DRIVER_DIR="$BASE_DIR/nvidia-driver"
CUDA_DIR="$BASE_DIR/cuda"
TOOLKIT_DIR="$BASE_DIR/container-toolkit"
CONFIG_FILE="$BASE_DIR/install-config.conf"
LOG_FILE="/var/log/nvidia-offline-install.log"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}NVIDIA 完整环境离线安装${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 记录日志
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo "安装开始时间: $(date)"
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用 root 权限运行此脚本${NC}"
    echo "使用: sudo $0"
    exit 1
fi

# 检查包目录
echo -e "${BLUE}[0/10] 检查安装包...${NC}"
if [ ! -d "$BASE_DIR" ]; then
    echo -e "${RED}错误: 找不到安装包目录 '$BASE_DIR'${NC}"
    exit 1
fi

# 读取配置
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    echo -e "${GREEN}✓${NC} 读取配置文件"
    echo "  NVIDIA 驱动版本: $NVIDIA_DRIVER_VERSION"
    echo "  CUDA 版本: $CUDA_VERSION"
else
    echo -e "${YELLOW}警告: 未找到配置文件，使用默认配置${NC}"
    NVIDIA_DRIVER_VERSION="575.51.03"
    CUDA_VERSION="12.9"
fi
echo ""

# 显示系统信息
echo -e "${BLUE}系统信息:${NC}"
echo "  操作系统: $(lsb_release -ds)"
echo "  内核版本: $(uname -r)"
echo "  架构: $(uname -m)"
echo ""

# 询问安装选项
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}安装选项配置${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo "请选择要安装的组件:"
echo ""
echo "1) 完整安装 (驱动 + CUDA + Container Toolkit) - 推荐"
echo "2) 仅安装驱动"
echo "3) 仅安装 CUDA (需要驱动已安装)"
echo "4) 仅安装 Container Toolkit (需要驱动已安装)"
echo "5) 自定义选择"
echo ""
read -p "请选择 [1-5]: " -n 1 -r INSTALL_CHOICE
echo ""
echo ""

INSTALL_DRIVER=false
INSTALL_CUDA=false
INSTALL_TOOLKIT=false

case $INSTALL_CHOICE in
    1)
        INSTALL_DRIVER=true
        INSTALL_CUDA=true
        INSTALL_TOOLKIT=true
        echo -e "${GREEN}选择: 完整安装${NC}"
        ;;
    2)
        INSTALL_DRIVER=true
        echo -e "${GREEN}选择: 仅安装驱动${NC}"
        ;;
    3)
        INSTALL_CUDA=true
        echo -e "${GREEN}选择: 仅安装 CUDA${NC}"
        ;;
    4)
        INSTALL_TOOLKIT=true
        echo -e "${GREEN}选择: 仅安装 Container Toolkit${NC}"
        ;;
    5)
        echo "自定义选择:"
        read -p "  安装 NVIDIA 驱动? (y/N): " -n 1 -r; echo
        [[ $REPLY =~ ^[Yy]$ ]] && INSTALL_DRIVER=true
        read -p "  安装 CUDA Toolkit? (y/N): " -n 1 -r; echo
        [[ $REPLY =~ ^[Yy]$ ]] && INSTALL_CUDA=true
        read -p "  安装 Container Toolkit? (y/N): " -n 1 -r; echo
        [[ $REPLY =~ ^[Yy]$ ]] && INSTALL_TOOLKIT=true
        ;;
    *)
        echo -e "${RED}无效选择，退出${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${YELLOW}将要安装:${NC}"
$INSTALL_DRIVER && echo "  ✓ NVIDIA 驱动 $NVIDIA_DRIVER_VERSION"
$INSTALL_CUDA && echo "  ✓ CUDA Toolkit $CUDA_VERSION"
$INSTALL_TOOLKIT && echo "  ✓ NVIDIA Container Toolkit"
echo ""
read -p "确认继续安装? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "安装已取消"
    exit 0
fi
echo ""

# ========================================
# 安装前检查
# ========================================
echo -e "${BLUE}[1/10] 安装前检查...${NC}"

# 检查是否已安装 NVIDIA 驱动
if command -v nvidia-smi &> /dev/null; then
    EXISTING_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
    echo -e "${YELLOW}⚠${NC} 检测到已安装的 NVIDIA 驱动: $EXISTING_DRIVER"

    if $INSTALL_DRIVER; then
        echo -e "${YELLOW}警告: 安装新驱动将覆盖现有驱动${NC}"
        read -p "是否继续? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            INSTALL_DRIVER=false
            echo "跳过驱动安装"
        fi
    fi
fi

# 检查 nouveau 驱动
if lsmod | grep -q nouveau; then
    echo -e "${YELLOW}⚠${NC} 检测到 nouveau 驱动正在使用"
    echo "需要禁用 nouveau 驱动才能安装 NVIDIA 驱动"

    if $INSTALL_DRIVER; then
        echo "正在禁用 nouveau 驱动..."
        cat > /etc/modprobe.d/blacklist-nouveau.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF
        update-initramfs -u
        echo -e "${YELLOW}警告: 需要重启系统后才能继续安装${NC}"
        echo "请运行: sudo reboot"
        echo "重启后重新运行此安装脚本"
        exit 0
    fi
fi

echo -e "${GREEN}✓${NC} 安装前检查完成"
echo ""

# ========================================
# 安装 NVIDIA 驱动
# ========================================
if $INSTALL_DRIVER; then
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}[2/10] 安装 NVIDIA 驱动${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    if [ ! -d "$DRIVER_DIR" ]; then
        echo -e "${RED}错误: 找不到驱动目录 '$DRIVER_DIR'${NC}"
        exit 1
    fi

    cd "$DRIVER_DIR"

    # 安装依赖
    echo "安装驱动依赖包..."
    if ls *.deb 1> /dev/null 2>&1; then
        dpkg -i *.deb 2>/dev/null || true
        apt-get install -f -y
    fi

    # 查找驱动安装包
    DRIVER_INSTALLER=$(ls NVIDIA-Linux-*.run 2>/dev/null | head -1)

    if [ -z "$DRIVER_INSTALLER" ]; then
        echo -e "${RED}错误: 找不到 NVIDIA 驱动安装包${NC}"
        cd - > /dev/null
        exit 1
    fi

    echo "找到驱动安装包: $DRIVER_INSTALLER"
    echo "开始安装 NVIDIA 驱动 (这可能需要几分钟)..."

    # 停止图形界面 (如果需要)
    systemctl stop gdm3 2>/dev/null || true
    systemctl stop lightdm 2>/dev/null || true

    # 安装驱动
    chmod +x "$DRIVER_INSTALLER"
    ./"$DRIVER_INSTALLER" --silent --dkms --no-questions || {
        echo -e "${RED}错误: 驱动安装失败${NC}"
        echo "请查看日志: /var/log/nvidia-installer.log"
        cd - > /dev/null
        exit 1
    }

    cd - > /dev/null

    # 验证安装
    if command -v nvidia-smi &> /dev/null; then
        echo -e "${GREEN}✓${NC} NVIDIA 驱动安装成功"
        INSTALLED_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
        echo "  已安装版本: $INSTALLED_DRIVER"
    else
        echo -e "${RED}错误: 驱动安装后无法找到 nvidia-smi${NC}"
        exit 1
    fi

    echo ""
else
    echo -e "${YELLOW}[2/10] 跳过 NVIDIA 驱动安装${NC}"
    echo ""
fi

# ========================================
# 安装 CUDA Toolkit
# ========================================
if $INSTALL_CUDA; then
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}[3/10] 安装 CUDA Toolkit${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    # 检查驱动
    if ! command -v nvidia-smi &> /dev/null; then
        echo -e "${RED}错误: 未检测到 NVIDIA 驱动，请先安装驱动${NC}"
        exit 1
    fi

    if [ ! -d "$CUDA_DIR" ]; then
        echo -e "${RED}错误: 找不到 CUDA 目录 '$CUDA_DIR'${NC}"
        exit 1
    fi

    cd "$CUDA_DIR"

    # 验证包完整性
    if [ -f SHA256SUMS ]; then
        echo "验证 CUDA 包完整性..."
        sha256sum -c SHA256SUMS --quiet || {
            echo -e "${YELLOW}警告: 部分包校验失败，但继续安装${NC}"
        }
    fi

    # 安装 CUDA keyring (如果存在)
    if [ -f cuda-archive-keyring.gpg ]; then
        cp cuda-archive-keyring.gpg /usr/share/keyrings/ 2>/dev/null || true
    fi

    if [ -f cuda-repository-pin-600 ]; then
        cp cuda-repository-pin-600 /etc/apt/preferences.d/ 2>/dev/null || true
    fi

    # 安装所有 deb 包
    echo "安装 CUDA 包 (这可能需要较长时间)..."
    dpkg -i *.deb 2>/dev/null || true

    # 修复依赖
    echo "修复依赖关系..."
    apt-get install -f -y

    cd - > /dev/null

    # 配置环境变量
    echo "配置 CUDA 环境变量..."
    if [ ! -f /etc/profile.d/cuda.sh ]; then
        cat > /etc/profile.d/cuda.sh <<'EOF'
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
EOF
    fi

    # 验证安装
    if [ -d /usr/local/cuda ]; then
        echo -e "${GREEN}✓${NC} CUDA Toolkit 安装成功"
        if [ -f /usr/local/cuda/version.txt ]; then
            cat /usr/local/cuda/version.txt | xargs echo "  CUDA 版本:"
        fi
    else
        echo -e "${YELLOW}警告: CUDA 可能未完全安装${NC}"
    fi

    echo ""
else
    echo -e "${YELLOW}[3/10] 跳过 CUDA Toolkit 安装${NC}"
    echo ""
fi

# ========================================
# 检查 Docker
# ========================================
echo -e "${BLUE}[4/10] 检查 Docker...${NC}"

if $INSTALL_TOOLKIT; then
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}错误: 未检测到 Docker${NC}"
        echo "Container Toolkit 需要 Docker，请先安装 Docker"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        echo -e "${RED}错误: Docker 未运行${NC}"
        echo "请启动 Docker: sudo systemctl start docker"
        exit 1
    fi

    echo -e "${GREEN}✓${NC} Docker 已就绪"
    docker --version | xargs echo " "
else
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}✓${NC} Docker 已安装"
    else
        echo -e "${YELLOW}⚠${NC} 未检测到 Docker (不影响当前安装)"
    fi
fi

echo ""

# ========================================
# 安装 NVIDIA Container Toolkit
# ========================================
if $INSTALL_TOOLKIT; then
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}[5/10] 安装 NVIDIA Container Toolkit${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    if [ ! -d "$TOOLKIT_DIR" ]; then
        echo -e "${RED}错误: 找不到 Container Toolkit 目录 '$TOOLKIT_DIR'${NC}"
        exit 1
    fi

    cd "$TOOLKIT_DIR"

    # 验证包完整性
    if [ -f SHA256SUMS ]; then
        echo "验证 Container Toolkit 包完整性..."
        sha256sum -c SHA256SUMS --quiet || {
            echo -e "${YELLOW}警告: 部分包校验失败，但继续安装${NC}"
        }
    fi

    # 安装 GPG 密钥
    if [ -f nvidia-container-toolkit-keyring.gpg ]; then
        cp nvidia-container-toolkit-keyring.gpg /usr/share/keyrings/ 2>/dev/null || true
    fi

    # 安装包
    echo "安装 Container Toolkit 包..."
    dpkg -i *.deb 2>/dev/null || true
    apt-get install -f -y

    cd - > /dev/null

    # 验证安装
    if command -v nvidia-ctk &> /dev/null; then
        echo -e "${GREEN}✓${NC} Container Toolkit 安装成功"
        nvidia-ctk --version | head -1 | xargs echo " "
    else
        echo -e "${RED}错误: Container Toolkit 安装失败${NC}"
        exit 1
    fi

    echo ""
else
    echo -e "${YELLOW}[5/10] 跳过 Container Toolkit 安装${NC}"
    echo ""
fi

# ========================================
# 配置 Docker Runtime
# ========================================
if $INSTALL_TOOLKIT; then
    echo -e "${BLUE}[6/10] 配置 Docker Runtime...${NC}"

    echo "配置 Docker 使用 NVIDIA runtime..."
    nvidia-ctk runtime configure --runtime=docker

    echo "重启 Docker 服务..."
    systemctl restart docker
    sleep 3

    if docker info &> /dev/null; then
        echo -e "${GREEN}✓${NC} Docker 配置完成"
    else
        echo -e "${RED}错误: Docker 重启失败${NC}"
        exit 1
    fi
    echo ""
else
    echo -e "${YELLOW}[6/10] 跳过 Docker 配置${NC}"
    echo ""
fi

# ========================================
# 加载内核模块
# ========================================
echo -e "${BLUE}[7/10] 加载内核模块...${NC}"

if $INSTALL_DRIVER; then
    echo "加载 NVIDIA 内核模块..."
    modprobe nvidia 2>/dev/null || echo -e "${YELLOW}  警告: 无法加载 nvidia 模块，可能需要重启${NC}"
    modprobe nvidia-uvm 2>/dev/null || true
fi

echo -e "${GREEN}✓${NC} 内核模块检查完成"
echo ""

# ========================================
# 创建验证脚本
# ========================================
echo -e "${BLUE}[8/10] 生成验证报告...${NC}"

VERIFY_REPORT="/tmp/nvidia-install-verify.txt"
cat > "$VERIFY_REPORT" <<EOF
NVIDIA 完整环境安装报告
=======================
安装时间: $(date)

已安装组件:
EOF

$INSTALL_DRIVER && echo "✓ NVIDIA 驱动 $NVIDIA_DRIVER_VERSION" >> "$VERIFY_REPORT"
$INSTALL_CUDA && echo "✓ CUDA Toolkit $CUDA_VERSION" >> "$VERIFY_REPORT"
$INSTALL_TOOLKIT && echo "✓ NVIDIA Container Toolkit" >> "$VERIFY_REPORT"

cat >> "$VERIFY_REPORT" <<EOF

系统信息:
---------
EOF

if command -v nvidia-smi &> /dev/null; then
    echo "NVIDIA 驱动:" >> "$VERIFY_REPORT"
    nvidia-smi --query-gpu=driver_version,name --format=csv,noheader >> "$VERIFY_REPORT"
fi

if [ -d /usr/local/cuda ]; then
    echo "" >> "$VERIFY_REPORT"
    echo "CUDA:" >> "$VERIFY_REPORT"
    if [ -f /usr/local/cuda/version.txt ]; then
        cat /usr/local/cuda/version.txt >> "$VERIFY_REPORT"
    fi
fi

if command -v nvidia-ctk &> /dev/null; then
    echo "" >> "$VERIFY_REPORT"
    echo "Container Toolkit:" >> "$VERIFY_REPORT"
    nvidia-ctk --version >> "$VERIFY_REPORT"
fi

echo -e "${GREEN}✓${NC} 验证报告: $VERIFY_REPORT"
echo ""

# ========================================
# 快速验证
# ========================================
echo -e "${BLUE}[9/10] 快速验证...${NC}"

VERIFY_PASSED=0
VERIFY_FAILED=0

if $INSTALL_DRIVER; then
    if nvidia-smi &> /dev/null; then
        echo -e "${GREEN}✓${NC} NVIDIA 驱动验证通过"
        ((VERIFY_PASSED++))
    else
        echo -e "${RED}✗${NC} NVIDIA 驱动验证失败"
        ((VERIFY_FAILED++))
    fi
fi

if $INSTALL_CUDA; then
    if [ -d /usr/local/cuda ]; then
        echo -e "${GREEN}✓${NC} CUDA Toolkit 验证通过"
        ((VERIFY_PASSED++))
    else
        echo -e "${RED}✗${NC} CUDA Toolkit 验证失败"
        ((VERIFY_FAILED++))
    fi
fi

if $INSTALL_TOOLKIT; then
    if command -v nvidia-ctk &> /dev/null; then
        echo -e "${GREEN}✓${NC} Container Toolkit 验证通过"
        ((VERIFY_PASSED++))
    else
        echo -e "${RED}✗${NC} Container Toolkit 验证失败"
        ((VERIFY_FAILED++))
    fi
fi

echo ""

# ========================================
# 完成
# ========================================
echo -e "${BLUE}[10/10] 安装完成${NC}"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}安装成功完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${CYAN}验证结果: ${GREEN}$VERIFY_PASSED${NC} 通过, ${RED}$VERIFY_FAILED${NC} 失败${NC}"
echo ""

if [ $VERIFY_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ 所有组件安装成功！${NC}"
else
    echo -e "${YELLOW}⚠ 部分组件可能需要重启系统后才能正常工作${NC}"
fi

echo ""
echo -e "${YELLOW}建议操作:${NC}"
echo "1. 重启系统以确保所有更改生效:"
echo "   sudo reboot"
echo ""
echo "2. 重启后运行完整验证:"
echo "   sudo ./verify-installation.sh"
echo ""

if $INSTALL_TOOLKIT; then
    echo "3. 测试 GPU 容器:"
    echo "   docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi"
    echo ""
fi

echo -e "${BLUE}日志文件: $LOG_FILE${NC}"
echo -e "${BLUE}验证报告: $VERIFY_REPORT${NC}"
echo ""

echo "安装完成时间: $(date)"
