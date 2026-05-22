# OpenTenBase 高级功能

> 本文档介绍 OpenTenBase 的高级功能和特性，帮助您充分发挥分布式数据库的能力。

---

## 1. 数据分区

OpenTenBase 支持表分区，将大表分成多个物理分区，提升查询性能和管理效率。

### 1.1 分区类型

#### 1.1.1 范围分区（RANGE）

按数值范围分区，适合时间序列数据。

```sql
-- 创建按日期范围分区的订单表
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    order_date DATE NOT NULL,
    amount DECIMAL(10,2),
    status VARCHAR(20)
) 
DISTRIBUTE BY HASH(order_id)
PARTITION BY RANGE (order_date)
(
    PARTITION p2023 VALUES LESS THAN ('2024-01-01'),
    PARTITION p2024_q1 VALUES LESS THAN ('2024-04-01'),
    PARTITION p2024_q2 VALUES LESS THAN ('2024-07-01'),
    PARTITION p2024_q3 VALUES LESS THAN ('2024-10-01'),
    PARTITION p2024_q4 VALUES LESS THAN ('2025-01-01'),
    PARTITION pmax VALUES LESS THAN (MAXVALUE)
);

-- 插入数据自动路由到对应分区
INSERT INTO orders VALUES 
(1, 100, '2024-03-15', 150.00, 'completed'),
(2, 101, '2024-06-20', 200.00, 'pending'),
(3, 102, '2024-09-25', 180.00, 'shipped');
```

#### 1.1.2 列表分区（LIST）

按离散值列表分区。

```sql
-- 创建按地区分区的销售表
CREATE TABLE sales (
    sale_id BIGINT,
    region VARCHAR(50) NOT NULL,
    amount DECIMAL(10,2),
    sale_date DATE
) 
DISTRIBUTE BY HASH(sale_id)
PARTITION BY LIST (region)
(
    PARTITION p_east VALUES ('华东', '华南'),
    PARTITION p_north VALUES ('华北', '东北'),
    PARTITION p_west VALUES ('西北', '西南'),
    PARTITION p_other VALUES (DEFAULT)
);
```

#### 1.1.3 哈希分区（HASH）

按哈希值分区，均匀分布数据。

```sql
-- 创建哈希分区的用户表
CREATE TABLE users (
    user_id BIGINT,
    username VARCHAR(100),
    email VARCHAR(100),
    created_at TIMESTAMP
) 
DISTRIBUTE BY HASH(user_id)
PARTITION BY HASH (user_id)
(
    PARTITION p0,
    PARTITION p1,
    PARTITION p2,
    PARTITION p3
);
```

### 1.2 分区管理操作

#### 1.2.1 查看分区信息

```sql
-- 查看表的分区
SELECT 
    schemaname,
    tablename,
    partitionname,
    partitiontype,
    partitionboundary
FROM pg_partition 
WHERE tablename = 'orders';

-- 查看分区大小
SELECT 
    partitionname,
    pg_size_pretty(pg_total_relation_size(partitionname::regclass)) AS size
FROM pg_partition 
WHERE tablename = 'orders';
```

#### 1.2.2 添加分区

```sql
-- 为范围分区表添加新分区
ALTER TABLE orders ADD PARTITION p2025_q1 
VALUES LESS THAN ('2025-04-01');

-- 为列表分区表添加新分区
ALTER TABLE sales ADD PARTITION p_south 
VALUES ('华中');
```

#### 1.2.3 删除分区

```sql
-- 删除分区（同时删除分区数据）
ALTER TABLE orders DROP PARTITION p2023;

-- 删除分区但保留数据（需要先导出）
-- 1. 创建临时表保存数据
CREATE TABLE orders_temp AS 
SELECT * FROM orders WHERE order_date >= '2023-01-01';

-- 2. 删除分区
ALTER TABLE orders DROP PARTITION p2023;

-- 3. 重新导入数据
INSERT INTO orders SELECT * FROM orders_temp;
```

#### 1.2.4 交换分区

将普通表与分区交换，用于批量数据加载。

```sql
-- 创建临时表
CREATE TABLE orders_staging (
    LIKE orders INCLUDING ALL
);

-- 加载大量数据到临时表
\copy orders_staging FROM '/data/orders.csv' CSV

-- 交换分区
ALTER TABLE orders EXCHANGE PARTITION p2024_q1 
WITH TABLE orders_staging;

-- 删除临时表
DROP TABLE orders_staging;
```

