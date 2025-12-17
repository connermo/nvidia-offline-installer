# NVIDIA GPU 环境离线安装工具集

适用于 Ubuntu 22.04 的 NVIDIA 完整 GPU 环境离线安装自动化工具。

## 📦 支持的安装方案

本工具集提供三种灵活的安装方案：

### 方案 A: 仅安装 Container Toolkit ⭐
**适用场景**: 驱动和 CUDA 已安装，只需要 Docker GPU 支持

- 下载脚本: `download-packages.sh`
- 安装脚本: `install-offline.sh`
- 包含: NVIDIA Container Toolkit

### 方案 B: 安装驱动 + CUDA ⭐⭐
**适用场景**: 全新系统，需要完整的 NVIDIA 开发环境

- 下载脚本: `download-driver-cuda.sh`
- 安装脚本: `install-driver-cuda.sh`
- 包含: NVIDIA 驱动 550.127.05 + CUDA 12.9

### 方案 C: 完整安装 ⭐⭐⭐
**适用场景**: 一次性安装所有组件

- 下载脚本: `download-all-packages.sh`
- 安装脚本: `install-all-offline.sh`
- 包含: NVIDIA 驱动 + CUDA + Container Toolkit

## 系统要求

- **操作系统**: Ubuntu 22.04 LTS (Jammy)
- **架构**: x86_64 / amd64
- **下载机器**: 需要互联网连接
- **目标机器**: 可以完全离线

## 快速开始

### 方式 1: 使用 Docker 下载 (推荐) 🐳

使用 Docker 在标准 Ubuntu 22.04 环境中下载，确保包的兼容性和完整性：

```bash
chmod +x download-with-docker.sh
./download-with-docker.sh
```

**优势**：
- ✅ 环境一致性：标准 Ubuntu 22.04 环境
- ✅ 依赖准确：使用最新的 apt 仓库
- ✅ 不污染宿主机：完全隔离
- ✅ 内置验证：自动检查包完整性

详细说明请查看 [DOCKER-USAGE.md](./DOCKER-USAGE.md)

### 方式 2: 使用交互式向导

```bash
sudo ./quick-start.sh
```

向导会引导你选择合适的安装方案。

---

## 方案 A: 仅安装 Container Toolkit

### 前置条件
- ✅ NVIDIA 驱动已安装
- ✅ CUDA 已安装 (可选但推荐)
- ✅ Docker 已安装并运行

### 步骤 1: 下载安装包 (联网机器)

```bash
chmod +x download-packages.sh
sudo ./download-packages.sh
```

### 步骤 2: 打包传输

```bash
tar -czf nvidia-container-toolkit-offline.tar.gz packages/ install-offline.sh
# 传输到目标服务器
```

### 步骤 3: 离线安装 (目标服务器)

```bash
tar -xzf nvidia-container-toolkit-offline.tar.gz
chmod +x install-offline.sh
sudo ./install-offline.sh
```

### 步骤 4: 验证

```bash
docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi
```

**预计下载大小**: ~50-100 MB

---

## 方案 B: 安装驱动 + CUDA

### 前置条件
- ✅ 全新的 Ubuntu 22.04 系统
- ❌ 不需要预先安装任何 NVIDIA 组件

### 步骤 1: 下载安装包 (联网机器)

```bash
chmod +x download-driver-cuda.sh
sudo ./download-driver-cuda.sh
```

下载包含:
- NVIDIA 驱动 550.127.05 (Production Branch)
- CUDA Toolkit 12.9
- 所有依赖包

### 步骤 2: 打包传输

```bash
tar -czf nvidia-driver-cuda-offline.tar.gz driver-cuda-packages/ install-driver-cuda.sh
# 传输到目标服务器
```

### 步骤 3: 离线安装 (目标服务器)

```bash
tar -xzf nvidia-driver-cuda-offline.tar.gz
chmod +x install-driver-cuda.sh
sudo ./install-driver-cuda.sh
```

安装过程:
1. 禁用 nouveau 驱动 (如果存在)
2. 安装 NVIDIA 驱动
3. 安装 CUDA Toolkit
4. 配置环境变量

### 步骤 4: 重启并验证

```bash
sudo reboot

# 重启后
nvidia-smi
nvcc --version
```

**预计下载大小**: ~3-5 GB
**安装时间**: 15-30 分钟
**⚠️ 重要**: 安装完成后必须重启系统

---

## 方案 C: 完整安装

### 前置条件
- ✅ 全新的 Ubuntu 22.04 系统
- ✅ Docker 已安装 (或可离线安装)

### 步骤 1: 下载所有组件 (联网机器)

