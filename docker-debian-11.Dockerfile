FROM debian:11

# Non-interactive mode
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    debhelper \
    devscripts \
    fakeroot \
    quilt \
    bison \
    flex \
    perl \
    libreadline-dev \
    zlib1g-dev \
    libssl-dev \
    libpam0g-dev \
    libxml2-dev \
    libldap2-dev \
    libossp-uuid-dev \
    uuid-dev \
    libcurl4-openssl-dev \
    liblz4-dev \
    libzstd-dev \
    libssh2-1-dev \
    libatomic1 \
    libatomic-ops-dev \
    gcc-12 \
    libgcc-12-dev \
    pkg-config \
    libtool \
    && (apt-get install -y libpqxx-dev || true) \
    && (apt-get install -y libcli11-dev || true) \
    && rm -rf /var/lib/apt/lists/*

# Ensure libatomic.so symlink exists for linking
# Use gcc-12's libatomic which has 128-bit atomics support
RUN set -e; \
    GCC12_LIB=/usr/lib/gcc/x86_64-linux-gnu/12; \
    if [ -f "$GCC12_LIB/libatomic.so" ]; then \
        ln -sf "$GCC12_LIB/libatomic.so" /usr/lib/x86_64-linux-gnu/libatomic.so; \
    elif [ -f "$GCC12_LIB/libatomic.a" ]; then \
        ln -sf "$GCC12_LIB/libatomic.a" /usr/lib/x86_64-linux-gnu/libatomic.a; \
    fi; \
    if [ ! -f /usr/lib/x86_64-linux-gnu/libatomic.so ] && [ -f /usr/lib/x86_64-linux-gnu/libatomic.so.1 ]; then \
        ln -sf /usr/lib/x86_64-linux-gnu/libatomic.so.1 /usr/lib/x86_64-linux-gnu/libatomic.so; \
    fi

# Work directory
WORKDIR /build

# Copy build script
COPY packaging/build-deb.sh /build/
RUN chmod +x /build/build-deb.sh

# Default: run build
CMD ["/build/build-deb.sh"]
