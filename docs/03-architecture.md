# OpenTenBase 架构详解

> 本文档深入讲解 OpenTenBase 的分布式架构设计，帮助您理解其工作原理和核心组件。

---

## 1. 整体架构

OpenTenBase 采用 shared-nothing 分布式架构，通过多个独立的节点协同工作，实现高性能的分布式数据库服务。

### 1.1 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                        应用层                                │
│                    (Client Applications)                     │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                       Coordinator Layer                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │   CN 1   │  │   CN 2   │  │   CN 3   │  │   CN 4   │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
│         │             │             │             │         │
│         └─────────────┴─────────────┴─────────────┘         │
│                           │                                 │
└───────────────────────────┼─────────────────────────────────┘
                            │
            ┌───────────────┴───────────────┐
            │                               │
            ▼                               ▼
┌───────────────────────────┐  ┌───────────────────────────┐
│       GTM Cluster         │  │     Datanode Cluster      │
│  ┌──────────┐  ┌────────┐  │  ┌──────────┐  ┌──────────┐ │
│  │ GTM-MAST │  │GTMSVR  │  │  │  DN 1    │  │  DN 2    │ │
│  └──────────┘  └────────┘  │  │(Primary) │  │(Primary) │ │
│                            │  └──────────┘  └──────────┘ │
│                            │         │             │       │
│                            │         ▼             ▼       │
│                            │  ┌──────────┐  ┌──────────┐ │
│                            │  │  DN 3    │  │  DN 4    │ │
│                            │  │(Standby) │  │(Standby) │ │
│                            │  └──────────┘  └──────────┘ │
└───────────────────────────┴──────────────────────────────┘
```

### 1.2 核心概念

- **Shared-Nothing**：每个节点拥有独立的 CPU、内存和存储，节点间通过网络通信
- **数据分片**：数据按照指定的分布策略分散到不同的 Datanode 节点
- **事务协调**：GTM 负责全局事务管理，确保分布式事务的一致性
- **透明扩展**：应用层无需关心数据的物理分布，像使用单机数据库一样使用 OpenTenBase

---

## 2. 核心组件详解

### 2.1 GTM（Global Transaction Manager）

GTM 是全局事务管理器，是 OpenTenBase 的核心组件之一。

#### 2.1.1 GTM 的职责

1. **全局事务 ID 分配**：为所有分布式事务分配唯一的全局事务 ID
2. **快照管理**：维护全局快照，确保 MVCC（多版本并发控制）的一致性
3. **分布式锁管理**：协调跨节点的锁操作
4. **两阶段提交协调**：确保分布式事务的原子性

#### 2.1.2 GTM 架构

GTM 采用主从架构：
- **GTM Master**：主节点，处理所有事务请求
- **GTM Standby**：备节点，通过流复制同步状态，提供高可用
- **GTM Proxy**：代理节点，缓存 GTM 信息，减少对 GTM Master 的压力

#### 2.1.3 GTM 配置

关键配置参数（`gtm.conf`）：

```ini
# GTM 监听地址
listen_addresses = '*'
port = 6666

# 数据目录
nodename = 'gtm_master'
data_directory = '/opt/opentenbase/gtm/data'

# 线程数（不能超过 CPU 核心数）
thread_count = 4

# 日志配置
log_connections = on
log_disconnections = on
```

#### 2.1.4 GTM 高可用

**GTM Standby 工作流程：**

1. 从 GTM Master 接收事务日志流
2. 重放日志，保持与 Master 状态一致
3. 当 Master 故障时，Standby 可以快速切换

**故障切换步骤：**

```bash
# 1. 停止当前 GTM Master
gtm_ctl -D /opt/opentenbase/gtm/data stop

# 2. 升级 GTM Standby 为 Master
gtm_ctl -D /opt/opentenbase/gtm_standby/data promote

