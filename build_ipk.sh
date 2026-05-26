#!/bin/bash
# Build luci-app-twofa IPK locally via OpenWrt SDK Docker image.
#
# LuCI apps use PKGARCH:=all, so one IPK works on every target architecture.
#
# Usage:
#   ./build_ipk.sh
#   OPENWRT_VERSION=23.05.5 ./build_ipk.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OPENWRT_VERSION="${OPENWRT_VERSION:-24.10.0}"
OPENWRT_BRANCH="${OPENWRT_BRANCH:-openwrt-${OPENWRT_VERSION}}"
SDK_IMAGE="${SDK_IMAGE:-openwrt/sdk:x86-64-${OPENWRT_VERSION}}"
OUTPUT_DIR="${ROOT}/bin_out"

case "${OPENWRT_VERSION}" in
	24.10.*) OPENWRT_BRANCH="openwrt-24.10" ;;
	23.05.*) OPENWRT_BRANCH="openwrt-23.05" ;;
	22.03.*) OPENWRT_BRANCH="openwrt-22.03" ;;
esac

echo "=========================================="
echo "Building luci-app-twofa"
echo "OpenWrt version : ${OPENWRT_VERSION}"
echo "LuCI branch     : ${OPENWRT_BRANCH}"
echo "SDK image       : ${SDK_IMAGE}"
echo "Output dir      : ${OUTPUT_DIR}"
echo "=========================================="

command -v docker >/dev/null 2>&1 || {
	echo "ERROR: docker is required for local builds." >&2
	exit 1
}

mkdir -p "${OUTPUT_DIR}"
rm -f "${OUTPUT_DIR}"/*.ipk

docker pull --platform linux/amd64 "${SDK_IMAGE}"

docker run --rm --platform linux/amd64 \
	-v "${ROOT}:/builder/package/luci-app-twofa" \
	-v "${ROOT}/.build/sdk-build.sh:/builder/sdk-build.sh:ro" \
	-e "OPENWRT_BRANCH=${OPENWRT_BRANCH}" \
	-w /builder \
	"${SDK_IMAGE}" \
	/bin/bash /builder/sdk-build.sh

chmod 644 "${OUTPUT_DIR}"/*.ipk 2>/dev/null || true

echo
echo "------------------------------------------------"
echo "Build complete. Generated packages:"
ls -lh "${OUTPUT_DIR}"/*.ipk
