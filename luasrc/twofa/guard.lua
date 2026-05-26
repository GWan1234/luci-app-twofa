local M = {}
local installed = false

local ADMIN_WHITELIST = {
	login = true,
	logout = true,
	ubus = true,
}

local function path_whitelisted(path)
	if not path or not path[1] then
		return true
	end

	if path[1] ~= "admin" then
		return true
	end

	if ADMIN_WHITELIST[path[2]] then
		return true
	end

	if path[2] == "services" and path[3] == "twofa" then
		return true
	end

	return false
end

local function should_block()
	local auth = require "luci.twofa.auth"
	local dsp = require "luci.dispatcher"
	local path = dsp.context and dsp.context.path

	if path_whitelisted(path) then
		return false
	end

	if not auth.is_enabled() then
		return false
	end

	return not auth.is_verified(auth.get_session_id())
end

function M.install()
	if installed then
		return
	end

	local ok, dsp = pcall(require, "luci.dispatcher")
	if not ok or not dsp then
		return
	end

	for _, name in ipairs({ "dispatch", "httpdispatch" }) do
		local orig = dsp[name]
		if type(orig) == "function" then
			dsp[name] = function(...)
				if should_block() then
					require("luci.twofa.auth").deny_access()
					return
				end
				return orig(...)
			end
			installed = true
			return
		end
	end
end

return M
