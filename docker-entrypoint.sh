#!/bin/bash
# docker-entrypoint.sh — run inside the cirros-builder container
set -euo pipefail

# Ensure loop device support (requires --privileged)
modprobe loop max_loop=16 2>/dev/null || true

# Expect the cirros source tree to be bind-mounted at /cirros
cd /cirros
[ -f bin/build-release ] || {
    echo "ERROR: /cirros does not look like a cirros source tree."
    echo "  Bind-mount the repo: -v \$PWD:/cirros"
    exit 1
}

VERSION="${1:-daily}"
shift || true

export CI_BUILD="${CI_BUILD:-true}"
export CI_BUILD_OUT="${CI_BUILD_OUT:-build-ci/}"

echo "==> Building CirrOS version: ${VERSION}"
echo "==> Architectures: ${ARCHES:-x86_64 arm aarch64 ppc64le riscv64}"

exec bin/build-release "${VERSION}" "$@"
