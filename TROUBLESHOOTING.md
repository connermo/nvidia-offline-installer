# 下载失败问题排查指南

## 概述

本指南帮助你诊断和解决 NVIDIA 离线安装包下载过程中的失败问题。

## 🔧 新增的诊断工具

### 1. 带分析功能的下载脚本

```bash
./download-with-analysis.sh
```

**功能**：
- 运行下载脚本并捕获所有输出
- 自动识别失败的包
- 分类失败包（关键/可选/文档等）
- 生成详细的分析报告

**输出**：
- `download-logs/full_download_YYYYMMDD_HHMMSS.log` - 完整日志
- `download-logs/failed_packages_YYYYMMDD_HHMMSS.txt` - 失败包列表

### 2. 失败包分析工具

```bash
./analyze-failures.sh download-logs/failed_packages_*.txt
```

**功能**：
- 详细分析失败包的重要性
- 区分关键包、可选包、虚拟包
- 提供具体的处理建议

## 📊 常见失败原因及解决方案

### 1. 包不存在 (PACKAGE_NOT_FOUND)

**症状**：
```
E: Unable to locate package xxx
```

**原因**：
- 包名错误或版本不存在
- `apt-rdepends` 返回了虚拟包名
- 包已经被移除或重命名

**判断是否重要**：
```bash
# 检查是否是虚拟包
apt-cache show <package-name>

# 如果返回 "N: Unable to locate package"，可能是虚拟包
```

**解决方案**：

**a) 如果是虚拟包或文档包**：
```bash
# 这些包通常可以忽略
# 示例：
#   - awk (虚拟包，由 gawk 或 mawk 提供)
#   - c-compiler (虚拟包，由 gcc 提供)
#   - xxx-doc (文档包)
```
✅ **可以忽略，继续安装**

**b) 如果是关键包**：
```bash
# 1. 更新包索引
sudo apt-get update

# 2. 搜索替代包
apt-cache search <package-name>

# 3. 检查包是否已更名
apt-cache madison <package-name>
```

### 2. 网络超时 (NETWORK_TIMEOUT)

**症状**：
```
Failed to fetch ...
Timeout was reached
```

**原因**：
- 网络不稳定
- 服务器响应慢
- 防火墙限制

**解决方案**：

```bash
# 1. 增加超时时间（修改脚本中的 --timeout 参数）
# 在下载脚本中找到：
wget --timeout=60 ...
# 改为：
wget --timeout=300 ...

# 2. 使用代理（如果可用）
export http_proxy="http://proxy.example.com:8080"
export https_proxy="http://proxy.example.com:8080"

# 3. 分批下载，降低并发
# 使用 download-with-analysis.sh 会自动重试失败的包
```

### 3. 文件404错误 (FILE_NOT_FOUND_404)

**症状**：
```
404 Not Found
Failed to fetch ...
```

**原因**：
- apt 包索引过期
- 包已经被更新到新版本
- 仓库镜像不同步

**解决方案**：

```bash
# 1. 更新 apt 索引
sudo apt-get update

# 2. 清理 apt 缓存
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update

# 3. 如果使用 Docker，重新构建镜像
docker rmi nvidia-offline-downloader:ubuntu22.04
./download-with-docker.sh
```

### 4. 磁盘空间不足 (DISK_SPACE)

**症状**：
```
No space left on device
```

**原因**：
- 下载目录所在分区空间不足
- 完整的 NVIDIA 环境可能需要 5-10GB

**解决方案**：

```bash
# 1. 检查可用空间
df -h .

# 2. 清理已下载的包（如果需要重新开始）
rm -rf packages/ driver-cuda-packages/

# 3. 更改下载目录到更大的分区
# 编辑下载脚本，修改 BASE_DIR 变量
```

### 5. 权限问题 (PERMISSION_DENIED)

**症状**：
```
Permission denied
```

**解决方案**：

```bash
# 使用 sudo 运行下载脚本
sudo ./download-driver-cuda.sh

# 或者更改目录权限
sudo chown -R $USER:$USER ./packages
```

## 🎯 诊断流程

### 步骤 1: 使用带分析功能的下载

```bash
# 运行带分析的下载脚本
./download-with-analysis.sh

# 选择场景（1/2/3）
# 等待下载完成
# 查看自动生成的分析报告
```

### 步骤 2: 查看详细日志

```bash
# 查看完整日志
cat download-logs/full_download_*.log | less

# 搜索错误
grep -i error download-logs/full_download_*.log
grep -i failed download-logs/full_download_*.log

# 查看失败的包
cat download-logs/failed_packages_*.txt
```

