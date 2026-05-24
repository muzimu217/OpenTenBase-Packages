Name:           opentenbase
Version:        %{!?otb_version:5.0}%{?otb_version}
Release:        1
Summary:        OpenTenBase distributed database system
License:        BSD
URL:            https://github.com/OpenTenBase/OpenTenBase
Source0:        opentenbase-%{version}-%{_arch}.tar.gz
Source1:        opentenbase-ctl
Source2:        pg_hba.conf.template

%define otb_ver %{version}
%define otb_prefix /usr/lib/opentenbase/%{otb_ver}

# Filter out GLIBC_PRIVATE dependency (false positive from RPM auto-detection)
%global __requires_exclude ^libc\\.so\\.6\\(GLIBC_PRIVATE\\)

BuildRequires:  gcc gcc-c++ make bison flex perl
BuildRequires:  readline-devel zlib-devel openssl-devel pam-devel
BuildRequires:  libxml2-devel openldap-devel libuuid-devel
BuildRequires:  libcurl-devel lz4-devel
BuildRequires:  pkg-config libtool

# Optional: may not be available in all repos (CRB/PowerTools)
# BuildRequires:  zstd-devel libssh2-devel

Requires:       openssl-libs readline zlib libxml2 openldap libuuid libcurl lz4-libs

%description
OpenTenBase is an advanced enterprise-level database management system
based on PostgreSQL. It supports distributed transactions, parallel
computing, security, management, and audit functions.

%prep
%setup -q -c -n opentenbase

%build
# Find the source directory (could be OpenTenBase, OpenTenBase-main, etc.)
SRCDIR=$(find . -maxdepth 1 -type d -name 'OpenTenBase*' -o -name 'opentenbase*' | head -1)
if [ -z "$SRCDIR" ]; then
    # Maybe the content is directly in the current directory
    if [ -f configure ]; then
        SRCDIR="."
    else
        echo "ERROR: Cannot find source directory"
        exit 1
    fi
fi
cd "$SRCDIR"

# GCC compatibility patches
if grep -q 'typedef char bool;' src/include/c.h 2>/dev/null; then
    sed -i 's/typedef char bool;/typedef _Bool bool;/' src/include/c.h
fi
if grep -q 'false, false, NULL' src/gtm/main/gtm_opt.c 2>/dev/null; then
    sed -i '/enable_gtm_resqueue_debug/,/},/{s/true, false, NULL/true, NULL, NULL, false, NULL/; s/false, false, NULL/false, NULL, NULL, false, NULL/}' src/gtm/main/gtm_opt.c
fi

# Patch configure to use dynamic linking instead of hardcoded /usr/local/lib paths
sed -i 's|/usr/local/lib/liblz4.a|-llz4|g' configure

# If zstd-devel is not installed, create stub headers and library symlink
# so configure can pass its zstd detection check
if [ ! -f /usr/include/zstd.h ]; then
    mkdir -p /usr/include
    cat > /usr/include/zstd.h << 'ZSTD_STUB'
/* Stub zstd.h for builds without zstd-devel */
#ifndef ZSTD_H_STUB
#define ZSTD_H_STUB
#include <stddef.h>
typedef enum { ZSTD_fast=1, ZSTD_dfast=2, ZSTD_greedy=3, ZSTD_lazy=4, ZSTD_lazy2=5, ZSTD_btlazy2=6, ZSTD_btopt=7, ZSTD_btultra=8 } ZSTD_strategy;
typedef struct ZSTD_CCtx_s ZSTD_CCtx;
static inline ZSTD_CCtx* ZSTD_createCCtx(void) { return (ZSTD_CCtx*)0; }
static inline size_t ZSTD_freeCCtx(ZSTD_CCtx* c) { (void)c; return 0; }
static inline size_t ZSTD_compress(void* d, size_t ds, const void* s, size_t ss, int l) { (void)d; (void)ds; (void)s; (void)ss; (void)l; return 0; }
static inline size_t ZSTD_compressBound(size_t s) { (void)s; return 0; }
static inline unsigned ZSTD_isError(size_t c) { (void)c; return 1; }
static inline const char* ZSTD_getErrorName(size_t c) { (void)c; return "zstd not available"; }
static inline int ZSTD_maxCLevel(void) { return 0; }
static inline size_t ZSTD_CCtx_setParameter(ZSTD_CCtx* c, int p, int v) { (void)c; (void)p; (void)v; return 0; }
static inline size_t ZSTD_CCtx_setPledgedSrcSize(ZSTD_CCtx* c, size_t s) { (void)c; (void)s; return 0; }
static inline size_t ZSTD_compress2(ZSTD_CCtx* c, void* d, size_t ds, const void* s, size_t ss) { (void)c; (void)d; (void)ds; (void)s; (void)ss; return 0; }
#define ZSTD_CLEVEL_DEFAULT 3
#define ZSTD_e_continue 0
#define ZSTD_e_end 1
#endif
ZSTD_STUB
    # Create libzstd.so symlink to libzstd.so.1 if it exists
    if [ -f /usr/lib64/libzstd.so.1 ] && [ ! -f /usr/lib64/libzstd.so ]; then
        ln -s libzstd.so.1 /usr/lib64/libzstd.so
    fi
    # Also patch configure to use -lzstd instead of static lib
    sed -i 's|/usr/local/lib/libzstd.a|-lzstd|g' configure
