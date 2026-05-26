#!/bin/bash
# Runs inside the OpenWrt SDK container.
set -euo pipefail

OPENWRT_BRANCH="${OPENWRT_BRANCH:-openwrt-24.10}"
PKG_DIR="/builder/package/luci-app-twofa"
OUT_DIR="${PKG_DIR}/bin_out"

echo "SDK build dir: $(pwd)"
echo "Package dir:   ${PKG_DIR}"

mkdir -p "${OUT_DIR}"
rm -f "${OUT_DIR}"/*.ipk

ensure_luci_feed() {
	if [ -f feeds/luci/luci.mk ]; then
		echo "luci feed already present"
		return 0
	fi

	echo "luci feed missing, cloning from GitHub mirror..."
	rm -rf feeds/luci
	git clone --depth 1 -b "${OPENWRT_BRANCH}" https://github.com/openwrt/luci.git feeds/luci \
		|| git clone --depth 1 https://github.com/openwrt/luci.git feeds/luci
}

echo "--- updating feeds ---"
./scripts/feeds update base packages routing telephony 2>&1 || true
ensure_luci_feed

echo "--- installing feeds ---"
./scripts/feeds install luci-base luci-compat luci-lib-nixio qrencode

echo "--- configuring package ---"
rm -rf tmp
make package/symlinks
grep -q 'CONFIG_PACKAGE_luci-app-twofa' .config 2>/dev/null || echo 'CONFIG_PACKAGE_luci-app-twofa=m' >> .config
make defconfig

if ! grep -q '^CONFIG_PACKAGE_luci-app-twofa=m' .config; then
	echo "ERROR: luci-app-twofa was not enabled in .config" >&2
	exit 1
fi

echo "--- compiling luci-app-twofa ---"
make "package/luci-app-twofa/compile" V=s -j"$(nproc)"

echo "--- collecting IPK ---"
find bin/packages -name 'luci-app-twofa*.ipk' -exec cp -t "${OUT_DIR}" {} +
if [ -z "$(ls -A "${OUT_DIR}"/*.ipk 2>/dev/null)" ]; then
	echo "ERROR: no IPK files found under bin/packages" >&2
	exit 1
fi

ls -lh "${OUT_DIR}"/*.ipk
echo "SDK build finished successfully."