### 步骤 3: 分析失败的包

```bash
# 使用分析工具
./analyze-failures.sh download-logs/failed_packages_*.txt

# 查看分类结果：
#   - 关键包失败 ❌ - 必须解决
#   - 虚拟包失败 ℹ️ - 可以忽略
#   - 可选包失败 📦 - 通常不影响
```

### 步骤 4: 处理失败的包

根据分析结果：

**a) 如果只有虚拟包和可选包失败**：
```bash
# ✅ 可以继续安装
# 失败的包不影响核心功能
```

**b) 如果有关键包失败**：
```bash
# 1. 更新包索引
sudo apt-get update

# 2. 手动下载失败的关键包
cd packages/cuda  # 或其他相应目录
sudo apt-get download <failed-package>

# 3. 验证下载
dpkg -I <failed-package>*.deb
```

## 📋 失败包分类参考

### 关键包（必需）
- `nvidia-driver-*` - NVIDIA 驱动
- `cuda-toolkit-*` - CUDA 工具包
- `cuda-runtime-*` - CUDA 运行时
- `nvidia-container-toolkit` - 容器工具包
- `libnvidia-*` - NVIDIA 库文件

### 可选包（通常不影响）
- `*-doc` - 文档包
- `*-examples` - 示例代码
- `*-dbg` - 调试符号
- `*-dev` - 开发头文件（编译时需要）

### 虚拟包（可以忽略）
- `awk` - 由 gawk/mawk 提供
- `c-compiler` - 由 gcc 提供
- `c-shell` - 由 csh/tcsh 提供
- `linux-headers` - 由具体版本的 headers 包提供

## 🔍 高级诊断

### 检查特定包的依赖

```bash
# 查看包的依赖关系
apt-cache depends <package-name>

# 查看包的反向依赖
apt-cache rdepends <package-name>

# 查看包的详细信息
apt-cache show <package-name>
```

### 验证已下载的包

```bash
# 检查所有 .deb 文件的完整性
find packages -name "*.deb" -exec dpkg -I {} \; > /dev/null 2>&1 || echo "发现损坏的包"

# 列出所有包及其大小
find packages -name "*.deb" -exec du -h {} \; | sort -h
```

### 使用 Docker 进行干净环境测试

```bash
# Docker 方式可以确保在标准 Ubuntu 22.04 环境中下载
./download-with-docker.sh

# 优势：
#   - 环境一致
#   - 依赖准确
#   - 易于重试
```

## 💡 最佳实践

1. **优先使用 Docker 方式下载**
   ```bash
   ./download-with-docker.sh
   ```
   这样可以避免大多数环境相关的问题。

2. **定期更新包索引**
   ```bash
   sudo apt-get update
   ```
   在下载前确保包索引是最新的。

3. **使用带分析的下载脚本**
   ```bash
   ./download-with-analysis.sh
   ```
   自动记录和分析失败原因。

4. **验证关键包**
   确保以下包成功下载：
   - NVIDIA 驱动 .run 文件
   - cuda-toolkit 核心包
   - nvidia-container-toolkit（如果需要）

5. **不要过分担心可选包失败**
   文档包、开发包、调试包的失败通常不影响运行。

## 📞 仍然无法解决？

如果按照以上步骤仍然有问题：

1. **收集信息**：
   ```bash
   # 系统信息
   lsb_release -a
   uname -r

   # 网络信息
   curl -I https://developer.nvidia.com

   # 失败的包列表
   cat download-logs/failed_packages_*.txt
   ```

2. **检查日志**：
   ```bash
   # 提供完整日志
   cat download-logs/full_download_*.log
   ```

3. **在 GitHub 提交 Issue**：
   https://github.com/connermo/nvidia-offline-installer/issues

   包含：
   - 系统版本
   - 使用的脚本
   - 失败包列表
   - 相关日志片段

## 总结

大多数下载失败可以分为以下几类：

| 失败类型 | 严重程度 | 处理方式 |
|---------|---------|---------|
| 虚拟包不存在 | ✅ 低 | 忽略 |
| 文档/开发包 | ✅ 低 | 可选 |
| 网络超时 | ⚠️ 中 | 重试 |
| 关键包404 | ❌ 高 | 更新索引 |
| 关键包不存在 | ❌ 高 | 检查版本 |

使用提供的诊断工具可以快速识别问题类型并采取相应措施。
