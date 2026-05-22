# OpenTenBase 仓库整合迁移计划

## 目标

将 Docker 集群部署方案从错误仓库（opentenbase-dev）迁移到正确仓库（opentenbase-deb），实现单一仓库包含所有部署能力。

## 仓库定位

**OpenTenBase-deb** = OpenTenBase 一站式部署仓库

```
opentenbase-deb/
├── debian/          # Debian 打包
├── rpm/             # RPM 打包（新增）
├── patches/         # 源码补丁
├── config/          # 配置模板
├── systemd/         # 服务文件
├── scripts/         # 构建和安装脚本
├── docker/
│   ├── build/       # 构建镜像（已有）
│   ├── runtime/     # 运行时镜像（已有）
│   ├── compose/     # 单机部署（已有）
│   ├── cluster/     # 分布式集群部署（新增，从 opentenbase-dev 迁移）
│   └── test-docker.sh
├── test/            # 测试脚本
└── docs/            # 文档
```

---

## 一、迁移 Docker 集群部署

### 1.1 迁移文件清单

| 源文件 | 目标位置 | 处理方式 |
|--------|----------|----------|
| `opentenbase-dev/docker/cluster/Dockerfile.centos` | `opentenbase-deb/docker/cluster/Dockerfile.centos` | 清理注释后迁移 |
| `opentenbase-dev/docker/cluster/setup.sh` | `opentenbase-deb/docker/cluster/setup.sh` | 清理注释后迁移 |
| `opentenbase-dev/docker/cluster/config.ini` | `opentenbase-deb/docker/cluster/config.ini` | 直接迁移 |
| `opentenbase-dev/docker/cluster/postgres.conf` | `opentenbase-deb/docker/cluster/postgres.conf` | 直接迁移 |

### 1.2 不迁移的文件

| 文件 | 原因 |
|------|------|
| `Dockerfile.cluster` | 废弃的 EulerOS 方案，已验证不可用 |
| `sshd_config` | EulerOS 方案专用，无用 |
| `docker-compose.yml` | setup.sh 会自动生成，不需要提交 |

### 1.3 清理内容

**Dockerfile.centos 需清理：**
- 搜索并替换 `参考官方 OpenTenBase-DevEnv example-distributed 模式` → `分布式集群镜像`

**setup.sh 需清理：**
- 搜索并替换 `基于官方 OpenTenBase-DevEnv example-distributed 模式` → 删除该行
- 检查所有注释，删除任何"参考官方"相关字样
- 检查 setup.sh 中生成的 docker-compose.yml 内容，确保无"参考官方"字样

---

## 二、新增 RPM 打包目录

### 2.1 目录结构

```
rpm/
├── opentenbase.spec        # RPM spec 文件
├── build-rpm.sh            # 构建脚本
└── README.md               # 说明文档
```

### 2.2 暂不实现

RPM 打包本次只创建目录结构和占位文件，具体实现后续进行。

---

## 三、服务器验证测试

### 3.1 测试环境

- 服务器：华为云 devenv（EulerOS aarch64）
- Docker：18.09.0
- 连接方式：`ssh devenv`

### 3.2 测试步骤

| 步骤 | 操作 | 预期结果 |
|------|------|----------|
| 1 | 上传文件到服务器 `~/docker-build/cluster/` | 文件传输成功 |
| 2 | `docker build --network=host -f Dockerfile.centos -t opentenbase-cluster:latest .` | 镜像构建成功 |
| 3 | `bash setup.sh` | 集群安装成功（4节点） |
| 4 | `docker exec -u opentenbase otb-gtm ./opentenbase_ctl status` | 4个节点全部 Running |
| 5 | `psql -h 127.0.0.1 -p 11000 -U opentenbase postgres` | 可连接数据库 |
| 6 | `docker-compose down` | 集群正常停止 |
| 7 | 清理服务器镜像和容器 | 释放磁盘空间 |

### 3.3 验证标准

- 镜像构建无错误
- SSH 连通性验证通过
- opentenbase_ctl install 成功（GTM + CN + 2DN）
- 所有节点状态为 Running
- 可通过 psql 连接 CN 节点
- 集群可正常启停

---

## 四、执行顺序

1. **清理并迁移文件** → `/tmp/opentenbase-deb/docker/cluster/`
2. **创建 RPM 目录结构** → `/tmp/opentenbase-deb/rpm/`
3. **上传到服务器验证** → `ssh devenv`
4. **清理工作区** → 确认 opentenbase-dev 中的旧文件已无用（可选删除）

---

## 五、风险和注意事项

- 服务器上已有运行中的集群容器，迁移前需先 `docker-compose down`
- CentOS Stream 9 构建需要 `--network=host` 参数
- opentenbase_ctl 依赖 sshpass、iproute、net-tools
- /data 目录权限必须为 755，否则 opentenbase 用户无法访问
- 验证测试完成后需清理服务器上的镜像和容器，避免占用磁盘空间
