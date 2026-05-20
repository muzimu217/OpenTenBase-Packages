#!/bin/bash
# OpenTenBase Integration Test Script
# Runs inside Docker container after package installation
# Usage: bash integration-test.sh
#
# This script is designed for CI environments where the test runs
# inside a Docker container with the packages pre-installed.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_info() { echo "[INFO] $1"; }

ERRORS=0

assert_command() {
    if command -v "$1" &>/dev/null; then
        log_pass "Command available: $1"
    else
        log_fail "Command not found: $1"
        ERRORS=$((ERRORS + 1))
    fi
}

assert_file() {
    if [ -f "$1" ]; then
        log_pass "File exists: $1"
    else
        log_fail "File missing: $1"
        ERRORS=$((ERRORS + 1))
    fi
}

assert_dir() {
    if [ -d "$1" ]; then
        log_pass "Directory exists: $1"
    else
        log_fail "Directory missing: $1"
        ERRORS=$((ERRORS + 1))
    fi
}

# ============================================
# Binary checks
# ============================================
log_info "=== Checking installed binaries ==="
assert_file /usr/lib/opentenbase/bin/postgres
assert_file /usr/lib/opentenbase/bin/psql
assert_file /usr/lib/opentenbase/bin/initdb
assert_file /usr/lib/opentenbase/bin/pg_ctl
assert_file /usr/lib/opentenbase/bin/pg_config
assert_command opentenbase-ctl

# ============================================
# Library checks
# ============================================
log_info "=== Checking libraries ==="
assert_dir /usr/lib/opentenbase/lib
assert_file /usr/lib/opentenbase/lib/libpq.so

# ============================================
# Config checks
# ============================================
log_info "=== Checking configuration ==="
assert_file /etc/opentenbase/opentenbase.conf
assert_file /etc/opentenbase/gtm.conf.template
assert_file /etc/opentenbase/postgresql.conf.coord.template
assert_file /etc/opentenbase/postgresql.conf.dn.template
assert_file /etc/opentenbase/pg_hba.conf.template

# ============================================
# Version check
# ============================================
log_info "=== Checking version ==="
VERSION=$(/usr/lib/opentenbase/bin/pg_config --version 2>/dev/null || echo "unknown")
log_info "pg_config version: $VERSION"

if echo "$VERSION" | grep -q "PostgreSQL"; then
    log_pass "Version string is valid"
else
    log_fail "Invalid version string: $VERSION"
    ERRORS=$((ERRORS + 1))
fi

# ============================================
# Summary
# ============================================
echo ""
if [ "$ERRORS" -eq 0 ]; then
    log_pass "All integration checks passed!"
    exit 0
else
    log_fail "$ERRORS check(s) failed!"
    exit 1
fi
