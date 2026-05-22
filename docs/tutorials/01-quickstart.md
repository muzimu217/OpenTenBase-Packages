# 5分钟快速开始

## 环境要求

| 资源 | 最小要求 | 推荐配置 |
|------|---------|---------|
| 操作系统 | Ubuntu 20.04 / Debian 11 | Ubuntu 24.04 / Debian 12 |
| CPU | 2核 | 4核+ |
| 内存 | 4GB | 8GB+ |
| 磁盘 | 20GB | 50GB+ |
| 权限 | sudo 权限 | root 或 sudo |

## 快速部署（推荐）

### 一键安装

```bash
# 下载并运行安装脚本
curl -sLO https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi10/install.sh
sudo bash install.sh
```

**预期输出：**
```
[INFO] OpenTenBase v5.0 Installer
[INFO] Detected Ubuntu 22.04 (jammy)
[INFO] Downloading packages from GitHub...
[OK] opentenbase_5.0-1ubuntu1_all.deb installed
[OK] opentenbase-server_5.0-1ubuntu1_amd64.deb installed
[OK] opentenbase-client_5.0-1ubuntu1_amd64.deb installed
[OK] opentenbase-contrib_5.0-1ubuntu1_amd64.deb installed
[OK] Packages installed successfully
```

### 初始化集群

```bash
opentenbase-ctl init
```

**预期输出：**
```
>> initgtm /var/lib/opentenbase/gtm
>> initdb coordinator at /var/lib/opentenbase/coordinator
>> initdb datanode at /var/lib/opentenbase/dn1
>> init complete. Run: opentenbase-ctl start
```

### 启动集群

```bash
opentenbase-ctl start
```

**预期输出：**
```
starting gtm
  gtm
starting coord
  coord
starting dn1
  dn1
registering GTM node in pgxc_node ...
registering coordinator node ...
registering datanode node ...
reloading connection pool ...
node group setup complete
creating sharding map ...
start complete
```

### 验证安装

```bash
# 查看集群状态
opentenbase-ctl status
```

**预期输出：**
```
OpenTenBase Cluster Status
===========================
GTM:      Running
Coordinator: Running
Datanode: Running
```

### 连接数据库

```bash
psql -h 127.0.0.1 -p 5432 -U opentenbase postgres
```

**预期输出：**
```
psql (10.0) (OpenTenBase 5.0.0)
Type "help" for help.

postgres=#
```

### 测试 SQL

```sql
-- 查看版本
SELECT version();

-- 查看节点
SELECT * FROM pgxc_node;

-- 创建测试表
CREATE TABLE test (id INT, name TEXT);

-- 插入数据
INSERT INTO test VALUES (1, 'Alice'), (2, 'Bob');

-- 查询数据
SELECT * FROM test;

-- 退出
\q
```

## 手动安装（进阶）

如果安装脚本不可用，可以手动下载 .deb 包：

```bash
# 下载所有 .deb 包
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi10/opentenbase_5.0-1ubuntu1_all.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi10/opentenbase-server_5.0-1ubuntu1_amd64.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi10/opentenbase-client_5.0-1ubuntu1_amd64.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi10/opentenbase-contrib_5.0-1ubuntu1_amd64.deb

# 安装
sudo dpkg -i *.deb
sudo apt-get install -f -y  # 解决依赖问题

# 初始化
sudo opentenbase-ctl init
sudo opentenbase-ctl start
```

## 常见问题

### 问题1：安装失败 - 找不到包

**错误信息：**
```
E: Unable to locate package opentenbase
```

**解决方法：**
```bash
# 检查操作系统版本
lsb_release -a

# 确保使用官方安装脚本
curl -sLO https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi10/install.sh
```

### 问题2：GTM 启动失败

**错误信息：**
```
FATAL: binding threads failed for 22
```

**解决方法：**
```bash
# v5.0-multi10 已自动处理此问题
# 检查 CPU 核心数
nproc

# 如果仍失败，手动设置线程数
echo "gtm_thread_count = 2" >> /var/lib/opentenbase/gtm/gtm.conf
opentenbase-ctl restart
```

### 问题3：端口被占用

**错误信息：**
```
FATAL: could not bind IPv6 socket: Address already in use
```

**解决方法：**
```bash
# 检查端口占用
sudo netstat -tlnp | grep -E '(5432|6666|15432)'

# 停止占用端口的服务
sudo kill -9 <PID>

# 或者修改配置文件中的端口号
sudo vim /etc/opentenbase/opentenbase.conf
```

### 问题4：内存不足

**错误信息：**
```
ERROR: out of memory
```

**解决方法：**
```bash
# 增加交换空间
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 验证
free -h
```

## 架构概览

OpenTenBase 是一个分布式数据库，由三个核心组件组成：

```
┌─────────────────────────────────────────────────────────────┐
│                     OpenTenBase 集群                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│    ┌──────────┐                                              │
│    │   GTM    │ ← 全局事务管理器（Port: 6666）              │
│    └─────┬────┘                                              │
│          │                                                   │
│    ┌─────┴────┐                                              │
│    │          │                                              │
│ ┌──▼───┐  ┌──▼───┐         ┌────────┐                       │
│ │ CN1  │  │ CN2  │  ...    │  CNx   │ ← 协调节点（Port: 5432） │
│ └──┬───┘  └──┬───┘         └────────┘                       │
│    │        │                                                   │
│    └────┬───┘                                                   │
│         │                                                       │
│    ┌────┴────┐                                                  │
│    │         │                                                  │
│ ┌──▼───┐ ┌──▼───┐        ┌────────┐                          │
│ │ DN1  │ │ DN2  │  ...   │  DNx   │ ← 数据节点（Port: 15432） │
│ └──────┘ └──────┘        └────────┘                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**组件说明：**
- **GTM（Global Transaction Manager）**：管理全局事务，分配全局事务 ID（GXID）
- **Coordinator（协调节点）**：接收客户端请求，解析 SQL，路由到对应的数据节点
- **Datanode（数据节点）**：存储实际数据，执行 SQL 查询

## 下一步

- 📖 阅读 [基础操作](02-basic-ops.md) - 学习常用的数据库操作
- 🏗️ 了解 [架构原理](03-architecture.md) - 深入理解分布式架构
- 🧪 尝试 [实验1：部署集群](../labs/lab-01-deploy.md) - 动手实践

## 资源链接

- 🌐 [GitHub 仓库](https://github.com/muzimu217/OpenTenBase-deb)
- 📦 [最新 Release](https://github.com/muzimu217/OpenTenBase-deb/releases)
- 📖 [OpenTenBase 官方文档](https://github.com/OpenTenBase/OpenTenBase)
- 💬 [问题反馈](https://github.com/muzimu217/OpenTenBase-deb/issues)