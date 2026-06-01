# OpenTenBase 故障排查

> 本文档提供常见问题的诊断和解决方法，帮助您快速定位和解决问题。

---

## 1. 连接问题

### 1.1 无法连接到数据库

**症状：**
```
psql: could not connect to server: Connection refused
```

**诊断步骤：**

```bash
# 1. 检查节点状态
opentenbase-ctl status all

# 2. 检查 Coordinator 是否运行
ps aux | grep postgres | grep coord

# 3. 检查端口是否监听
netstat -tlnp | grep 15432
```

**常见原因和解决方案：**

| 原因 | 解决方案 |
|------|---------|
| 节点未启动 | `opentenbase-ctl start all` |
| 端口被占用 | 修改 `postgresql.conf` 中的 `port` |
| 防火墙阻止 | 检查防火墙规则 |
| 监听地址配置错误 | 检查 `postgresql.conf` 中的 `listen_addresses` |

### 1.2 连接数过多

**症状：**
```
FATAL: remaining connection slots are reserved for non-replication superuser connections
```

**诊断：**

```sql
-- 查看当前连接数
SELECT count(*) FROM pg_stat_activity;

-- 查看最大连接数
SHOW max_connections;

-- 查看活跃连接
SELECT 
    datname,
    usename,
    state,
    count(*) AS connection_count
FROM pg_stat_activity
GROUP BY datname, usename, state
ORDER BY connection_count DESC;
```

**解决方案：**

```sql
-- 临时增加连接数（需要重启）
ALTER SYSTEM SET max_connections = 500;
-- 然后重启：opentenbase-ctl restart all

-- 或使用连接池
-- 配置 pgBouncer 或其他连接池工具
```

### 1.3 连接超时

**症状：**
```
FATAL: terminating connection due to administrator command
```

**诊断：**

```sql
-- 查看连接超时设置
SHOW statement_timeout;
SHOW idle_in_transaction_session_timeout;
```

**解决方案：**

```sql
-- 调整超时参数
ALTER SYSTEM SET statement_timeout = '300s';
ALTER SYSTEM SET idle_in_transaction_session_timeout = '600s';
```

---

## 2. 性能问题

### 2.1 查询慢

**诊断步骤：**

```sql
-- 1. 查看执行计划
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT * FROM orders WHERE user_id = 100;

-- 2. 查看慢查询日志
tail -f /opt/opentenbase/coord/log/postgresql-*.log | grep "duration:"

-- 3. 使用 pg_stat_statements
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    rows
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;
```

**常见优化方法：**

#### 2.1.1 缺少索引

```sql
-- 查看表的索引
SELECT indexname, indexdef 
FROM pg_indexes 
WHERE tablename = 'orders';

-- 创建索引
CREATE INDEX idx_orders_user_id ON orders(user_id);

-- 检查索引使用情况
SELECT * FROM pg_stat_user_indexes 
WHERE relname = 'orders';
```

#### 2.1.2 数据倾斜

```sql
-- 检查数据分布
SELECT 
    node_name,
    count(*) AS row_count,
    pg_size_pretty(pg_total_relation_size('orders'::regclass)) AS size
FROM pgxc_node
CROSS JOIN (SELECT * FROM orders) t
GROUP BY node_name
ORDER BY row_count;
```

#### 2.1.3 统计信息过时

```sql
-- 手动收集统计信息
ANALYZE orders;

-- 收集所有表的统计信息
ANALYZE;

-- 查看统计信息更新时间
SELECT 
    relname,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables;
```

### 2.2 锁等待

**症状：**
查询长时间不返回，没有 CPU 消耗。

**诊断：**

```sql
-- 查看锁等待
SELECT 
    pid,
    usename,
    datname,
    state,
    query,
    wait_event_type,
    wait_event
FROM pg_stat_activity
WHERE wait_event IS NOT NULL;

-- 查看锁信息
SELECT 
    l.locktype,
    l.database,
    l.relation,
    l.page,
    l.tuple,
    l.virtualxid,
    l.transactionid,
    l.classid,
    l.objid,
    l.objsubid,
    l.virtualtransaction,
    l.pid,
    l.mode,
    l.granted,
    a.usename,
    a.query,
    a.query_start,
    age(now(), a.query_start) AS "age"
FROM pg_locks l
LEFT JOIN pg_stat_activity a ON l.pid = a.pid
WHERE NOT l.granted
ORDER BY a.query_start;
```

**解决方案：**

