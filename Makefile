include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-twofa
PKG_VERSION:=1.0
PKG_RELEASE:=5

PKG_LICENSE:=MIT
PKG_MAINTAINER:=YourName

LUCI_TITLE:=Two-factor authentication for LuCI
LUCI_DEPENDS:=+qrencode +luci-lib-nixio +luci-base +luci-compat
LUCI_PKGARCH:=all
LUCI_LANG:=zh-cn zh_Hans

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
