include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-twofa
PKG_VERSION:=1.0
PKG_RELEASE:=11

PKG_LICENSE:=MIT
PKG_MAINTAINER:=YourName

LUCI_TITLE:=Two-factor authentication for LuCI
LUCI_DEPENDS:=+qrencode +luci-lib-nixio +luci-base +luci-compat
LUCI_PKGARCH:=all
# Languages are auto-detected from po/<lang>/ by luci.mk via LUCI_LANGUAGES.
# Only directories whose name matches a known LUCI_LANG.<name> entry (see luci.mk)
# are built. zh_Hans -> luci-app-twofa.zh-cn.lmo via LUCI_LC_ALIAS.zh_Hans=zh-cn.
# The postinst hook below makes a zh-hans.lmo alias so LuCI's normalised lookup
# (gsub('_','-'):lower()) finds it when uci.luci.main.lang = 'zh_Hans'.

include $(TOPDIR)/feeds/luci/luci.mk

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

# 1) i18n alias: luci-app-twofa.zh-cn.lmo -> .zh-hans.lmo
#    LuCI's i18n.load() normalises uci.luci.main.lang via gsub('_','-'):lower(),
#    so 'zh_Hans' becomes 'zh-hans' and never matches 'zh-cn.lmo'.
if [ -f /usr/lib/lua/luci/i18n/luci-app-twofa.zh-cn.lmo ] && \
   [ ! -f /usr/lib/lua/luci/i18n/luci-app-twofa.zh-hans.lmo ]; then
	cp -f /usr/lib/lua/luci/i18n/luci-app-twofa.zh-cn.lmo \
	      /usr/lib/lua/luci/i18n/luci-app-twofa.zh-hans.lmo
fi

# 2) rpcd: restart so the new /usr/libexec/rpcd/luci-app-twofa is enumerated
#    and the luci-app-twofa ubus object becomes resolvable
#    (rpcd derives the object name from the script's basename verbatim).
/etc/init.d/rpcd enable >/dev/null 2>&1 || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true

# 3) Drop any stale session-state from a previous install so old ACL snapshots
#    don't get re-applied to brand-new sessions.
rm -f /var/run/luci-twofa-sessions.json

# 4) Clear LuCI menu/module cache so the new menu.d/acl.d entries take effect.
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null

exit 0
endef

define Package/$(PKG_NAME)/postrm
#!/bin/sh
rm -f /var/run/luci-twofa-sessions.json 2>/dev/null
rm -f /usr/lib/lua/luci/i18n/luci-app-twofa.zh-hans.lmo 2>/dev/null
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null
exit 0
endef

# call BuildPackage - OpenWrt buildroot signature
