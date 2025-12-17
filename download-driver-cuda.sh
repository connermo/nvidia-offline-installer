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
            # 简单验证：检查文件是否存在且不为空
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
DRIVER_DIR="$BASE_DIR"  # 驱动和依赖下载到 packages/
CUDA_DIR="$BASE_DIR"    # CUDA 也下载到 packages/，实现自动去重

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
mkdir -p "$BASE_DIR"
echo -e "${GREEN}✓${NC} 目录创建完成: $BASE_DIR"
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

# 驱动下载 URL
DRIVER_FILENAME="NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VERSION}.run"
DRIVER_URL="https://download.nvidia.com/XFree86/Linux-x86_64/${NVIDIA_DRIVER_VERSION}/${DRIVER_FILENAME}"
MAX_RETRIES=3

echo "下载驱动安装包: $DRIVER_FILENAME"
echo "下载地址: $DRIVER_URL"
cd "$DRIVER_DIR"

# 检查文件是否已存在且完整
if [ -f "$DRIVER_FILENAME" ]; then
    echo "检测到已存在的驱动文件，验证完整性..."

    # 获取远程文件大小
    REMOTE_SIZE=$(curl -sI "$DRIVER_URL" | grep -i Content-Length | awk '{print $2}' | tr -d '\r')
    LOCAL_SIZE=$(stat -f%z "$DRIVER_FILENAME" 2>/dev/null || stat -c%s "$DRIVER_FILENAME" 2>/dev/null)

    if [ "$REMOTE_SIZE" = "$LOCAL_SIZE" ] && [ ! -z "$REMOTE_SIZE" ]; then
        echo -e "${GREEN}✓${NC} 驱动文件完整，跳过下载"
        echo "  本地大小: $LOCAL_SIZE 字节"
        chmod +x "$DRIVER_FILENAME"
    else
        echo -e "${YELLOW}⚠${NC} 文件不完整或大小不匹配"
        echo "  远程大小: ${REMOTE_SIZE:-未知} 字节"
        echo "  本地大小: $LOCAL_SIZE 字节"
        echo "  将重新下载..."
        rm -f "$DRIVER_FILENAME"
    fi
fi

# 下载文件（如果需要）
if [ ! -f "$DRIVER_FILENAME" ]; then
    echo "开始下载驱动..."
    DOWNLOAD_SUCCESS=false

    for attempt in $(seq 1 $MAX_RETRIES); do
        echo ""
        echo "尝试 $attempt/$MAX_RETRIES..."

        # 使用 wget 下载，支持断点续传
        if wget -c --show-progress --timeout=120 --tries=3 "$DRIVER_URL"; then
            echo ""
            echo -e "${GREEN}✓${NC} 驱动下载成功"

            # 再次验证文件完整性
            REMOTE_SIZE=$(curl -sI "$DRIVER_URL" | grep -i Content-Length | awk '{print $2}' | tr -d '\r')
            LOCAL_SIZE=$(stat -f%z "$DRIVER_FILENAME" 2>/dev/null || stat -c%s "$DRIVER_FILENAME" 2>/dev/null)

            if [ "$REMOTE_SIZE" = "$LOCAL_SIZE" ] && [ ! -z "$REMOTE_SIZE" ]; then
                echo -e "${GREEN}✓${NC} 文件完整性验证通过"
                echo "  文件大小: $LOCAL_SIZE 字节"
                chmod +x "$DRIVER_FILENAME"
                DOWNLOAD_SUCCESS=true
                break
            else
                echo -e "${YELLOW}⚠${NC} 文件大小不匹配，将重试..."
                rm -f "$DRIVER_FILENAME"
            fi
        else
            echo -e "${YELLOW}⚠${NC} 下载失败"
            if [ $attempt -lt $MAX_RETRIES ]; then
                echo "等待 5 秒后重试..."
                sleep 5
            fi
        fi
    done

    # 如果所有重试都失败
    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        echo ""
        echo -e "${RED}错误: 驱动下载失败（已重试 $MAX_RETRIES 次）${NC}"
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
            cd - > /dev/null
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

