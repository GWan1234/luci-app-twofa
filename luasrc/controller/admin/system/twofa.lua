module("luci.controller.admin.system.twofa", package.seeall)

require "luci.twofa.auth"

function index()
	entry({"admin", "services", "twofa"}, cbi("admin_system/twofa"), _("2FA Settings"), 99)
	entry({"admin", "services", "twofa", "status"}, call("action_status")).leaf = true
	entry({"admin", "services", "twofa", "verify"}, call("action_verify")).leaf = true
end

function action_status()
	local auth = require "luci.twofa.auth"
	local sid = auth.get_session_id()
	luci.http.prepare_content("application/json")
	luci.http.write_json({
		enabled = auth.is_enabled(),
		verified = auth.is_verified(sid)
	})
end

function action_verify()
	local auth = require "luci.twofa.auth"
	local json = require "luci.jsonc"
	local val = json.parse(luci.http.read_content() or "{}")
	local sid = auth.get_session_id()
	luci.http.prepare_content("application/json")
	luci.http.write_json({ success = auth.verify_token(sid, val.token) })
end
