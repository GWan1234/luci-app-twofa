include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-twofa
PKG_VERSION:=1.0
PKG_RELEASE:=4

PKG_LICENSE:=MIT
PKG_MAINTAINER:=YourName

LUCI_TITLE:=Two-factor authentication for LuCI
# 修正依赖名称：nixio -> luci-lib-nixio
# 添加 luci-compat 以确保在较新版本的 OpenWrt 上兼容 CBI
LUCI_DEPENDS:=+qrencode +luci-lib-nixio +luci-base +luci-compat
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
