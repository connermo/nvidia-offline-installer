#!/bin/bash

##############################################################################
# NVIDIA 驱动 + CUDA Toolkit 离线安装脚本
# 适用于: Ubuntu 22.04
# 安装: NVIDIA 驱动 575.51.03 + CUDA 12.9
##############################################################################

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 目录配置 - 统一使用 packages/ 目录
BASE_DIR="./packages"
PACKAGES_DIR="$BASE_DIR"  # 所有包都在统一目录
CONFIG_FILE="$BASE_DIR/install-config.conf"
LOG_FILE="/var/log/nvidia-driver-cuda-install.log"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}NVIDIA 驱动 + CUDA 离线安装${NC}"
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
echo -e "${BLUE}[0/8] 检查安装包...${NC}"
if [ ! -d "$BASE_DIR" ]; then
    echo -e "${RED}错误: 找不到安装包目录 '$BASE_DIR'${NC}"
    echo "请确保已解压离线安装包并在正确的目录下运行"
    exit 1
fi

# 读取配置
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    echo -e "${GREEN}✓${NC} 读取配置文件"
    echo "  NVIDIA 驱动版本: $NVIDIA_DRIVER_VERSION"
    echo "  CUDA 版本: $CUDA_VERSION"
else
    echo -e "${YELLOW}警告: 未找到配置文件${NC}"
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

# ========================================
# 安装前检查
# ========================================
echo -e "${BLUE}[1/8] 安装前检查...${NC}"

# 检查是否已安装 NVIDIA 驱动
if command -v nvidia-smi &> /dev/null; then
    EXISTING_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
    echo -e "${YELLOW}⚠${NC} 检测到已安装的 NVIDIA 驱动: $EXISTING_DRIVER"
    echo ""
    read -p "是否继续安装新驱动（将覆盖现有驱动）? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "安装已取消"
        exit 0
    fi
fi

# 检查 nouveau 驱动
if lsmod | grep -q nouveau; then
    echo -e "${YELLOW}⚠${NC} 检测到 nouveau 驱动正在使用"
    echo "禁用 nouveau 驱动..."

    cat > /etc/modprobe.d/blacklist-nouveau.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF

    update-initramfs -u
    echo -e "${YELLOW}警告: 已禁用 nouveau 驱动${NC}"
    echo -e "${YELLOW}请重启系统后重新运行此脚本${NC}"
    echo ""
    echo "重启命令: sudo reboot"
    exit 0
fi

# 检查内核头文件
KERNEL_VERSION=$(uname -r)
HEADERS_DIR="/usr/src/linux-headers-$KERNEL_VERSION"

if [ ! -d "$HEADERS_DIR" ]; then
    echo -e "${RED}⚠ 警告: 未检测到当前内核的头文件${NC}"
    echo ""
    echo "  当前内核版本: $KERNEL_VERSION"
    echo "  需要的头文件: linux-headers-$KERNEL_VERSION"
    echo ""

    # 检查离线包中是否有对应的 linux-headers
    if ls "$PACKAGES_DIR"/linux-headers-${KERNEL_VERSION}*.deb 1> /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} 在离线包中找到对应的内核头文件"
        echo "将在安装依赖时自动安装"
    else
        echo -e "${YELLOW}✗${NC} 离线包中没有对应版本的内核头文件"
        echo ""
        echo -e "${YELLOW}解决方案（选择其一）:${NC}"
        echo ""
        echo "1. 【推荐】如果有网络连接，现在安装:"
        echo -e "   ${CYAN}sudo apt-get install linux-headers-$KERNEL_VERSION${NC}"
        echo ""
        echo "2. 在下载机器上重新下载，指定正确的内核版本:"
        echo "   ./download-with-docker.sh"
        echo "   > 目标机器内核版本: $KERNEL_VERSION"
        echo ""
        echo "3. 继续安装（可能失败）"
        echo "   驱动安装可能因缺少内核头文件而失败"
        echo ""

        read -p "是否现在尝试在线安装 linux-headers? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "尝试在线安装 linux-headers..."
            if apt-get update && apt-get install -y linux-headers-$KERNEL_VERSION; then
                echo -e "${GREEN}✓${NC} 内核头文件安装成功"
            else
                echo -e "${RED}✗${NC} 内核头文件安装失败"
                echo ""
                read -p "是否继续安装驱动（可能失败）? (y/N): " -n 1 -r
                echo ""
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    echo "安装已取消"
                    exit 1
                fi
            fi
        else
            echo ""
            read -p "是否继续安装（可能因缺少头文件而失败）? (y/N): " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "安装已取消"
                echo ""
                echo "请安装 linux-headers 后重新运行此脚本"
                exit 1
            fi
        fi
    fi
    echo ""
