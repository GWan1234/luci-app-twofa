include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-twofa
PKG_VERSION:=1.0
PKG_RELEASE:=5

PKG_LICENSE:=MIT
PKG_MAINTAINER:=YourName

LUCI_TITLE:=Two-factor authentication for LuCI
LUCI_DEPENDS:=+qrencode +luci-lib-nixio +luci-base +luci-compat
LUCI_PKGARCH:=all
# Languages are auto-detected from po/<lang>/ by luci.mk via LUCI_LANGUAGES.
# Only directories whose name matches a known LUCI_LANG.<name> entry (see luci.mk)
# are built. zh_Hans -> luci-app-twofa.zh-cn.lmo via LUCI_LC_ALIAS.zh_Hans=zh-cn.

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