# 检查目标内核版本
if [ -z "$TARGET_KERNEL_VERSION" ]; then
    echo ""
    echo -e "${YELLOW}注意: 内核头文件版本问题${NC}"
    echo ""
    echo "linux-headers 必须与目标机器的内核版本完全匹配"
    echo "当前环境内核: $(uname -r)"
    echo ""
    read -p "目标机器内核版本（留空跳过 linux-headers）: " TARGET_KERNEL_VERSION
    echo ""
fi

# 基础依赖（不含内核头文件）
DRIVER_DEPS="build-essential dkms pkg-config libglvnd-dev"

# 如果指定了目标内核版本，添加 linux-headers
if [ ! -z "$TARGET_KERNEL_VERSION" ]; then
    echo "将下载内核版本 $TARGET_KERNEL_VERSION 的头文件"
    DRIVER_DEPS="$DRIVER_DEPS linux-headers-$TARGET_KERNEL_VERSION"
else
    echo -e "${YELLOW}跳过 linux-headers 下载${NC}"
    echo "安装时需要在目标机器上运行: sudo apt-get install linux-headers-\$(uname -r)"
fi

download_packages_batch "$DRIVER_DEPS" "驱动基础依赖"

echo ""
echo "下载二级依赖..."
# 下载常见依赖的依赖（排除 linux-headers，因为它有内核版本依赖）
for dep in build-essential dkms pkg-config libglvnd-dev; do
    SUBDEPS=$(apt-cache depends $dep 2>/dev/null | grep "Depends:" | awk '{print $2}' | tr '\n' ' ')
    if [ ! -z "$SUBDEPS" ]; then
        download_packages_batch "$SUBDEPS" "$dep 的依赖"
    fi
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
CUDA_CORE_PACKAGES="cuda-toolkit-${CUDA_VERSION_FULL} cuda-runtime-${CUDA_VERSION_FULL} cuda-drivers"
download_packages_batch "$CUDA_CORE_PACKAGES" "CUDA 核心包"

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
RUN_COUNT=$(ls -1 "$PACKAGES_DIR"/*.run 2>/dev/null | wc -l)
DEB_COUNT=$(ls -1 "$PACKAGES_DIR"/*.deb 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh "$BASE_DIR" | cut -f1)

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}下载完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}下载统计:${NC}"
echo "  .run 文件: $RUN_COUNT 个"
echo "  .deb 包: $DEB_COUNT 个"
echo "  总大小: $TOTAL_SIZE"
echo ""
echo -e "${BLUE}下载位置:${NC}"
echo "  $BASE_DIR/ (所有包统一存放)"
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}后续步骤指引${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${CYAN}步骤 1: 打包压缩${NC}"
echo "在当前机器上执行:"
echo ""
echo -e "  ${GREEN}tar -czf nvidia-driver-cuda-$(date +%Y%m%d).tar.gz packages/ install-driver-cuda.sh${NC}"
echo ""

echo -e "${CYAN}步骤 2: 传输到目标机器${NC}"
echo "使用 SCP 或其他方式传输:"
echo ""
echo -e "  ${GREEN}scp nvidia-driver-cuda-$(date +%Y%m%d).tar.gz user@target-host:/tmp/${NC}"
echo ""

echo -e "${CYAN}步骤 3: 在目标机器上解压并安装${NC}"
echo ""
echo -e "  ${GREEN}cd /tmp${NC}"
echo -e "  ${GREEN}tar -xzf nvidia-driver-cuda-$(date +%Y%m%d).tar.gz${NC}"
echo -e "  ${GREEN}chmod +x install-driver-cuda.sh${NC}"
echo -e "  ${GREEN}sudo ./install-driver-cuda.sh${NC}"
echo ""

echo -e "${CYAN}步骤 4: 重启并验证${NC}"
echo ""
echo -e "  ${GREEN}sudo reboot${NC}"
echo ""
echo "  重启后执行:"
echo -e "  ${GREEN}nvidia-smi${NC}"
echo -e "  ${GREEN}nvcc --version${NC}"
echo ""

echo -e "${BLUE}提示: 驱动和 CUDA 安装后必须重启系统${NC}"
echo ""