### 1.3 分区裁剪（Partition Pruning）

查询时自动跳过不相关的分区，提升性能。

```sql
-- 只扫描 p2024_q1 分区
EXPLAIN SELECT * FROM orders 
WHERE order_date >= '2024-01-01' AND order_date < '2024-04-01';

-- 执行计划中显示：
-- Partition Prune: "p2024_q1"
```

---

## 2. 全局索引

全局索引支持跨分区的唯一索引，确保数据的全局唯一性。

### 2.1 创建全局唯一索引

```sql
-- 在分区表上创建全局唯一索引
CREATE UNIQUE INDEX GLOBAL idx_orders_order_id 
ON orders (order_id);

-- 创建全局普通索引
CREATE INDEX GLOBAL idx_orders_user_date 
ON orders (user_id, order_date);
```

### 2.2 全局索引限制

- 全局索引不支持部分索引（WHERE 条件）
- 全局索引不支持表达式索引
- 全局索引维护成本较高

### 2.3 本地索引 vs 全局索引

```sql
-- 本地索引：每个分区独立维护
CREATE INDEX idx_orders_date 
ON orders (order_date);

-- 全局索引：跨分区维护唯一性
CREATE UNIQUE INDEX GLOBAL idx_orders_id 
ON orders (order_id);
```

**选择建议：**
- 本地索引：适合分区查询性能优化
- 全局索引：确保全局唯一性，查询跨分区数据

---

## 3. 物化视图

物化视图是预先计算并存储的查询结果，提升复杂查询性能。

### 3.1 创建物化视图

```sql
-- 创建销售汇总物化视图
CREATE MATERIALIZED VIEW mv_sales_summary AS
SELECT 
    region,
    product_category,
    DATE_TRUNC('month', sale_date) AS month,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount,
    AVG(amount) AS avg_amount
FROM sales
GROUP BY region, product_category, month
WITH DATA;

-- 创建唯一索引
CREATE UNIQUE INDEX mv_sales_summary_idx 
ON mv_sales_summary (region, product_category, month);
```

### 3.2 刷新物化视图

```sql
-- 完全刷新（CONCURRENTLY 避免锁表）
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_sales_summary;

-- 完全刷新（可能锁表）
REFRESH MATERIALIZED VIEW mv_sales_summary;
```

### 3.3 物化视图应用场景

1. **报表查询**：预计算汇总数据
2. **复杂连接**：避免重复执行复杂 JOIN
3. **实时统计**：定期刷新统计数据

```sql
-- 查询物化视图（比原始查询快得多）
SELECT * FROM mv_sales_summary 
WHERE region = '华东' AND month = '2024-03-01';
```

---

## 4. 表空间

表空间允许将数据库对象存储在不同的物理位置。

### 4.1 创建表空间

```bash
# 创建表空间目录
sudo mkdir -p /data/opentenbase/fast_storage
sudo chown opentenbase:opentenbase /data/opentenbase/fast_storage
```

```sql
-- 创建表空间
CREATE TABLESPACE fast_storage 
LOCATION '/data/opentenbase/fast_storage';

-- 创建表空间
CREATE TABLESPACE archive_storage 
LOCATION '/data/opentenbase/archive_storage';
```

### 4.2 使用表空间

```sql
-- 在指定表空间创建表
CREATE TABLE hot_data (
    id BIGINT,
    data TEXT
) TABLESPACE fast_storage;

-- 移动表到其他表空间
ALTER TABLE hot_data SET TABLESPACE archive_storage;

-- 在指定表空间创建索引
CREATE INDEX idx_hot_data_id 
ON hot_data (id) TABLESPACE fast_storage;
```

### 4.3 表空间应用场景

1. **性能优化**：热点数据放在 SSD，冷数据放在 HDD
2. **成本优化**：历史数据放在低成本存储
3. **I/O 隔离**：不同业务使用不同存储设备

---

## 5. 复杂查询优化

### 5.1 CTE（Common Table Expression）

使用 CTE 提高复杂查询的可读性和性能。

