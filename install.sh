#!/bin/bash
# OpenTenBase v5.0 installer — supports Ubuntu 20.04, 22.04, 24.04
# Usage: bash install.sh [directory]
#   directory: path to .deb files (default: download from GitHub)

set -e

REPO="muzimu217/opentenbase-deb"
TAG="v5.0-multi7"

echo "OpenTenBase v5.0 Installer"
echo "========================="

# Check root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (sudo bash install.sh)" >&2
    exit 1
fi

# Detect Ubuntu version
if [ ! -f /etc/os-release ]; then
    echo "ERROR: cannot detect OS version (/etc/os-release not found)" >&2
    exit 1
fi

. /etc/os-release
CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

case "$CODENAME" in
    noble)  SUFFIX=".noble" ;;      # 24.04: opentenbase_5.0-1ubuntu1.noble_amd64.deb
    jammy)  SUFFIX=".jammy" ;;      # 22.04: opentenbase_5.0-1ubuntu1.jammy_amd64.deb
    focal)  SUFFIX=".focal" ;;      # 20.04: opentenbase_5.0-1ubuntu1.focal_amd64.deb
    *)
        echo "ERROR: unsupported Ubuntu version: $CODENAME" >&2
        echo "Supported: focal (20.04), jammy (22.04), noble (24.04)" >&2
        exit 1
        ;;
esac

echo "Detected: Ubuntu $VERSION_ID ($CODENAME)"

DIR="${1:-.}"
VER="5.0-1ubuntu1${SUFFIX}"

DEBS=(
    "opentenbase_${VER}_all.deb"
    "opentenbase-server_${VER}_amd64.deb"
    "opentenbase-client_${VER}_amd64.deb"
    "opentenbase-contrib_${VER}_amd64.deb"
)

# Check if .deb files exist, if not download from GitHub
cd "$DIR"
if [ ! -f "${DEBS[0]}" ]; then
    echo ">> Downloading packages from GitHub..."
    for deb in "${DEBS[@]}"; do
        echo "  $deb"
        curl -sLO "https://github.com/${REPO}/releases/download/${TAG}/${deb}"
    done
    echo ""
fi

# Verify files exist
missing=0
for deb in "${DEBS[@]}"; do
    if [ ! -f "$deb" ]; then
        echo "ERROR: $deb not found" >&2
        missing=1
    fi
done
[ $missing -eq 1 ] && exit 1

# Install with automatic dependency resolution
echo ">> Installing packages and dependencies..."
apt-get update -qq 2>/dev/null || true
apt-get install -y -qq ./*.deb

echo ""
echo ">> Installation complete!"
echo ""
echo "Quick start:"
echo "  opentenbase-ctl init    # Initialize cluster"
echo "  opentenbase-ctl start   # Start all nodes"
echo "  opentenbase-ctl status  # Check status"
echo ""
echo "Connect:"
echo "  opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres"