```sql
-- 查找阻塞的进程
SELECT blocked_locks.pid AS blocked_pid,
       blocked_activity.usename AS blocked_user,
       blocking_locks.pid AS blocking_pid,
       blocking_activity.usename AS blocking_user,
       blocked_activity.query AS blocked_statement,
       blocking_activity.query AS current_statement_in_blocking_process,
       blocked_activity.application_name AS blocked_application,
       blocking_activity.application_name AS blocking_application
FROM pg_catalog.pg_locks blocked_locks
    JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
    JOIN pg_catalog.pg_locks blocking_locks 
        ON blocking_locks.locktype = blocked_locks.locktype
        AND blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE
        AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
        AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
        AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
        AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
        AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
        AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
        AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
        AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
        AND blocking_locks.pid != blocked_locks.pid
    JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.GRANTED;

-- 终止阻塞进程（谨慎使用）
SELECT pg_terminate_backend(blocking_pid);
```

### 2.3 事务膨胀

**症状：**
数据库体积异常增大，性能下降。

**诊断：**

```sql
-- 查看最老的事务
SELECT 
    pid,
    usename,
    state,
    query_start,
    state_change,
    backend_start,
    age(now(), query_start) AS age
FROM pg_stat_activity
WHERE state IN ('idle in transaction', 'active')
ORDER BY query_start
LIMIT 10;

-- 查看事务 ID 消耗
SELECT datname, age(datfrozenxid) 
FROM pg_database
WHERE datname = current_database();
```

**解决方案：**

```sql
-- 1. 终止长时间运行的事务
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
AND query_start < now() - interval '1 hour';

-- 2. 执行 VACUUM
VACUUM VERBOSE;

-- 3. 执行 VACUUM FULL（会锁表）
VACUUM FULL orders;

-- 4. 配置自动清理
ALTER SYSTEM SET autovacuum = on;
ALTER SYSTEM SET autovacuum_max_workers = 3;
ALTER SYSTEM SET autovacuum_naptime = '1min';
```

---

## 3. 复制问题

### 3.1 Datanode 主从复制延迟

**诊断：**

```sql
-- 在 Standby 节点查询
SELECT 
    pg_is_in_recovery(),
    pg_last_xact_replay_timestamp(),
    now() - pg_last_xact_replay_timestamp() AS replication_lag;

-- 在 Primary 节点查询
SELECT 
    application_name,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn
FROM pg_stat_replication;
```

**常见原因：**

| 原因 | 解决方案 |
|------|---------|
| 网络延迟 | 优化网络，检查带宽 |
| Standby 性能不足 | 升级 Standby 硬件 |
| 大事务 | 避免单事务过大 |
| 写入压力大 | 限制写入速率 |

### 3.2 复制中断

**症状：**
Standby 节点报错，停止复制。

**诊断：**

```bash
# 查看日志
tail -f /opt/opentenbase/datanode2/log/postgresql-*.log

# 常见错误：
# - could not receive data from WAL stream
# - invalid record length at ...
# - FATAL: could not connect to the primary server
```

**解决方案：**

```bash
# 1. 检查网络连通性
ping <primary_ip>

# 2. 重建 Standby（注意：会丢失数据）
# 在 Primary 节点
pg_basebackup -h <standby_ip> -D /opt/opentenbase/datanode_standby/data \
    -P -U repuser -X stream -C -S datanode_standby_slot

# 3. 或使用 pg_rewind 快速恢复
pg_rewind --target-pgdata=/opt/opentenbase/datanode2/data \
    --source-server="host=<primary_ip> port=5432 user=repuser dbname=postgres"
```

### 3.3 GTM Standby 不同步

**诊断：**

```bash
# 查看 GTM 日志
tail -f /opt/opentenbase/gtm_standby/log/gtm.log

# 检查 GTM Standby 进程
ps aux | grep gtm | grep standby
```

**解决方案：**

```bash
# 1. 检查 GTM Master 配置
cat /opt/opentenbase/gtm/data/gtm.conf | grep standby
# 确保 gtm_standby_host 和 gtm_standby_port 配置正确

# 2. 重启 GTM Standby
gtm_ctl -D /opt/opentenbase/gtm_standby/data restart

# 3. 如果仍不同步，重建 Standby
rm -rf /opt/opentenbase/gtm_standby/data
opentenbase-ctl init gtm_standby
opentenbase-ctl start gtm_standby
```

---

## 4. GTM 问题

### 4.1 GTM 线程绑定失败

**症状：**
```
FATAL: binding threads failed for 22
```