```sql
-- 使用 CTE 计算多层汇总
WITH regional_sales AS (
    -- 第一层：按地区汇总
    SELECT 
        region,
        SUM(amount) AS total_sales
    FROM sales
    GROUP BY region
),
top_regions AS (
    -- 第二层：筛选 Top 5 地区
    SELECT region, total_sales
    FROM regional_sales
    ORDER BY total_sales DESC
    LIMIT 5
)
-- 最终查询
SELECT 
    r.region,
    r.total_sales,
    r.total_sales * 100.0 / rs.total_global AS percentage
FROM top_regions r
CROSS JOIN (SELECT SUM(total_sales) AS total_global FROM regional_sales) rs
ORDER BY r.total_sales DESC;
```

### 5.2 窗口函数

窗口函数用于复杂的分析计算。

```sql
-- 计算移动平均
SELECT 
    sale_date,
    amount,
    AVG(amount) OVER (
        ORDER BY sale_date 
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS moving_avg_3day,
    SUM(amount) OVER (
        ORDER BY sale_date 
        RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW
    ) AS sum_7day
FROM sales
ORDER BY sale_date;

-- 计算排名
SELECT 
    product_id,
    sales_count,
    RANK() OVER (ORDER BY sales_count DESC) AS rank,
    DENSE_RANK() OVER (ORDER BY sales_count DESC) AS dense_rank,
    ROW_NUMBER() OVER (ORDER BY sales_count DESC) AS row_num
FROM (
    SELECT product_id, COUNT(*) AS sales_count
    FROM sales
    GROUP BY product_id
) t;
```

### 5.3 分布式 Join 优化

#### 5.3.1 选择合适的分布键

```sql
-- 不好的分布键：导致大量数据重分布
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    amount DECIMAL
) DISTRIBUTE BY HASH(order_id);  -- order_id 对连接没有帮助

CREATE TABLE order_items (
    item_id BIGINT,
    order_id BIGINT,
    product_id BIGINT,
    quantity INT
) DISTRIBUTE BY HASH(item_id);   -- item_id 与 orders 无关

-- 优化：使用相同的分布键
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    amount DECIMAL
) DISTRIBUTE BY HASH(order_id);

CREATE TABLE order_items (
    item_id BIGINT,
    order_id BIGINT,
    product_id BIGINT,
    quantity INT
) DISTRIBUTE BY HASH(order_id);  -- 与 orders 相同，避免重分布
```

#### 5.3.2 使用复制表

```sql
-- 小表使用复制表，避免广播
CREATE TABLE product_categories (
    category_id INT PRIMARY KEY,
    category_name VARCHAR(100)
) DISTRIBUTE BY REPLICATION;

-- 连接时无需广播，减少网络传输
SELECT 
    p.product_name,
    c.category_name,
    s.amount
FROM products p
JOIN product_categories c ON p.category_id = c.category_id
JOIN sales s ON p.product_id = s.product_id;
```

### 5.4 查询提示（Hints）

使用查询提示优化执行计划。

```sql
-- 强制使用 Hash Join
/*+ HashJoin(s o) */
SELECT * FROM sales s 
JOIN orders o ON s.order_id = o.order_id;

-- 强制使用 Nested Loop
/*+ NestLoop(s o) */
SELECT * FROM sales s 
JOIN orders o ON s.order_id = o.order_id;
```

---

## 6. 并行查询

OpenTenBase 支持并行查询，充分利用多核 CPU。

### 6.1 配置并行查询

```sql
-- 设置并行工作进程数
SET max_parallel_workers_per_gather = 4;

-- 设置并行度
SET parallel_tuple_cost = 0.01;
SET parallel_setup_cost = 100;
```

### 6.2 并行查询示例

```sql
-- 并行扫描大表
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM large_table;

-- 输出中显示：
-- -> Parallel Seq Scan on large_table
```

### 6.3 并行创建索引

```sql
-- 并行创建索引
CREATE INDEX CONCURRENTLY idx_large_table_col 
ON large_table (column) 
WITH (parallel_workers = 4);
```

---

## 7. 数据导入导出

### 7.1 批量导入

#### 7.1.1 使用 COPY

```sql
-- 从 CSV 文件导入
COPY orders FROM '/data/orders.csv' 
WITH (
    FORMAT CSV,
    HEADER,
    DELIMITER ',',
    ENCODING 'UTF8'
);

-- 导出到 CSV
COPY orders TO '/data/orders_export.csv' 
WITH (
    FORMAT CSV,
    HEADER,
    DELIMITER ','
);
```

#### 7.1.2 使用 pg_bulkload

OpenTenBase 提供高性能批量加载工具。

