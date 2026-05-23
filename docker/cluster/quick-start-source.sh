#!/bin/bash
# OpenTenBase 源码编译快速启动脚本
# 用法: ./quick-start-source.sh [opentenbase_source_path]

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

# 检查依赖
check_dependencies() {
    log_step "检查依赖..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    if ! command -v docker compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi
    
    log_info "依赖检查通过"
}

# 检查源码
check_source() {
    SOURCE_PATH="${1:-./opentenbase-source}"
    
    log_step "检查源码路径: $SOURCE_PATH"
    
    if [ ! -d "$SOURCE_PATH" ]; then
        log_warn "源码目录不存在: $SOURCE_PATH"
        read -p "是否下载 OpenTenBase 源码? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "下载 OpenTenBase 源码..."
            git clone https://github.com/Tencent/OpenTenBase.git "$SOURCE_PATH"
        else
            log_error "请指定有效的源码路径"
            exit 1
        fi
    fi
    
    if [ ! -f "$SOURCE_PATH/configure" ] && [ ! -f "$SOURCE_PATH/Makefile" ]; then
        log_error "源码目录无效（未找到 configure 或 Makefile）"
        exit 1
    fi
    
    # 获取绝对路径
    SOURCE_PATH=$(cd "$SOURCE_PATH" && pwd)
    log_info "源码路径: $SOURCE_PATH"
}

# 构建镜像
build_image() {
    log_step "构建 Docker 镜像..."
    
    cd "$(dirname "$0")/../.."
    
    log_info "这可能需要几分钟..."
    docker compose -f docker/cluster/docker-compose.source.yml build builder
    
    log_info "镜像构建完成"
}

# 启动编译容器
start_builder() {
    log_step "启动编译容器..."
    
    cd "$(dirname "$0")/../.."
    
    export OPENTENBASE_SOURCE="$SOURCE_PATH"
    docker compose -f docker/cluster/docker-compose.source.yml up -d builder
    
    log_info "编译容器已启动"
}

# 编译 OpenTenBase
build_opentenbase() {
    log_step "开始编译 OpenTenBase..."
    log_warn "这可能需要 30-60 分钟，请耐心等待..."
    
    # 在容器内执行编译
    docker exec -it opentenbase-builder /bin/bash -c "
        set -e
        cd /data/opentenbase/source
        
        # 检查是否有 configure
        if [ ! -f configure ]; then
            echo '生成 configure 文件...'
            ./autogen.sh || true
        fi
        
        # 执行编译脚本
        /data/opentenbase/build-source.sh /data/opentenbase/source
    "
    
    log_info "OpenTenBase 编译完成"
}

# 启动集群
start_cluster() {
    log_step "启动 OpenTenBase 集群..."
    
    cd "$(dirname "$0")/../.."
    
    export OPENTENBASE_SOURCE="$SOURCE_PATH"
    docker compose -f docker/cluster/docker-compose.source.yml up -d gtm cn dn1 dn2
    
    log_info "等待集群启动..."
    sleep 30
    
    # 检查集群状态
    docker compose -f docker/cluster/docker-compose.source.yml ps
    
    log_info "集群启动完成"
}

# 测试集群
test_cluster() {
    log_step "测试集群连接..."
    
    # 等待集群完全就绪
    sleep 10
    
    # 尝试连接
    if docker exec opentenbase-cn-source /data/opentenbase/install/bin/psql -h localhost -U opentenbase -d opentenbase -c "SELECT * FROM pgxc_node;" &> /dev/null; then
        log_info "集群测试成功！"
        docker exec opentenbase-cn-source /data/opentenbase/install/bin/psql -h localhost -U opentenbase -d opentenbase -c "SELECT * FROM pgxc_node;"
    else
        log_warn "集群可能还在启动中，请稍后手动测试"
        log_info "测试命令:"
        echo "  docker exec -it opentenbase-cn-source /data/opentenbase/install/bin/psql -h localhost -U opentenbase -d opentenbase"
    fi
}

# 显示信息
show_info() {
    echo ""
    log_info "========================================="
    log_info "部署完成！"
    log_info "========================================="
    echo ""
    echo "集群信息:"
    echo "  GTM:          localhost:6666"
    echo "  Coordinator:  localhost:15432"
    echo "  Datanode 1:   localhost:15433"
    echo "  Datanode 2:   localhost:15434"
    echo ""
    echo "常用命令:"
    echo "  查看状态:    docker compose -f docker/cluster/docker-compose.source.yml ps"
    echo "  查看日志:    docker compose -f docker/cluster/docker-compose.source.yml logs"
    echo "  停止集群:    docker compose -f docker/cluster/docker-compose.source.yml down"
    echo "  启动集群:    docker compose -f docker/cluster/docker-compose.source.yml up -d"
    echo "  重新编译:    docker exec -it opentenbase-builder bash"
    echo "              cd /data/opentenbase/source && make -j\$(nproc) && make install"
    echo ""
    echo "连接集群:"
    echo "  docker exec -it opentenbase-cn-source /data/opentenbase/install/bin/psql -h localhost -U opentenbase -d opentenbase"
    echo ""
    echo "修改源码后重新编译:"
    echo "  1. 在宿主机修改源码: $SOURCE_PATH"
    echo "  2. 进入编译容器: docker exec -it opentenbase-builder bash"
    echo "  3. 清理并重新编译: cd /data/opentenbase/source && make clean && make -j\$(nproc) && make install"
    echo "  4. 重启集群: docker compose -f docker/cluster/docker-compose.source.yml restart cn dn1 dn2"
    echo ""
}

# 主函数
main() {
    echo "========================================"
    echo "  OpenTenBase 源码编译快速部署"
    echo "========================================"
    echo ""
    
    check_dependencies
    check_source "$1"
    
    read -p "是否开始构建镜像? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        build_image
    else
        log_info "跳过镜像构建，假设镜像已存在"
    fi
    
    start_builder
    
    read -p "是否开始编译 OpenTenBase? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        build_opentenbase
    else
        log_info "跳过编译，假设编译产物已存在"
    fi
    
    start_cluster
    test_cluster
    show_info
}

main "$@"