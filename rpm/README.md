# OpenTenBase RPM 打包

## 目录结构

```
rpm/
├── opentenbase.spec        # RPM spec 文件
├── build-rpm.sh            # 构建脚本
└── README.md               # 本文件
```

## 构建方法

### 前置条件

- EulerOS / CentOS / aarch64 系统
- rpmbuild 工具（`yum install rpm-build`）
- OpenTenBase 编译产物 tarball（`opentenbase-5.0-aarch64.tar.gz`）

### 构建步骤

```bash
# 1. 构建 RPM
bash build-rpm.sh /path/to/opentenbase-5.0-aarch64.tar.gz

# 2. 安装 RPM
sudo rpm -ivh ~/rpmbuild/RPMS/aarch64/opentenbase-5.0.0-1.aarch64.rpm

# 3. 验证安装
psql --version
initdb --version
gtm --version
```

## 安装后配置

RPM 安装后会自动执行 `ldconfig`，库文件路径 `/usr/lib/opentenbase/lib` 已加入系统库搜索路径。

### 二进制文件位置

| 路径 | 说明 |
|------|------|
| `/usr/lib/opentenbase/bin/` | 主程序目录 |
| `/usr/lib/opentenbase/lib/` | 库文件 |
| `/usr/lib/opentenbase/share/` | 共享数据 |
| `/usr/lib/opentenbase/include/` | 头文件 |
| `/usr/bin/psql`, `/usr/bin/initdb` 等 | 符号链接 |
| `/etc/ld.so.conf.d/opentenbase.conf` | 库路径配置 |

## 部署模式

### 单节点部署（GTM + CN）

适用于开发测试和功能验证。

```bash
# 设置环境变量
export LD_LIBRARY_PATH=/usr/lib/opentenbase/lib
export PATH=/usr/lib/opentenbase/bin:$PATH

# 创建数据目录
mkdir -p ~/otb-data/{gtm,cn}

# 1. 初始化并启动 GTM
gtm_ctl init -Z gtm -D ~/otb-data/gtm
gtm -D ~/otb-data/gtm -l ~/otb-data/gtm.log &

# 2. 初始化 CN（必须指定 GTM 信息）
initdb -D ~/otb-data/cn --nodename=cn0001 --nodetype=coordinator \
  --master_gtm_nodename=gtm0001 --master_gtm_ip=127.0.0.1 --master_gtm_port=6666

# 3. 配置 CN
echo "listen_addresses = '*'" >> ~/otb-data/cn/postgresql.conf
echo "port = 5432" >> ~/otb-data/cn/postgresql.conf
echo "host all all 0.0.0.0/0 trust" >> ~/otb-data/cn/pg_hba.conf

# 4. 启动 CN
pg_ctl -D ~/otb-data/cn -l ~/otb-data/cn.log start -Z coordinator

# 5. 验证
psql -h 127.0.0.1 -p 5432 -U $(whoami) postgres -c "SELECT * FROM pgxc_node;"
```

### 多机多节点部署（GTM + CN + DN）

适用于生产环境。需要多台服务器，每台有独立 IP。

**已知限制**：单机多节点（GTM+CN+DN 部署在同一台机器）不支持。CN 和 DN 的 forward manager 都默认绑定 `127.0.0.1:6669`，会导致端口冲突。Docker 部署不受影响（每个容器有独立 IP）。

详细部署步骤请参考 [部署指南](../docs/tutorials/07-deployment.md)。

### 卸载

```bash
# 停止所有节点后卸载
sudo rpm -e opentenbase
```

## 支持的架构

- aarch64 (ARM64)