# 3. 更新 Coordinator 和 Datanode 配置，指向新的 GTM Master
```

### 2.2 Coordinator（协调节点）

Coordinator 是 OpenTenBase 的接入层，负责处理客户端请求和协调分布式操作。

#### 2.2.1 Coordinator 的职责

1. **SQL 解析和优化**：解析 SQL 语句，生成执行计划
2. **路由分发**：将 SQL 请求路由到相应的 Datanode 节点
3. **结果聚合**：收集各 Datanode 的执行结果，进行聚合处理
4. **负载均衡**：在多个 Coordinator 之间分发请求
5. **全局一致性**：通过 GTM 确保分布式操作的一致性

#### 2.2.2 Coordinator 工作流程

```
Client → Coordinator
         │
         ├─ 1. SQL 解析
         │
         ├─ 2. 查询计划生成
         │
         ├─ 3. 路由决策
         │
         ├─ 4. 向 Datanode 发送请求
         │
         ├─ 5. 收集结果
         │
         └─ 6. 返回最终结果给 Client
```

#### 2.2.3 SQL 执行流程

**简单查询示例：**

```sql
-- 查询单个表（数据在一个 Datanode）
SELECT * FROM t1 WHERE id = 100;

Coordinator:
  1. 查询 pgxc_node 确定 t1 分布在 DN1
  2. 将查询发送到 DN1
  3. 接收 DN1 返回的结果
  4. 返回给客户端
```

**分布式查询示例：**

```sql
-- 查询分布在不同节点的表
SELECT t1.name, t2.amount 
FROM t1 JOIN t2 ON t1.id = t2.id
WHERE t1.status = 'active';

Coordinator:
  1. 解析 SQL，识别表分布：
     - t1 分布在 DN1、DN2
     - t2 分布在 DN3、DN4
  2. 生成分布式执行计划：
     - 在各节点并行执行过滤 WHERE 条件
     - 进行数据重分布（REDISTRIBUTE）或广播（BROADCAST）
     - 在各节点执行 JOIN
  3. 协调各节点执行
  4. 聚合结果
  5. 返回给客户端
```

#### 2.2.4 Coordinator 配置

关键配置参数（`postgresql.conf`）：

```ini
# 连接配置
max_connections = 200

# 工作进程
max_worker_processes = 8

# Coordinator 特有配置
coord_type = coordinator
enable_foreignkey = on  # 启用外键约束
enable_hashjoin = on    # 启用 Hash Join
```

### 2.3 Datanode（数据节点）

Datanode 是 OpenTenBase 的存储层，负责实际的数据存储和查询执行。

#### 2.3.1 Datanode 的职责

1. **数据存储**：存储实际的数据行
2. **本地查询执行**：执行 Coordinator 分发的 SQL 片段
3. **本地事务**：管理本地数据的事务
4. **数据复制**：与 Standby 节点同步数据

#### 2.3.2 数据分片策略

OpenTenBase 支持两种数据分布方式：

**1. 哈希分布（HASH）**

```sql
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    amount DECIMAL,
    order_date TIMESTAMP
) DISTRIBUTE BY HASH(order_id);
```

- 根据 `order_id` 的哈希值决定数据落在哪个节点
- 数据均匀分布，适合高并发的点查询
- 分布列的选择影响查询性能

**2. 模数分布（MODULO）**

```sql
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    amount DECIMAL,
    order_date TIMESTAMP
) DISTRIBUTE BY MODULO(order_id);
```

- 使用 `order_id % 节点数` 决定数据位置
- 适合分布列是连续整数的场景

**3. 复制表（REPLICATION）**

```sql
CREATE TABLE region (
    region_id INT PRIMARY KEY,
    region_name VARCHAR(50)
) DISTRIBUTE BY REPLICATION;
```

- 表数据在每个 Datanode 上都有完整副本
- 适合小表（字典表、配置表）

#### 2.3.3 主从复制

Datanode 支持异步流复制实现高可用：

```
┌────────────────┐         ┌────────────────┐
│   DN Primary   │────────>│  DN Standby    │
│   (读写)       │  WAL    │  (只读)         │
└────────────────┘         └────────────────┘
```

**复制延迟监控：**

```sql
-- 在 Standby 节点查询复制延迟
SELECT pg_is_in_recovery(), 
       pg_last_xact_replay_timestamp(),
       now() - pg_last_xact_replay_timestamp() AS replication_lag;