```bash
chmod +x download-all-packages.sh
sudo ./download-all-packages.sh
```

### 步骤 2: 打包传输

```bash
tar -czf nvidia-full-offline.tar.gz packages/ install-all-offline.sh
# 传输到目标服务器
```

### 步骤 3: 离线安装 (目标服务器)

```bash
tar -xzf nvidia-full-offline.tar.gz
chmod +x install-all-offline.sh
sudo ./install-all-offline.sh
```

安装脚本会提供交互选项:
1. 完整安装 (推荐)
2. 仅安装驱动
3. 仅安装 CUDA
4. 仅安装 Container Toolkit
5. 自定义选择

**预计下载大小**: ~4-6 GB
**安装时间**: 20-40 分钟

---

## 验证安装

### 完整验证脚本

```bash
chmod +x verify-installation.sh
sudo ./verify-installation.sh
```

验证内容:
- ✅ NVIDIA 驱动状态
- ✅ CUDA Toolkit 安装
- ✅ Container Toolkit 配置
- ✅ Docker GPU 支持
- ✅ 运行测试容器

### 手动验证

**验证驱动**:
```bash
nvidia-smi
```

**验证 CUDA**:
```bash
nvcc --version
cat /usr/local/cuda/version.txt
```

**验证 Container Toolkit**:
```bash
nvidia-ctk --version
docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi
```

---

## Docker 使用示例

### docker run 命令

```bash
# 使用所有 GPU
docker run --gpus all your-image

# 使用指定数量的 GPU
docker run --gpus 2 your-image

# 使用指定的 GPU
docker run --gpus '"device=0,1"' your-image

# 指定 GPU 能力
docker run --gpus 'all,capabilities=compute' your-image
```

### docker-compose.yml

```yaml
version: '3.8'

services:
  gpu-service:
    image: your-image
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all  # 或指定数量
              capabilities: [gpu]
```

### Kubernetes

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-pod
spec:
  containers:
  - name: cuda-container
    image: nvidia/cuda:12.3.0-base-ubuntu22.04
    resources:
      limits:
        nvidia.com/gpu: 1
```

---

## 文件结构

```
nvidia-offline/
├── README.md                      # 本文档
├── QUICKSTART.txt                 # 快速参考指南
├── VERSION                        # 版本信息
│
├── 方案 A: Container Toolkit
│   ├── download-packages.sh       # 下载脚本
│   └── install-offline.sh         # 安装脚本
│
├── 方案 B: 驱动 + CUDA
│   ├── download-driver-cuda.sh    # 下载脚本
│   └── install-driver-cuda.sh     # 安装脚本
│
├── 方案 C: 完整安装
│   ├── download-all-packages.sh   # 下载脚本
│   └── install-all-offline.sh     # 安装脚本
│
├── 工具脚本
│   ├── quick-start.sh             # 交互式向导
│   └── verify-installation.sh     # 验证脚本
│
└── 生成的目录 (运行后)
    ├── packages/                  # Container Toolkit 包
    ├── driver-cuda-packages/      # 驱动+CUDA 包
    └── logs/                      # 安装日志
```

---

## 故障排除

### 问题 1: nouveau 驱动冲突

**症状**: 安装驱动时提示 nouveau 驱动正在使用

**解决方案**:
```bash
# 安装脚本会自动禁用 nouveau
# 按提示重启系统后重新运行安装脚本
sudo reboot
```

### 问题 2: 驱动安装后 nvidia-smi 失败

**解决方案**:
```bash
# 重启系统
sudo reboot

# 检查内核模块
lsmod | grep nvidia

# 手动加载模块
sudo modprobe nvidia
```

### 问题 3: CUDA 找不到

**解决方案**:
```bash
# 检查 CUDA 安装
ls -la /usr/local/cuda

# 手动配置环境变量
echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc
```

### 问题 4: Docker 无法使用 GPU

**解决方案**:
```bash
# 重新配置 Docker runtime
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# 检查配置
cat /etc/docker/daemon.json
docker info | grep -i runtime
```

### 问题 5: 依赖包缺失

**解决方案**:
```bash
# 在联网机器上重新下载
sudo ./download-***.sh  # 重新运行下载脚本

# 或在目标机器上尝试修复
sudo apt-get install -f
```

### 问题 6: 内核版本不匹配

**症状**: DKMS 编译失败

**解决方案**:
```bash
# 确保安装了当前内核的头文件
sudo apt-get install linux-headers-$(uname -r)