```bash
# 创建控制文件
cat > orders.ctl << EOF
TABLE = orders
TYPE = CSV
INFILE = /data/orders.csv
DELIMITER = ','
QUOTE = '"'
ESCAPE = '\'
SKIP = 1
DIRECT = TRUE
EOF

# 执行批量加载
pg_bulkload -d opentenbase -U opentenbase orders.ctl
```

### 7.2 数据导出

#### 7.2.1 使用 pg_dump

```bash
# 导出整个数据库
pg_dump -h localhost -p 15432 -U opentenbase \
    -f backup.sql opentenbase

# 只导出表结构
pg_dump -h localhost -p 15432 -U opentenbase \
    --schema-only -f schema.sql opentenbase

# 只导出数据
pg_dump -h localhost -p 15432 -U opentenbase \
    --data-only -f data.sql opentenbase
```

#### 7.2.2 导出特定表

```bash
# 导出特定表
pg_dump -h localhost -p 15432 -U opentenbase \
    -t orders -f orders.sql opentenbase

# 导出多个表
pg_dump -h localhost -p 15432 -U opentenbase \
    -t orders -t order_items -f tables.sql opentenbase
```

---

## 8. 存储过程和函数

### 8.1 PL/pgSQL 存储过程

```sql
-- 创建存储过程
CREATE OR REPLACE PROCEDURE process_orders()
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_count INT;
BEGIN
    -- 查询待处理订单
    SELECT COUNT(*) INTO v_order_count
    FROM orders
    WHERE status = 'pending';
    
    -- 处理订单
    UPDATE orders
    SET status = 'processed',
        processed_at = NOW()
    WHERE status = 'pending';
    
    -- 记录日志
    INSERT INTO processing_logs (message, order_count, created_at)
    VALUES ('Orders processed', v_order_count, NOW());
    
    COMMIT;
END;
$$;

-- 调用存储过程
CALL process_orders();
```

### 8.2 函数

```sql
-- 创建函数
CREATE OR REPLACE FUNCTION get_user_total_amount(p_user_id BIGINT)
RETURNS DECIMAL
LANGUAGE plpgsql
AS $$
DECLARE
    v_total DECIMAL;
BEGIN
    SELECT COALESCE(SUM(amount), 0) INTO v_total
    FROM orders
    WHERE user_id = p_user_id;
    
    RETURN v_total;
END;
$$;

-- 调用函数
SELECT get_user_total_amount(100);
```

### 8.3 触发器

```sql
-- 创建触发器函数
CREATE OR REPLACE FUNCTION update_user_balance()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status = 'completed' THEN
        UPDATE user_balance
        SET balance = balance - NEW.amount
        WHERE user_id = NEW.user_id;
    END IF;
    
    RETURN NEW;
END;
$$;

-- 创建触发器
CREATE TRIGGER trg_update_balance
AFTER INSERT OR UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION update_user_balance();
```

---

## 9. 全局序列

全局序列确保在分布式环境下生成唯一的序列号。

### 9.1 创建全局序列

```sql
-- 创建全局序列
CREATE GLOBAL SEQUENCE global_order_id
START WITH 1
INCREMENT BY 1
MINVALUE 1
NO MAXVALUE
CACHE 20;

-- 使用全局序列
INSERT INTO orders (order_id, user_id, amount)
VALUES (NEXTVAL('global_order_id'), 100, 150.00);

-- 批量获取序列值
SELECT NEXTVAL('global_order_id') FROM generate_series(1, 10);
```

### 9.2 序列管理

```sql
-- 查看序列当前值
SELECT last_value FROM global_order_id;

-- 重置序列
SELECT setval('global_order_id', 1, false);

-- 修改序列属性
ALTER SEQUENCE global_order_id INCREMENT BY 10;
```

---

## 10. 全局约束

OpenTenBase 支持跨节点的约束检查。

### 10.1 全局主键

```sql
-- 创建全局主键
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    amount DECIMAL,
    PRIMARY KEY (order_id)  -- 自动创建全局唯一索引
) DISTRIBUTE BY HASH(order_id);
```

### 10.2 全局外键

```sql
-- 创建全局外键
CREATE TABLE order_items (
    item_id BIGINT,
    order_id BIGINT,
    product_id BIGINT,
    quantity INT,
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
) DISTRIBUTE BY HASH(order_id);

-- 启用外键检查
SET enable_foreignkey = on;
```