```

#### 2.3.4 Datanode 配置

关键配置参数（`postgresql.conf`）：

```ini
# 连接配置
max_connections = 100

# 连接池配置
pooler_port = 6667
pooler_maximum_connections = 100

# 工作内存
shared_buffers = 2GB
work_mem = 64MB
maintenance_work_mem = 256MB

# WAL 配置
wal_level = hot_standby
max_wal_senders = 5
wal_keep_size = 1GB
```

---

## 3. 分布式事务处理

### 3.1 两阶段提交协议（2PC）

OpenTenBase 使用两阶段提交协议确保分布式事务的原子性。

#### 3.1.1 工作流程

**阶段一：准备阶段（Prepare Phase）**

```
1. Client 向 Coordinator 发送 COMMIT
2. Coordinator 请求 GTM 分配全局事务 ID
3. Coordinator 向参与事务的所有 Datanode 发送 PREPARE
4. 每个 Datanode：
   - 写入 Prepare 日志
   - 锁定相关资源
   - 返回 "Yes" 或 "No"
```

**阶段二：提交阶段（Commit Phase）**

```
如果所有 Datanode 都返回 "Yes"：
  1. Coordinator 决定 COMMIT
  2. 通知所有 Datanode COMMIT
  3. 各 Datanode 执行 COMMIT，释放锁
  4. Coordinator 返回成功给 Client

如果任一 Datanode 返回 "No"：
  1. Coordinator 决定 ROLLBACK
  2. 通知所有 Datanode ROLLBACK
  3. 各 Datanode 回滚，释放锁
  4. Coordinator 返回失败给 Client
```

#### 3.1.2 分布式事务示例

```sql
BEGIN;

-- 在 DN1 上执行
INSERT INTO orders (order_id, user_id, amount) 
VALUES (1001, 1, 100.00);

-- 在 DN2 上执行
INSERT INTO order_items (item_id, order_id, product_id, quantity) 
VALUES (1001, 1001, 2001, 2);

-- 在 DN3 上执行
UPDATE user_balance SET balance = balance - 100.00 
WHERE user_id = 1;

COMMIT;  -- 触发两阶段提交
```

### 3.2 MVCC 和快照隔离

#### 3.2.1 全局快照

GTM 为每个事务分配一个全局快照，包含：
- 最小的活跃事务 ID（xmin）
- 最大的已提交事务 ID（xmax）
- 活跃事务列表

```sql
-- 查看当前事务快照信息
SELECT pgxc_snapshot_xmin(), pgxc_snapshot_xmax(), pgxc_snapshot_count();
```

#### 3.2.2 快照隔离级别

OpenTenBase 支持标准的隔离级别：

- **READ COMMITTED**：默认级别，每次查询都能看到已提交的数据
- **REPEATABLE READ**：事务内多次查询看到相同的数据快照

```sql
-- 设置隔离级别
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
```

### 3.3 分布式锁机制

OpenTenBase 实现了协调的分布式锁机制：

1. **本地锁**：Datanode 节点内部的锁
2. **全局锁**：通过 GTM 协调的跨节点锁

```sql
-- 显式加锁
SELECT * FROM orders WHERE order_id = 1001 FOR UPDATE;

-- 表级锁
LOCK TABLE orders IN EXCLUSIVE MODE;
```

---

## 4. SQL 执行流程

### 4.1 查询路由

Coordinator 根据 `pgxc_node` 表确定数据位置：

```sql
-- 查看数据分布信息
SELECT node_name, node_type, node_host, node_port 
FROM pgxc_node 
WHERE node_type = 'D';

