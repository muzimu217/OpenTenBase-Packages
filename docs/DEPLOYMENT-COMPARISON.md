# OpenTenBase 部署方式对比

> 详细对比预编译和源码编译两种部署方式的优缺点。

---

## 1. 快速对比表

| 特性 | 预编译方式 | 源码编译方式 |
|------|-----------|-------------|
| **部署时间** | ~2 分钟 | 30-60 分钟（首次） |
| **启动时间** | ~2 分钟 | ~2 分钟 |
| **镜像大小** | ~500 MB | ~2 GB |
| **二次开发** | ❌ 不支持 | ✅ 支持 |
| **自定义选项** | ❌ 不支持 | ✅ 支持 |
| **调试信息** | ❌ 无 | ✅ 可选 |
| **适用场景** | 生产环境 | 开发/学习环境 |
| **学习价值** | 低 | 高 |
| **性能** | 优化过 | 可自定义优化 |

---

## 2. 预编译方式

### 2.1 文件结构

```
docker-compose.yml
├── gtm          ← 使用预编译二进制
├── cn           ← 使用预编译二进制
├── dn1          ← 使用预编译二进制
└── dn2          ← 使用预编译二进制
```

### 2.2 部署步骤

```bash
# 1. 一键启动
cd opentenbase-deb/docker/cluster
docker compose up -d

# 2. 完成！
psql -h localhost -p 15432 -U opentenbase -d opentenbase
```

### 2.3 优点

✅ **快速部署**：2 分钟内完成  
✅ **简单易用**：无需编译知识  
✅ **生产就绪**：经过充分测试  
✅ **资源占用小**：镜像体积小  
✅ **跨平台**：支持多个 Linux 发行版  

### 2.4 缺点

❌ **无法二次开发**：二进制文件无法修改  
❌ **无法调试**：没有调试符号  
❌ **无法定制**：编译选项固定  
❌ **学习价值低**：看不到编译过程  

### 2.5 适用场景

- 生产环境部署
- 快速测试和验证
- 学习基础使用
- 演示和教学（快速展示）

---

## 3. 源码编译方式

### 3.1 文件结构

```
docker-compose.source.yml
├── builder      ← 编译环境（挂载源码）
├── gtm          ← 使用编译产物
├── cn           ← 使用编译产物
├── dn1          ← 使用编译产物
└── dn2          ← 使用编译产物

源码挂载:
${OPENTENBASE_SOURCE} → /data/opentenbase/source

编译产物:
/data/opentenbase/build/    ← 构建文件
/data/opentenbase/install/  ← 安装文件
```

### 3.2 部署步骤

```bash
# 1. 下载源码
git clone https://github.com/Tencent/OpenTenBase.git opentenbase-source

# 2. 启动编译环境
export OPENTENBASE_SOURCE=./opentenbase-source
docker compose -f docker-compose.source.yml up -d builder

# 3. 编译（30-60 分钟）
docker exec -it opentenbase-builder bash
/data/opentenbase/build-source.sh /data/opentenbase/source

# 4. 启动集群
docker compose -f docker-compose.source.yml up -d

# 5. 完成！
docker exec -it opentenbase-cn-source \
  /data/opentenbase/install/bin/psql -h localhost -U opentenbase -d opentenbase
```

### 3.3 二次开发流程

```bash
# 1. 在宿主机修改源码
cd opentenbase-source
vim src/backend/executor/nodeModifyTable.c

# 2. 增量编译（5-10 分钟）
docker exec -it opentenbase-builder bash
cd /data/opentenbase/source
make -j$(nproc)
make install

# 3. 重启集群测试
docker compose -f docker-compose.source.yml restart cn dn1 dn2

# 4. 测试修改
docker exec -it opentenbase-cn-source \
  /data/opentenbase/install/bin/psql -h localhost -U opentenbase -d opentenbase
```

### 3.4 优点

✅ **完整二次开发支持**  
✅ **自定义编译选项**  
✅ **调试符号可用**  
✅ **学习价值高**：理解编译过程  
✅ **性能优化**：可根据硬件定制  
✅ **贡献开源**：可以提交 PR  

### 3.5 缺点

❌ **首次编译慢**：30-60 分钟  
❌ **资源占用大**：需要更多内存和磁盘  
❌ **复杂度高**：需要编译知识  
❌ **依赖多**：需要编译工具链  

### 3.6 适用场景

- 二次开发和定制
- 性能优化研究
- 深度学习和研究
- 贡献开源项目
- 教学演示（展示编译过程）

---

## 4. 性能对比

### 4.1 编译性能

| 方式 | 首次编译 | 增量编译 | 完整重编译 |
|------|---------|---------|-----------|
| 预编译 | N/A | N/A | N/A |
| 源码编译 | 30-60 分钟 | 5-10 分钟 | 20-40 分钟 |

### 4.2 运行性能

| 方式 | 内存占用 | 磁盘占用 | 查询性能 |
|------|---------|---------|---------|
| 预编译 | ~500 MB | ~500 MB | 基准 |
| 源码编译 | ~2 GB | ~2 GB | 相同（默认）<br>可优化 |

### 4.3 开发效率

| 任务 | 预编译 | 源码编译 |
|------|-------|---------|
| 修改代码 | ❌ 不可能 | ✅ 5-10 分钟 |
| 调试 | ❌ 不可能 | ✅ 可用 GDB |
| 性能分析 | ❌ 不可能 | ✅ 可用 perf |
| 自定义选项 | ❌ 不可能 | ✅ 灵活配置 |

---

## 5. 技术细节对比

### 5.1 Dockerfile 对比

