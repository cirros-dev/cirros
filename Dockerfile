# Dockerfile for CirrOS build environment
#
# Build image:
#   docker build -t cirros-builder .
#
# Run (--privileged is required for loop mounts inside bin/bundle):
#   docker run --privileged --rm \
#     -v "$PWD":/cirros \
#     -v cirros-dl:/cirros/download \
#     -v cirros-ccache:/cirros/ccache \
#     cirros-builder daily
#
# Build a specific tagged release:
#   docker run --privileged --rm \
#     -v "$PWD":/cirros \
#     -v cirros-dl:/cirros/download \
#     -v cirros-ccache:/cirros/ccache \
#     cirros-builder 0.3.2
#
# Build only x86_64:
#   docker run --privileged --rm \
#     -e ARCHES=x86_64 \
#     -v "$PWD":/cirros \
#     -v cirros-dl:/cirros/download \
#     -v cirros-ccache:/cirros/ccache \
#     cirros-builder daily

FROM ubuntu:22.04

LABEL description="CirrOS image build environment (Ubuntu 22.04 / Buildroot 2022.02.4)"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV USER=root

# ── All build dependencies ────────────────────────────────────────────────────
# system-setup DEPS + CI extras + tools used implicitly (cpio, kmod, binutils, sudo)
RUN apt-get update && apt-get install -y --no-install-recommends \
    # system-setup DEPS
    bc \
    bison \
    build-essential \
    dosfstools \
    flex \
    gdisk \
    gettext \
    git \
    grub-common \
    kpartx \
    libncurses5-dev \
    lsb-release \
    mtools \
    parallel \
    python3 \
    qemu-utils \
    quilt \
    rsync \
    sudo \
    texinfo \
    unzip \
    wget \
    xz-utils \
    zstd \
    # implicit deps (used by bundle/grab-kernels but not listed in system-setup)
    binutils \
    cpio \
    kmod \
    # CI extras (boot testing + OpenFirmware for ppc64le)
    cloud-utils \
    openbios-ppc \
    qemu-system-arm \
    qemu-system-misc \
    qemu-system-ppc \
    qemu-system-x86 \
    && rm -rf /var/lib/apt/lists/*

# ── Loop device nodes ─────────────────────────────────────────────────────────
# Pre-create /dev/loop* nodes for environments where the container /dev is
# minimal. At runtime --privileged exposes the host kernel's loop subsystem.
RUN for i in $(seq 0 7); do \
      [ -e /dev/loop$i ] || mknod /dev/loop$i b 7 $i; \
    done

WORKDIR /cirros

# Entrypoint that validates the bind-mount and delegates to bin/build-release
COPY docker-entrypoint.sh /usr/local/bin/cirros-build
RUN chmod +x /usr/local/bin/cirros-build

# Declare cache-friendly volume mount points
VOLUME ["/cirros/download", "/cirros/ccache"]

ENTRYPOINT ["/usr/local/bin/cirros-build"]
CMD ["daily"]
