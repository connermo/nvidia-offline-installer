#!/bin/bash

##############################################################################
# 快速诊断下载失败原因
# 自动检查日志并分析常见问题
##############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}下载失败快速诊断${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 查找最新的日志文件
LATEST_LOG=""
if [ -d "download-logs" ]; then
    LATEST_LOG=$(ls -t download-logs/*.log 2>/dev/null | head -1)
fi

if [ -z "$LATEST_LOG" ] || [ ! -f "$LATEST_LOG" ]; then
    echo -e "${YELLOW}未找到下载日志文件${NC}"
    echo ""
    echo "请先运行下载脚本:"
    echo "  ./download-with-docker.sh"
    echo "或"
    echo "  ./download-with-analysis.sh"
    echo ""
    exit 1
fi

echo "分析日志: $LATEST_LOG"
echo ""

# 统计失败类型
echo -e "${CYAN}[1/5] 统计失败类型...${NC}"
echo ""

PACKAGE_NOT_FOUND=$(grep -c "Unable to locate package\|E: Package.*has no installation candidate" "$LATEST_LOG" 2>/dev/null || echo "0")
HTTP_404=$(grep -c "404.*Not Found\|Failed to fetch.*404" "$LATEST_LOG" 2>/dev/null || echo "0")
NETWORK_TIMEOUT=$(grep -c "timeout\|timed out\|Connection timed out" "$LATEST_LOG" 2>/dev/null || echo "0")
CONNECTION_FAILED=$(grep -c "Failed to connect\|Could not resolve\|Connection refused" "$LATEST_LOG" 2>/dev/null || echo "0")
TOTAL_FAILED=$(grep -c "失败\|Failed\|✗" "$LATEST_LOG" 2>/dev/null || echo "0")

echo "失败统计:"
echo "  包不存在: $PACKAGE_NOT_FOUND"
echo "  404错误: $HTTP_404"
echo "  网络超时: $NETWORK_TIMEOUT"
echo "  连接失败: $CONNECTION_FAILED"
echo "  总失败提及: $TOTAL_FAILED"
echo ""

# 分析主要问题
echo -e "${CYAN}[2/5] 诊断主要问题...${NC}"
echo ""

MAIN_ISSUE=""
SOLUTION=""

if [ $PACKAGE_NOT_FOUND -gt 20 ]; then
    MAIN_ISSUE="大量包不存在"
    echo -e "${RED}⚠️  主要问题: 包不存在 ($PACKAGE_NOT_FOUND 个)${NC}"
    echo ""
    echo "可能原因:"
    echo "  1. apt-rdepends 返回了虚拟包名"
    echo "  2. 包已经被移除或重命名"
    echo "  3. 依赖关系解析错误"
    echo ""
    SOLUTION="check_virtual_packages"

elif [ $HTTP_404 -gt 10 ]; then
    MAIN_ISSUE="大量404错误"
    echo -e "${RED}⚠️  主要问题: 404错误 ($HTTP_404 个)${NC}"
    echo ""
    echo "可能原因:"
    echo "  1. apt 包索引过期"
    echo "  2. 包已更新到新版本，旧版本被移除"
    echo ""
    SOLUTION="update_apt"

elif [ $NETWORK_TIMEOUT -gt 5 ] || [ $CONNECTION_FAILED -gt 5 ]; then
    MAIN_ISSUE="网络问题"
    echo -e "${RED}⚠️  主要问题: 网络连接问题${NC}"
    echo ""
    echo "可能原因:"
    echo "  1. 网络不稳定"
    echo "  2. 防火墙限制"
    echo "  3. DNS解析问题"
    echo ""
    SOLUTION="check_network"

else
    echo -e "${GREEN}✓${NC} 失败数量在正常范围内"
    echo ""
    echo "说明: 少量失败通常是虚拟包或可选包，不影响使用"
    SOLUTION="analyze_packages"
fi

# 检查关键包
echo -e "${CYAN}[3/5] 检查关键包状态...${NC}"
echo ""

DRIVER_SUCCESS=$(grep -c "nvidia.*driver.*✓\|NVIDIA.*driver.*成功" "$LATEST_LOG" 2>/dev/null || echo "0")
CUDA_SUCCESS=$(grep -c "cuda.*toolkit.*✓\|CUDA.*成功" "$LATEST_LOG" 2>/dev/null || echo "0")

if [ $DRIVER_SUCCESS -gt 0 ]; then
    echo -e "${GREEN}✓${NC} NVIDIA 驱动下载成功"
else
    echo -e "${YELLOW}?${NC} NVIDIA 驱动状态未知"
fi

if [ $CUDA_SUCCESS -gt 0 ]; then
    echo -e "${GREEN}✓${NC} CUDA 工具包下载成功"
else
    echo -e "${YELLOW}?${NC} CUDA 工具包状态未知"
fi

echo ""

# 提取失败包示例
echo -e "${CYAN}[4/5] 失败包示例...${NC}"
echo ""

echo "前10个失败的包:"
grep -E "Unable to locate package|E: Package.*has no installation candidate|404.*Not Found" "$LATEST_LOG" | \
    grep -oE "[a-z0-9][a-z0-9+._-]+" | \
    sort -u | head -10 | while read pkg; do
    if [[ "$pkg" =~ ^(awk|c-compiler|c-shell|x11-common|debconf-2.0)$ ]]; then
        echo -e "  ${GREEN}○${NC} $pkg ${GREEN}(虚拟包)${NC}"
    elif [[ "$pkg" == *"-doc"* ]] || [[ "$pkg" == *"-examples"* ]]; then
        echo -e "  ${CYAN}◇${NC} $pkg ${CYAN}(文档)${NC}"
    elif [[ "$pkg" == *"-dev"* ]]; then
        echo -e "  ${CYAN}◇${NC} $pkg ${CYAN}(开发包)${NC}"
    elif [[ "$pkg" == *"cuda"* ]] || [[ "$pkg" == *"nvidia"* ]]; then
        echo -e "  ${YELLOW}!${NC} $pkg ${YELLOW}(需要检查)${NC}"
    else
        echo -e "  ${NC}·${NC} $pkg"
    fi
done

echo ""

# 建议解决方案
echo -e "${CYAN}[5/5] 建议解决方案...${NC}"
echo ""

case $SOLUTION in
    "update_apt")
        echo -e "${GREEN}推荐方案: 更新 apt 包索引${NC}"
        echo ""
        echo "1. 如果使用 Docker:"
        echo -e "   ${CYAN}# Docker 会自动 apt-get update，重新构建镜像${NC}"
        echo "   docker rmi nvidia-offline-downloader:ubuntu22.04"
        echo "   ./download-with-docker.sh"
        echo ""
        echo "2. 如果直接运行:"
        echo "   sudo apt-get update"
        echo "   sudo ./download-driver-cuda.sh"
        ;;

    "check_virtual_packages")
        echo -e "${GREEN}推荐方案: 分析失败包${NC}"
        echo ""
        echo "很多失败可能是虚拟包或可选包，不影响使用"
        echo ""
        echo "运行详细分析:"
        FAILED_FILE=$(ls -t download-logs/failed_packages_*.txt 2>/dev/null | head -1)
        if [ -n "$FAILED_FILE" ]; then
            echo -e "   ${CYAN}./analyze-failures.sh $FAILED_FILE${NC}"
        else
            echo "   ./analyze-failures.sh download-logs/failed_packages_*.txt"
        fi
        ;;

    "check_network")
        echo -e "${GREEN}推荐方案: 检查网络连接${NC}"
        echo ""
        echo "1. 测试网络连接:"
        echo "   ping -c 3 archive.ubuntu.com"
        echo "   ping -c 3 developer.nvidia.com"
        echo ""
        echo "2. 检查防火墙设置"
        echo ""
        echo "3. 尝试使用 Docker (更稳定):"
        echo "   ./download-with-docker.sh"
        ;;

    "analyze_packages")
        echo -e "${GREEN}推荐方案: 详细分析失败包${NC}"
        echo ""
        FAILED_FILE=$(ls -t download-logs/failed_packages_*.txt 2>/dev/null | head -1)
        if [ -n "$FAILED_FILE" ]; then
            echo "运行详细分析:"
            echo -e "   ${CYAN}./analyze-failures.sh $FAILED_FILE${NC}"
        else
            echo "未找到失败包列表文件"
        fi
        ;;
esac

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}诊断完成${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 询问是否查看完整日志
read -p "是否查看完整日志? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "最后100行日志:"
    echo "----------------------------------------"
    tail -100 "$LATEST_LOG"
fi
