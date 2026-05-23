# OpenTenBase .deb Packaging

English | [中文](README_zh.md)

Ubuntu .deb packaging for [OpenTenBase](https://github.com/OpenTenBase/OpenTenBase) v5.0 (distributed SQL database based on PostgreSQL 10).

## Quick Install

### One-line Install (Recommended)

```bash
# Download and run installer
curl -sLO https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi10/install.sh
sudo bash install.sh
```

The installer automatically:
- Detects OS version (Ubuntu 20.04/22.04/24.04, Debian 11/12)
- Downloads correct .deb packages
- Resolves dependencies via apt

### Manual Install

```bash
# For Ubuntu 24.04 (Noble)
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi10/opentenbase_5.0-1ubuntu1.noble_all.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi10/opentenbase-server_5.0-1ubuntu1.noble_amd64.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi10/opentenbase-client_5.0-1ubuntu1.noble_amd64.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi10/opentenbase-contrib_5.0-1ubuntu1.noble_amd64.deb
sudo dpkg -i ./*.deb || sudo apt-get install -f -y
```

> **Note**: If `dpkg` reports missing dependencies (e.g. `libossp-uuid16` or `libpqxx-7.8t64`), these are packaging metadata errors — the binaries do **not** actually require these libraries at runtime. Use `sudo dpkg --force-depends -i ./*.deb` to install, then run `sudo mkdir -p /usr/lib/opentenbase/lib/postgresql` before proceeding.

## Packages

| Package | Description |
|---------|-------------|
| `opentenbase` | Metapackage (depends on server + client) |
| `opentenbase-server` | Server binaries (postgres, gtm, pg_ctl) + service driver |
| `opentenbase-client` | Client utilities (psql, pg_dump) |
| `opentenbase-contrib` | Contributed extensions (pgbench, oid2name, etc.) |
| `libopentenbase-dev` | Development headers + pg_config |
| `opentenbase-doc` | SGML documentation sources |

## Quick Start

### Initialize Cluster

```bash
# Initialize GTM + Coordinator + Datanode
opentenbase-ctl init
```

### Start Cluster

```bash
# Start all nodes
opentenbase-ctl start
```

### Check Status

```bash
# Check cluster status
opentenbase-ctl status
```

### Connect to Database

```bash
# Connect via psql (default database is template1)
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1
```

### Stop Cluster

```bash
# Stop all nodes
opentenbase-ctl stop
```

## Architecture

### Installation Paths

- **Main directory**: `/usr/lib/opentenbase/` (isolated from system PostgreSQL)
- **Config directory**: `/etc/opentenbase/`
- **Data directory**: `/var/lib/opentenbase/`
- **Log directory**: `/var/log/opentenbase/`
- **Management script**: `/usr/bin/opentenbase-ctl`

### Port Layout

| Service | Port | Description |
|---------|------|-------------|
| GTM | 6666 | Global Transaction Manager |
| Coordinator | 5432 | Coordinator node (external) |
| Datanode | 15432 | Data node |
| Coordinator Pooler | 6667 | Connection pool |
| Datanode Pooler | 6668 | Connection pool |
| Coordinator Forward | 6669 | Forward port |
| Datanode Forward | 6670 | Forward port |

### Startup Order

```
opentenbase-ctl start
    ├── 1. start_gtm()           # Start GTM
    ├── 2. start_coord()         # Start Coordinator
    ├── 3. register_nodes()      # Register nodes to pgxc_node
    │   ├── CREATE GTM NODE ...
    │   ├── CREATE NODE coord1 ...
    │   ├── CREATE NODE dn001 ...
    │   ├── pgxc_pool_reload()
    │   └── EXECUTE DIRECT ON (dn001) 'CREATE GTM NODE ...'
    ├── 4. start_dn1()           # Start Datanode
    └── 5. register_nodes()      # Final registration (ensure propagation)
```

## Build from Source

### Install Build Dependencies

```bash
apt install -y debhelper-compat bison flex perl gcc g++ make \
    libreadline-dev zlib1g-dev libssl-dev libpam0g-dev \
    libxml2-dev libldap2-dev libossp-uuid-dev uuid-dev \
    libcurl4-openssl-dev liblz4-dev libzstd-dev \
    libcli11-dev libpqxx-dev quilt libtool pkg-config
```

### Clone Source

```bash
git clone https://github.com/OpenTenBase/OpenTenBase.git
cd OpenTenBase
```

### Copy Packaging Files

```bash
cp -r /path/to/debian/ ./
```

### Build Packages

```bash
# Full compile
fakeroot debian/rules binary
```

### Build with Docker (Recommended)

```bash
# Clone repo and build for a specific distro
git clone https://github.com/muzimu217/OpenTenBase-deb.git
cd OpenTenBase-deb

# Build for Ubuntu 20.04
./test-build.sh -d ubuntu -v 20.04

# Build all 5 distros
./test-build.sh --all
```

## Deployment Modes

| Mode | Components | Use Case | Status |
|------|-----------|----------|--------|
| Single Node | GTM + CN | Dev/Test | Verified |
| Docker Multi-node | GTM + CN + N*DN | Test/Prod | Verified |
| Multi-machine | GTM + CN + N*DN | Production | Verified |
| Single-machine Multi-node | GTM + CN + DN | Not supported | Port conflict |

> **Note**: Single-machine multi-node is not supported because CN and DN forward managers both bind to `127.0.0.1:6669`, causing port conflicts. Docker multi-node is unaffected (each container has its own IP). See [Deployment Guide](tutorials/07-deployment.md).

## Known Limitations

1. **License Issue**: OpenTenBase requires a valid license for write operations. Open-source version is read-only.
2. **Single-machine Multi-node**: Not supported due to forward manager port conflict (CN and DN both bind to 127.0.0.1:6669). Use Docker or multi-machine deployment instead.
3. **No systemd**: Some container environments don't have systemd, use `opentenbase-ctl` directly.

## Troubleshooting

### Common Issues

#### 1. Installation Failed: Dependency Issues

If `sudo apt install ./*.deb` fails with missing dependencies like `libossp-uuid16` or `libpqxx-7.8t64`:

```bash
# Force install (these libraries are NOT actually needed at runtime)
sudo dpkg --force-depends -i ./*.deb

# Create missing plugin directory
sudo mkdir -p /usr/lib/opentenbase/lib/postgresql
```

#### 2. Cannot Connect to Database

```bash
# Check cluster status
opentenbase-ctl status

# View logs
tail -f /var/log/opentenbase/coord.log

# Note: default database is template1, not postgres
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1
```

#### 3. GTM Startup Failed

```bash
# Check GTM logs
tail -f /var/log/opentenbase/gtm.log

# Reinitialize cluster
opentenbase-ctl stop
opentenbase-ctl init
opentenbase-ctl start
```

#### 4. Port Conflict

```bash
# Check port usage
sudo netstat -tlnp | grep -E '(5432|6666|15432)'

# Stop conflicting services
sudo systemctl stop postgresql
```

## Contributing

Welcome to contribute code, report issues, or suggest improvements!

### Report Issues

1. Visit [Issues](https://github.com/muzimu217/OpenTenBase-deb/issues)
2. Click "New Issue"
3. Describe the issue in detail, including:
   - Ubuntu version
   - Error messages
   - Steps to reproduce

### Submit Code

1. Fork this repository
2. Create feature branch: `git checkout -b feature/your-feature`
3. Commit changes: `git commit -m 'Add your feature'`
4. Push branch: `git push origin feature/your-feature`
5. Create Pull Request

## License

Same as OpenTenBase (Apache 2.0).

## Related Links

- **GitHub Repository**: https://github.com/muzimu217/OpenTenBase-deb
- **Upstream Repository**: https://github.com/OpenTenBase/OpenTenBase
- **OpenTenBase Documentation**: https://github.com/OpenTenBase/OpenTenBase/wiki

---

**Maintainer**: muzimu217
**Last Updated**: 2026-05-23
