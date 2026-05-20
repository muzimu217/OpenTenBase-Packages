#!/bin/bash
# OpenTenBase GPG 签名脚本
# 用法: ./sign-packages.sh [选项]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 显示帮助
show_help() {
    echo "OpenTenBase GPG 签名脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -k, --key KEY          指定 GPG 密钥 ID"
    echo "  -p, --packages DIR     指定软件包目录"
    echo "  -r, --repo DIR         指定仓库目录"
    echo "  -e, --export FILE      导出公钥到文件"
    echo "  -g, --generate         生成新的 GPG 密钥"
    echo "  -l, --list             列出所有 GPG 密钥"
    echo "  -h, --help             显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -g                           # 生成新密钥"
    echo "  $0 -k ABCD1234 -p ./packages    # 签名软件包"
    echo "  $0 -e public.key                # 导出公钥"
}

# 生成 GPG 密钥
generate_gpg_key() {
    log_step "生成 GPG 密钥..."
    
    echo ""
    echo "请选择密钥类型:"
    echo "1. RSA (默认)"
    echo "2. Ed25519"
    read -p "选择 [1]: " key_type
    
    case "$key_type" in
        2)
            key_type="Ed25519"
            key_length=""
            ;;
        *)
            key_type="RSA"
            key_length="4096"
            ;;
    esac
    
    read -p "请输入姓名: " name
    read -p "请输入邮箱: " email
    read -p "请输入注释 (可选): " comment
    
    echo ""
    log_info "正在生成 GPG 密钥..."
    echo ""
    echo "请按照提示操作："
    echo "1. 选择密钥有效期（建议：0 = 永不过期）"
    echo "2. 确认信息"
    echo "3. 设置密码（可选，但建议设置）"
    echo ""
    
    if [ "$key_type" = "Ed25519" ]; then
        gpg --full-generate-key --expert << EOF
Key-Type: eddsa
Key-Curve: ed25519
Name-Real: $name
Name-Email: $email
Name-Comment: $comment
Expire-Date: 0
%commit
EOF
    else
        gpg --full-generate-key << EOF
Key-Type: RSA
Key-Length: $key_length
Name-Real: $name
Name-Email: $email
Name-Comment: $comment
Expire-Date: 0
%commit
EOF
    fi
    
    log_info "GPG 密钥已生成"
    
    # 列出密钥
    echo ""
    log_info "生成的密钥："
    gpg --list-keys --keyid-format long "$email"
}

# 列出 GPG 密钥
list_gpg_keys() {
    log_step "列出 GPG 密钥..."
    
    echo ""
    echo "=== 公钥 ==="
    gpg --list-keys --keyid-format long
    
    echo ""
    echo "=== 私钥 ==="
    gpg --list-secret-keys --keyid-format long
}

# 导出公钥
export_public_key() {
    local key_id=$1
    local output_file=$2
    
    log_step "导出公钥..."
    
    if [ -z "$output_file" ]; then
        output_file="opentenbase-gpg-key.asc"
    fi
    
    if [ -z "$key_id" ]; then
        # 使用默认密钥
        gpg --armor --export > "$output_file"
    else
        gpg --armor --export "$key_id" > "$output_file"
    fi
    
    log_info "公钥已导出到: $output_file"
    echo ""
    echo "请将此文件上传到仓库服务器，并确保可以通过以下 URL 访问："
    echo "  https://opentenbase.org/repo/gpg-key.asc"
}

