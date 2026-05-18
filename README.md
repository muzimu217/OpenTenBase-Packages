# OpenTenBase .deb Packaging

Ubuntu .deb packaging for [OpenTenBase](https://github.com/OpenTenBase/OpenTenBase) v5.0 (distributed SQL database based on PostgreSQL 10).

## Packages

| Package | Description |
|---------|-------------|
| `opentenbase` | Metapackage (depends on server + client) |
| `opentenbase-server` | Server binaries (postgres, gtm, pg_ctl) + service driver |
| `opentenbase-client` | Client utilities (psql, pg_dump) |
| `opentenbase-contrib` | Contributed extensions (pgbench, oid2name, etc.) |
| `libopentenbase-dev` | Development headers + pg_config |
| `opentenbase-doc` | SGML documentation sources |

## Build

On Ubuntu 24.04:

```bash
# Install build dependencies
apt install -y debhelper-compat bison flex perl gcc g++ make \
    libreadline-dev zlib1g-dev libssl-dev libpam0g-dev \
    libxml2-dev libldap2-dev libossp-uuid-dev uuid-dev \
    libcurl4-openssl-dev liblz4-dev libzstd-dev \
    libcli11-dev libpqxx-dev quilt libtool pkg-config

# Clone OpenTenBase source
git clone https://github.com/OpenTenBase/OpenTenBase.git
cd OpenTenBase

# Copy debian/ directory into source tree
cp -r /path/to/debian/ ./

# Build (full compile)
fakeroot debian/rules binary

# Or rebuild only .deb packages (no recompile)
fakeroot debian/rules binary
```

## Install

```bash
cd output/
apt install -y ./opentenbase_5.0-1ubuntu1_all.deb \
    ./opentenbase-server_5.0-1ubuntu1_amd64.deb \
    ./opentenbase-client_5.0-1ubuntu1_amd64.deb \
    ./opentenbase-contrib_5.0-1ubuntu1_amd64.deb
```

## Usage

```bash
# Initialize cluster (GTM + Coordinator + Datanode)
opentenbase-ctl init

# Start all nodes
opentenbase-ctl start

# Check status
opentenbase-ctl status

# Connect via psql
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres

# Stop all nodes
opentenbase-ctl stop
```

## Architecture

- Installs to `/usr/lib/opentenbase/` (isolated from system PostgreSQL)
- Config in `/etc/opentenbase/`
- Data in `/var/lib/opentenbase/`
- Logs in `/var/log/opentenbase/`
- Managed by `/usr/bin/opentenbase-ctl`

## License

Same as OpenTenBase (Apache 2.0).
