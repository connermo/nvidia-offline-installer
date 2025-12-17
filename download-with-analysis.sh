#!/bin/bash

##############################################################################
# 带分析功能的下载脚本包装器
# 功能：
#   - 运行下载脚本并捕获详细输出
#   - 自动分析失败的包
#   - 生成完整报告
##############################################################################

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="./download-logs"
FULL_LOG="$LOG_DIR/full_download_${TIMESTAMP}.log"

mkdir -p "$LOG_DIR"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}带日志分析的 NVIDIA 包下载${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 选择下载脚本
echo -e "${YELLOW}请选择下载场景:${NC}"
echo "1) 仅 Container Toolkit"
echo "2) 驱动 + CUDA"
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

if [ ! -f "$DOWNLOAD_SCRIPT" ]; then
    echo -e "${RED}错误: 未找到下载脚本 $DOWNLOAD_SCRIPT${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}开始下载...${NC}"
echo "完整日志将保存到: $FULL_LOG"
echo ""

# 运行下载脚本并记录输出
chmod +x "$DOWNLOAD_SCRIPT"
if sudo bash "$DOWNLOAD_SCRIPT" 2>&1 | tee "$FULL_LOG"; then
    DOWNLOAD_EXIT=0
else
    DOWNLOAD_EXIT=$?
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}分析下载结果...${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 从日志中提取失败信息
FAILED_PACKAGES_FILE="$LOG_DIR/failed_packages_${TIMESTAMP}.txt"

# 分析apt-get download失败的包
grep -E "(失败|Failed|Unable to locate|404.*Not Found)" "$FULL_LOG" | \
    grep -oE "[a-z0-9][a-z0-9+.-]+" | \
    sort -u > "$FAILED_PACKAGES_FILE" 2>/dev/null || true

# 统计下载结果
TOTAL_LINES=$(wc -l < "$FULL_LOG")
SUCCESS_COUNT=$(grep -c "✓" "$FULL_LOG" 2>/dev/null || echo "0")
FAILED_COUNT=$(grep -c "失败\|Failed" "$FULL_LOG" 2>/dev/null || echo "0")

echo "下载统计:"
echo "  总日志行数: $TOTAL_LINES"
echo "  成功标记: $SUCCESS_COUNT"
echo "  失败标记: $FAILED_COUNT"
echo ""

# 检查是否有失败的包
if [ -s "$FAILED_PACKAGES_FILE" ]; then
    FAILED_PKG_COUNT=$(wc -l < "$FAILED_PACKAGES_FILE")
    echo -e "${YELLOW}发现 $FAILED_PKG_COUNT 个失败的包${NC}"
    echo ""

    # 分类失败的包
    echo "失败包列表（前20个）:"
    head -20 "$FAILED_PACKAGES_FILE" | while read pkg; do
        # 尝试判断包的类型
        if [[ "$pkg" == *"-doc" ]] || [[ "$pkg" == *"-examples" ]]; then
            echo -e "  ${CYAN}◇${NC} $pkg (文档/示例 - 可选)"
        elif [[ "$pkg" == *"-dev" ]]; then
            echo -e "  ${CYAN}◇${NC} $pkg (开发包 - 编译时需要)"
        elif [[ "$pkg" == *"cuda"* ]] || [[ "$pkg" == *"nvidia"* ]]; then
            echo -e "  ${RED}✗${NC} $pkg (关键包)"
        else
            echo -e "  ${YELLOW}?${NC} $pkg"
        fi
    done

    if [ $FAILED_PKG_COUNT -gt 20 ]; then
        echo "  ... 还有 $((FAILED_PKG_COUNT - 20)) 个"
    fi
    echo ""

    # 提供建议
    echo -e "${YELLOW}建议操作:${NC}"
    echo ""

    # 检查是否有关键包失败
    CRITICAL_FAILED=$(grep -E "(cuda|nvidia|container-toolkit)" "$FAILED_PACKAGES_FILE" 2>/dev/null | wc -l)

    if [ $CRITICAL_FAILED -gt 0 ]; then
        echo -e "${RED}⚠️  检测到 $CRITICAL_FAILED 个关键包下载失败！${NC}"
        echo ""
        echo "1. 更新 apt 包索引:"
        echo "   sudo apt-get update"
        echo ""
        echo "2. 检查网络连接，然后重新运行下载脚本"
        echo ""
        echo "3. 手动下载失败的关键包:"
        grep -E "(cuda|nvidia|container-toolkit)" "$FAILED_PACKAGES_FILE" | head -5 | while read pkg; do
            echo "   sudo apt-get download $pkg"
        done
        echo ""
        echo -e "${RED}注意: 关键包缺失可能导致离线安装失败！${NC}"
    else
        echo -e "${GREEN}✓ 没有检测到关键包失败${NC}"
        echo ""
        echo "失败的包大多是可选包（文档、开发包等），不影响核心功能"
        echo "如果需要这些包，可以:"
        echo "  1. 运行 'sudo apt-get update' 更新包索引"
        echo "  2. 重新运行下载脚本"
        echo ""
        echo -e "${GREEN}可以继续进行离线安装！${NC}"
    fi
else
    echo -e "${GREEN}✓ 未检测到失败的包${NC}"
    echo -e "${GREEN}所有包下载成功！${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}日志文件${NC}"
echo -e "${BLUE}========================================${NC}"
echo "完整日志: $FULL_LOG"
echo "失败包列表: $FAILED_PACKAGES_FILE"
echo ""

# 检查下载的包
echo -e "${BLUE}检查下载的文件...${NC}"
if [ -d "packages" ] || [ -d "driver-cuda-packages" ]; then
    for dir in packages driver-cuda-packages; do
        if [ -d "$dir" ]; then
            echo ""
            echo "目录: $dir"
            DEB_COUNT=$(find "$dir" -name "*.deb" 2>/dev/null | wc -l)
            RUN_COUNT=$(find "$dir" -name "*.run" 2>/dev/null | wc -l)
            TOTAL_SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)

            echo "  .deb 文件: $DEB_COUNT"
            echo "  .run 文件: $RUN_COUNT"
            echo "  总大小: $TOTAL_SIZE"
        fi
    done
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}下载完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if [ $DOWNLOAD_EXIT -ne 0 ]; then
    echo -e "${YELLOW}注意: 下载脚本返回了非零退出码 ($DOWNLOAD_EXIT)${NC}"
    echo "请检查上面的日志和分析结果"
    echo ""
fi

echo "后续步骤:"
echo "1. 查看详细日志: cat $FULL_LOG"
echo "2. 如有失败，查看: cat $FAILED_PACKAGES_FILE"
echo "3. 将 packages 目录复制到目标机器进行离线安装"
echo ""
