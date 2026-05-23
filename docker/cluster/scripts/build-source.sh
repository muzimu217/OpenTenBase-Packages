#!/bin/bash
# OpenTenBase 源码编译脚本
# 用法: ./build-source.sh [opentenbase_source_dir]

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# 默认路径
SOURCE_DIR="${1:-/data/opentenbase/source}"
BUILD_DIR="/data/opentenbase/build"
INSTALL_DIR="/data/opentenbase/install"

# 检查源码目录
check_source() {
    log_step "检查源码目录: $SOURCE_DIR"
    
    if [ ! -d "$SOURCE_DIR" ]; then
        log_error "源码目录不存在: $SOURCE_DIR"
        log_info "请执行: git clone https://github.com/Tencent/OpenTenBase.git $SOURCE_DIR"
        exit 1
    fi

    if [ ! -f "$SOURCE_DIR/configure" ]; then
        log_warn "未找到 configure 文件，尝试生成..."
        cd "$SOURCE_DIR"
        if [ -f "autogen.sh" ]; then
            ./autogen.sh || {
                log_error "autogen.sh 执行失败"
                exit 1
            }
        else
            log_error "无法生成 configure 文件"
            exit 1
        fi
    fi

    log_info "源码目录检查通过"
}

# 安装编译依赖
install_dependencies() {
    log_step "检查编译依赖..."
    
    # 检查 gcc
    if ! command -v gcc &> /dev/null; then
        log_error "gcc 未安装"
        exit 1
    fi
    
    # 检查 make
    if ! command -v make &> /dev/null; then
        log_error "make 未安装"
        exit 1
    fi
    
    log_info "编译依赖检查通过"
}

# 配置编译选项
configure_build() {
    log_step "配置编译选项..."
    
    cd "$SOURCE_DIR"
    
    # 清理之前的构建
    make distclean 2>/dev/null || true
    
    # 创建构建目录
    mkdir -p "$BUILD_DIR"
    
    # 配置选项
    ./configure \
        --prefix="$INSTALL_DIR" \
        --enable-debug \
        --enable-cassert \
        --enable-depend \
        --with-openssl \
        --with-pam \
        --with-ldap \
        --with-libxml \
        --with-libcurl \
        --with-lz4 \
        --with-zstd \
        --with-uuid=e2fs \
        CFLAGS="-O2 -g" \
        --enable-thread-safety
    
    log_info "配置完成"
}

# 编译
build() {
    log_step "开始编译（这可能需要 30-60 分钟）..."
    
    cd "$SOURCE_DIR"
    
    # 使用多核编译
    CORES=$(nproc 2>/dev/null || echo "2")
    log_info "使用 $CORES 个 CPU 核心进行编译"
    
    make -j"$CORES"
    
    log_info "编译完成"
}

# 安装
install() {
    log_step "安装到 $INSTALL_DIR..."
    
    cd "$SOURCE_DIR"
    make install
    
    # 创建符号链接
    mkdir -p /usr/local/bin
    ln -sf "$INSTALL_DIR/bin"/* /usr/local/bin/ 2>/dev/null || true
    
    log_info "安装完成"
}

# 修复权限
fix_permissions() {
    log_step "修复文件权限..."
    
    chown -R opentenbase:opentenbase "$INSTALL_DIR" 2>/dev/null || true
    
    log_info "权限修复完成"
}

# 显示信息
show_info() {
    echo ""
    log_info "========================================="
    log_info "编译成功！"
    log_info "========================================="
    echo ""
    echo "安装目录: $INSTALL_DIR"
    echo "二进制文件: $INSTALL_DIR/bin"
    echo ""
    echo "主要命令:"
    echo "  GTM:     $INSTALL_DIR/bin/gtm"
    echo "  Coordinator: $INSTALL_DIR/bin/postgres --coordinator"
    echo "  Datanode:   $INSTALL_DIR/bin/postgres --datanode"
    echo ""
    log_info "现在可以运行集群了！"
    echo ""
}

# 主函数
main() {
    echo "========================================"
    echo "  OpenTenBase 源码编译脚本"
    echo "========================================"
    echo ""
    
    check_source
    install_dependencies
    configure_build
    build
    install
    fix_permissions
    show_info
}

main "$@"