# 签名软件包
sign_packages() {
    local key_id=$1
    local packages_dir=$2
    
    log_step "签名软件包..."
    
    if [ -z "$packages_dir" ]; then
        log_error "请指定软件包目录"
        return 1
    fi
    
    if [ ! -d "$packages_dir" ]; then
        log_error "软件包目录不存在: $packages_dir"
        return 1
    fi
    
    local count=0
    for deb in "$packages_dir"/*.deb; do
        if [ -f "$deb" ]; then
            log_info "签名: $(basename $deb)"
            
            if [ -z "$key_id" ]; then
                dpkg-sig --sign builder "$deb"
            else
                dpkg-sig --sign builder -k "$key_id" "$deb"
            fi
            
            ((count++))
        fi
    done
    
    log_info "已签名 $count 个软件包"
}

# 签名仓库
sign_repo() {
    local key_id=$1
    local repo_dir=$2
    
    log_step "签名仓库..."
    
    if [ -z "$repo_dir" ]; then
        log_error "请指定仓库目录"
        return 1
    fi
    
    if [ ! -d "$repo_dir" ]; then
        log_error "仓库目录不存在: $repo_dir"
        return 1
    fi
    
    cd "$repo_dir"
    
    # 生成 InRelease 文件
    log_info "生成 InRelease 文件..."
    if [ -z "$key_id" ]; then
        gpg --armor --detach-sign --output dists/*/InRelease dists/*/Release
    else
        gpg --armor --detach-sign -k "$key_id" --output dists/*/InRelease dists/*/Release
    fi
    
    # 生成 Release.gpg 文件
    log_info "生成 Release.gpg 文件..."
    if [ -z "$key_id" ]; then
        gpg --armor --detach-sign --output dists/*/Release.gpg dists/*/Release
    else
        gpg --armor --detach-sign -k "$key_id" --output dists/*/Release.gpg dists/*/Release
    fi
    
    log_info "仓库已签名"
}

# 验证签名
verify_signatures() {
    local packages_dir=$1
    
    log_step "验证签名..."
    
    if [ -z "$packages_dir" ]; then
        log_error "请指定软件包目录"
        return 1
    fi
    
    if [ ! -d "$packages_dir" ]; then
        log_error "软件包目录不存在: $packages_dir"
        return 1
    fi
    
    local success_count=0
    local fail_count=0
    
    for deb in "$packages_dir"/*.deb; do
        if [ -f "$deb" ]; then
            echo -n "验证: $(basename $deb) ... "
            
            if dpkg-sig --verify "$deb" &> /dev/null; then
                echo -e "${GREEN}✓ 有效${NC}"
                ((success_count++))
            else
                echo -e "${RED}✗ 无效${NC}"
                ((fail_count++))
            fi
        fi
    done
    
    echo ""
    echo "验证结果："
    echo "  有效: $success_count"
    echo "  无效: $fail_count"
    
    if [ "$fail_count" -gt 0 ]; then
        return 1
    fi
}

# 主函数
main() {
    local key_id=""
    local packages_dir=""
    local repo_dir=""
    local export_file=""
    local generate=false
    local list=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -k|--key)
                key_id="$2"
                shift 2
                ;;
            -p|--packages)
                packages_dir="$2"
                shift 2
                ;;
            -r|--repo)
                repo_dir="$2"
                shift 2
                ;;
            -e|--export)
                export_file="$2"
                shift 2
                ;;
            -g|--generate)
                generate=true
                shift
                ;;
            -l|--list)
                list=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo "========================================"
    log_step "OpenTenBase GPG 签名工具"
    echo "========================================"
    echo ""
    
    # 生成密钥
    if [ "$generate" = true ]; then
        generate_gpg_key
        exit 0
    fi
    
    # 列出密钥
    if [ "$list" = true ]; then
        list_gpg_keys
        exit 0
    fi
    
    # 导出公钥
    if [ -n "$export_file" ]; then
        export_public_key "$key_id" "$export_file"
        exit 0
    fi
    
    # 签名软件包
    if [ -n "$packages_dir" ]; then
        sign_packages "$key_id" "$packages_dir"
        exit 0
    fi
    
    # 签名仓库
    if [ -n "$repo_dir" ]; then
        sign_repo "$key_id" "$repo_dir"
        exit 0
    fi
    
    # 如果没有参数，显示帮助
    show_help
}

# 执行主函数
main "$@"