fi


# Architecture flags
CFLAGS="-O2 -g -DNOLIC -Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration -Wno-error=int-conversion -Wno-incompatible-pointer-types"
%ifarch x86_64
CFLAGS="$CFLAGS -msse4.2 -mcrc32"
%endif
%ifarch aarch64
CFLAGS="$CFLAGS -march=armv8-a"
%endif
export CFLAGS
export LDFLAGS="-Wl,-rpath,%{otb_prefix}/lib"

CONFIGURE_OPTS="--prefix=%{otb_prefix} \
    --sysconfdir=/etc/opentenbase/%{otb_ver} \
    --datadir=%{otb_prefix}/share \
    --libdir=%{otb_prefix}/lib \
    --includedir=%{otb_prefix}/include \
    --enable-user-switch \
    --with-openssl \
    --with-uuid=e2fs \
    --with-pam \
    --with-ldap \
    --with-libxml \
    --with-lz4"

# Optional: zstd support (zstd-devel may not be available in all repos)
if [ -f /usr/include/zstd.h ] && pkg-config --exists libzstd 2>/dev/null; then
    CONFIGURE_OPTS="$CONFIGURE_OPTS --with-zstd"
    echo "NOTE: zstd-devel found, building with zstd support"
else
    echo "NOTE: zstd-devel not found, building with stub zstd support"
fi

./configure $CONFIGURE_OPTS

make -j$(nproc)

# Build contrib, but skip uuid-ossp (requires OSSP UUID not available on RPM distros)
sed -i 's/^SUBDIRS += uuid-ossp/# SUBDIRS += uuid-ossp/' contrib/Makefile
sed -i 's/^ALWAYS_SUBDIRS += uuid-ossp/# ALWAYS_SUBDIRS += uuid-ossp/' contrib/Makefile
make -C contrib -j$(nproc)

%install
SRCDIR=$(find . -maxdepth 1 -type d -name 'OpenTenBase*' -o -name 'opentenbase*' | head -1)
if [ -z "$SRCDIR" ]; then
    if [ -f Makefile ]; then
        SRCDIR="."
    else
        echo "ERROR: Cannot find source directory in install"
        exit 1
    fi
fi
cd "$SRCDIR"

make DESTDIR=%{buildroot} install
make DESTDIR=%{buildroot} -C contrib install

# Create symlinks in /usr/bin
mkdir -p %{buildroot}/usr/bin
for f in %{buildroot}%{otb_prefix}/bin/*; do
    bname=$(basename "$f")
    ln -s %{otb_prefix}/bin/"$bname" %{buildroot}/usr/bin/"$bname"
done

# Install opentenbase-ctl management script
install -m 755 %{SOURCE1} %{buildroot}/usr/bin/opentenbase-ctl

# Install pg_hba.conf template
mkdir -p %{buildroot}/etc/opentenbase/%{otb_ver}
install -m 644 %{SOURCE2} %{buildroot}/etc/opentenbase/%{otb_ver}/pg_hba.conf.template

# Install switch-version script
cat > %{buildroot}/usr/bin/opentenbase-switch-version << 'SWITCHSCRIPT'
#!/bin/bash
# opentenbase-switch-version — switch between installed OpenTenBase versions
set -e
CONF_DIR="/etc/opentenbase"
CURRENT_LINK="$CONF_DIR/current"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
check_root() { [ "$(id -u)" -eq 0 ] || { log_error "must run as root"; exit 1; }; }
list_versions() {
    local versions=()
    for dir in "$CONF_DIR"/*/; do
        [ -d "$dir" ] || continue
        local ver=$(basename "$dir")
        [ "$ver" = "current" ] && continue
        [ -f "$dir/opentenbase.conf" ] && versions+=("$ver")
    done
    echo "${versions[@]}"
}
get_current() {
    [ -L "$CURRENT_LINK" ] && basename "$(readlink -f "$CURRENT_LINK")" || echo ""
}
show_version_info() {
    local ver="$1" current=$(get_current) marker=""
    [ "$ver" = "$current" ] && marker=" ${GREEN}(active)${NC}"
    local home="" port=""
    [ -f "$CONF_DIR/$ver/opentenbase.conf" ] && {
        home=$(grep '^OTB_HOME=' "$CONF_DIR/$ver/opentenbase.conf" | cut -d'"' -f2)
        port=$(grep '^COORD_PORT=' "$CONF_DIR/$ver/opentenbase.conf" | cut -d= -f2 | tr -d ' ')
    }
    echo -e "  $ver${marker}"
    [ -n "$home" ] && echo "    prefix: $home"
    [ -n "$port" ] && echo "    coord port: $port"
}
cmd_list() {
    local versions=$(list_versions)
    [ -z "$versions" ] && { log_warn "No OpenTenBase versions found in $CONF_DIR"; exit 0; }
    echo "Installed OpenTenBase versions:"
    echo ""
    for ver in $versions; do show_version_info "$ver"; done
    echo ""
    local current=$(get_current)
    [ -n "$current" ] && log_info "Active version: $current" || log_warn "No active version set"
}
cmd_switch() {
    local target="$1"
    [ ! -d "$CONF_DIR/$target" ] && { log_error "Version $target not found"; exit 1; }
    [ ! -f "$CONF_DIR/$target/opentenbase.conf" ] && { log_error "No config for version $target"; exit 1; }
    local current=$(get_current)
    [ "$target" = "$current" ] && { log_info "Already on version $target"; return 0; }
    if pgrep -x postgres >/dev/null 2>&1 || pgrep -x gtm >/dev/null 2>&1; then
        log_warn "OpenTenBase server processes are running."
        echo "  opentenbase-ctl stop"
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r; echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
    ln -sfn "$CONF_DIR/$target" "$CURRENT_LINK"
    log_info "Switched to OpenTenBase $target"
    echo "Active config: $CONF_DIR/current/opentenbase.conf"
    local port=$(grep '^COORD_PORT=' "$CONF_DIR/$target/opentenbase.conf" | cut -d= -f2 | tr -d ' ')
    [ -n "$port" ] && echo "Coordinator port: $port"
    echo ""
    echo "To initialize and start:"
    echo "  opentenbase-ctl init"
    echo "  opentenbase-ctl start"
}
case "${1:-}" in
    -h|--help) echo "Usage: opentenbase-switch-version [version]"; cmd_list ;;
    "") cmd_list ;;
    *) check_root; cmd_switch "$1" ;;
