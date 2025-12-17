#!/bin/bash

##############################################################################
# NVIDIA Container Toolkit 安装验证脚本
# 用途: 验证 NVIDIA Container Toolkit 是否正确安装和配置
##############################################################################

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}NVIDIA Container Toolkit 安装验证${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 计数器
PASSED=0
FAILED=0
WARNING=0

# 测试函数
test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

test_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

test_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNING++))
}

echo -e "${BLUE}[1] 检查 NVIDIA 驱动${NC}"
if command -v nvidia-smi &> /dev/null; then
    DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
    test_pass "NVIDIA 驱动已安装 (版本: $DRIVER_VERSION)"

    # 运行 nvidia-smi
    if nvidia-smi &> /dev/null; then
        GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
        test_pass "检测到 $GPU_COUNT 个 GPU"
        nvidia-smi --query-gpu=name --format=csv,noheader | while read gpu; do
            echo "    - $gpu"
        done
    else
        test_fail "nvidia-smi 无法运行"
    fi
else
    test_fail "未找到 NVIDIA 驱动"
fi
echo ""

echo -e "${BLUE}[2] 检查 CUDA${NC}"
if [ -d /usr/local/cuda ]; then
    test_pass "CUDA 已安装"
    if [ -f /usr/local/cuda/version.txt ]; then
        CUDA_VERSION=$(cat /usr/local/cuda/version.txt)
        echo "    版本: $CUDA_VERSION"
    elif command -v nvcc &> /dev/null; then
        CUDA_VERSION=$(nvcc --version | grep "release" | awk '{print $5}' | sed 's/,//')
        echo "    版本: $CUDA_VERSION"
    fi
else
    test_warn "CUDA 未安装 (不是必需的)"
fi
echo ""

echo -e "${BLUE}[3] 检查 Docker${NC}"
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
    test_pass "Docker 已安装 (版本: $DOCKER_VERSION)"

    if docker info &> /dev/null; then
        test_pass "Docker 服务正在运行"
    else
        test_fail "Docker 服务未运行"
    fi
else
    test_fail "未找到 Docker"
fi
echo ""

echo -e "${BLUE}[4] 检查 NVIDIA Container Toolkit${NC}"
if dpkg -l | grep -q nvidia-container-toolkit; then
    TOOLKIT_VERSION=$(dpkg -l | grep nvidia-container-toolkit | head -1 | awk '{print $3}')
    test_pass "nvidia-container-toolkit 已安装 (版本: $TOOLKIT_VERSION)"
else
    test_fail "nvidia-container-toolkit 未安装"
fi

if dpkg -l | grep -q libnvidia-container1; then
    test_pass "libnvidia-container1 已安装"
else
    test_fail "libnvidia-container1 未安装"
fi

if dpkg -l | grep -q libnvidia-container-tools; then
    test_pass "libnvidia-container-tools 已安装"
else
    test_fail "libnvidia-container-tools 未安装"
fi

if command -v nvidia-ctk &> /dev/null; then
    test_pass "nvidia-ctk 命令可用"
else
    test_fail "nvidia-ctk 命令不可用"
fi
echo ""

echo -e "${BLUE}[5] 检查 Docker Runtime 配置${NC}"
if [ -f /etc/docker/daemon.json ]; then
    test_pass "/etc/docker/daemon.json 存在"

    if grep -q "nvidia" /etc/docker/daemon.json; then
        test_pass "Docker daemon.json 包含 NVIDIA runtime 配置"
        echo "    配置内容:"
        cat /etc/docker/daemon.json | grep -A 5 "nvidia" | sed 's/^/    /'
    else
        test_fail "Docker daemon.json 未包含 NVIDIA runtime 配置"
    fi
else
    test_fail "/etc/docker/daemon.json 不存在"
fi

# 检查 docker info
if docker info 2>/dev/null | grep -qi "nvidia"; then
    test_pass "Docker info 显示 NVIDIA runtime"
else
    test_warn "Docker info 未显示 NVIDIA runtime"
fi
echo ""

echo -e "${BLUE}[6] 功能测试${NC}"
echo "测试 1: 运行基础 CUDA 容器"
echo "命令: docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi"
echo ""

if timeout 60s docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi &> /tmp/nvidia-test.log; then
    test_pass "CUDA 容器测试成功"
    echo ""
    echo "容器内 GPU 信息:"
    cat /tmp/nvidia-test.log | tail -20 | sed 's/^/    /'
    rm -f /tmp/nvidia-test.log
else
    if [ ! -f /tmp/nvidia-test.log ]; then
        test_warn "无法运行测试容器 (可能需要先拉取镜像)"
        echo "    请手动运行: docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi"
    else
        test_fail "CUDA 容器测试失败"
        echo "错误信息:"
        cat /tmp/nvidia-test.log | sed 's/^/    /'
        rm -f /tmp/nvidia-test.log
    fi
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}验证结果汇总${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "通过: ${GREEN}$PASSED${NC}"
echo -e "失败: ${RED}$FAILED${NC}"
echo -e "警告: ${YELLOW}$WARNING${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ 所有关键测试通过！NVIDIA Container Toolkit 已正确安装。${NC}"
    echo ""
    echo "你现在可以在 Docker 容器中使用 GPU："
    echo ""
    echo "示例命令:"
    echo "  docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi"
    echo "  docker run --rm --gpus all your-gpu-image:latest"
    echo ""
    exit 0
else
    echo -e "${RED}✗ 发现 $FAILED 个问题，请检查上述失败项。${NC}"
    echo ""
    echo "常见问题排查:"
    echo "1. 确保 NVIDIA 驱动已正确安装: nvidia-smi"
    echo "2. 确保 Docker 服务正在运行: sudo systemctl status docker"
    echo "3. 重新配置 Docker runtime: sudo nvidia-ctk runtime configure --runtime=docker"
    echo "4. 重启 Docker: sudo systemctl restart docker"
    echo ""
    echo "详细文档请参考 README.md"
    exit 1
fi
