#!/bin/bash

##############################################################################
# NVIDIA 完整环境离线安装 - 快速开始脚本
# 用途: 自动化整个流程 - 从下载到打包
# 包含: NVIDIA 驱动 + CUDA Toolkit + Container Toolkit
##############################################################################

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}NVIDIA 完整环境离线安装${NC}"
echo -e "${GREEN}快速开始向导${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${CYAN}支持组件: 驱动 + CUDA + Container Toolkit${NC}"
echo ""

# 检查网络连接
echo -e "${BLUE}检查网络连接...${NC}"
if ! ping -c 1 google.com &> /dev/null && ! ping -c 1 baidu.com &> /dev/null; then
    echo -e "${RED}错误: 无法连接到互联网${NC}"
    echo "此脚本需要在联网环境下运行以下载安装包"
    echo ""
    echo "如果你已经下载了安装包,请直接运行:"
    echo "  sudo ./install-all-offline.sh"
    exit 1
fi
echo -e "${GREEN}✓${NC} 网络连接正常"
echo ""

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 需要 root 权限${NC}"
    echo "请使用: sudo $0"
    exit 1
fi

# 显示当前系统信息
echo -e "${BLUE}当前系统信息:${NC}"
echo "  操作系统: $(lsb_release -ds)"
echo "  内核版本: $(uname -r)"
echo "  架构: $(uname -m)"
echo ""

# 检查是否为 Ubuntu 22.04
if ! grep -q "22.04" /etc/os-release; then
    echo -e "${YELLOW}警告: 检测到非 Ubuntu 22.04 系统${NC}"
    echo "此工具专为 Ubuntu 22.04 设计,其他版本可能无法正常工作"
    echo ""
    read -p "是否继续? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}操作模式选择${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "1) 下载安装包 (在联网机器上运行)"
echo "2) 离线安装 (在目标服务器上运行)"
echo "3) 一键安装 (在联网的目标服务器上运行)"
echo "4) 退出"
echo ""
read -p "请选择 [1-4]: " -n 1 -r
echo
echo ""

case $REPLY in
    1)
        echo -e "${GREEN}==> 模式 1: 下载安装包${NC}"
        echo ""

        if [ ! -f "download-packages.sh" ]; then
            echo -e "${RED}错误: 找不到 download-packages.sh${NC}"
            exit 1
        fi

        # 运行下载脚本
        bash download-packages.sh

        if [ $? -eq 0 ]; then
            echo ""
            echo -e "${GREEN}下载成功!${NC}"
            echo ""
            echo -e "${YELLOW}下一步: 打包并传输到目标服务器${NC}"
            echo ""
            echo "运行以下命令打包:"
            echo -e "${BLUE}tar -czf nvidia-container-toolkit-offline.tar.gz packages/ install-offline.sh README.md${NC}"
            echo ""
            echo "然后将压缩包传输到目标离线服务器"
        else
            echo -e "${RED}下载失败,请检查错误信息${NC}"
            exit 1
        fi
        ;;

    2)
        echo -e "${GREEN}==> 模式 2: 离线安装${NC}"
        echo ""

        if [ ! -f "install-offline.sh" ]; then
            echo -e "${RED}错误: 找不到 install-offline.sh${NC}"
            exit 1
        fi

        if [ ! -d "packages" ]; then
            echo -e "${RED}错误: 找不到 packages 目录${NC}"
            echo "请确保已解压离线安装包"
            exit 1
        fi

        # 运行安装脚本
        bash install-offline.sh
        ;;

    3)
        echo -e "${GREEN}==> 模式 3: 一键安装 (联网)${NC}"
        echo ""
        echo -e "${YELLOW}此模式将:${NC}"
        echo "  1. 下载所有必要的安装包"
        echo "  2. 立即在当前机器上安装"
        echo ""
        read -p "确认继续? (y/N): " -n 1 -r
        echo

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi

        # 下载
        if [ -f "download-packages.sh" ]; then
            echo ""
            echo -e "${BLUE}步骤 1/2: 下载安装包...${NC}"
            bash download-packages.sh

            if [ $? -ne 0 ]; then
                echo -e "${RED}下载失败${NC}"
                exit 1
            fi
        else
            echo -e "${RED}错误: 找不到 download-packages.sh${NC}"
            exit 1
        fi

        # 安装
        if [ -f "install-offline.sh" ]; then
            echo ""
            echo -e "${BLUE}步骤 2/2: 安装...${NC}"
            sleep 2
            bash install-offline.sh
        else
            echo -e "${RED}错误: 找不到 install-offline.sh${NC}"
            exit 1
        fi
        ;;

    4)
        echo "退出"
        exit 0
        ;;

    *)
        echo -e "${RED}无效的选择${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}操作完成!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