else
    echo -e "${GREEN}✓${NC} 检测到内核头文件: $HEADERS_DIR"
fi

echo -e "${GREEN}✓${NC} 安装前检查完成"
echo ""

# ========================================
# 安装 NVIDIA 驱动依赖
# ========================================
echo -e "${CYAN}[2/8] 安装驱动依赖包${NC}"
echo ""

if [ ! -d "$PACKAGES_DIR" ]; then
    echo -e "${RED}错误: 找不到驱动目录 '$PACKAGES_DIR'${NC}"
    exit 1
fi

cd "$PACKAGES_DIR"

if ls *.deb 1> /dev/null 2>&1; then
    echo "安装依赖包..."
    dpkg -i *.deb 2>/dev/null || true
    apt-get install -f -y || {
        echo -e "${YELLOW}警告: 部分依赖安装失败，继续安装驱动${NC}"
    }
    echo -e "${GREEN}✓${NC} 依赖包安装完成"
else
    echo -e "${YELLOW}⚠${NC} 未找到依赖包文件"
fi

cd - > /dev/null
echo ""

# ========================================
# 安装 NVIDIA 驱动
# ========================================
echo -e "${CYAN}[3/8] 安装 NVIDIA 驱动${NC}"
echo ""

cd "$PACKAGES_DIR"

# 查找驱动安装包
DRIVER_INSTALLER=$(ls NVIDIA-Linux-*.run 2>/dev/null | head -1)

if [ -z "$DRIVER_INSTALLER" ]; then
    echo -e "${RED}错误: 找不到 NVIDIA 驱动安装包 (.run 文件)${NC}"
    cd - > /dev/null
    exit 1
fi

echo "找到驱动安装包: $DRIVER_INSTALLER"
echo -e "${YELLOW}开始安装驱动 (这可能需要 5-10 分钟，请耐心等待)...${NC}"
echo ""

# 停止图形界面
echo "停止图形界面服务..."
systemctl stop gdm3 2>/dev/null || true
systemctl stop gdm 2>/dev/null || true
systemctl stop lightdm 2>/dev/null || true
systemctl stop sddm 2>/dev/null || true

# 安装驱动
chmod +x "$DRIVER_INSTALLER"

echo "执行驱动安装..."
./"$DRIVER_INSTALLER" \
    --silent \
    --dkms \
    --no-questions \
    --install-libglvnd || {
    echo -e "${RED}错误: 驱动安装失败${NC}"
    echo "详细日志: /var/log/nvidia-installer.log"
    cd - > /dev/null
    exit 1
}

cd - > /dev/null

# 验证驱动安装
echo ""
if command -v nvidia-smi &> /dev/null; then
    echo -e "${GREEN}✓${NC} NVIDIA 驱动安装成功"
    if nvidia-smi &> /dev/null; then
        INSTALLED_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
        echo "  已安装版本: $INSTALLED_DRIVER"
        echo ""
        echo "GPU 信息:"
        nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader | sed 's/^/  /'
    else
        echo -e "${YELLOW}⚠${NC} nvidia-smi 无法运行，可能需要重启"
    fi
else
    echo -e "${RED}错误: 驱动安装后无法找到 nvidia-smi${NC}"
    exit 1
fi

echo ""

# ========================================
# 安装 CUDA Toolkit
# ========================================
echo -e "${CYAN}[4/8] 安装 CUDA Toolkit${NC}"
echo ""

