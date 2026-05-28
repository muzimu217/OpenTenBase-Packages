#!/bin/bash
# OpenTenBase RPM Repository Setup Script
# Usage: curl -sSL https://raw.githubusercontent.com/muzimu217/OpenTenBase-deb/main/scripts/setup-rpm.sh | sudo bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

REPO_BASE_URL="https://muzimu217.github.io/OpenTenBase-deb/rpm"
GPG_KEY_URL="${REPO_BASE_URL}/gpg-key.asc"

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script requires root privileges"
        echo "Please use: sudo bash $0"
        exit 1
    fi
}

detect_os() {
    log_step "Detecting operating system ..."

    if [ ! -f /etc/os-release ]; then
        log_error "Cannot detect operating system"
        exit 1
    fi

    . /etc/os-release

    case "$ID" in
        rocky|almalinux|centos|rhel)
            case "$VERSION_ID" in
                8*|9*)
                    REPO_SUBDIR="el${VERSION_ID%%.*}"
                    ;;
                *)
                    log_warn "$ID $VERSION_ID not tested, using el9 repo"
                    REPO_SUBDIR="el9"
                    ;;
            esac
            ;;
        fedora)
            REPO_SUBDIR="fedora"
            ;;
        openeuler)
            REPO_SUBDIR="openeuler"
            ;;
        *)
            log_error "Unsupported distribution: $ID"
            echo "Supported: Rocky Linux 8/9, AlmaLinux 8/9, CentOS Stream 8/9, Fedora 40+, openEuler 22.03+"
            exit 1
            ;;
    esac

    ARCH=$(uname -m)
    log_info "Detected: $ID $VERSION_ID ($ARCH)"
}

add_gpg_key() {
    log_step "Adding GPG key ..."

    rpm --import "$GPG_KEY_URL" 2>/dev/null || {
        log_warn "rpm --import failed, trying alternative method"
        curl -fsSL "$GPG_KEY_URL" -o /tmp/opentenbase-gpg-key.asc
        rpm --import /tmp/opentenbase-gpg-key.asc
        rm -f /tmp/opentenbase-gpg-key.asc
    }

    log_info "GPG key imported"
}

configure_repo() {
    log_step "Configuring YUM/DNF repository ..."

    local repo_url="${REPO_BASE_URL}/${REPO_SUBDIR}/${ARCH}"

    cat > /etc/yum.repos.d/opentenbase.repo << EOF
[opentenbase]
name=OpenTenBase Packages
baseurl=${repo_url}
enabled=1
gpgcheck=1
gpgkey=${GPG_KEY_URL}
EOF

    chmod 644 /etc/yum.repos.d/opentenbase.repo
    log_info "Repository configured: /etc/yum.repos.d/opentenbase.repo"
}

update_cache() {
    log_step "Updating package cache ..."

    if command -v dnf &>/dev/null; then
        dnf makecache 2>/dev/null || log_warn "dnf makecache failed"
    else
        yum makecache 2>/dev/null || log_warn "yum makecache failed"
    fi

    log_info "Package cache updated"
}

show_install_info() {
    echo ""
    echo "========================================"
    echo -e "${GREEN}  OpenTenBase repository configured!${NC}"
    echo "========================================"
    echo ""
    echo "Install OpenTenBase:"
    echo ""
    echo "  # Full package (recommended)"
    if command -v dnf &>/dev/null; then
        echo "  sudo dnf install opentenbase"
    else
        echo "  sudo yum install opentenbase"
    fi
    echo ""
    echo "  # Or install individual components"
    echo "  # opentenbase-server"
    echo "  # opentenbase-client"
    echo "  # opentenbase-contrib"
    echo ""
    echo "Quick start:"
    echo "  opentenbase-ctl init    # Initialize cluster"
    echo "  opentenbase-ctl start   # Start all nodes"
    echo "  opentenbase-ctl status  # Check status"
    echo ""
    echo "========================================"
}

main() {
    echo "========================================"
    echo "  OpenTenBase RPM Repository Setup"
    echo "========================================"
    echo ""

    check_root
    detect_os
    add_gpg_key
    configure_repo
    update_cache
    show_install_info
}

main "$@"
