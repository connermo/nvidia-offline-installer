#!/bin/bash

##############################################################################
# 增强版下载脚本 - 带详细日志和错误分析
# 功能：
#   - 详细记录每个包的下载状态
#   - 分析失败原因
#   - 生成失败包报告
#   - 区分关键包和可选包
##############################################################################

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志文件
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="./download-logs"
LOG_FILE="$LOG_DIR/download_${TIMESTAMP}.log"
ERROR_LOG="$LOG_DIR/errors_${TIMESTAMP}.log"
SUCCESS_LOG="$LOG_DIR/success_${TIMESTAMP}.log"
FAILED_PACKAGES="$LOG_DIR/failed_packages_${TIMESTAMP}.txt"

mkdir -p "$LOG_DIR"

# 统计变量
TOTAL_PACKAGES=0
SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# 失败包分类
declare -A FAILURE_REASONS

# 日志函数
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE" "$ERROR_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE" "$SUCCESS_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# 检查包是否存在于仓库
check_package_exists() {
    local pkg="$1"
    apt-cache show "$pkg" > /dev/null 2>&1
    return $?
}

# 获取失败原因
get_failure_reason() {
    local pkg="$1"
    local error_output="$2"

    if echo "$error_output" | grep -qi "unable to locate package"; then
        echo "PACKAGE_NOT_FOUND"
    elif echo "$error_output" | grep -qi "404.*not found"; then
        echo "FILE_NOT_FOUND_404"
    elif echo "$error_output" | grep -qi "timeout\|timed out"; then
        echo "NETWORK_TIMEOUT"
    elif echo "$error_output" | grep -qi "connection.*failed\|couldn't connect"; then
        echo "CONNECTION_FAILED"
    elif echo "$error_output" | grep -qi "no space left"; then
        echo "DISK_SPACE"
    elif echo "$error_output" | grep -qi "permission denied"; then
        echo "PERMISSION_DENIED"
    else
        echo "UNKNOWN"
    fi
}

# 增强的包下载函数
download_package_with_analysis() {
    local pkg="$1"
    local max_retries=3
    local retry_delay=2

    TOTAL_PACKAGES=$((TOTAL_PACKAGES + 1))

    echo -n "  [$TOTAL_PACKAGES] 下载 $pkg... "

    # 检查包是否存在
    if ! check_package_exists "$pkg"; then
        echo -e "${RED}✗${NC} (包不存在)"
        log_error "Package not found in repository: $pkg"
        echo "$pkg|PACKAGE_NOT_FOUND|包在仓库中不存在" >> "$FAILED_PACKAGES"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILURE_REASONS["PACKAGE_NOT_FOUND"]=$((${FAILURE_REASONS["PACKAGE_NOT_FOUND"]:-0} + 1))
        return 1
    fi

    # 检查是否已下载
    local pkg_file=$(apt-cache show "$pkg" 2>/dev/null | grep "^Filename:" | head -1 | awk '{print $2}' | xargs basename)
    if [ -n "$pkg_file" ] && [ -f "$pkg_file" ]; then
        # 验证文件完整性
        if dpkg -I "$pkg_file" > /dev/null 2>&1; then
            echo -e "${BLUE}↷${NC} (已存在)"
            log "Package already downloaded and valid: $pkg"
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            return 0
        else
            echo -e "${YELLOW}!${NC} (已存在但损坏，重新下载)"
            rm -f "$pkg_file"
        fi
    fi

    # 尝试下载
    local error_output=""
    for attempt in $(seq 1 $max_retries); do
        if [ $attempt -gt 1 ]; then
            echo -n "重试 $attempt/$max_retries... "
        fi

        error_output=$(apt-get download "$pkg" 2>&1)
        local exit_code=$?

        if [ $exit_code -eq 0 ]; then
            # 验证下载的文件
            pkg_file=$(apt-cache show "$pkg" 2>/dev/null | grep "^Filename:" | head -1 | awk '{print $2}' | xargs basename)
            if [ -n "$pkg_file" ] && [ -f "$pkg_file" ]; then
                if dpkg -I "$pkg_file" > /dev/null 2>&1; then
                    echo -e "${GREEN}✓${NC}"
                    log_success "Downloaded: $pkg"
                    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                    return 0
                else
                    echo -e "${RED}✗${NC} (文件损坏)"
                    rm -f "$pkg_file"
                fi
            fi
        fi

        if [ $attempt -lt $max_retries ]; then
            sleep $retry_delay
            retry_delay=$((retry_delay * 2))  # 指数退避
        fi
    done

    # 所有重试失败
    local reason=$(get_failure_reason "$pkg" "$error_output")
    echo -e "${RED}✗${NC} ($reason)"
    log_error "Failed to download: $pkg (Reason: $reason)"
    echo "$pkg|$reason|$error_output" >> "$FAILED_PACKAGES"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    FAILURE_REASONS["$reason"]=$((${FAILURE_REASONS["$reason"]:-0} + 1))

    return 1
}