if [ ! -d "$PACKAGES_DIR" ]; then
    echo -e "${RED}错误: 找不到 CUDA 目录 '$PACKAGES_DIR'${NC}"
    exit 1
fi

cd "$PACKAGES_DIR"

# 检查包数量
CUDA_PKG_COUNT=$(ls -1 *.deb 2>/dev/null | wc -l)
if [ "$CUDA_PKG_COUNT" -eq 0 ]; then
    echo -e "${RED}错误: 找不到 CUDA 安装包${NC}"
    cd - > /dev/null
    exit 1
fi

echo "找到 $CUDA_PKG_COUNT 个 CUDA 安装包"

# 验证包完整性
if [ -f SHA256SUMS ]; then
    echo "验证 CUDA 包完整性..."
    if sha256sum -c SHA256SUMS --quiet 2>/dev/null; then
        echo -e "${GREEN}✓${NC} 包完整性验证通过"
    else
        echo -e "${YELLOW}⚠${NC} 部分包校验失败，但继续安装"
    fi
fi

# 安装 CUDA keyring (如果存在)
if [ -f cuda-keyring_*.deb ]; then
    echo "安装 CUDA keyring..."
    dpkg -i cuda-keyring_*.deb 2>/dev/null || true
fi

if [ -f cuda-archive-keyring.gpg ]; then
    cp cuda-archive-keyring.gpg /usr/share/keyrings/ 2>/dev/null || true
fi

# 安装所有 CUDA 包
echo ""
echo -e "${YELLOW}安装 CUDA 包 (这可能需要 10-20 分钟，请耐心等待)...${NC}"
dpkg -i *.deb 2>/dev/null || true

# 修复依赖
echo "修复依赖关系..."
apt-get install -f -y || {
    echo -e "${YELLOW}⚠${NC} 依赖修复遇到问题，继续...${NC}"
}

cd - > /dev/null

# 配置环境变量
echo ""
echo "配置 CUDA 环境变量..."
cat > /etc/profile.d/cuda.sh <<'EOF'
# CUDA environment variables
export PATH=/usr/local/cuda/bin${PATH:+:${PATH}}
export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
export CUDA_HOME=/usr/local/cuda
EOF

# 使环境变量立即生效
source /etc/profile.d/cuda.sh 2>/dev/null || true

# 验证 CUDA 安装
if [ -d /usr/local/cuda ]; then
    echo -e "${GREEN}✓${NC} CUDA Toolkit 安装成功"
    echo "  安装路径: /usr/local/cuda"

    if [ -f /usr/local/cuda/version.txt ]; then
        CUDA_VER=$(cat /usr/local/cuda/version.txt)
        echo "  CUDA 版本: $CUDA_VER"
    elif [ -f /usr/local/cuda/version.json ]; then
        CUDA_VER=$(grep -oP '"cuda".*?"version".*?"\K[0-9.]+' /usr/local/cuda/version.json 2>/dev/null | head -1)
        echo "  CUDA 版本: $CUDA_VER"
    fi

    if command -v nvcc &> /dev/null; then
        echo -e "${GREEN}✓${NC} nvcc 编译器可用"
        nvcc --version | grep "release" | sed 's/^/  /'
    fi
else
    echo -e "${YELLOW}⚠${NC} CUDA 可能未完全安装到 /usr/local/cuda"
fi

echo ""

# ========================================
# 加载内核模块
# ========================================
echo -e "${BLUE}[5/8] 加载内核模块...${NC}"

echo "加载 NVIDIA 内核模块..."
modprobe nvidia 2>/dev/null || {
    echo -e "${YELLOW}⚠${NC} 无法加载 nvidia 模块，可能需要重启系统"
}
modprobe nvidia-uvm 2>/dev/null || true
modprobe nvidia-modeset 2>/dev/null || true

echo -e "${GREEN}✓${NC} 内核模块加载完成"
echo ""

# ========================================
# 验证安装
# ========================================
echo -e "${BLUE}[6/8] 验证安装...${NC}"

