# 使用 Docker 下载 NVIDIA 离线安装包

## 为什么使用 Docker？

使用 Docker 下载有以下优势：

1. **环境一致性**：在标准的 Ubuntu 22.04 环境中下载，确保包的兼容性
2. **依赖关系准确**：apt-get 会解析最新的依赖关系
3. **不污染宿主机**：所有操作在容器中进行，不影响你的系统
4. **可重复性**：可以随时删除容器重新开始
5. **验证功能**：可以在容器中验证包的完整性
6. **跨平台**：可以在任何支持 Docker 的系统上运行

## 前置要求

- 已安装 Docker（[安装指南](https://docs.docker.com/engine/install/)）
- Docker 服务正在运行
- 足够的磁盘空间（建议 10GB+）

## 快速开始

### 1. 运行 Docker 下载脚本

```bash
./download-with-docker.sh
```

### 2. 选择下载场景

脚本会提示你选择：

```
1) 仅 Container Toolkit（驱动和 CUDA 已安装）
2) 驱动 + CUDA（新系统安装）
3) 完整安装（所有组件）
```

### 3. 等待下载完成

脚本会：
- 自动构建 Ubuntu 22.04 Docker 镜像
- 在容器中下载所有必要的包
- 将包保存到 `./packages` 目录
- 显示下载统计信息

### 4. 可选：验证包完整性

下载完成后，脚本会询问是否验证包的完整性：

```
是否在 Docker 容器中验证安装包? (y/N):
```

选择 `y` 会在容器中检查所有 .deb 包是否损坏。

## 工作原理

### Docker 镜像

使用 `Dockerfile.download` 构建基础镜像：

- 基于 `ubuntu:22.04`
- 安装必要工具：wget, curl, apt-rdepends 等
- 配置国内镜像源（可选）
- 设置非交互式环境

### 挂载目录

```bash
docker run --rm \
    -v "$(pwd):/workspace" \    # 挂载当前目录到容器
    -w /workspace \              # 设置工作目录
    ...
```

这样：
- 容器内的 `/workspace` 对应宿主机的当前目录
- 下载的包保存在 `/workspace/packages`
- 宿主机上的 `./packages` 目录会包含所有下载的文件

### 环境变量

可以通过环境变量自定义版本：

```bash
docker run --rm \
    -e NVIDIA_DRIVER_VERSION="550.127.05" \
    -e CUDA_VERSION="12.9" \
    -e CUDA_VERSION_FULL="12-9" \
    ...
```

## 手动使用 Docker

如果你想手动控制整个过程：

### 1. 构建镜像

```bash
docker build -t nvidia-offline-downloader:ubuntu22.04 -f Dockerfile.download .
```

### 2. 运行容器进行下载

**下载所有组件**：
```bash
docker run --rm \
    -v "$(pwd):/workspace" \
    -w /workspace \
    nvidia-offline-downloader:ubuntu22.04 \
    bash download-all-packages.sh
```

**仅下载驱动 + CUDA**：
```bash
docker run --rm \
    -v "$(pwd):/workspace" \
    -w /workspace \
    nvidia-offline-downloader:ubuntu22.04 \
    bash download-driver-cuda.sh
```

**仅下载 Container Toolkit**：
```bash
docker run --rm \
    -v "$(pwd):/workspace" \
    -w /workspace \
    nvidia-offline-downloader:ubuntu22.04 \
    bash download-packages.sh
```

### 3. 验证包完整性

```bash
docker run --rm \
    -v "$(pwd)/packages:/packages:ro" \
    nvidia-offline-downloader:ubuntu22.04 \
    bash -c "
        find /packages -name '*.deb' | while read deb; do
            dpkg -I \"\$deb\" > /dev/null 2>&1 || echo \"损坏: \$deb\"
        done
    "
```

## 优势对比

| 特性 | 直接下载 | Docker 下载 |
|------|---------|------------|
| 环境一致性 | ❌ 依赖宿主机环境 | ✅ 标准 Ubuntu 22.04 |
| 依赖准确性 | ⚠️ 可能有差异 | ✅ 使用最新仓库 |
| 系统影响 | ⚠️ 可能修改 apt 源 | ✅ 完全隔离 |
| 可重复性 | ⚠️ 需要手动清理 | ✅ 删除容器即可 |
| 跨平台 | ❌ 限制多 | ✅ 任何系统 |
| 验证功能 | ❌ 需要额外工具 | ✅ 内置验证 |

## 常见问题

### Q1: Docker 镜像构建失败？

检查网络连接，或使用国内镜像源。可以编辑 `Dockerfile.download`：

```dockerfile
# 使用阿里云镜像
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.aliyun.com@g' /etc/apt/sources.list
```

### Q2: 下载速度慢？

这取决于你的网络和 NVIDIA/Ubuntu 仓库的速度。Docker 方案不会更慢，因为：
- 容器使用宿主机网络
- 下载直接保存到宿主机目录
- 没有额外的网络层

### Q3: 容器内的包和直接下载有区别吗？

没有区别。Docker 方案只是提供了一个干净的 Ubuntu 22.04 环境来运行下载脚本，下载的包完全相同。

### Q4: 可以离线使用吗？

不可以。Docker 方案仍然需要网络连接来下载包。它的优势在于：
- 确保在正确的环境中下载
- 验证包的完整性
- 不污染宿主机

### Q5: 下载失败了怎么办？

1. 检查 Docker 日志
2. 重新运行脚本（支持断点续传）
3. 手动进入容器调试：

```bash
docker run --rm -it \
    -v "$(pwd):/workspace" \
    -w /workspace \
    nvidia-offline-downloader:ubuntu22.04 \
    bash
```

## 后续步骤

下载完成后：

1. 将 `packages` 目录复制到目标机器
2. 根据场景选择安装脚本：
   - **场景 A**: `./install-offline.sh`
   - **场景 B**: `./install-driver-cuda.sh`
   - **场景 C**: `./install-all-offline.sh`

## 清理

删除 Docker 镜像：

```bash
docker rmi nvidia-offline-downloader:ubuntu22.04
```

删除下载的包：

```bash
rm -rf ./packages
```
