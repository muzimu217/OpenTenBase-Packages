# OpenTenBase .deb 打包

[English](README.md) | 中文

Ubuntu .deb 打包方案，用于 [OpenTenBase](https://github.com/OpenTenBase/OpenTenBase) v5.0（基于 PostgreSQL 10 的分布式 SQL 数据库）。

## 快速安装

### 一键安装（推荐）

```bash
# 下载并运行安装脚本
curl -sLO https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi10/install.sh
sudo bash install.sh
```

安装脚本会自动：
- 检测系统版本（Ubuntu 20.04/22.04/24.04、Debian 11/12）
- 下载对应的 .deb 软件包
- 通过 apt 解决依赖关系

### 手动安装

```bash
# 对于 Ubuntu 24.04 (Noble)
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi10/opentenbase_5.0-1ubuntu1.noble_all.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi10/opentenbase-server_5.0-1ubuntu1.noble_amd64.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi10/opentenbase-client_5.0-1ubuntu1.noble_amd64.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi10/opentenbase-contrib_5.0-1ubuntu1.noble_amd64.deb
sudo dpkg -i ./*.deb || sudo apt-get install -f -y
```

> **注意**：如果 `dpkg` 报告缺少依赖（如 `libossp-uuid16` 或 `libpqxx-7.8t64`），这是打包元数据错误——二进制文件运行时**并不需要**这些库。使用 `sudo dpkg --force-depends -i ./*.deb` 安装，然后执行 `sudo mkdir -p /usr/lib/opentenbase/lib/postgresql` 再继续。

## 软件包说明

| 软件包 | 描述 |
|--------|------|
| `opentenbase` | 元软件包（依赖 server + client） |
| `opentenbase-server` | 服务端二进制文件（postgres, gtm, pg_ctl）+ 服务驱动 |
| `opentenbase-client` | 客户端工具（psql, pg_dump） |
| `opentenbase-contrib` | 扩展组件（pgbench, oid2name 等） |
| `libopentenbase-dev` | 开发头文件 + pg_config |
| `opentenbase-doc` | SGML 文档源 |

## 快速开始

### 初始化集群

```bash
# 初始化 GTM + Coordinator + Datanode
opentenbase-ctl init
```

### 启动集群

```bash
# 启动所有节点
opentenbase-ctl start
```

### 检查状态

```bash
# 查看集群状态
opentenbase-ctl status
```

### 连接数据库

```bash
# 通过 psql 连接（默认数据库为 template1）
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1
```

### 停止集群

```bash
# 停止所有节点
opentenbase-ctl stop
```

## 架构说明

### 安装路径

- **主目录**：`/usr/lib/opentenbase/`（与系统 PostgreSQL 隔离）
- **配置目录**：`/etc/opentenbase/`
- **数据目录**：`/var/lib/opentenbase/`
- **日志目录**：`/var/log/opentenbase/`
- **管理脚本**：`/usr/bin/opentenbase-ctl`

### 端口规划

| 服务 | 端口 | 说明 |
|------|------|------|
| GTM | 6666 | 全局事务管理器 |
| Coordinator | 5432 | 协调节点（对外） |
| Datanode | 15432 | 数据节点 |
| Coordinator Pooler | 6667 | 连接池 |
| Datanode Pooler | 6668 | 连接池 |
| Coordinator Forward | 6669 | 转发端口 |
| Datanode Forward | 6670 | 转发端口 |

### 启动顺序

```
opentenbase-ctl start
    ├── 1. start_gtm()           # 启动 GTM
    ├── 2. start_coord()         # 启动 Coordinator
    ├── 3. register_nodes()      # 注册节点到 pgxc_node
    │   ├── CREATE GTM NODE ...
    │   ├── CREATE NODE coord1 ...
    │   ├── CREATE NODE dn001 ...
    │   ├── pgxc_pool_reload()
    │   └── EXECUTE DIRECT ON (dn001) 'CREATE GTM NODE ...'
    ├── 4. start_dn1()           # 启动 Datanode
    └── 5. register_nodes()      # 最终注册（确保传播完成）
```

## 从源码构建

### 安装构建依赖

```bash
apt install -y debhelper-compat bison flex perl gcc g++ make \
    libreadline-dev zlib1g-dev libssl-dev libpam0g-dev \
    libxml2-dev libldap2-dev libossp-uuid-dev uuid-dev \
    libcurl4-openssl-dev liblz4-dev libzstd-dev \
    libcli11-dev libpqxx-dev quilt libtool pkg-config
```

### 克隆源码

```bash
git clone https://github.com/OpenTenBase/OpenTenBase.git
cd OpenTenBase
```

### 复制打包文件

```bash
cp -r /path/to/debian/ ./
```

### 构建软件包

```bash
# 完整编译
fakeroot debian/rules binary

# 或者仅重新打包（不重新编译）
fakeroot debian/rules binary
```

## 部署模式

| 模式 | 组件 | 适用场景 | 状态 |
|------|------|---------|------|
| 单节点 | GTM + CN | 开发测试 | 已验证 |
| Docker 多节点 | GTM + CN + N*DN | 测试/生产 | 已验证 |
| 多机多节点 | GTM + CN + N*DN | 生产环境 | 已验证 |
| 单机多节点 | GTM + CN + DN | 不支持 | 端口冲突 |

> **注意**：单机多节点不支持，因为 CN 和 DN 的 forward manager 都默认绑定 `127.0.0.1:6669`，导致端口冲突。Docker 多节点不受影响（每个容器有独立 IP）。详见 [部署指南](tutorials/07-deployment.md)。

## 已知限制

1. **许可证问题**：OpenTenBase 需要有效许可证才能执行写操作。开源版本为只读模式。
2. **单机多节点**：由于 forward manager 端口冲突（CN 和 DN 都绑定 127.0.0.1:6669），不支持单机多节点部署。请使用 Docker 或多机部署。
3. **无 systemd**：某些容器环境没有 systemd，使用 `opentenbase-ctl` 直接管理。

## 故障排查

### 常见问题

#### 1. 安装失败：依赖关系问题

如果 `sudo apt install ./*.deb` 报告缺少 `libossp-uuid16` 或 `libpqxx-7.8t64` 等依赖：

```bash
# 强制安装（这些库运行时并不需要）
sudo dpkg --force-depends -i ./*.deb

# 创建缺失的插件目录
sudo mkdir -p /usr/lib/opentenbase/lib/postgresql
```

#### 2. 无法连接到数据库

```bash
# 检查集群状态
opentenbase-ctl status

# 查看日志
tail -f /var/log/opentenbase/coord.log

# 注意：默认数据库是 template1，不是 postgres
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1
```

#### 3. GTM 启动失败

```bash
# 检查 GTM 日志
tail -f /var/log/opentenbase/gtm.log

# 重新初始化集群
opentenbase-ctl stop
opentenbase-ctl init
opentenbase-ctl start
```

#### 4. 端口冲突

```bash
# 检查端口占用
sudo netstat -tlnp | grep -E '(5432|6666|15432)'

# 停止冲突的服务
sudo systemctl stop postgresql
```

## 贡献指南

欢迎贡献代码、报告问题或提出改进建议！

### 报告问题

1. 访问 [Issues](https://github.com/muzimu217/OpenTenBase-deb/issues)
2. 点击 "New Issue"
3. 描述问题详情，包括：
   - Ubuntu 版本
   - 错误信息
   - 复现步骤

### 提交代码

1. Fork 本仓库
2. 创建特性分支：`git checkout -b feature/your-feature`
3. 提交更改：`git commit -m 'Add your feature'`
4. 推送分支：`git push origin feature/your-feature`
5. 创建 Pull Request

## 许可证

与 OpenTenBase 相同（Apache 2.0）。

## 相关链接

- **GitHub 仓库**：https://github.com/muzimu217/OpenTenBase-deb
- **上游仓库**：https://github.com/OpenTenBase/OpenTenBase
- **OpenTenBase 文档**：https://github.com/OpenTenBase/OpenTenBase/wiki

---

**维护者**：muzimu217
**最后更新**：2026-05-23
