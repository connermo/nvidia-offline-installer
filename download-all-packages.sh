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

# 下载辅助函数 - 带重试、多线程和完整性检查
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_retries="${3:-3}"
    local description="${4:-文件}"

    # 检查是否安装了 aria2c（支持多线程下载）
    local use_aria2=false
    if command -v aria2c &> /dev/null; then
        use_aria2=true
        echo "  使用 aria2c 多线程下载 (16线程)"
    fi

    for attempt in $(seq 1 $max_retries); do
        if [ $attempt -gt 1 ]; then
            echo "  重试 $attempt/$max_retries: $description"
        fi

        local download_success=false

        if [ "$use_aria2" = true ]; then
            # 使用 aria2c 多线程下载（16个连接）
            if aria2c \
                --max-connection-per-server=16 \
                --split=16 \
                --min-split-size=1M \
                --continue=true \
                --max-tries=3 \
                --timeout=60 \
                --connect-timeout=30 \
                --summary-interval=0 \
                --console-log-level=warn \
                --dir="$(dirname "$output")" \
                --out="$(basename "$output")" \
                "$url" 2>&1; then
                download_success=true
            fi
        else
            # 使用 wget 下载
            if wget -c -q --show-progress --timeout=60 "$url" -O "$output" 2>&1; then
                download_success=true
            fi
        fi

        if [ "$download_success" = true ]; then
            if [ -f "$output" ] && [ -s "$output" ]; then
                return 0
            fi
        fi

        if [ $attempt -lt $max_retries ]; then
            sleep 2
        fi
    done

    return 1
}

