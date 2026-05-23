#!/bin/bash
# OpenTenBase RPM 构建脚本
# 用法: bash build-rpm.sh <tarball_path>
# 示例: bash build-rpm.sh /path/to/opentenbase-5.0-aarch64.tar.gz

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARBALL="$1"

if [ -z "$TARBALL" ]; then
    echo "用法: bash build-rpm.sh <tarball_path>"
    echo "示例: bash build-rpm.sh /path/to/opentenbase-5.0-aarch64.tar.gz"
    exit 1
fi

if [ ! -f "$TARBALL" ]; then
    err "找不到文件: $TARBALL"
fi

# 检查 rpmbuild
if ! command -v rpmbuild &>/dev/null; then
    err "rpmbuild 未安装，请先安装 rpm-build 包"
fi

log "使用 tarball: $TARBALL"

# 创建 rpmbuild 目录结构
RPMBUILD_DIR="$HOME/rpmbuild"
mkdir -p "$RPMBUILD_DIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# 复制源文件和 spec
cp "$TARBALL" "$RPMBUILD_DIR/SOURCES/"
cp "$SCRIPT_DIR/opentenbase.spec" "$RPMBUILD_DIR/SPECS/"

log "开始构建 RPM..."
rpmbuild -ba "$RPMBUILD_DIR/SPECS/opentenbase.spec"

log "=========================================="
log "RPM 构建完成！"
log "=========================================="
log "RPM 包位置: $RPMBUILD_DIR/RPMS/aarch64/"
ls -lh "$RPMBUILD_DIR/RPMS/aarch64/"*.rpm 2>/dev/null
log "=========================================="
log "安装命令: sudo rpm -ivh $RPMBUILD_DIR/RPMS/aarch64/opentenbase-*.rpm"
log "=========================================="