**原因：**
GTM 尝试绑定的线程数超过了 CPU 核心数。

**解决方案：**

```bash
# 1. 检查 CPU 核心数
nproc

# 2. 检查 GTM 配置
grep thread_count /opt/opentenbase/gtm/data/gtm.conf

# 3. 修改配置（确保不超过 CPU 核心数）
vim /opt/opentenbase/gtm/data/gtm.conf
# 设置：thread_count = 2（或等于 nproc 的值）
# 注意：gtm_thread_count 不是合法参数，请使用 thread_count

# 4. 重启 GTM
gtm_ctl -D /opt/opentenbase/gtm/data restart
```

**自动化修复：**

使用 `opentenbase-ctl` 脚本自动检测并设置合适的线程数：

```bash
# 脚本会自动检测 CPU 核心数并设置合适的 GTM 线程数
opentenbase-ctl init gtm
```

### 4.2 GTM 连接超时

**症状：**
Coordinator 或 Datanode 无法连接到 GTM。

**诊断：**

```bash
# 检查 GTM 是否运行
ps aux | grep gtm

# 检查端口
netstat -tlnp | grep 6666

# 检查日志
tail -f /opt/opentenbase/gtm/log/gtm.log
```

**解决方案：**

```bash
# 1. 检查配置文件
cat /opt/opentenbase/gtm/data/gtm.conf | grep -E "(listen_addresses|port)"

# 2. 检查防火墙
sudo firewall-cmd --list-ports
sudo firewall-cmd --add-port=6666/tcp --permanent

# 3. 重启 GTM
gtm_ctl -D /opt/opentenbase/gtm/data restart

# 4. 如果 GTM 损坏，重建 GTM
rm -rf /opt/opentenbase/gtm/data
opentenbase-ctl init gtm
opentenbase-ctl start gtm
```

### 4.3 GTM 内存不足

**症状：**
GTM 进程 OOM（Out of Memory）。

**诊断：**

```bash
# 查看 GTM 内存使用
ps aux | grep gtm | awk '{print $6/1024 " MB"}'

# 查看 dmesg 日志
dmesg | grep -i "out of memory"
```

**解决方案：**

```ini
# 调整 GTM 配置
# gtm.conf
gtm_max_connections = 100  # 降低最大连接数
gtm_buffer_size = 2048      # 降低缓冲区大小
```

---

## 5. 数据一致性问题

### 5.1 分布式事务失败

**症状：**
分布式事务部分提交部分失败。

**诊断：**

```sql
-- 查看分布式事务日志
SELECT * FROM pgxc_node_error_history;

-- 检查节点状态
SELECT * FROM pgxc_node WHERE node_is_active = false;
```

**解决方案：**

```sql
-- 1. 检查所有节点状态
SELECT node_name, node_host, node_port, node_is_active 
FROM pgxc_node;

-- 2. 重启失败节点
opentenbase-ctl restart datanode1

-- 3. 检查 GTM 状态
gtm_ctl -D /opt/opentenbase/gtm/data status

-- 4. 如需手动修复，使用两阶段提交
PREPARE TRANSACTION 'transaction_id';
COMMIT PREPARED 'transaction_id';
-- 或
ROLLBACK PREPARED 'transaction_id';
```

### 5.2 数据不一致

**症状：**
不同 Datanode 上的数据不一致。

**诊断：**

```sql
-- 统计各节点的行数
SELECT 
    node_name,
    count(*)
FROM pgxc_node
CROSS JOIN (SELECT * FROM orders) t
GROUP BY node_name;

-- 检查主从数据一致性
-- 在 Primary 和 Standby 执行相同的统计查询
SELECT count(*) FROM orders;
```

**解决方案：**

```bash
# 1. 检查复制延迟
# 在 Standby 节点执行
SELECT pg_last_xact_replay_timestamp();

# 2. 等待同步完成
# 正常情况下复制会自动同步

# 3. 如需强制同步，重建 Standby
pg_basebackup -h <standby_ip> -D /opt/opentenbase/datanode_standby/data \
    -P -U repuser -X stream -C -S datanode_standby_slot
```

---

## 6. 磁盘空间问题

### 6.1 磁盘空间不足

**诊断：**

```bash
# 查看磁盘使用情况
df -h

# 查看数据库大小
SELECT 
    datname,
    pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database
ORDER BY pg_database_size(datname) DESC;

# 查看表大小
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;
```

**解决方案：**

