#!/usr/bin/env bash
# =============================================================================
# OpenTenBase Advanced Test Runner
# =============================================================================
# Starts a cluster, runs all advanced test suites, then tears down.
# Designed to run after multi-node-test.sh in CI.
#
# Usage: bash test/run-advanced-tests.sh
# =============================================================================
set -e

BIN_DIR="/usr/lib/opentenbase/5.0/bin"
TEST_BASE="/tmp/otb-adv-test"
GTM_DATA="${TEST_BASE}/gtm"
COORD_DATA="${TEST_BASE}/coord"
DN_DATA="${TEST_BASE}/dn1"
LOG_DIR="${TEST_BASE}/logs"
GTM_PORT=6666
COORD_PORT=5432
DN_PORT=15432
STARTUP_TIMEOUT=30

log() { echo "[adv-test] $(date '+%H:%M:%S') $*"; }
fail() { echo "[adv-test] FAIL: $*" >&2; stop_services 2>/dev/null; rm -rf "${TEST_BASE}" 2>/dev/null; exit 1; }

check_port() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then ss -tlnp 2>/dev/null | grep -q ":${port} "
    elif command -v netstat >/dev/null 2>&1; then netstat -tlnp 2>/dev/null | grep -q ":${port} "
    else (echo >/dev/tcp/127.0.0.1/"${port}") 2>/dev/null; fi
}

wait_for_port() {
    local port="$1" timeout="$2" elapsed=0
    while ! check_port "${port}"; do
        [ "${elapsed}" -ge "${timeout}" ] && return 1
        sleep 1; elapsed=$((elapsed + 1))
    done
}

as_svc() { su -s /bin/bash -c "$1" "${SVC_USER}"; }
append_conf() { local f="$1"; shift; printf '%s\n' "$@" >> "${f}"; }

stop_services() {
    [ -d "${COORD_DATA}" ] && "${BIN_DIR}/pg_ctl" stop -D "${COORD_DATA}" -Z coordinator -m fast 2>/dev/null || true
    [ -d "${DN_DATA}" ] && "${BIN_DIR}/pg_ctl" stop -D "${DN_DATA}" -Z datanode -m fast 2>/dev/null || true
    [ -d "${GTM_DATA}" ] && "${BIN_DIR}/gtm_ctl" stop -D "${GTM_DATA}" -Z gtm -m fast 2>/dev/null || true
}

# Root check
[ "$(id -u)" -eq 0 ] || { log "Not root, re-executing with sudo..."; exec sudo "$0" "$@"; }

# Resolve service user
SVC_USER=""
if id opentenbase >/dev/null 2>&1; then SVC_USER="opentenbase"
elif id postgres >/dev/null 2>&1; then SVC_USER="postgres"
else
    if command -v useradd >/dev/null 2>&1; then useradd -r -s /bin/bash -d "${TEST_BASE}" otbtest 2>/dev/null || true
    elif command -v adduser >/dev/null 2>&1; then adduser -S -s /bin/bash -h "${TEST_BASE}" otbtest 2>/dev/null || true; fi
    SVC_USER="otbtest"
fi
log "Service user: ${SVC_USER}"

# Prepare directories
rm -rf "${TEST_BASE}"
mkdir -p "${GTM_DATA}" "${COORD_DATA}" "${DN_DATA}" "${LOG_DIR}"
chown "${SVC_USER}:${SVC_USER}" "${TEST_BASE}" "${GTM_DATA}" "${COORD_DATA}" "${DN_DATA}" "${LOG_DIR}"

# Start GTM
log "Starting GTM..."
as_svc "${BIN_DIR}/initgtm -D ${GTM_DATA} -Z gtm" || fail "initgtm failed"
as_svc "${BIN_DIR}/gtm_ctl start -D ${GTM_DATA} -Z gtm -l ${LOG_DIR}/gtm.log" || fail "GTM start failed"
wait_for_port "${GTM_PORT}" "${STARTUP_TIMEOUT}" || fail "GTM not listening"
log "GTM up on port ${GTM_PORT}"

# Start Datanode
log "Starting Datanode..."
as_svc "${BIN_DIR}/initdb -D ${DN_DATA} --nodename=dn1" || fail "Datanode initdb failed"
append_conf "${DN_DATA}/postgresql.conf" \
    "gtm_host = '127.0.0.1'" "gtm_port = ${GTM_PORT}" \
    "gtm_backup_host = ''" "gtm_backup_port = 0" \
    "pooler_port = 6661" "max_pool_size = 100" \
    "listen_addresses = '*'" "port = ${DN_PORT}"
cat > "${DN_DATA}/pg_hba.conf" <<HBA
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
HBA
chown "${SVC_USER}:${SVC_USER}" "${DN_DATA}/postgresql.conf" "${DN_DATA}/pg_hba.conf"
as_svc "${BIN_DIR}/pg_ctl start -D ${DN_DATA} -Z datanode -l ${LOG_DIR}/dn1.log" || fail "Datanode start failed"
wait_for_port "${DN_PORT}" "${STARTUP_TIMEOUT}" || fail "Datanode not listening"
log "Datanode up on port ${DN_PORT}"

# Start Coordinator
log "Starting Coordinator..."
as_svc "${BIN_DIR}/initdb -D ${COORD_DATA} --nodename=coord" || fail "Coordinator initdb failed"
append_conf "${COORD_DATA}/postgresql.conf" \
    "gtm_host = '127.0.0.1'" "gtm_port = ${GTM_PORT}" \
    "gtm_backup_host = ''" "gtm_backup_port = 0" \
    "pooler_port = 6662" "max_pool_size = 100" \
    "listen_addresses = '*'" "port = ${COORD_PORT}"
cat > "${COORD_DATA}/pg_hba.conf" <<HBA
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
HBA
chown "${SVC_USER}:${SVC_USER}" "${COORD_DATA}/postgresql.conf" "${COORD_DATA}/pg_hba.conf"
as_svc "${BIN_DIR}/pg_ctl start -D ${COORD_DATA} -Z coordinator -l ${LOG_DIR}/coord.log" || fail "Coordinator start failed"
wait_for_port "${COORD_PORT}" "${STARTUP_TIMEOUT}" || fail "Coordinator not listening"
log "Coordinator up on port ${COORD_PORT}"

# Register datanode
log "Registering datanode..."
as_svc "${BIN_DIR}/psql -h 127.0.0.1 -p ${COORD_PORT} -c \"CREATE NODE dn1 WITH (TYPE = 'datanode', HOST = '127.0.0.1', PORT = ${DN_PORT});\"" 2>&1 || true
as_svc "${BIN_DIR}/psql -h 127.0.0.1 -p ${COORD_PORT} -c \"SELECT pgxc_pool_reload();\"" 2>&1 || true

# Run advanced tests
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0

for test_script in "${SCRIPT_DIR}"/advanced/test_*.sh; do
    [ -f "$test_script" ] || continue
    test_name=$(basename "$test_script" .sh)
    log "Running ${test_name}..."
    if bash "$test_script"; then
        log "${test_name}: PASSED"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        log "${test_name}: FAILED"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
done

# Cleanup
log "Stopping cluster..."
stop_services
sleep 1
rm -rf "${TEST_BASE}"
[ "${SVC_USER}" = "otbtest" ] && userdel otbtest 2>/dev/null || true

# Summary
echo ""
log "========================================="
log "  Advanced Tests: ${TOTAL_PASS} passed, ${TOTAL_FAIL} failed"
log "========================================="

if [ "${TOTAL_FAIL}" -gt 0 ]; then
    exit 1
fi
exit 0
