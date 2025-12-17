#!/bin/bash

##############################################################################
# 失败包分析工具
# 功能：
#   - 分析失败包的重要性
#   - 区分关键包和可选包
#   - 提供处理建议
##############################################################################

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 关键包列表（这些包是必需的）
CRITICAL_PACKAGES=(
    "nvidia-driver-"
    "cuda-toolkit"
    "cuda-runtime"
    "cuda-drivers"
    "nvidia-container-toolkit"
    "libnvidia-"
    "nvidia-kernel"
)

# 可选包模式（这些通常不重要）
OPTIONAL_PATTERNS=(
    ".*-doc$"           # 文档包
    ".*-dev$"           # 开发包（某些情况下需要）
    ".*-dbg$"           # 调试符号
    ".*-examples$"      # 示例代码
    "lib.*-perl$"       # Perl 绑定
    "python.*-"         # Python 绑定（取决于需求）
)

# 虚拟包或元包（通常可以忽略）
VIRTUAL_PATTERNS=(
    "^x11-common$"
    "^awk$"
    "^c-compiler$"
    "^c-shell$"
    "^linux-headers$"
)

# 判断包是否关键
is_critical_package() {
    local pkg="$1"
    for pattern in "${CRITICAL_PACKAGES[@]}"; do
        if [[ "$pkg" == *"$pattern"* ]]; then
            return 0
        fi
    done
    return 1
}

# 判断包是否可选
is_optional_package() {
    local pkg="$1"
    for pattern in "${OPTIONAL_PATTERNS[@]}"; do
        if [[ "$pkg" =~ $pattern ]]; then
            return 0
        fi
    done
    return 1
}

# 判断包是否是虚拟包
is_virtual_package() {
    local pkg="$1"
    for pattern in "${VIRTUAL_PATTERNS[@]}"; do
        if [[ "$pkg" =~ $pattern ]]; then
            return 0
        fi
    done
    return 1
}

# 分析失败包
analyze_failed_packages() {
    local failed_file="$1"

    if [ ! -f "$failed_file" ]; then
        echo -e "${RED}错误: 未找到失败包文件: $failed_file${NC}"
        exit 1
    fi

    local critical_failures=()
    local optional_failures=()
    local virtual_failures=()
    local unknown_failures=()

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}失败包分析报告${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    # 读取并分类失败包
    while IFS='|' read -r pkg reason details; do
        if is_critical_package "$pkg"; then
            critical_failures+=("$pkg|$reason")
        elif is_virtual_package "$pkg"; then
            virtual_failures+=("$pkg|$reason")
        elif is_optional_package "$pkg"; then
            optional_failures+=("$pkg|$reason")
        else
            unknown_failures+=("$pkg|$reason")
        fi
    done < "$failed_file"

    # 报告关键包失败
    if [ ${#critical_failures[@]} -gt 0 ]; then
        echo -e "${RED}⚠️  关键包失败 (${#critical_failures[@]} 个) - 需要处理${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        for entry in "${critical_failures[@]}"; do
            IFS='|' read -r pkg reason <<< "$entry"
            echo -e "  ${RED}✗${NC} $pkg"
            echo -e "     原因: $reason"
        done
        echo ""
    fi

    # 报告虚拟包失败
    if [ ${#virtual_failures[@]} -gt 0 ]; then
        echo -e "${YELLOW}ℹ️  虚拟包/元包失败 (${#virtual_failures[@]} 个) - 可以忽略${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        for entry in "${virtual_failures[@]}"; do
            IFS='|' read -r pkg reason <<< "$entry"
            echo -e "  ${YELLOW}○${NC} $pkg (虚拟包)"
        done
        echo ""
    fi

    # 报告可选包失败
    if [ ${#optional_failures[@]} -gt 0 ]; then
        echo -e "${CYAN}📦 可选包失败 (${#optional_failures[@]} 个) - 通常不影响使用${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        for entry in "${optional_failures[@]}"; do
            IFS='|' read -r pkg reason <<< "$entry"
            echo -e "  ${CYAN}◇${NC} $pkg"
            if [[ "$pkg" == *"-doc" ]]; then
                echo -e "     (文档包 - 不影响功能)"
            elif [[ "$pkg" == *"-dev" ]]; then
                echo -e "     (开发包 - 编译时需要)"
            elif [[ "$pkg" == *"-dbg" ]]; then
                echo -e "     (调试包 - 调试时需要)"
            fi
        done
        echo ""
    fi

    # 报告未知类别失败
    if [ ${#unknown_failures[@]} -gt 0 ]; then
        echo -e "${YELLOW}❓ 其他失败包 (${#unknown_failures[@]} 个) - 需要评估${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        for entry in "${unknown_failures[@]}"; do
            IFS='|' read -r pkg reason <<< "$entry"
            echo -e "  ${YELLOW}?${NC} $pkg"
            echo -e "     原因: $reason"
        done
        echo ""
    fi

    # 总结和建议
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}总结与建议${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    local total_failed=$((${#critical_failures[@]} + ${#optional_failures[@]} + ${#virtual_failures[@]} + ${#unknown_failures[@]}))
    echo "总失败包数: $total_failed"
    echo "  - 关键包: ${#critical_failures[@]}"
    echo "  - 虚拟包: ${#virtual_failures[@]}"
    echo "  - 可选包: ${#optional_failures[@]}"
    echo "  - 未知包: ${#unknown_failures[@]}"
    echo ""

    if [ ${#critical_failures[@]} -gt 0 ]; then
        echo -e "${RED}⚠️  警告: 发现关键包下载失败！${NC}"
        echo ""
        echo "建议操作:"
        echo "  1. 检查网络连接"
        echo "  2. 运行 'sudo apt-get update' 更新包索引"
        echo "  3. 尝试手动下载失败的关键包:"
        for entry in "${critical_failures[@]}"; do
            IFS='|' read -r pkg reason <<< "$entry"
            echo "     sudo apt-get download $pkg"
        done
        echo ""
        echo -e "${RED}注意: 关键包缺失可能导致安装失败！${NC}"
        echo ""
        return 1
    elif [ ${#unknown_failures[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚠️  有一些未分类的失败包${NC}"
        echo ""
        echo "建议:"
        echo "  1. 虚拟包和可选包的失败通常可以忽略"
        echo "  2. 如果是依赖包，检查是否已经包含在下载的包中"
        echo "  3. 可以先尝试安装，如果缺少依赖会有提示"
        echo ""
        return 0
    else
        echo -e "${GREEN}✓ 所有失败的包都是非关键包${NC}"
        echo ""
        echo "说明:"
        echo "  - 虚拟包: 通常是元包或别名，可以忽略"
        echo "  - 可选包: 文档、开发头文件等，不影响运行时"
        echo ""
        echo -e "${GREEN}可以继续进行离线安装！${NC}"
        echo ""
        return 0
    fi
}

# 主函数
main() {
    if [ $# -eq 0 ]; then
        echo "用法: $0 <失败包文件路径>"
        echo ""
        echo "示例:"
        echo "  $0 download-logs/failed_packages_20250617_120000.txt"
        echo ""
        echo "或使用最新的失败包文件:"
        if [ -d "download-logs" ]; then
            latest=$(ls -t download-logs/failed_packages_*.txt 2>/dev/null | head -1)
            if [ -n "$latest" ]; then
                echo "  $0 $latest"
            fi
        fi
        exit 1
    fi

    analyze_failed_packages "$1"
}

main "$@"