```sql
-- 1. 清理旧数据
DELETE FROM orders WHERE order_date < '2023-01-01';
VACUUM orders;

-- 2. 使用表空间将大表移到其他磁盘
-- 见 04-advanced.md 表空间章节

-- 3. 压缩表
ALTER TABLE orders SET (toast_compression = 'lz4');
VACUUM FULL orders;

-- 4. 清理 WAL 日志
# postgresql.conf
archive_mode = on
archive_command = 'cp %p /backup/wal/%f'

# 定期清理
find /backup/wal -mtime +7 -delete
```

### 6.2 WAL 日志膨胀

**症状：**
`pg_wal` 目录占用大量空间。

**诊断：**

```bash
# 查看 WAL 目录大小
du -sh /opt/opentenbase/datanode1/data/pg_wal

# 查看 WAL 文件数量
ls /opt/opentenbase/datanode1/data/pg_wal | wc -l
```

**解决方案：**

```sql
-- 1. 检查复制状态
SELECT * FROM pg_stat_replication;

-- 2. 增加保留时间
ALTER SYSTEM SET wal_keep_size = '2GB';

-- 3. 减少复制延迟
# 检查网络，优化查询

-- 4. 手动检查点
CHECKPOINT;
```

---

## 7. 备份恢复问题

### 7.1 pg_basebackup 失败

**症状：**
备份命令报错。

**诊断：**

```bash
# 尝试备份
pg_basebackup -h localhost -p 5432 -U opentenbase \
    -D /backup/standby -P -X stream -C -S standby_slot

# 常见错误：
# - could not connect to server
# - FATAL: no pg_hba.conf entry for replication connection
```

**解决方案：**

```ini
# 1. 配置 pg_hba.conf
host    replication     repuser         0.0.0.0/0               md5

# 2. 配置 postgresql.conf
wal_level = replica
max_wal_senders = 5
wal_keep_size = 1GB

# 3. 重启节点
opentenbase-ctl restart datanode1

# 4. 重新尝试备份
```

### 7.2 恢复失败

**症状：**
Standby 节点无法启动。

**诊断：**

```bash
# 查看日志
tail -f /opt/opentenbase/datanode2/log/postgresql-*.log

# 检查 recovery.conf 或 postgresql.auto.conf
cat /opt/opentenbase/datanode2/data/postgresql.auto.conf | grep primary_conninfo
```

**解决方案：**

```bash
# 1. 检查主从配置
cat /opt/opentenbase/datanode2/data/postgresql.auto.conf

# 2. 验证网络连接
ping <primary_ip>

# 3. 重建 Standby
rm -rf /opt/opentenbase/datanode2/data/*
pg_basebackup -h <primary_ip> -D /opt/opentenbase/datanode2/data \
    -P -U repuser -X stream -C -S datanode2_slot

# 4. 启动 Standby
opentenbase-ctl start datanode2
```

---

## 8. 日志分析

### 8.1 常见日志级别

```ini
# postgresql.conf
log_min_messages = warning    # 记录警告及以上
log_error_verbosity = verbose # 详细错误信息
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h ' # 日志前缀
```

### 8.2 关键日志位置

```bash
# Coordinator 日志
/opt/opentenbase/coord/log/postgresql-<date>.log

# GTM 日志
/opt/opentenbase/gtm/log/gtm.log

# Datanode 日志
/opt/opentenbase/datanode1/log/postgresql-<date>.log
/opt/opentenbase/datanode2/log/postgresql-<date>.log
```

### 8.3 日志分析技巧

```bash
# 1. 查看错误日志
grep -i "error" /opt/opentenbase/coord/log/postgresql-*.log

# 2. 查看慢查询
grep "duration:" /opt/opentenbase/coord/log/postgresql-*.log \
    | awk '{if ($NF > 1000) print}'

# 3. 查看连接失败
grep "FATAL" /opt/opentenbase/coord/log/postgresql-*.log

# 4. 实时监控
tail -f /opt/opentenbase/coord/log/postgresql-*.log | grep -i "error"
```

---

## 9. 监控指标

### 9.1 关键性能指标

```sql
-- 1. 查询性能
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    rows
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;

-- 2. 锁等待
SELECT count(*) 
FROM pg_locks 
WHERE NOT granted;

-- 3. 连接数
SELECT count(*) FROM pg_stat_activity;

-- 4. 事务状态
SELECT 
    state,
    count(*) AS count
FROM pg_stat_activity
GROUP BY state;
```

### 9.2 集群健康检查