-- 查看表的分布策略
SELECT schemaname, tablename, distributiontype, distkey 
FROM pgxc_class 
WHERE tablename = 'orders';
```

### 4.2 查询计划生成

#### 4.2.1 查看执行计划

```sql
-- 查看分布式执行计划
EXPLAIN (VERBOSE, COSTS OFF) 
SELECT t1.name, t2.amount 
FROM t1 JOIN t2 ON t1.id = t2.id
WHERE t1.status = 'active';
```

#### 4.2.2 执行计划关键节点

- **Gather Motion**：从多个节点收集数据
- **Hash Join**：分布式 Hash 连接
- **Redistribute Motion**：数据重分布
- **Broadcast Motion**：数据广播到所有节点

### 4.3 查询流程图

```
┌──────────────────────────────────────────────────────────┐
│                       查询执行流程                         │
└──────────────────────────────────────────────────────────┘

Client: SELECT * FROM orders WHERE user_id = 100;

    ↓
Coordinator
    ↓
┌───────────────────────────────────────────────┐
│ 1. SQL 解析和验证                              │
│ 2. 查询 pgxc_class 确定 orders 分布在 DN1, DN2 │
│ 3. 计算 user_id = 100 应该路由到哪个节点       │
│    (假设路由到 DN1)                            │
│ 4. 生成执行计划                                │
└───────────────────────────────────────────────┘
    ↓
┌───────────────────────────────────────────────┐
│ Coordinator → DN1:                            │
│ SELECT * FROM orders WHERE user_id = 100;     │
└───────────────────────────────────────────────┘
    ↓
DN1
    ↓
┌───────────────────────────────────────────────┐
│ 1. 执行本地查询                                │
│ 2. 扫描本地数据                                │
│ 3. 应用 WHERE 条件                             │
│ 4. 返回结果集                                  │
└───────────────────────────────────────────────┘
    ↓
Coordinator
    ↓
┌───────────────────────────────────────────────┐
│ 1. 接收 DN1 的结果                             │
│ 2. 应用额外的过滤（如果有）                    │
│ 3. 排序（如果有 ORDER BY）                     │
│ 4. 限制结果集（如果有 LIMIT）                  │
│ 5. 返回给 Client                               │
└───────────────────────────────────────────────┘
    ↓
Client: 接收查询结果
```

---

## 5. 数据一致性和高可用

### 5.1 一致性保障

OpenTenBase 提供多层次的一致性保障：

1. **ACID 特性**：通过 GTM 和 2PC 确保分布式事务的 ACID
2. **MVCC**：多版本并发控制，避免读写冲突
3. **外键约束**：支持跨节点的外键约束

### 5.2 高可用架构

#### 5.2.1 组件级高可用

- **GTM**：主从架构，自动故障切换
- **Coordinator**：多个 Coordinator，负载均衡
- **Datanode**：主从复制，异步或同步模式

#### 5.2.2 故障检测和恢复

```sql
-- 查看集群健康状态
SELECT * FROM pgxc_node WHERE node_is_primary = false;

-- 查看复制状态
SELECT * FROM pg_stat_replication;
```

### 5.3 数据备份和恢复

详见 `05-troubleshoot.md` 中的备份恢复章节。

---

## 6. 性能优化原理

### 6.1 查询优化策略

1. **下推过滤**：尽可能将 WHERE 条件下推到 Datanode
2. **并行执行**：充分利用多节点并行处理
3. **数据本地化**：减少跨节点数据传输
4. **连接重写**：选择最优的连接算法

### 6.2 分布式 JOIN 策略

**1. Nested Loop Join**

```sql
-- 适合小表与大表连接
SELECT * FROM small_table JOIN large_table 
ON small_table.id = large_table.id;
```

**2. Hash Join**

```sql
-- 适合大表连接，在内存中构建 Hash 表
SELECT * FROM table1 JOIN table2 
ON table1.id = table2.id;
```

**3. Merge Join**

```sql
-- 适合已排序的数据
SELECT * FROM table1 JOIN table2 
ON table1.id = table2.id 
WHERE table1.sort_key > 100;
```

### 6.3 数据倾斜问题

**问题：** 某个节点的数据量远大于其他节点

**解决方案：**

1. **重新选择分布列**
2. **使用复合分布键**
3. **定期数据重分布**

```sql
-- 重新分布表（需要重建）
ALTER TABLE orders DISTRIBUTE BY HASH(user_id);
```

---

## 7. 监控和诊断

### 7.1 关键监控指标

#### 7.1.1 集群级别

- **节点健康状态**
- **连接数**
- **QPS（每秒查询数）**
- **事务延迟**

#### 7.1.2 节点级别

- **CPU 使用率**
- **内存使用率**
- **磁盘 I/O**
- **网络流量**

### 7.2 性能视图

```sql
-- 查询节点信息
SELECT * FROM pgxc_node;

