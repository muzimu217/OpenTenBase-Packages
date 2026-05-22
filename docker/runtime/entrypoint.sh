#!/bin/bash
# OpenTenBase Docker entrypoint
# Handles initialization and startup for GTM, Coordinator, and Datanode

set -e

NODE_TYPE="${NODE_TYPE:-}"
NODE_NAME="${NODE_NAME:-}"
GTM_HOST="${GTM_HOST:-gtm}"
GTM_PORT="${GTM_PORT:-6666}"
COORD_HOST="${COORD_HOST:-coordinator}"
COORD_PORT="${COORD_PORT:-5432}"
DN_PORT="${DN_PORT:-15432}"

DATA_DIR="/var/lib/opentenbase/data/${NODE_NAME}"

log() {
    echo "[${NODE_NAME}] $(date '+%H:%M:%S') $1"
}

wait_for_port() {
    local host=$1 port=$2 timeout=${3:-60}
    log "Waiting for ${host}:${port}..."
    for i in $(seq 1 "$timeout"); do
        if bash -c "echo > /dev/tcp/${host}/${port}" 2>/dev/null; then
            log "${host}:${port} is ready"
            return 0
        fi
        sleep 1
    done
    log "ERROR: ${host}:${port} not ready after ${timeout}s"
    return 1
}

# ============================================
# GTM
# ============================================
init_gtm() {
    if [ ! -f "$DATA_DIR/gtm.conf" ]; then
        log "Initializing GTM..."
        mkdir -p "$DATA_DIR"
        chown opentenbase:opentenbase "$DATA_DIR"
        sudo -u opentenbase /usr/lib/opentenbase/bin/initgtm -Z gtm -D "$DATA_DIR"

        cat >> "$DATA_DIR/gtm.conf" <<EOF
port = $GTM_PORT
listen_addresses = '*'
EOF
    fi

    log "Starting GTM on port $GTM_PORT..."
    exec sudo -u opentenbase /usr/lib/opentenbase/bin/gtm -D "$DATA_DIR"
}

# ============================================
# Coordinator
# ============================================
init_coordinator() {
    if [ ! -f "$DATA_DIR/postgresql.conf" ]; then
        log "Initializing Coordinator..."
        mkdir -p "$DATA_DIR"
        chown opentenbase:opentenbase "$DATA_DIR"
        sudo -u opentenbase /usr/lib/opentenbase/bin/initdb -D "$DATA_DIR" --nodename=coordinator --nodetype=coordinator

        cat >> "$DATA_DIR/postgresql.conf" <<EOF
port = $COORD_PORT
listen_addresses = '*'
gtm_host = '$GTM_HOST'
gtm_port = $GTM_PORT
pooler_port = $((COORD_PORT + 2000))
EOF

        echo "host all all 0.0.0.0/0 trust" >> "$DATA_DIR/pg_hba.conf"
    fi

    # Wait for GTM
    wait_for_port "$GTM_HOST" "$GTM_PORT"

    log "Starting Coordinator on port $COORD_PORT..."
    sudo -u opentenbase /usr/lib/opentenbase/bin/postgres --coordinator -D "$DATA_DIR" &
    COORD_PID=$!

    # Wait for coordinator to accept connections
    wait_for_port "127.0.0.1" "$COORD_PORT" 30

    # Register nodes (idempotent - ignore errors if already registered)
    log "Registering nodes in pgxc_node..."
    sudo -u opentenbase /usr/lib/opentenbase/bin/psql -h 127.0.0.1 -p "$COORD_PORT" -U opentenbase -d postgres -c \
        "CREATE NODE gtm_master WITH (TYPE='gtm', HOST='$GTM_HOST', PORT=$GTM_PORT);" 2>/dev/null || true
    sudo -u opentenbase /usr/lib/opentenbase/bin/psql -h 127.0.0.1 -p "$COORD_PORT" -U opentenbase -d postgres -c \
        "CREATE NODE coord1 WITH (TYPE='coordinator', HOST='$COORD_HOST', PORT=$COORD_PORT, PREFERRED);" 2>/dev/null || true
    sudo -u opentenbase /usr/lib/opentenbase/bin/psql -h 127.0.0.1 -p "$COORD_PORT" -U opentenbase -d postgres -c \
        "CREATE NODE dn001 WITH (TYPE='datanode', HOST='datanode1', PORT=15432, PREFERRED);" 2>/dev/null || true
    sudo -u opentenbase /usr/lib/opentenbase/bin/psql -h 127.0.0.1 -p "$COORD_PORT" -U opentenbase -d postgres -c \
        "SELECT pgxc_pool_reload();" 2>/dev/null || true

    log "Coordinator ready"
    wait $COORD_PID
}

# ============================================
# Datanode
# ============================================
init_datanode() {
    if [ ! -f "$DATA_DIR/postgresql.conf" ]; then
        log "Initializing Datanode..."
        mkdir -p "$DATA_DIR"
        chown opentenbase:opentenbase "$DATA_DIR"
        sudo -u opentenbase /usr/lib/opentenbase/bin/initdb -D "$DATA_DIR" --nodename="$NODE_NAME" --nodetype=datanode

        cat >> "$DATA_DIR/postgresql.conf" <<EOF
port = $DN_PORT
listen_addresses = '*'
gtm_host = '$GTM_HOST'
gtm_port = $GTM_PORT
pooler_port = $((DN_PORT + 2000))
EOF

        echo "host all all 0.0.0.0/0 trust" >> "$DATA_DIR/pg_hba.conf"
    fi

    # Wait for GTM
    wait_for_port "$GTM_HOST" "$GTM_PORT"

    log "Starting Datanode on port $DN_PORT..."
    sudo -u opentenbase /usr/lib/opentenbase/bin/postgres --datanode -D "$DATA_DIR" &
    DN_PID=$!

    # Wait for datanode to accept connections
    wait_for_port "127.0.0.1" "$DN_PORT" 30

    # Register nodes on datanode
    log "Registering nodes on datanode..."
    sudo -u opentenbase /usr/lib/opentenbase/bin/psql -h 127.0.0.1 -p "$DN_PORT" -U opentenbase -d postgres -c \
        "CREATE NODE gtm_master WITH (TYPE='gtm', HOST='$GTM_HOST', PORT=$GTM_PORT);" 2>/dev/null || true
    sudo -u opentenbase /usr/lib/opentenbase/bin/psql -h 127.0.0.1 -p "$DN_PORT" -U opentenbase -d postgres -c \
        "CREATE NODE coord1 WITH (TYPE='coordinator', HOST='$COORD_HOST', PORT=$COORD_PORT);" 2>/dev/null || true
    sudo -u opentenbase /usr/lib/opentenbase/bin/psql -h 127.0.0.1 -p "$DN_PORT" -U opentenbase -d postgres -c \
        "CREATE NODE $NODE_NAME WITH (TYPE='datanode', HOST='$NODE_NAME', PORT=$DN_PORT, PREFERRED);" 2>/dev/null || true
    sudo -u opentenbase /usr/lib/opentenbase/bin/psql -h 127.0.0.1 -p "$DN_PORT" -U opentenbase -d postgres -c \
        "SELECT pgxc_pool_reload();" 2>/dev/null || true

    log "Datanode ready"
    wait $DN_PID
}

# ============================================
# Main
# ============================================
case "$NODE_TYPE" in
    gtm)         init_gtm ;;
    coordinator) init_coordinator ;;
    datanode)    init_datanode ;;
    *)
        log "ERROR: NODE_TYPE must be gtm, coordinator, or datanode"
        exit 1
        ;;
esac
