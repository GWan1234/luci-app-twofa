module("luci.controller.admin.system.twofa", package.seeall)

-- Menu entry is also defined in /usr/share/luci/menu.d/luci-app-twofa.json so
-- that the modern client-side dispatcher can pick it up. The Lua entry below
-- is kept so legacy code paths that look up the controller don't 404.
--
-- All status / verify endpoints have moved to the rpcd plugin
-- (/usr/libexec/rpcd/luci-app-twofa) which exposes them as the
-- `luci.twofa` ubus object. That gives rpcd-level enforcement: when a
-- session has not yet satisfied TOTP, the plugin revokes every non-twofa
-- ACL on the session so ubus uci.get / network.* / etc. are denied.

function index()
	entry({ "admin", "services", "twofa" },
		cbi("admin_system/twofa"),
		_("2FA Settings"), 99)
end