-- 查看表大小
SELECT pg_size_pretty(pg_total_relation_size('orders'));

-- 查看慢查询
SELECT * FROM pg_stat_statements 
ORDER BY total_time DESC 
LIMIT 10;

-- 查看锁等待
SELECT * FROM pg_locks 
WHERE NOT granted;
```

### 7.3 日志分析

```bash
# Coordinator 日志
tail -f /opt/opentenbase/coord/log/postgresql-*.log

# GTM 日志
tail -f /opt/opentenbase/gtm/log/gtm.log

# Datanode 日志
tail -f /opt/opentenbase/datanode1/log/postgresql-*.log
```

---

## 8. 扩展性和弹性

### 8.1 水平扩展

**添加新的 Datanode：**

1. 部署新的 Datanode 节点
2. 在 `pgxc_node` 中注册新节点
3. 重新分布数据（可选）

```sql
-- 注册新节点
INSERT INTO pgxc_node 
VALUES ('dn5', 'D', '192.168.1.105', 5432, false, false);
```

### 8.2 数据重分布

```bash
# 使用 gs_expand 工具（OpenTenBase 工具集）
gs_expand -i /opt/opentenbase/config/expand.conf
```

---

## 9. 安全架构

### 9.1 认证和授权

```sql
-- 创建用户
CREATE USER student WITH PASSWORD 'password';

-- 授权
GRANT SELECT, INSERT ON orders TO student;

-- 撤销权限
REVOKE ALL ON orders FROM student;
```

### 9.2 数据加密

- **SSL 连接**：加密客户端与服务器之间的通信
- **TDE**：透明数据加密（需要额外配置）

### 9.3 审计日志

```ini
# postgresql.conf 配置
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_statement = 'all'  # 记录所有 SQL
```

---

## 10. 常见架构问题

### 10.1 GTM 单点问题

**问题：** GTM Master 故障可能导致集群不可用

**解决方案：**
- 部署 GTM Standby
- 使用 GTM Proxy 缓存信息
- 定期监控 GTM 健康状态

### 10.2 分布式事务性能

**问题：** 跨节点事务性能较差

**优化建议：**
- 尽量避免跨节点事务
- 将相关数据分布到同一节点
- 考虑使用本地临时表

### 10.3 数据倾斜

**问题：** 数据分布不均匀导致部分节点负载过高

**解决方案：**
- 重新选择分布列
- 使用复合分布键
- 定期检查数据分布情况

---

## 11. 总结

OpenTenBase 的分布式架构通过以下核心设计实现高性能和高可用：

1. **Shared-Nothing 架构**：无共享资源，易于水平扩展
2. **GTm 事务协调**：确保分布式事务的一致性
3. **智能路由**：Coordinator 智能路由请求，最小化网络传输
4. **主从复制**：组件级高可用，快速故障恢复
5. **灵活的数据分布**：支持多种分布策略，适应不同场景

理解这些架构原理，有助于您更好地使用 OpenTenBase，进行性能优化和故障排查。

---

## 12. 延伸阅读

- [02-basic-ops.md](./02-basic-ops.md)：基础操作指南
- [04-advanced.md](./04-advanced.md)：高级功能和优化
- [05-troubleshoot.md](./05-troubleshoot.md)：故障排查指南
- [06-best-practices.md](./06-best-practices.md)：最佳实践

---

**作者：** OpenTenBase 社区  
**更新时间：** 2024-05  
**版本：** 1.0