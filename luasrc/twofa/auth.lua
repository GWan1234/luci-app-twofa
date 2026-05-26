local uci = require "luci.model.uci".cursor()
local fs  = require "nixio.fs"
local json = require "luci.jsonc"
local totp = require "luci.twofa.totp"
local http = require "luci.http"

local M = {}
local SESSION_FILE = "/var/run/luci-twofa-sessions.json"

local function get_data()
	return json.parse(fs.readfile(SESSION_FILE) or "{}") or {}
end

function M.get_session_id()
	local dsp = require "luci.dispatcher"
	if dsp.context and dsp.context.authsession then
		return dsp.context.authsession
	end
	return http.getcookie("sysauth")
end

function M.is_enabled()
	return uci:get("twofa", "global", "enabled") == "1"
end

function M.is_verified(sid)
	if not M.is_enabled() then
		return true
	end
	if not sid or sid == "" then
		return false
	end
	return get_data()[sid] == true
end

function M.verify_token(sid, token)
	local secret = uci:get("twofa", "global", "secret")
	if secret and totp.verify(secret, token) then
		local d = get_data()
		d[sid] = true
		fs.writefile(SESSION_FILE, json.stringify(d))
		return true
	end
	return false
end

function M.deny_access()
	http.status(403, "Forbidden")
	http.prepare_content("application/json")
	http.write_json({ error = "Two-Factor Authentication Required" })
	http.close()
end

function M.check_access()
	if not M.is_enabled() then
		return true
	end
	if M.is_verified(M.get_session_id()) then
		return true
	end
	M.deny_access()
	return false
end

require "luci.twofa.guard".install()

return M