# 或者更新系统并使用匹配的内核
sudo apt-get update && sudo apt-get upgrade
```

---

## 卸载

### 卸载 Container Toolkit

```bash
sudo apt-get remove --purge nvidia-container-toolkit \
    nvidia-container-toolkit-base \
    libnvidia-container-tools \
    libnvidia-container1
sudo systemctl restart docker
```

### 卸载 CUDA

```bash
sudo apt-get remove --purge 'cuda-*'
sudo rm -rf /usr/local/cuda*
```

### 卸载 NVIDIA 驱动

```bash
# 使用驱动自带的卸载工具
sudo /usr/bin/nvidia-uninstall

# 或使用包管理器
sudo apt-get remove --purge 'nvidia-*'
sudo apt-get autoremove
```

---

## 兼容性说明

### 驱动版本

| 驱动版本 | CUDA 支持 | 推荐用途 |
|---------|----------|---------|
| 575.x   | 12.9     | 最新特性 |
| 550.x   | 12.4     | 长期支持 |
| 535.x   | 12.2     | 稳定版本 |

### CUDA 版本

| CUDA 版本 | 最低驱动要求 | Ubuntu 22.04 |
|----------|------------|-------------|
| 12.9     | 575.x      | ✅ 支持 |
| 12.4     | 550.x      | ✅ 支持 |
| 12.0     | 525.x      | ✅ 支持 |
| 11.8     | 520.x      | ✅ 支持 |

### Docker 版本

- **最低**: Docker 19.03
- **推荐**: Docker 20.10+
- **支持**: Docker CE / Docker EE

---

## 性能优化建议

### 1. 持久化模式

```bash
# 启用 GPU 持久化模式（减少启动延迟）
sudo nvidia-smi -pm 1
```

### 2. 电源管理

```bash
# 设置最大性能模式
sudo nvidia-smi -pl 300  # 设置功耗上限（瓦特）
```

### 3. Docker 优化

```json
{
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  },
  "default-runtime": "nvidia"
}
```

---

## 常见使用场景

### 场景 1: 深度学习训练

```bash
# PyTorch
docker run --gpus all -it pytorch/pytorch:latest

# TensorFlow
docker run --gpus all -it tensorflow/tensorflow:latest-gpu

# JAX
docker run --gpus all -it nvcr.io/nvidia/jax:latest
```

### 场景 2: CUDA 开发

```bash
# 编译 CUDA 程序
nvcc -o hello hello.cu
./hello

# 使用 Docker 进行开发
docker run --gpus all -v $(pwd):/workspace nvidia/cuda:12.3.0-devel-ubuntu22.04
```

### 场景 3: 多 GPU 训练

```bash
# 指定使用的 GPU
CUDA_VISIBLE_DEVICES=0,1 python train.py

# Docker 中使用多 GPU
docker run --gpus 2 your-training-image
```

---

## 更新和维护

### 更新驱动

```bash
# 下载新版本驱动
sudo ./download-driver-cuda.sh  # 修改版本号后运行

# 安装新版本（会覆盖旧版本）
sudo ./install-driver-cuda.sh
```

### 更新 CUDA

```bash
# CUDA 支持多版本并存
# 新版本会安装到 /usr/local/cuda-X.Y
# 使用软链接切换版本

sudo ln -sfn /usr/local/cuda-12.9 /usr/local/cuda
```

### 更新 Container Toolkit

```bash
# 重新下载并安装
sudo ./download-packages.sh
sudo ./install-offline.sh
```

---

## 安全注意事项

1. **驱动签名**: 生产环境建议使用 UEFI Secure Boot 签名的驱动
2. **包完整性**: 所有脚本都会验证 SHA256 校验和
3. **网络隔离**: 离线安装包适用于内网隔离环境
4. **权限管理**: 安装需要 root 权限，请在可信环境执行

---

## 参考资料

- [NVIDIA 驱动下载](https://www.nvidia.com/Download/index.aspx)
- [CUDA Toolkit 文档](https://docs.nvidia.com/cuda/)
- [Container Toolkit 文档](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/)
- [Docker GPU 支持](https://docs.docker.com/config/containers/resource_constraints/#gpu)
- [NVIDIA NGC Catalog](https://catalog.ngc.nvidia.com/)

---

## 许可证

本工具脚本为开源工具。NVIDIA 软件组件遵循其各自的许可证：
- NVIDIA 驱动: NVIDIA Software License
- CUDA Toolkit: NVIDIA End User License Agreement
- Container Toolkit: Apache 2.0 License

---

## 贡献

欢迎提交 Issue 和 Pull Request！

---

**最后更新**: 2025-12-17
**维护状态**: ✅ 活跃维护
**测试环境**: Ubuntu 22.04 LTS + NVIDIA RTX 系列
