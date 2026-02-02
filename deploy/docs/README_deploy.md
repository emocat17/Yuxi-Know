# Yuxi-Know 离线迁移部署指南

本文档详细说明如何将 Yuxi-Know 项目进行打包、导出离线镜像，并在无外网环境的机器上进行一键部署。

## 目录结构说明

```
deploy/
├── archives/               # [自动生成] 存放导出的 Docker 镜像文件 (.tar)
├── config/
│   ├── deploy.conf         # 离线部署脚本配置文件
│   └── save.conf           # 镜像导出脚本配置文件
├── docs/
│   └── README_deploy.md    # 本部署指南
├── logs/                   # 脚本运行日志
├── scripts/
│   ├── deploy-offline.sh   # 离线部署脚本 (在目标机器运行)
│   └── export-images.sh    # 镜像导出脚本 (在源机器运行)
├── .env.prod               # (可选) 生产环境配置文件模板
├── docker-compose.custom.yml # 用于部署和导出的 Docker Compose 配置文件
└── docker-compose-deployed.yml # (部署后生成) 实际运行的 Docker Compose 文件
```

## 1. 源机器：准备与导出

在可以连接外网的机器上进行以下操作。

### 1.1 准备环境
确保已安装 Docker 和 Docker Compose。
确保项目根目录下的 `.env` 文件已配置正确（参考 `.env.example`）。

### 1.2 启动并验证服务
使用 `deploy` 目录下的配置启动服务，确保镜像已构建或拉取，且服务运行正常。

```bash
# 在项目根目录下执行
# 注意：Windows 用户建议使用 Git Bash 执行脚本

# 启动服务 (构建并后台运行)
docker compose -f deploy/docker-compose.custom.yml up --build -d
```

### 1.3 导出离线镜像
运行导出脚本，脚本会自动读取 `deploy/docker-compose.custom.yml` 中的镜像列表，将它们保存为 `.tar` 文件到 `deploy/archives/` 目录。

**功能特性：**
*   **自动重命名**：脚本会自动将 `yuxi-` 前缀的镜像重命名为 `graph-` 前缀，以保持离线环境的一致性。
*   **断点续传**：如果 `deploy/archives/` 下已存在对应的镜像文件，脚本会自动跳过，避免重复导出。
*   **配置灵活**：可通过修改 `deploy/config/save.conf` 调整导出目录、项目名称等配置。

```bash
# 在项目根目录下执行
bash deploy/scripts/export-images.sh
```

脚本执行完成后，检查 `deploy/archives/` 目录，应包含所有服务的镜像文件（如 `graph-know_graph-api_0.5.dev_*.tar` 等）。
同时会生成 `deploy/archives/images_manifest.json` 文件，记录导出的镜像信息。

## 2. 目标机器：离线部署

将整个 `Yuxi-Know` 项目文件夹（包含 `deploy/archives` 中的镜像）拷贝到目标机器。

### 2.1 准备配置
确保目标机器上的 `.env` 文件已根据实际环境修改（如数据库密码、API Key 等）。如果目标机器完全隔离，请确保所有必要的模型文件也已拷贝到 `models/` 目录。

### 2.2 执行一键部署
在目标机器上运行离线部署脚本。

```bash
# 在项目根目录下执行
bash deploy/scripts/deploy-offline.sh
```

该脚本会自动执行以下步骤：
1.  加载 `deploy/archives/` 目录下的所有 `.tar` 镜像文件到 Docker。
2.  根据 `deploy/config/deploy.conf` 和 `deploy/docker-compose.custom.yml` 生成最终的部署配置。
3.  启动 Docker 容器服务。

### 2.3 验证部署
检查容器运行状态：

```bash
docker ps
```

访问 Web 界面（默认端口 5173）和 API 文档（默认端口 5050/docs）验证服务是否正常。

## 常见问题

*   **脚本执行权限**：如果提示 `Permission denied`，请先执行 `chmod +x deploy/scripts/*.sh` 添加执行权限。
*   **镜像加载失败**：请检查 `deploy/archives/` 下的 `.tar` 文件是否完整，可以尝试重新导出。
*   **端口冲突**：如果目标机器端口被占用，请修改 `deploy/docker-compose.custom.yml` 或 `.env` 中的端口配置。
