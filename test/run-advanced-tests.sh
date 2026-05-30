#!/usr/bin/env bash
# =============================================================================
# OpenTenBase Advanced Test Runner
# =============================================================================
# Starts a cluster, runs all advanced test suites, then tears down.
# Uses direct process start (not gtm_ctl/pg_ctl) to avoid zombie detection.
# =============================================================================
set -e

BIN_DIR="/usr/lib/opentenbase/5.0/bin"
TEST_BASE="/tmp/otb-adv-test"
GTM_DATA="${TEST_BASE}/gtm"
COORD_DATA="${TEST_BASE}/coord"
DN_DATA="${TEST_BASE}/dn1"
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

stop_services() {
    pkill -f "gtm -D ${GTM_DATA}" 2>/dev/null || true
    pkill -f "postgres.*datanode.*${DN_DATA}" 2>/dev/null || true
    pkill -f "postgres.*coordinator.*${COORD_DATA}" 2>/dev/null || true
    sleep 1
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

as_svc() { su -s /bin/bash -c "$1" "${SVC_USER}"; }
append_conf() { local f="$1"; shift; printf '%s\n' "$@" >> "${f}"; }

# Kill any existing processes
stop_services

# Prepare directories
rm -rf "${TEST_BASE}"
mkdir -p "${GTM_DATA}" "${COORD_DATA}" "${DN_DATA}"
chown "${SVC_USER}:${SVC_USER}" "${TEST_BASE}" "${GTM_DATA}" "${COORD_DATA}" "${DN_DATA}"

# Initialize and start GTM (direct start, not gtm_ctl)
log "Starting GTM..."
as_svc "${BIN_DIR}/initgtm -D ${GTM_DATA} -Z gtm" || fail "initgtm failed"
cat > "${GTM_DATA}/gtm.conf" <<EOF
listen_addresses = '*'
port = ${GTM_PORT}
nodename = 'one'
EOF
chown "${SVC_USER}:${SVC_USER}" "${GTM_DATA}/gtm.conf"
as_svc "${BIN_DIR}/gtm -D ${GTM_DATA}" > /tmp/adv-gtm.log 2>&1 &
GTM_PID=$!
sleep 3
if kill -0 $GTM_PID 2>/dev/null; then
    log "GTM up on port ${GTM_PORT} (PID $GTM_PID)"
else
    fail "GTM failed to start"
fi

# Initialize and start Datanode
log "Starting Datanode..."
as_svc "${BIN_DIR}/initdb -D ${DN_DATA} --nodename=dn1 --nodetype=datanode --master_gtm_nodename=one --master_gtm_ip=127.0.0.1 --master_gtm_port=${GTM_PORT}" || fail "Datanode initdb failed"
append_conf "${DN_DATA}/postgresql.conf" \
    "port = ${DN_PORT}" "pooler_port = 6661" "forward_port = 6670" \
    "listen_addresses = '*'"
cat > "${DN_DATA}/pg_hba.conf" <<HBA
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
HBA
chown "${SVC_USER}:${SVC_USER}" "${DN_DATA}/postgresql.conf" "${DN_DATA}/pg_hba.conf"
as_svc "${BIN_DIR}/postgres --datanode -D ${DN_DATA}" > /tmp/adv-dn.log 2>&1 &
DN_PID=$!
sleep 3
if kill -0 $DN_PID 2>/dev/null; then
    log "Datanode up on port ${DN_PORT} (PID $DN_PID)"
else
    fail "Datanode failed to start"
fi

# Initialize and start Coordinator
log "Starting Coordinator..."
as_svc "${BIN_DIR}/initdb -D ${COORD_DATA} --nodename=coord --nodetype=coordinator --master_gtm_nodename=one --master_gtm_ip=127.0.0.1 --master_gtm_port=${GTM_PORT}" || fail "Coordinator initdb failed"
append_conf "${COORD_DATA}/postgresql.conf" \
    "port = ${COORD_PORT}" "pooler_port = 6662" "forward_port = 6669" \
    "listen_addresses = '*'"
cat > "${COORD_DATA}/pg_hba.conf" <<HBA
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
HBA
chown "${SVC_USER}:${SVC_USER}" "${COORD_DATA}/postgresql.conf" "${COORD_DATA}/pg_hba.conf"
as_svc "${BIN_DIR}/postgres --coordinator -D ${COORD_DATA}" > /tmp/adv-coord.log 2>&1 &
COORD_PID=$!
sleep 3
if kill -0 $COORD_PID 2>/dev/null; then
    log "Coordinator up on port ${COORD_PORT} (PID $COORD_PID)"
else
    fail "Coordinator failed to start"
fi

# Register nodes
log "Registering nodes..."
COORD_PSQL="${BIN_DIR}/psql -h 127.0.0.1 -p ${COORD_PORT} -U ${SVC_USER} -d postgres -X -q"
DN_PSQL="${BIN_DIR}/psql -h 127.0.0.1 -p ${DN_PORT} -U ${SVC_USER} -d postgres -X -q"

as_svc "${COORD_PSQL} -c \"CREATE GTM NODE gtm_master WITH (HOST='127.0.0.1', PORT=${GTM_PORT}, PRIMARY);\"" 2>/dev/null || true
as_svc "${COORD_PSQL} -c \"CREATE NODE dn1 WITH (TYPE='datanode', HOST='127.0.0.1', PORT=${DN_PORT}, FORWARD=6670, PRIMARY, PREFERRED);\"" 2>/dev/null || true
as_svc "${COORD_PSQL} -c \"SELECT pgxc_pool_reload();\"" 2>/dev/null || true
as_svc "${DN_PSQL} -c \"CREATE GTM NODE gtm_master WITH (HOST='127.0.0.1', PORT=${GTM_PORT}, PRIMARY);\"" 2>/dev/null || true
as_svc "${DN_PSQL} -c \"CREATE NODE coord WITH (TYPE='coordinator', HOST='127.0.0.1', PORT=${COORD_PORT}, FORWARD=6669);\"" 2>/dev/null || true
as_svc "${DN_PSQL} -c \"SELECT pgxc_pool_reload();\"" 2>/dev/null || true
log "Nodes registered"

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
