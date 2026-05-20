#!/bin/bash
# OpenTenBase .deb Build Script
# Usage: ./build-deb.sh [source_dir] [output_dir]

set -e

# Default paths
SOURCE_DIR="${1:-/source}"
OUTPUT_DIR="${2:-/output}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check source directory
check_source() {
    if [ ! -d "$SOURCE_DIR" ]; then
        log_error "Source directory not found: $SOURCE_DIR"
        exit 1
    fi

    if [ ! -f "$SOURCE_DIR/configure" ] && [ ! -f "$SOURCE_DIR/Makefile" ]; then
        log_error "No build files found (configure or Makefile)"
        exit 1
    fi
}

# Install build dependencies
install_dependencies() {
    log_info "Installing build dependencies..."

    apt-get update -qq
    apt-get install -y -qq \
        build-essential \
        debhelper \
        devscripts \
        fakeroot \
        quilt \
        bison \
        flex \
        perl \
        libreadline-dev \
        zlib1g-dev \
        libssl-dev \
        libpam0g-dev \
        libxml2-dev \
        libldap2-dev \
        libossp-uuid-dev \
        uuid-dev \
        libcurl4-openssl-dev \
        liblz4-dev \
        libzstd-dev \
        libssh2-1-dev \
        libatomic1 \
        pkg-config \
        libtool

    # Optional packages (may not exist on all distro versions)
    apt-get install -y libpqxx-dev 2>/dev/null || log_warn "libpqxx-dev not available"
    apt-get install -y libcli11-dev 2>/dev/null || log_warn "libcli11-dev not available"

    # IMPORTANT: Remove system libpq-dev to avoid linker picking up system libpq
    # instead of OpenTenBase's private libpq with custom functions.
    # The system libpq lacks PQconnectdbParallel, PQresultCommandId, etc.
    apt-get remove -y libpq-dev 2>/dev/null || true
    # Remove the system libpq.so symlink but keep libpq.so.5 (runtime)
    rm -f /usr/lib/x86_64-linux-gnu/libpq.so 2>/dev/null || true

    # Update shared library cache
    ldconfig

    # OpenTenBase's configure hardcodes /usr/local/lib/libzstd.a and /usr/local/lib/liblz4.a
    log_info "Setting up library symlinks for configure..."
    mkdir -p /usr/local/lib

    for f in /usr/lib/x86_64-linux-gnu/libzstd.a /usr/lib/x86_64-linux-gnu/libzstd.so \
             /usr/lib/x86_64-linux-gnu/liblz4.a /usr/lib/x86_64-linux-gnu/liblz4.so; do
        if [ -f "$f" ]; then
            ln -sf "$f" "/usr/local/lib/$(basename $f)"
        fi
    done

    # Ensure -latomic is available for 128-bit atomics
    # On Debian, libatomic.so may not exist even with libatomic1 installed.
    log_info "Setting up libatomic for 128-bit atomics..."

    # Install libatomic1 if not present
    apt-get install -y -qq libatomic1 2>/dev/null || true

    # Find and symlink libatomic.so
    if [ ! -f /usr/lib/x86_64-linux-gnu/libatomic.so ]; then
        # Try 1: gcc -print-file-name
        gcc_path=$(gcc -print-file-name=libatomic.so 2>/dev/null)
        if [ -n "$gcc_path" ] && [ -f "$gcc_path" ]; then
            ln -sf "$gcc_path" /usr/lib/x86_64-linux-gnu/libatomic.so
            log_info "Symlinked libatomic.so from gcc path: $gcc_path"
        # Try 2: Symlink from libatomic.so.1
        elif [ -f /usr/lib/x86_64-linux-gnu/libatomic.so.1 ]; then
            ln -sf /usr/lib/x86_64-linux-gnu/libatomic.so.1 /usr/lib/x86_64-linux-gnu/libatomic.so
            log_info "Symlinked libatomic.so from libatomic.so.1"
        # Try 3: Find it anywhere
        else
            found=$(find /usr/lib -name "libatomic.so*" -type f 2>/dev/null | head -1)
            if [ -n "$found" ]; then
                ln -sf "$found" /usr/lib/x86_64-linux-gnu/libatomic.so
                log_info "Symlinked libatomic.so from: $found"
            else
                log_warn "libatomic.so not found - 128-bit atomics may fail"
            fi
        fi
    fi

    # Verify libatomic.so exists and has the required symbol
    if [ -f /usr/lib/x86_64-linux-gnu/libatomic.so ]; then
        log_info "libatomic.so found at: $(readlink -f /usr/lib/x86_64-linux-gnu/libatomic.so)"
        if nm -D /usr/lib/x86_64-linux-gnu/libatomic.so 2>/dev/null | grep -q "sync_val_compare_and_swap_16"; then
            log_info "libatomic.so has __sync_val_compare_and_swap_16"
        else
            log_warn "libatomic.so does NOT have __sync_val_compare_and_swap_16"
            # Try to find it in GCC's internal libraries (gcc-12, gcc-13, etc.)
            found=0
            for gcc_ver in 13 12 11 10; do
                gcc_lib_dir="/usr/lib/gcc/x86_64-linux-gnu/$gcc_ver"
                for lib in "$gcc_lib_dir/libatomic.so" "$gcc_lib_dir/libatomic.a"; do
                    if [ -f "$lib" ]; then
                        if nm -D "$lib" 2>/dev/null | grep -q "sync_val_compare_and_swap_16" || \
                           nm "$lib" 2>/dev/null | grep -q "sync_val_compare_and_swap_16"; then
                            log_info "Found __sync_val_compare_and_swap_16 in: $lib"
                            ln -sf "$lib" "/usr/lib/x86_64-linux-gnu/$(basename $lib)"
                            found=1
                            break 2
                        fi
                    fi
                done
            done
            if [ "$found" -eq 0 ]; then
                log_warn "No libatomic with __sync_val_compare_and_swap_16 found"
                log_warn "Trying static libatomic from GCC..."
                for gcc_ver in 13 12 11 10; do
                    gcc_lib_dir="/usr/lib/gcc/x86_64-linux-gnu/$gcc_ver"
                    if [ -f "$gcc_lib_dir/libatomic.a" ]; then
                        log_info "Using static libatomic.a from gcc-$gcc_ver"
                        ln -sf "$gcc_lib_dir/libatomic.a" /usr/lib/x86_64-linux-gnu/libatomic.a
                        break
                    fi
                done
            fi
        fi
    else
        log_error "libatomic.so not found after setup!"
    fi
}

