# OpenTenBase Docker E2E Test Results

**Date:** 2026-06-02
**Architecture:** aarch64 (ARM64)
**Test Environment:** DevEnvVM (HCE 2.0, 4vCPUs, 8GB RAM)
**Package:** opentenbase-5.0-1.aarch64.rpm

## Test Matrix

| Distro | Image | Pkg Format | Install | init | start | status | SQL query | SHARD table | stop | Result |
|--------|-------|------------|---------|------|-------|--------|-----------|-------------|------|--------|
| Rocky Linux 9 | `rockylinux:9` | RPM | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | **PASS** |
| openEuler 24.03 | `openeuler/openeuler:24.03` | RPM | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | **PASS** |
| Ubuntu 22.04 | `ubuntu:22.04` | tarball | ⚠️ | ❌ | — | — | — | — | — | **SKIP** |

## Detailed Results

### Rocky Linux 9 ✅

```
$ opentenbase-ctl status
gtm:   RUNNING
dn1:   RUNNING
coord: RUNNING

$ psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1 -c "SELECT version();"
PostgreSQL 10.0 @ OpenTenBase_v5.0 (commit: b612d77cb) on aarch64-unknown-linux-gnu

$ CREATE TABLE docker_test (id int, name text) DISTRIBUTE BY SHARD(id);
$ INSERT INTO docker_test VALUES (1, 'hello from rocky9 docker');
 id |           name
----+--------------------------
  1 | hello from rocky9 docker
```

**Dependencies installed:** `sudo`, `which`, `shadow-utils`, `procps-ng`

### openEuler 24.03 ✅

```
$ opentenbase-ctl status
gtm:   RUNNING
dn1:   RUNNING
coord: RUNNING

$ psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1 -c "SELECT version();"
PostgreSQL 10.0 @ OpenTenBase_v5.0 (commit: b612d77cb) on aarch64-unknown-linux-gnu

$ CREATE TABLE docker_test (id int, name text) DISTRIBUTE BY SHARD(id);
$ INSERT INTO docker_test VALUES (1, 'hello from openeuler docker');
 id |            name
----+-----------------------------
  1 | hello from openeuler docker
```

**Dependencies installed:** `sudo`, `which`, `shadow-utils`, `procps-ng`, `util-linux-user`

### Ubuntu 22.04 — SKIPPED

**Reason:** The RPM binary was compiled on HCE 2.0 (CentOS 8-based) with OpenSSL 1.1 dependencies (`libssl.so.1.1`, `libcrypto.so.1.1`). Ubuntu 22.04 ships OpenSSL 3.0 and does not provide OpenSSL 1.1 libraries.

**Resolution:** ARM64 DEB packages need to be built natively on Ubuntu to test DEB installation. The CI `build-deb.yml` currently only builds `amd64` packages. Adding ARM64 DEB builds requires native ARM64 CI runners.

## Key Findings

1. **RPM installation works cleanly** on both Rocky 9 and openEuler 24.03 (aarch64)
2. **`procps-ng` is required** in minimal containers — `opentenbase-ctl status` uses `pgrep` which depends on `ps`
3. **`util-linux-user` is required** on openEuler — provides `runuser` command used by `opentenbase-ctl`
4. **Binary compatibility:** RPM packages are tied to the build system's glibc/OpenSSL versions. Cross-distro DEB testing requires native builds.
5. **Shared memory:** `--privileged -v /dev/shm:/dev/shm` is required for the pooler's shared memory allocation

## Dependencies by Distro

| Distro | Required Packages |
|--------|------------------|
| Rocky Linux 9 | `sudo`, `which`, `shadow-utils`, `procps-ng` |
| openEuler 24.03 | `sudo`, `which`, `shadow-utils`, `procps-ng`, `util-linux-user` |
| Ubuntu 22.04 | N/A (needs native DEB build) |