```sql
-- 查看所有节点状态
SELECT 
    node_name,
    node_type,
    node_host,
    node_port,
    node_is_active
FROM pgxc_node
ORDER BY node_type, node_name;

-- 查看复制延迟
-- 在每个 Datanode Standby 执行
SELECT 
    pg_is_in_recovery(),
    pg_last_xact_replay_timestamp(),
    now() - pg_last_xact_replay_timestamp() AS lag;

-- 查看表分布
SELECT 
    schemaname,
    tablename,
    distributiontype,
    node_count
FROM pgxc_class;
```

---

## 10. 常见错误代码

| 错误代码 | 说明 | 解决方案 |
|---------|------|---------|
| 08001 | 连接失败 | 检查网络、防火墙、节点状态 |
| 08003 | 连接不存在 | 重新建立连接 |
| 08006 | 连接异常 | 检查服务器状态 |
| 22012 | 除以零 | 检查 SQL 逻辑 |
| 23502 | NOT NULL 约束 | 检查数据完整性 |
| 23503 | 外键约束 | 检查关联数据 |
| 23505 | 唯一约束冲突 | 检查重复数据 |
| 40001 | 序列化失败 | 重试事务 |
| 57014 | 查询取消 | 增加超时时间 |
| 53200 | 内存不足 | 增加 work_mem |
| 54000 | 超过连接限制 | 增加 max_connections |
| 55000 | 对象不存在 | 检查对象名 |

---

## 11. 应急处理流程

### 11.1 节点故障

```bash
# 1. 确认故障节点
opentenbase-ctl status all

# 2. 尝试重启
opentenbase-ctl restart <node>

# 3. 如果重启失败，检查日志
tail -f /opt/opentenbase/<node>/log/*.log

# 4. 如果数据损坏，恢复备份
# 见备份恢复章节
```

### 11.2 集群故障

```bash
# 1. 停止所有节点
opentenbase-ctl stop all

# 2. 检查 GTM
gtm_ctl -D /opt/opentenbase/gtm/data status

# 3. 启动 GTM
opentenbase-ctl start gtm

# 4. 启动 Datanode
opentenbase-ctl start datanode

# 5. 启动 Coordinator
opentenbase-ctl start coord

# 6. 验证集群
psql -h localhost -p 15432 -U opentenbase -c "SELECT * FROM pgxc_node;"
```

### 11.3 数据损坏

```bash
# 1. 立即停止写操作
opentenbase-ctl stop coord

# 2. 检查数据完整性
pg_checksums -D /opt/opentenbase/datanode1/data

# 3. 恢复最近备份
pg_restore -h localhost -p 15432 -U opentenbase \
    -d opentenbase /backup/opentenbase.dump

# 4. 重放 WAL 日志
# PostgreSQL 会自动恢复
```

---

## 12. 获取帮助

### 12.1 日志收集

```bash
# 收集集群日志
mkdir -p /tmp/opentenbase_logs
cp /opt/opentenbase/*/log/*.log /tmp/opentenbase_logs/

# 收集配置文件
cp /opt/opentenbase/*/data/*.conf /tmp/opentenbase_logs/

# 收集系统信息
dmesg > /tmp/opentenbase_logs/dmesg.log
ps aux > /tmp/opentenbase_logs/ps.log
netstat -tlnp > /tmp/opentenbase_logs/netstat.log

# 打包
tar -czf opentenbase_logs.tar.gz -C /tmp opentenbase_logs
```

### 12.2 社区资源

- **OpenTenBase GitHub**: https://github.com/Tencent/OpenTenBase
- **文档**: https://docs.opentenbase.org
- **Issue**: https://github.com/Tencent/OpenTenBase/issues

---

## 13. 总结

故障排查的关键步骤：

1. **收集信息**：日志、错误信息、系统状态
2. **定位问题**：根据症状缩小问题范围
3. **分析原因**：结合架构和配置分析根本原因
4. **实施修复**：选择合适的解决方案
5. **验证结果**：确认问题已解决
6. **预防措施**：总结经验，避免重复发生

**重要原则：**
- 不要在不确定的情况下随意修改配置
- 修改前务必备份配置文件
- 优先使用最小影响方案
- 记录所有操作和结果

---

## 14. 延伸阅读

- [03-architecture.md](./03-architecture.md)：架构详解
- [04-advanced.md](./04-advanced.md)：高级功能
- [06-best-practices.md](./06-best-practices.md)：最佳实践

---

**作者：** OpenTenBase 社区  
**更新时间：** 2024-05  
**版本：** 1.0