#!/bin/bash

##############################################################################
# 清理下载包的 URL 编码文件名
# 将 %XX 格式的编码字符替换为实际字符
##############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PACKAGES_DIR="./packages"

if [ ! -d "$PACKAGES_DIR" ]; then
    echo -e "${RED}错误: 找不到 packages 目录${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}清理 URL 编码的文件名${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

cd "$PACKAGES_DIR"

# 统计包含 % 的文件
ENCODED_COUNT=$(ls -1 | grep "%" 2>/dev/null | wc -l | tr -d ' ')

if [ "$ENCODED_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✓${NC} 没有需要清理的文件名"
    exit 0
fi

echo "发现 $ENCODED_COUNT 个包含 URL 编码的文件"
echo ""

# 显示前 10 个示例
echo "示例文件（前10个）:"
ls -1 | grep "%" | head -10 | while read file; do
    # URL 解码
    decoded=$(echo "$file" | sed 's/%3A/:/g; s/%2B/+/g; s/%2F/\//g; s/%20/ /g; s/%3D/=/g')
    echo "  $file → $decoded"
done
echo ""

# 询问是否继续
read -p "是否重命名这些文件? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

echo ""
echo "重命名文件..."
echo ""

RENAMED=0
FAILED=0

ls -1 | grep "%" 2>/dev/null | while read file; do
    # URL 解码 (处理常见的编码)
    decoded=$(echo "$file" | \
        sed 's/%3A/:/g; s/%2B/+/g; s/%2F/\//g; s/%20/ /g; s/%3D/=/g; \
             s/%21/!/g; s/%23/#/g; s/%24/$/g; s/%25/%/g; s/%26/\&/g; \
             s/%27/'\''/g; s/%28/(/g; s/%29/)/g; s/%2A/*/g; s/%2C/,/g; \
             s/%3B/;/g; s/%3C/</g; s/%3E/>/g; s/%3F/?/g; s/%40/@/g; \
             s/%5B/[/g; s/%5D/]/g; s/%5E/^/g; s/%60/`/g; s/%7B/{/g; \
             s/%7C/|/g; s/%7D/}/g; s/%7E/~/g')

    if [ "$file" != "$decoded" ]; then
        if mv "$file" "$decoded" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $file → $decoded"
            RENAMED=$((RENAMED + 1))
        else
            echo -e "  ${RED}✗${NC} 失败: $file"
            FAILED=$((FAILED + 1))
        fi
    fi
done

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}清理完成${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "重命名: $RENAMED 个文件"
if [ $FAILED -gt 0 ]; then
    echo -e "${YELLOW}失败: $FAILED 个文件${NC}"
fi
echo ""
echo -e "${CYAN}注意:${NC} URL 编码的文件名是正常的，不影响安装"
echo "只有在需要手动查看文件名时才需要清理"
echo ""