VERIFY_PASSED=0
VERIFY_FAILED=0

# 验证驱动
if nvidia-smi &> /dev/null; then
    echo -e "${GREEN}✓${NC} NVIDIA 驱动验证通过"
    ((VERIFY_PASSED++))
else
    echo -e "${RED}✗${NC} NVIDIA 驱动验证失败"
    ((VERIFY_FAILED++))
fi

# 验证 CUDA
if [ -d /usr/local/cuda ] && command -v nvcc &> /dev/null; then
    echo -e "${GREEN}✓${NC} CUDA Toolkit 验证通过"
    ((VERIFY_PASSED++))
else
    echo -e "${RED}✗${NC} CUDA Toolkit 验证失败"
    ((VERIFY_FAILED++))
fi

# 验证 GPU 可访问性
if nvidia-smi --query-gpu=name --format=csv,noheader &> /dev/null; then
    echo -e "${GREEN}✓${NC} GPU 可访问性验证通过"
    ((VERIFY_PASSED++))
else
    echo -e "${RED}✗${NC} GPU 访问验证失败"
    ((VERIFY_FAILED++))
fi

echo ""

# ========================================
# 生成安装报告
# ========================================
echo -e "${BLUE}[7/8] 生成安装报告...${NC}"

REPORT_FILE="/tmp/nvidia-driver-cuda-install-report.txt"
cat > "$REPORT_FILE" <<EOF
NVIDIA 驱动 + CUDA 安装报告
===========================
安装时间: $(date)

系统信息:
---------
操作系统: $(lsb_release -ds)
内核版本: $(uname -r)
架构: $(uname -m)

安装组件:
---------
EOF

if command -v nvidia-smi &> /dev/null; then
    echo "✓ NVIDIA 驱动" >> "$REPORT_FILE"
    nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1 | xargs echo "  驱动版本:" >> "$REPORT_FILE"
fi

if [ -d /usr/local/cuda ]; then
    echo "✓ CUDA Toolkit" >> "$REPORT_FILE"
    if [ -f /usr/local/cuda/version.txt ]; then
        cat /usr/local/cuda/version.txt | xargs echo "  版本:" >> "$REPORT_FILE"
    fi
fi

echo "" >> "$REPORT_FILE"
echo "GPU 信息:" >> "$REPORT_FILE"
if nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=index,name,driver_version,memory.total --format=csv >> "$REPORT_FILE"
fi

echo -e "${GREEN}✓${NC} 安装报告已生成: $REPORT_FILE"
echo ""

# ========================================
# 完成
# ========================================
echo -e "${BLUE}[8/8] 安装完成${NC}"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}安装成功完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${CYAN}验证结果: ${GREEN}$VERIFY_PASSED${NC} 通过, ${RED}$VERIFY_FAILED${NC} 失败${NC}"
echo ""

if [ $VERIFY_FAILED -gt 0 ]; then
    echo -e "${YELLOW}⚠ 部分组件验证失败${NC}"
    echo -e "${YELLOW}建议重启系统后重新验证${NC}"
    echo ""
fi

echo -e "${YELLOW}重要提示:${NC}"
echo "1. ${YELLOW}强烈建议重启系统${NC}以确保所有更改生效:"
echo "   sudo reboot"
echo ""
echo "2. 重启后验证安装:"
echo "   nvidia-smi              # 查看 GPU 状态"
echo "   nvcc --version          # 查看 CUDA 编译器版本"
echo ""
echo "3. 测试 CUDA 示例 (可选):"
echo "   cd /usr/local/cuda/samples/1_Utilities/deviceQuery"
echo "   sudo make"
echo "   ./deviceQuery"
echo ""
echo "4. 如需安装 NVIDIA Container Toolkit (用于 Docker):"
echo "   请使用 download-packages.sh 和 install-offline.sh"
echo ""

echo -e "${BLUE}日志文件: $LOG_FILE${NC}"
echo -e "${BLUE}安装报告: $REPORT_FILE${NC}"
echo ""

echo "安装完成时间: $(date)"