esac
SWITCHSCRIPT
chmod 755 %{buildroot}/usr/bin/opentenbase-switch-version

# ldconfig config
mkdir -p %{buildroot}/etc/ld.so.conf.d
echo '%{otb_prefix}/lib' > %{buildroot}/etc/ld.so.conf.d/opentenbase.conf

# Versioned directories
mkdir -p %{buildroot}/etc/opentenbase/%{otb_ver}
mkdir -p %{buildroot}/var/lib/opentenbase/%{otb_ver}
mkdir -p %{buildroot}/var/log/opentenbase/%{otb_ver}
mkdir -p %{buildroot}/var/run/opentenbase

# Version marker
echo "%{otb_ver}" > %{buildroot}%{otb_prefix}/VERSION

# Generate config
cat > %{buildroot}/etc/opentenbase/%{otb_ver}/opentenbase.conf <<CONF
ENABLED_NODES="gtm dn1 coord"
OTB_USER="opentenbase"
OTB_GROUP="opentenbase"
OTB_HOME="%{otb_prefix}"
GTM_PGDATA="/var/lib/opentenbase/%{otb_ver}/gtm"
GTM_PORT=6666
GTM_LOG="/var/log/opentenbase/%{otb_ver}/gtm.log"
COORD_PGDATA="/var/lib/opentenbase/%{otb_ver}/coord"
COORD_PORT=5432
COORD_NODENAME="coord1"
COORD_LOG="/var/log/opentenbase/%{otb_ver}/coord.log"
DN1_PGDATA="/var/lib/opentenbase/%{otb_ver}/dn1"
DN1_PORT=15432
DN1_NODENAME="dn001"
DN1_LOG="/var/log/opentenbase/%{otb_ver}/dn1.log"
COORD_FORWARD_PORT=6669
DN1_FORWARD_PORT=6670
COORD_POOLER_PORT=6667
DN1_POOLER_PORT=6668
START_ORDER="gtm coord dn1"
STOP_ORDER="coord dn1 gtm"
CONF

%files
%{otb_prefix}
/usr/bin/*
/etc/ld.so.conf.d/opentenbase.conf
%dir /etc/opentenbase/%{otb_ver}
%dir /var/lib/opentenbase/%{otb_ver}
%dir /var/log/opentenbase/%{otb_ver}
%dir /var/run/opentenbase
%config(noreplace) /etc/opentenbase/%{otb_ver}/opentenbase.conf
/etc/opentenbase/%{otb_ver}/pg_hba.conf.template

%post
ldconfig
if [ ! -L /etc/opentenbase/current ]; then
    ln -sf /etc/opentenbase/%{otb_ver} /etc/opentenbase/current
fi
if ! getent group opentenbase >/dev/null 2>&1; then
    groupadd --system opentenbase 2>/dev/null || true
fi
if ! getent passwd opentenbase >/dev/null 2>&1; then
    useradd --system --gid opentenbase --home-dir /var/lib/opentenbase \
        --shell /bin/bash --comment "OpenTenBase administrator" opentenbase 2>/dev/null || true
fi
chown opentenbase:opentenbase /var/lib/opentenbase/%{otb_ver}
chown opentenbase:opentenbase /var/log/opentenbase/%{otb_ver}
chown opentenbase:opentenbase /var/run/opentenbase

%postun
ldconfig