# 并行下载包函数 - 支持并发和重试
download_packages_batch() {
    local package_list="$1"
    local description="$2"
    local max_parallel="${3:-10}"  # 默认10个并发
    local failed_packages=()
    local success_packages=()
    local skipped_packages=()

    echo "并行下载: $description (并发数: $max_parallel)"

    # 创建临时目录存储下载结果
    local temp_dir=$(mktemp -d)

    # 将包列表转换为数组并过滤虚拟包
    local pkg_array=()
    echo "检查包的有效性..."
    for pkg in $package_list; do
        # 使用 apt-cache show 检查包是否真实存在
        if apt-cache show "$pkg" > /dev/null 2>&1; then
            pkg_array+=("$pkg")
        else
            echo -e "  ${YELLOW}跳过虚拟包:${NC} $pkg"
            skipped_packages+=("$pkg")
        fi
    done

    local total=${#pkg_array[@]}
    local current=0

    if [ $total -eq 0 ]; then
        echo -e "${YELLOW}没有需要下载的包${NC}"
        rm -rf "$temp_dir"
        return
    fi

    echo "实际需要下载: $total 个包"
    if [ ${#skipped_packages[@]} -gt 0 ]; then
        echo "跳过虚拟包: ${#skipped_packages[@]} 个"
    fi
    echo ""

    # 并行下载
    for pkg in "${pkg_array[@]}"; do
        # 控制并发数
        while [ $(jobs -r | wc -l) -ge $max_parallel ]; do
            sleep 0.1
        done

        current=$((current + 1))

        # 在后台下载
        (
            if apt-get download "$pkg" > "$temp_dir/${pkg}.log" 2>&1; then
                echo "SUCCESS:$pkg" >> "$temp_dir/results.txt"
                echo -e "  [$current/$total] ${GREEN}✓${NC} $pkg"
            else
                echo "FAILED:$pkg" >> "$temp_dir/results.txt"
                echo -e "  [$current/$total] ${YELLOW}✗${NC} $pkg"
            fi
        ) &
    done

    # 等待所有下载完成
    wait

    echo ""
    echo "第一轮下载完成，检查结果..."

    # 收集失败的包
    if [ -f "$temp_dir/results.txt" ]; then
        while IFS=':' read -r status pkg; do
            if [ "$status" = "FAILED" ]; then
                failed_packages+=("$pkg")
            else
                success_packages+=("$pkg")
            fi
        done < "$temp_dir/results.txt"
    fi

    echo "  成功: ${#success_packages[@]}"
    echo "  失败: ${#failed_packages[@]}"

    # 重试失败的包（串行，更稳定）
    if [ ${#failed_packages[@]} -gt 0 ]; then
        echo ""
        echo "重试失败的包..."
        local retry_success=()

        for pkg in "${failed_packages[@]}"; do
            local retried=false
            for attempt in $(seq 1 2); do
                echo -n "  重试 $pkg (尝试 $attempt/2)... "
                if apt-get download "$pkg" 2>/dev/null 1>&2; then
                    echo -e "${GREEN}✓${NC}"
                    retry_success+=("$pkg")
                    retried=true
                    break
                else
                    echo -e "${YELLOW}失败${NC}"
                fi
                sleep 1
            done

            if [ "$retried" = false ]; then
                echo -e "    ${RED}⚠ $pkg 最终失败${NC}"
            fi
        done

        # 更新失败列表
        if [ ${#retry_success[@]} -gt 0 ]; then
            echo ""
            echo "重试后成功: ${#retry_success[@]} 个"
        fi
    fi

    # 清理临时目录
    rm -rf "$temp_dir"
}

# 配置 - 可根据需要修改
NVIDIA_DRIVER_VERSION="550.127.05"
CUDA_VERSION="12.9"
CUDA_VERSION_FULL="12-9"  # 用于包名
UBUNTU_VERSION="22.04"
UBUNTU_CODENAME="jammy"

# 目录配置 - 统一使用 packages/ 目录，避免重复
BASE_DIR="./packages"
DOWNLOAD_DIR="$BASE_DIR"
DRIVER_DIR="$BASE_DIR"    # 驱动和依赖下载到 packages/
CUDA_DIR="$BASE_DIR"      # CUDA 也下载到 packages/
TOOLKIT_DIR="$BASE_DIR"   # Container Toolkit 也下载到 packages/，实现自动去重
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
mkdir -p "$BASE_DIR"
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

# 检查已存在文件的完整性
if [ -f "$DRIVER_FILENAME" ]; then
    echo "检测到已存在的驱动文件，验证完整性..."
    REMOTE_SIZE=$(curl -sI "$DRIVER_URL" | grep -i Content-Length | awk '{print $2}' | tr -d '\r')
    LOCAL_SIZE=$(stat -f%z "$DRIVER_FILENAME" 2>/dev/null || stat -c%s "$DRIVER_FILENAME" 2>/dev/null)

    if [ "$REMOTE_SIZE" = "$LOCAL_SIZE" ] && [ ! -z "$REMOTE_SIZE" ]; then
        echo -e "${GREEN}✓${NC} 驱动文件完整，跳过下载"
        chmod +x "$DRIVER_FILENAME"
    else
        echo "  文件不完整，将重新下载..."
        rm -f "$DRIVER_FILENAME"
    fi
fi

# 下载驱动文件（支持断点续传和重试）
if [ ! -f "$DRIVER_FILENAME" ]; then
    echo "开始下载驱动 (支持断点续传)..."
    if download_with_retry "$DRIVER_URL" "$DRIVER_FILENAME" 5 "NVIDIA 驱动"; then
        echo -e "${GREEN}✓${NC} 驱动下载成功"
        chmod +x "$DRIVER_FILENAME"

        # 验证下载后的文件完整性
        REMOTE_SIZE=$(curl -sI "$DRIVER_URL" | grep -i Content-Length | awk '{print $2}' | tr -d '\r')
        LOCAL_SIZE=$(stat -f%z "$DRIVER_FILENAME" 2>/dev/null || stat -c%s "$DRIVER_FILENAME" 2>/dev/null)

        if [ "$REMOTE_SIZE" != "$LOCAL_SIZE" ] || [ -z "$REMOTE_SIZE" ]; then
            echo -e "${YELLOW}⚠${NC} 警告: 无法验证文件完整性，但下载已完成"
        fi
    else
        echo ""
        echo -e "${RED}错误: 驱动下载失败 (已尝试 5 次)${NC}"
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
    "cuda-${CUDA_VERSION_FULL}"
)

echo "下载 CUDA 核心包 (${#CUDA_PACKAGES[@]} 个包)..."
download_packages_batch "${CUDA_PACKAGES[@]}"

echo ""
echo "分析并下载 CUDA 依赖关系（使用 apt 模拟安装）..."
echo "说明: 使用 apt-get 模拟安装获取准确的依赖包列表"
echo ""

# 使用 apt-get install --simulate 获取真实依赖列表
# 这比 apt-rdepends 更准确，只返回真实存在的包
TEMP_DEPS=$(mktemp)

for pkg in cuda-toolkit-${CUDA_VERSION_FULL} cuda-runtime-${CUDA_VERSION_FULL}; do
    echo "  分析 $pkg 的依赖..."
    # 使用 --simulate 模拟安装，获取将要安装的包列表
    apt-get install --simulate "$pkg" 2>/dev/null | \
        grep "^Inst " | \
        awk '{print $2}' | \
        sort -u >> "$TEMP_DEPS"
done

# 去重并过滤已经下载的核心包
UNIQUE_DEPS=$(cat "$TEMP_DEPS" | sort -u | \
    grep -v "cuda-toolkit-${CUDA_VERSION_FULL}" | \
    grep -v "cuda-runtime-${CUDA_VERSION_FULL}" | \
    grep -v "cuda-drivers" | \
    grep -v "cuda-cudart-${CUDA_VERSION_FULL}" | \
    grep -v "cuda-libraries-${CUDA_VERSION_FULL}" | \
    grep -v "cuda-nvcc-${CUDA_VERSION_FULL}" | \
    grep -v "cuda-${CUDA_VERSION_FULL}" | \
    tr '\n' ' ')

rm -f "$TEMP_DEPS"

if [ ! -z "$UNIQUE_DEPS" ]; then
    # 转换为数组以计数
    DEP_ARRAY=($UNIQUE_DEPS)
    TOTAL_DEPS=${#DEP_ARRAY[@]}

    echo ""
    echo "发现 $TOTAL_DEPS 个依赖包需要下载"
    echo ""

    # 使用并行下载
    download_packages_batch "$UNIQUE_DEPS" "CUDA 依赖包" 10
else
    echo -e "${YELLOW}⚠${NC} 未找到额外依赖包（可能已经包含在核心包中）"
fi

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
echo "  $BASE_DIR/ (所有包统一存放)"
echo ""
TOTAL_SIZE=$(du -sh "$BASE_DIR" | cut -f1)
echo "  总大小: $TOTAL_SIZE"
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
echo -e "  ${GREEN}tar -czf nvidia-full-${DATE_STAMP}.tar.gz packages/ install-all-offline.sh${NC}"
echo ""

echo -e "${CYAN}步骤 2: 传输到目标机器${NC}"
echo "使用 SCP 或其他方式传输:"
echo ""
echo -e "  ${GREEN}scp nvidia-full-${DATE_STAMP}.tar.gz user@target-host:/tmp/${NC}"
echo ""

echo -e "${CYAN}步骤 3: 在目标机器上解压并安装${NC}"
echo ""
echo -e "  ${GREEN}cd /tmp${NC}"
echo -e "  ${GREEN}tar -xzf nvidia-full-${DATE_STAMP}.tar.gz${NC}"
echo -e "  ${GREEN}chmod +x install-all-offline.sh${NC}"
echo -e "  ${GREEN}sudo ./install-all-offline.sh${NC}"
echo ""

echo -e "${CYAN}步骤 4: 重启并验证${NC}"
echo ""
echo -e "  ${GREEN}sudo reboot${NC}"
echo ""
echo "  重启后执行:"
echo -e "  ${GREEN}nvidia-smi${NC}"
echo -e "  ${GREEN}nvcc --version${NC}"
echo -e "  ${GREEN}docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi${NC}"
echo ""

echo -e "${BLUE}提示: 驱动和 CUDA 安装后必须重启系统${NC}"
echo ""