# 批量下载函数
download_packages_batch_with_logging() {
    local package_list="$1"
    local description="$2"

    log ""
    log "========================================"
    log "批量下载: $description"
    log "========================================"

    local pkg_array=($package_list)
    local batch_total=${#pkg_array[@]}
    log "包总数: $batch_total"
    log ""

    for pkg in $package_list; do
        download_package_with_analysis "$pkg" || true
    done

    log ""
}

# 生成下载报告
generate_report() {
    log ""
    log "========================================"
    log "下载完成 - 统计报告"
    log "========================================"
    log "总包数: $TOTAL_PACKAGES"
    log "成功: $SUCCESS_COUNT (${GREEN}✓${NC})"
    log "跳过（已存在）: $SKIPPED_COUNT (${BLUE}↷${NC})"
    log "失败: $FAILED_COUNT (${RED}✗${NC})"

    if [ $FAILED_COUNT -gt 0 ]; then
        log ""
        log "失败原因统计:"
        for reason in "${!FAILURE_REASONS[@]}"; do
            local count=${FAILURE_REASONS[$reason]}
            case $reason in
                "PACKAGE_NOT_FOUND")
                    log "  - 包不存在: $count"
                    ;;
                "FILE_NOT_FOUND_404")
                    log "  - 文件未找到(404): $count"
                    ;;
                "NETWORK_TIMEOUT")
                    log "  - 网络超时: $count"
                    ;;
                "CONNECTION_FAILED")
                    log "  - 连接失败: $count"
                    ;;
                "DISK_SPACE")
                    log "  - 磁盘空间不足: $count"
                    ;;
                "UNKNOWN")
                    log "  - 未知原因: $count"
                    ;;
                *)
                    log "  - $reason: $count"
                    ;;
            esac
        done

        log ""
        log_warning "失败包列表已保存到: $FAILED_PACKAGES"
        log ""
        log "建议操作:"

        if [ ${FAILURE_REASONS["PACKAGE_NOT_FOUND"]:-0} -gt 0 ]; then
            log "  1. 包不存在: 这些包可能是虚拟包或已废弃，通常可以忽略"
        fi

        if [ ${FAILURE_REASONS["NETWORK_TIMEOUT"]:-0} -gt 0 ] || [ ${FAILURE_REASONS["CONNECTION_FAILED"]:-0} -gt 0 ]; then
            log "  2. 网络问题: 检查网络连接，稍后重新运行脚本"
        fi

        if [ ${FAILURE_REASONS["FILE_NOT_FOUND_404"]:-0} -gt 0 ]; then
            log "  3. 文件404: 运行 'apt-get update' 更新包索引"
        fi
    else
        log ""
        log_success "所有包下载成功！"
    fi

    log ""
    log "详细日志: $LOG_FILE"
    log "错误日志: $ERROR_LOG"
    log "成功日志: $SUCCESS_LOG"
}

# 主函数
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}增强版包下载工具（带日志分析）${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    log "下载开始时间: $(date)"
    log "日志目录: $LOG_DIR"
    log ""

    # 这里可以调用原有的下载逻辑
    # 例如导出函数供其他脚本使用

    echo "此脚本提供增强的下载函数，可被其他脚本调用"
    echo ""
    echo "可用函数:"
    echo "  - download_package_with_analysis <package_name>"
    echo "  - download_packages_batch_with_logging <package_list> <description>"
    echo "  - generate_report"
    echo ""
    echo "使用方法: 在其他脚本中 source 此文件"
    echo "  source download-with-logging.sh"
}

# 如果直接运行，显示帮助
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main
fi

# 导出函数供其他脚本使用
export -f log log_error log_success log_warning
export -f check_package_exists get_failure_reason
export -f download_package_with_analysis
export -f download_packages_batch_with_logging
export -f generate_report
