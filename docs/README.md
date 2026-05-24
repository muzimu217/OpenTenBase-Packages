# OpenTenBase Packages

English | [中文](README_zh.md)

> **Official cross-platform package repository for OpenTenBase** — Enterprise-grade multi-format, multi-distro packaging and distribution for the OpenTenBase distributed SQL database.

---

## Overview

**OpenTenBase Packages** is the official packaging and distribution project for [OpenTenBase](https://github.com/OpenTenBase/OpenTenBase), a distributed SQL database based on PostgreSQL. We provide standardized binary packages for major Linux distributions, supporting both DEB (Debian/Ubuntu) and RPM (RHEL/CentOS/Fedora) packaging systems across x86_64 and ARM64 architectures.

**Goal**: Build a **long-term maintained, auto-built, multi-version coexisting** official package repository for OpenTenBase — like PostgreSQL's `apt.postgresql.org` and Docker's `download.docker.com`.

---

## Features

| Feature | Description |
|---------|-------------|
| **Multi-format** | DEB (`.deb`) + RPM (`.rpm`) dual format support |
| **Multi-distro** | Ubuntu 20.04 / 22.04 / 24.04, Debian 11 / 12, RHEL/CentOS 8/9, Fedora, Rocky Linux, AlmaLinux, OpenEuler |
| **Multi-arch** | x86_64 (amd64) + ARM64 (aarch64) |
| **Multi-version coexistence** | Install v5.0 / v2.6 / v2.5 and dev versions side-by-side, switch with `opentenbase-ctl switch` |
| **One-line install** | `curl -sSL ... \| sudo bash` — auto-detects OS, downloads correct packages, resolves dependencies |
| **CI/CD automation** | GitHub Actions for automated build, sign, and publish |
| **systemd integration** | Native systemd service units, managed via `systemctl` |
| **Cluster management** | Built-in `opentenbase-ctl` script for one-command init, start, stop |

---

## Quick Install

### One-line Install (Recommended)

```bash
curl -sLO https://github.com/muzimu217/OpenTenBase-packages/releases/latest/download/install.sh
sudo bash install.sh
```

The installer automatically:
- Detects operating system and version
- Configures package repository (APT / YUM)
- Downloads and installs the correct package format
- Resolves all dependencies

### APT Manual Install (Debian / Ubuntu)

```bash
# Add repository
curl -sSL https://github.com/muzimu217/OpenTenBase-packages/releases/latest/download/setup-apt.sh | sudo bash

# Install
sudo apt update
sudo apt install opentenbase
```

### YUM/DNF Manual Install (RHEL / CentOS / Fedora)

```bash
# Add repository
curl -sSL https://github.com/muzimu217/OpenTenBase-packages/releases/latest/download/setup-rpm.sh | sudo bash

# Install
sudo dnf install opentenbase
```

---

## Package Inventory

| Package | Format | Description |
|---------|--------|-------------|
| `opentenbase` | DEB / RPM | Metapackage — depends on server + client |
| `opentenbase-server` | DEB / RPM | Server binaries (postgres, gtm, pg_ctl) + service driver + cluster management |
| `opentenbase-client` | DEB / RPM | Client utilities (psql, pg_dump, pg_restore, etc.) |
| `opentenbase-contrib` | DEB / RPM | Extensions (pgbench, pg_stat_statements, postgres_fdw, etc.) |
| `libopentenbase-dev` | DEB / RPM | Development headers + static libraries + pg_config |
| `opentenbase-doc` | DEB / RPM | Documentation |

---

## Platform Support Matrix

| Distribution | Version | DEB | RPM | x86_64 | ARM64 | Status |
|-------------|---------|:---:|:---:|:------:|:-----:|--------|
| Ubuntu | 20.04 (Focal) | ✅ | — | ✅ | ✅ | Verified |
| Ubuntu | 22.04 (Jammy) | ✅ | — | ✅ | ✅ | Verified |
| Ubuntu | 24.04 (Noble) | ✅ | — | ✅ | ✅ | Verified |
| Debian | 11 (Bullseye) | ✅ | — | ✅ | ✅ | Verified |
| Debian | 12 (Bookworm) | ✅ | — | ✅ | ✅ | Verified |
| RHEL / CentOS | 8 | — | ✅ | ✅ | ✅ | Verified |
| RHEL / CentOS | 9 | — | ✅ | ✅ | ✅ | Verified |
| Rocky Linux | 8 / 9 | — | ✅ | ✅ | ✅ | Verified |
| AlmaLinux | 8 / 9 | — | ✅ | ✅ | ✅ | Verified |
| Fedora | 39+ | — | ✅ | ✅ | ✅ | Verified |
| OpenEuler | 22.03+ | — | ✅ | ✅ | ✅ | Verified |

---

## Quick Start

```bash
# 1. Initialize cluster (GTM + Coordinator + Datanode)
opentenbase-ctl init

# 2. Start cluster
opentenbase-ctl start

# 3. Check cluster status
opentenbase-ctl status

# 4. Connect to database
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1

# 5. Stop cluster
opentenbase-ctl stop
```

### Version Switching

```bash
# List installed versions
opentenbase-ctl versions

# Switch to a specific version
opentenbase-ctl switch 5.0

# Switch to a development build
opentenbase-ctl switch master-b612d77c
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    OpenTenBase Packages                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌───────────────┐   ┌───────────────┐   ┌──────────────┐     │
│   │  DEB Packages │   │  RPM Packages │   │   Docker     │     │
│   │  Ubuntu/Debian│   │  RHEL/CentOS  │   │   Images     │     │
│   │  (14 targets) │   │  (14 targets) │   │              │     │
│   └───────┬───────┘   └───────┬───────┘   └──────┬───────┘     │
│           │                   │                   │             │
│           └───────────────────┼───────────────────┘             │
│                               │                                 │
│                     ┌─────────▼─────────┐                       │
│                     │   GPG Signature   │                       │
│                     └─────────┬─────────┘                       │
│                               │                                 │
│                     ┌─────────▼─────────┐                       │
│                     │  Version Manager  │                       │
│                     │  v5.0 / v2.6 / …  │                       │
│                     └─────────┬─────────┘                       │
│                               │                                 │
│                     ┌─────────▼─────────┐                       │
│                     │  GitHub Actions   │                       │
│                     │  Auto Build & Ship│                       │
│                     └───────────────────┘                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Installation Paths

| Path | Purpose |
|------|---------|
| `/usr/lib/opentenbase/<version>/` | Binaries and libraries (isolated from system PostgreSQL) |
| `/etc/opentenbase/<version>/` | Configuration files |
| `/var/lib/opentenbase/<version>/` | Data directory |
| `/var/log/opentenbase/<version>/` | Log directory |
| `/usr/bin/opentenbase-ctl` | Cluster management script |

---

## Build from Source

### Docker Build (Recommended)

```bash
git clone https://github.com/muzimu217/OpenTenBase-packages.git
cd OpenTenBase-packages

# Build for all distributions
./scripts/build-multi.sh --all

# Build for Ubuntu 24.04 only
./scripts/build-multi.sh -d ubuntu -v 24.04

# Build RPM only
./scripts/build-multi.sh --rpm
```

### Local Build

```bash
# Install build dependencies
sudo apt install -y debhelper-compat bison flex perl libreadline-dev \
    zlib1g-dev libssl-dev libxml2-dev libldap2-dev uuid-dev pkg-config

# Build DEB packages
./scripts/build-deb.sh

# Build RPM packages
./scripts/build-rpm.sh
```

---

## Directory Structure

```
OpenTenBase-packages/
├── .github/workflows/       # CI/CD pipelines
├── config/                  # Default configuration templates
├── debian/                  # DEB packaging rules
├── rpm/                     # RPM packaging rules
├── docker/                  # Docker build environments
├── scripts/                 # Build, release, signing scripts
├── systemd/                 # systemd service units
├── patches/                 # Source patches
├── test/                    # Automated tests
└── docs/                    # Documentation
```

---

## Known Limitations

| Limitation | Description |
|-----------|-------------|
| Write license | OpenTenBase open-source edition is read-only; write operations require a valid license |
| Single-machine multi-node | Not supported due to forward manager port conflict; use Docker or multi-machine deployment |

---

## Contributing

Contributions are welcome — code, bug reports, and improvement suggestions!

1. Fork this repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit and push your changes
4. Create a Pull Request

See [Contributing Guide](CONTRIBUTING.md) for details.

---

## License

Same as OpenTenBase — [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).

---

## Links

| Resource | Link |
|----------|------|
| **This project** | https://github.com/muzimu217/OpenTenBase-packages |
| **Upstream repo** | https://github.com/OpenTenBase/OpenTenBase |
| **OpenTenBase docs** | https://github.com/OpenTenBase/OpenTenBase/wiki |
| **Issue tracker** | [Issues](https://github.com/muzimu217/OpenTenBase-packages/issues) |

---

**Maintainer**: muzimu217
**Last Updated**: 2026-05-24
