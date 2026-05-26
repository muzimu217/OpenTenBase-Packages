# OpenTenBase 5.0 打包测试计划

## 测试目标
验证所有构建的 DEB/RPM 包在各发行版上能正确安装、多节点部署、基本 CRUD 操作通过。

## 测试范围

### DEB 包（amd64）

| 发行版 | 安装测试 | 多节点测试 | 状态 |
|--------|---------|-----------|------|
| Ubuntu 20.04 (focal) | TODO | TODO | - |
| Ubuntu 22.04 (jammy) | TODO | TODO | - |
| Ubuntu 24.04 (noble) | CI 通过 | TODO | 单节点 OK |
| Ubuntu 25.04 (plucky) | TODO | TODO | - |
| Debian 11 (bullseye) | TODO | TODO | - |
| Debian 12 (bookworm) | CI 通过 | TODO | 单节点 OK |
| Debian 13 (trixie) | TODO | TODO | - |

### RPM 包（x86_64）

| 发行版 | 安装测试 | 多节点测试 | 状态 |
|--------|---------|-----------|------|
| Rocky Linux 8 | TODO | TODO | - |
| Rocky Linux 9 | TODO | TODO | - |
| CentOS Stream 8 | TODO | TODO | - |
| CentOS Stream 9 | TODO | TODO | - |
| AlmaLinux 8 | TODO | TODO | - |
| AlmaLinux 9 | TODO | TODO | - |
| openEuler 22.03 | TODO | TODO | - |
| Fedora 40 | TODO | TODO | - |

### RPM 包（aarch64）

| 发行版 | 安装测试 | 多节点测试 | 状态 |
|--------|---------|-----------|------|
| EulerOS 2.0 | 手动通过 | 手动通过 | DONE |

## 测试用例

### 1. 安装测试（每个发行版）
```bash
# DEB
sudo dpkg -i opentenbase*.deb
# 或
sudo apt install -f -y

# RPM
sudo rpm -ivh opentenbase*.rpm
```

验证项：
- [ ] 包安装无报错
- [ ] 二进制文件存在：`postgres`, `psql`, `initdb`, `pg_ctl`, `gtm`, `opentenbase-ctl`
- [ ] 配置文件存在：`/etc/opentenbase/5.0/` 下模板文件
- [ ] 库文件存在：`libpq.so`, `libecpg.so` 等
- [ ] 用户 `opentenbase` 已创建
- [ ] `ldconfig` 后库可加载

### 2. 多节点部署测试（每个发行版至少跑一次）
```bash
# 初始化 GTM
initgtm -Z gtm -D /tmp/otb/gtm
# 配置 gtm.conf: listen_addresses = '*', port = 6666

# 初始化 Datanode
initdb --datanode -D /tmp/otb/dn1 \
  --master_gtm_ip=localhost --master_gtm_port=6666 --master_gtm_nodename=one
# 配置: port=5433, pooler_port=6668, forward_port=6670

# 初始化 Coordinator
initdb --coordinator -D /tmp/otb/coord \
  --master_gtm_ip=localhost --master_gtm_port=6666 --master_gtm_nodename=one
# 配置: port=5432, pooler_port=6669, forward_port=6671

# 启动
gtm -D /tmp/otb/gtm &
postgres --datanode -D /tmp/otb/dn1 &
postgres --coordinator -D /tmp/otb/coord &

# 注册节点
psql -p 5432 -c "CREATE NODE dn1 WITH (type='datanode', host='localhost', port=5433);"
psql -p 5433 -c "CREATE NODE coord WITH (type='coordinator', host='localhost', port=5432);"

# 创建分片组
psql -p 5432 -c "CREATE NODE GROUP mygroup WITH (dn1);"
psql -p 5432 -c "CREATE SHARDING GROUP TO GROUP mygroup;"
```

验证项：
- [ ] GTM 启动正常，端口 6666
- [ ] Datanode 启动正常，端口 5433
- [ ] Coordinator 启动正常，端口 5432
- [ ] 节点注册成功
- [ ] 分片组创建成功

### 3. CRUD 测试
```sql
-- 建表（分片表）
CREATE TABLE t1 (id int PRIMARY KEY, name text) DISTRIBUTE BY SHARDING;

-- 插入
INSERT INTO t1 VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie');

-- 查询
SELECT * FROM t1;
SELECT * FROM t1 WHERE id = 2;

-- 更新
UPDATE t1 SET name = 'Alice2' WHERE id = 1;

-- 删除
DELETE FROM t1 WHERE id = 3;

-- 验证最终状态
SELECT * FROM t1 ORDER BY id;
-- 期望: 1|Alice2, 2|Bob

-- 建表（普通表）
CREATE TABLE t2 (id int, val text);
INSERT INTO t2 VALUES (100, 'test');
SELECT * FROM t2;

-- 清理
DROP TABLE t1;
DROP TABLE t2;
```

验证项：
- [ ] 分片表 CREATE 成功
- [ ] INSERT 3 条
- [ ] SELECT 全表和 WHERE 条件
- [ ] UPDATE 1 条
- [ ] DELETE 1 条
- [ ] 普通表 CRUD
- [ ] DROP TABLE 清理

### 4. 其他验证
- [ ] `opentenbase-ctl status` 输出正常
- [ ] `opentenbase-ctl stop` 干净停止
- [ ] 无 license 时仍可读写（license bypass 生效）
- [ ] 2 核服务器上 GTM 正常启动（CPU binding 修复生效）

## 执行策略

### Docker 自动化测试（推荐）
为每个发行版创建 Docker 容器，运行安装 + 多节点 + CRUD 测试脚本。

```bash
# 示例：Ubuntu 24.04
docker run --rm -v ./packages:/packages ubuntu:24.04 bash -c "
  apt-get update && apt-get install -y sudo procps libatomic1
  dpkg -i /packages/*.deb
  # 运行多节点测试脚本
  /test/multi-node-test.sh
"
```

### 测试脚本
- `test/smoke-test.sh` — 已有，单节点安装测试
- `test/multi-node-test.sh` — 待创建，多节点部署 + CRUD 测试

## 优先级
1. **P0**：Ubuntu 22.04/24.04, Debian 12, Rocky 9 — 最常用服务器发行版
2. **P1**：Ubuntu 20.04, Debian 11, AlmaLinux 9, CentOS Stream 9
3. **P2**：其余发行版 + ARM64