### 10.3 约束检查开销

全局约束会增加事务开销，建议：
- 在数据导入期间临时禁用
- 定期维护和重建约束

```sql
-- 禁用外键检查
SET enable_foreignkey = off;

-- 导入数据...
INSERT INTO order_items VALUES ...

-- 重新启用
SET enable_foreignkey = on;
```

---

## 11. 性能调优

### 11.1 Work_mem 调优

```sql
-- 为复杂查询增加工作内存
SET work_mem = '256MB';

-- 永久设置（需要重启）
ALTER SYSTEM SET work_mem = '256MB';
```

### 11.2 随机页面成本

```sql
-- SSD 存储降低随机 I/O 成本
SET random_page_cost = 1.1;  -- 默认 4.0

-- HDD 存储保持默认或更高
SET random_page_cost = 4.0;
```

### 11.3 统计信息收集

```sql
-- 手动收集统计信息
ANALYZE orders;

-- 收集更详细的统计信息
ANALYZE orders (column1, column2);

-- 收集整个数据库的统计信息
ANALYZE;
```

### 11.4 查询重写

```sql
-- 启用查询重写
SET enable_query_rewrite = on;

-- 创建物化视图
CREATE MATERIALIZED VIEW mv_summary AS
SELECT user_id, COUNT(*), SUM(amount)
FROM orders
GROUP BY user_id;

-- 查询自动重写为物化视图
SELECT user_id, COUNT(*), SUM(amount)
FROM orders
GROUP BY user_id;
-- 等价于：
-- SELECT * FROM mv_summary;
```

---

## 12. 安全增强

### 12.1 行级安全（Row-Level Security）

```sql
-- 启用行级安全
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- 创建策略：用户只能看到自己的订单
CREATE POLICY user_orders_policy ON orders
FOR SELECT
USING (user_id = current_user_id());

-- 创建策略：用户只能修改自己的订单
CREATE POLICY user_update_policy ON orders
FOR UPDATE
USING (user_id = current_user_id());
```

### 12.2 列级权限

```sql
-- 创建视图隐藏敏感列
CREATE VIEW orders_public AS
SELECT 
    order_id,
    user_id,
    order_date
FROM orders;

-- 授予视图访问权限
GRANT SELECT ON orders_public TO public;

-- 拒绝直接访问表
REVOKE SELECT ON orders FROM public;
```

### 12.3 SSL 连接

```bash
# 配置 SSL
# postgresql.conf
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'

# pg_hba.conf
hostssl all all 0.0.0.0/0 md5
```

---

## 13. 监控和诊断

### 13.1 慢查询日志

```sql
-- 记录执行时间超过 1 秒的查询
SET log_min_duration_statement = 1000;

-- 记录所有查询
SET log_statement = 'all';

-- 查看慢查询
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    max_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;
```

### 13.2 查询计划分析

```sql
-- 详细分析执行计划
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT * FROM orders 
WHERE user_id = 100 AND order_date > '2024-01-01';

-- 输出包含：
-- - 执行时间
-- - 缓冲区命中
-- - 详细的节点信息
```

### 13.3 性能视图

```sql
-- 表统计信息
SELECT * FROM pg_stat_user_tables;

-- 索引使用情况
SELECT * FROM pg_stat_user_indexes;

-- 活跃连接
SELECT * FROM pg_stat_activity;
```

---

## 14. 总结

OpenTenBase 提供了丰富的高级功能：

1. **数据分区**：提升大表查询性能
2. **全局索引**：确保跨分区唯一性
3. **物化视图**：预计算复杂查询
4. **复杂查询优化**：CTE、窗口函数、查询提示
5. **并行查询**：充分利用多核 CPU
6. **数据导入导出**：高效批量操作
7. **存储过程**：业务逻辑封装
8. **全局序列和约束**：分布式数据完整性
9. **性能调优**：灵活的参数配置
10. **安全增强**：多层安全保护

掌握这些高级功能，可以充分发挥 OpenTenBase 分布式数据库的能力。

---

## 15. 延伸阅读

- [03-architecture.md](./03-architecture.md)：架构详解
- [05-troubleshoot.md](./05-troubleshoot.md)：故障排查
- [06-best-practices.md](./06-best-practices.md)：最佳实践

---

**作者：** OpenTenBase 社区  
**更新时间：** 2024-05  
**版本：** 1.0