# Apply patches
apply_patches() {
    log_info "Applying patches..."

    cd "$SOURCE_DIR"

    # Apply bool/stdbool patch
    if [ -f debian/patches/01-bool-stdbool.patch ]; then
        patch -p1 < debian/patches/01-bool-stdbool.patch || true
    fi

    # Apply nolic sharding patch
    if [ -f debian/patches/02-nolic-sharding.patch ]; then
        patch -p1 < debian/patches/02-nolic-sharding.patch || true
    fi

    # Remove merge conflict artifact files
    rm -f src/interfaces/libpq/fe-connect.c.BASE.c \
          src/interfaces/libpq/fe-connect.c.LOCAL.c \
          src/interfaces/libpq/fe-connect.c.REMOTE.c 2>/dev/null || true
}

# Build packages
build_packages() {
    log_info "Building packages..."

    cd "$SOURCE_DIR"

    # Clean previous build
    fakeroot debian/rules clean || true

    # Build packages
    fakeroot debian/rules binary

    # Move to output directory
    mkdir -p "$OUTPUT_DIR"
    mv ../*.deb "$OUTPUT_DIR/"
}

# Verify packages
verify_packages() {
    log_info "Verifying packages..."

    cd "$OUTPUT_DIR"

    for deb in *.deb; do
        echo "=== $deb ==="
        dpkg-deb -I "$deb" | head -15
        echo
    done
}

# Main
main() {
    echo "========================================"
    echo "  OpenTenBase .deb Build Script"
    echo "========================================"
    echo ""

    check_source
    install_dependencies
    apply_patches
    build_packages
    verify_packages

    log_info "Build complete!"
    log_info "Packages: $OUTPUT_DIR"
}

main "$@"

