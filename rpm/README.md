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
```

## 安装后配置

RPM 安装后会自动执行 `ldconfig`，库文件路径 `/usr/lib/opentenbase/lib` 已加入系统库搜索路径。

### 二进制文件位置

- 主程序：`/usr/lib/opentenbase/bin/`
- 符号链接：`/usr/bin/` (psql, initdb, pg_ctl, gtm 等)
- 库文件：`/usr/lib/opentenbase/lib/`
- 共享数据：`/usr/lib/opentenbase/share/`

### 卸载

```bash
sudo rpm -e opentenbase
```

## 支持的架构

- aarch64 (ARM64)