**预编译方式：**
```dockerfile
FROM centos:stream9

# 直接复制预编译的二进制
COPY --from=opentenbase-euleros /usr/lib/opentenbase /usr/lib/opentenbase
COPY opentenbase-5.0-aarch64.tar.gz /data/opentenbase/

CMD ["/usr/sbin/sshd", "-D"]
```

**源码编译方式：**
```dockerfile
FROM centos:stream9

# 安装编译工具链
RUN dnf install -y gcc make bison flex \
    openssl-devel readline-devel zlib-devel ...

# 挂载源码
VOLUME /data/opentenbase/source

# 编译脚本
COPY build-source.sh /data/opentenbase/

CMD ["/usr/sbin/sshd", "-D"]
```

### 5.2 启动流程对比

**预编译方式：**
```
1. Docker Compose 启动容器
2. 解压预编译包
3. 初始化数据库
4. 启动服务
总计：~2 分钟
```

**源码编译方式：**
```
1. Docker Compose 启动容器
2. 挂载源码到容器
3. 执行 configure
4. 编译源码 (make -jN)
5. 安装到 /usr/local (make install)
6. 初始化数据库
7. 启动服务
总计：30-60 分钟（首次）
```

### 5.3 编译选项对比

**预编译方式：**
- 固定的编译选项
- 优化级别：-O2
- 无调试符号
- 无断言检查

**源码编译方式：**
```bash
./configure \
    --prefix=/data/opentenbase/install \
    --enable-debug \              # ✅ 可选
    --enable-cassert \            # ✅ 可选
    --with-openssl \              # ✅ 可选
    --with-pam \                  # ✅ 可选
    --with-ldap \                 # ✅ 可选
    --with-libxml \               # ✅ 可选
    --with-lz4 \                  # ✅ 可选
    --with-zstd \                 # ✅ 可选
    CFLAGS="-O2 -g"               # ✅ 可自定义
```

---

## 6. 使用建议

### 6.1 选择预编译方式的场景

- ✅ **生产环境部署**：稳定、可靠
- ✅ **快速演示**：2 分钟启动，快速展示
- ✅ **学习基础**：了解基本使用
- ✅ **功能测试**：验证特定功能
- ✅ **资源受限**：内存或磁盘有限

### 6.2 选择源码编译方式的场景

- ✅ **二次开发**：需要修改源码
- ✅ **性能优化**：需要自定义编译选项
- ✅ **深度学习**：理解内部机制
- ✅ **开源贡献**：需要提交代码
- ✅ **定制需求**：添加自定义功能

### 6.3 混合使用

推荐的开发工作流：

```bash
# 1. 日常开发使用预编译方式（快速）
docker compose up -d

# 2. 修改代码后切换到源码编译
#    修改源码
vim opentenbase-source/src/backend/...

# 3. 编译测试
./quick-start-source.sh

# 4. 测试通过后使用预编译方式部署
```

---

## 7. 常见问题

### Q1: 源码编译后可以切换回预编译吗？

**答：** 可以。两种方式是独立的，可以随时切换。

```bash
# 停止源码编译集群
docker compose -f docker-compose.source.yml down

# 启动预编译集群
docker compose up -d
```

### Q2: 源码编译的产物可以导出吗？

**答：** 可以。

```bash
# 导出编译产物
docker cp opentenbase-builder:/data/opentenbase/install ./opentenbase-compiled

# 打包
tar czf opentenbase-compiled.tar.gz opentenbase-compiled/

# 在其他机器使用
docker run -v $(pwd)/opentenbase-compiled:/usr/lib/opentenbase ...
```

### Q3: 源码编译的版本可以提交到仓库吗？

**答：** 不推荐。编译产物很大（~2 GB），会导致仓库臃肿。

推荐做法：
- 使用 Docker Registry 存储编译镜像
- 或提供编译脚本，让用户自行编译

### Q4: 如何加速源码编译？

**答：** 几种方法：

1. **使用 ccache**：
```bash
dnf install -y ccache
export USE_CCACHE=1
```

2. **增量编译**：只编译修改的文件
```bash
make -j$(nproc)  # 不执行 make clean
```

3. **使用宿主机编译**（更快）：
```bash
# 在宿主机安装依赖并编译
# 然后挂载到容器
docker run -v $(pwd)/opentenbase-compiled:/usr/lib/opentenbase ...
```

### Q5: 源码编译的集群性能会比预编译差吗？

**答：** 不会。

- 默认编译选项相同（-O2）
- 运行时代码完全一样
- 如果启用调试信息，可能稍慢 5-10%

---

## 8. 总结

| 需求 | 推荐方式 | 原因 |
|------|---------|------|
| 快速部署 | 预编译 | 2 分钟启动 |
| 生产环境 | 预编译 | 稳定可靠 |
| 学习基础 | 预编译 | 简单易用 |
| 二次开发 | 源码编译 | 必需 |
| 性能优化 | 源码编译 | 可定制 |
| 开源贡献 | 源码编译 | 必需 |
| 深度学习 | 源码编译 | 可调试 |
| 资源受限 | 预编译 | 占用小 |

**核心原则**：
- **预编译方式**：快速、简单、生产就绪
- **源码编译方式**：灵活、强大、开发友好

**推荐实践**：
1. 开发者使用源码编译方式（或同时使用两种）
2. 生产环境使用预编译方式
3. 代码贡献必须通过源码编译测试

---

## 9. 延伸阅读

- [source-build-guide.md](./source-build-guide.md)：源码编译详细指南
- [01-quickstart.md](./tutorials/01-quickstart.md)：快速入门（预编译方式）
- [03-architecture.md](./tutorials/03-architecture.md)：架构详解

---

**作者：** OpenTenBase 社区  
**更新时间：** 2024-05  
**版本：** 1.0