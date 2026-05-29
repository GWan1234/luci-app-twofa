-- TOTP (RFC 6238) verifier.
--
-- Two production lessons baked into this rewrite:
--
--   1. base32 decoding must mask the accumulator after every emitted byte,
--      otherwise `buffer` exceeds 2^31 by the 13th input char and Lua 5.3+
--      (which ImmortalWrt / recent OpenWrt ships) raises
--      "arithmetic overflow" on integer conversion.
--
--   2. nixio.crypto is OPTIONAL. The libnixio variant shipped on some
--      firmwares (notably ImmortalWrt's default) was compiled without
--      OpenSSL, so `nixio.crypto.hmac` simply doesn't exist. We therefore
--      ship a self-contained pure-Lua HMAC-SHA1 implementation that uses
--      only band/bor/bxor on 32-bit values plus arithmetic rotates, which
--      works on every Lua bit module that has ever shipped with LuCI.

local nixio = require "nixio"

-- Resolve a working bit module; only basic 32-bit boolean ops are needed.
local bit = nixio.bit
if not bit then
	local ok, b = pcall(require, "bit");   if ok then bit = b end
end
if not bit then
	local ok, b = pcall(require, "bit32"); if ok then bit = b end
end
assert(bit and bit.band and bit.bor and bit.bxor,
	"totp: no bit module available (need nixio.bit, bit, or bit32)")

local band = bit.band
local bor  = bit.bor
local bxor = bit.bxor

local M = {}

-- ----------------------------------------------------------------------------
-- 32-bit rotate-left, computed with arithmetic so we never feed a value
-- larger than 2^32 into bit.lshift (that's the trap Lua 5.3+ falls into).
-- ----------------------------------------------------------------------------
local function rol(x, n)
	local pow = 2 ^ (32 - n)
	local hi  = math.floor(x / pow)
	return (x - hi * pow) * 2 ^ n + hi
end

-- ----------------------------------------------------------------------------
-- SHA-1 over an arbitrary byte string. Returns 20 raw bytes.
-- ----------------------------------------------------------------------------
local function sha1(msg)
	local orig_len = #msg
	msg = msg .. "\x80"
	while (#msg % 64) ~= 56 do
		msg = msg .. "\0"
	end
	-- Append the original length in bits as a 64-bit big-endian integer.
	local bits = orig_len * 8
	local tail = {}
	for i = 1, 8 do
		tail[i] = string.char(math.floor(bits / 2 ^ ((8 - i) * 8)) % 256)
	end
	msg = msg .. table.concat(tail)

	local h0, h1, h2, h3, h4 =
		0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
	local w = {}

	for blk = 1, #msg, 64 do
		for i = 0, 15 do
			local p = blk + i * 4
			w[i] = string.byte(msg, p)     * 16777216
				 + string.byte(msg, p + 1) * 65536
				 + string.byte(msg, p + 2) * 256
				 + string.byte(msg, p + 3)
		end
		for i = 16, 79 do
			w[i] = rol(bxor(bxor(w[i-3], w[i-8]), bxor(w[i-14], w[i-16])), 1)
		end

		local a, b, c, d, e = h0, h1, h2, h3, h4
		for i = 0, 79 do
			local f, k
			if i < 20 then
				f = bor(band(b, c), band(bxor(0xFFFFFFFF, b), d))
				k = 0x5A827999
			elseif i < 40 then
				f = bxor(bxor(b, c), d)
				k = 0x6ED9EBA1
			elseif i < 60 then
				f = bor(bor(band(b, c), band(b, d)), band(c, d))
				k = 0x8F1BBCDC
			else
				f = bxor(bxor(b, c), d)
				k = 0xCA62C1D6
			end
			local t = (rol(a, 5) + f + e + k + w[i]) % 0x100000000
			e = d; d = c; c = rol(b, 30); b = a; a = t
		end

		h0 = (h0 + a) % 0x100000000
		h1 = (h1 + b) % 0x100000000
		h2 = (h2 + c) % 0x100000000
		h3 = (h3 + d) % 0x100000000
		h4 = (h4 + e) % 0x100000000
	end

	local out = {}
	for _, h in ipairs({ h0, h1, h2, h3, h4 }) do
		for i = 1, 4 do
			out[#out + 1] = string.char(math.floor(h / 2 ^ ((4 - i) * 8)) % 256)
		end
	end
	return table.concat(out)
end

-- ----------------------------------------------------------------------------
-- HMAC-SHA1: 20 raw bytes. Pure-Lua fallback when nixio.crypto is missing.
-- ----------------------------------------------------------------------------
local function hmac_sha1_pure(key, msg)
	if #key > 64 then key = sha1(key) end
	if #key < 64 then key = key .. string.rep("\0", 64 - #key) end
	local ipad, opad = {}, {}
	for i = 1, 64 do
		local k = string.byte(key, i)
		ipad[i] = string.char(bxor(k, 0x36))
		opad[i] = string.char(bxor(k, 0x5C))
	end
	return sha1(table.concat(opad) .. sha1(table.concat(ipad) .. msg))
end

local function hex2bin(hex)
	return (hex:gsub("..", function(cc) return string.char(tonumber(cc, 16)) end))
end

local hmac_sha1
if nixio.crypto and nixio.crypto.hmac then
	hmac_sha1 = function(key, msg)
		return hex2bin(nixio.crypto.hmac("sha1", key, msg))
	end
else
	hmac_sha1 = hmac_sha1_pure
end

M._hmac_backend = (nixio.crypto and nixio.crypto.hmac) and "nixio.crypto" or "pure-lua"

-- ----------------------------------------------------------------------------
-- Big-endian 8-byte counter, no bit ops needed.
-- ----------------------------------------------------------------------------
local function pack_int64(num)
	local t = {}
	for i = 8, 1, -1 do
		t[i] = string.char(num % 256)
		num = math.floor(num / 256)
	end
	return table.concat(t)
end

local B32_MAP = {
	A=0,  B=1,  C=2,  D=3,  E=4,  F=5,  G=6,  H=7,
	I=8,  J=9,  K=10, L=11, M=12, N=13, O=14, P=15,
	Q=16, R=17, S=18, T=19, U=20, V=21, W=22, X=23,
	Y=24, Z=25, ["2"]=26, ["3"]=27, ["4"]=28, ["5"]=29,
	["6"]=30, ["7"]=31,
}

local function base32_decode(s)
	s = (s or ""):upper():gsub("[^A-Z2-7]", "")
	local buffer    = 0
	local bits_left = 0
	local out       = {}
	for i = 1, #s do
		local v = B32_MAP[s:sub(i, i)]
		if not v then error("base32: invalid char at position " .. i) end
		buffer    = buffer * 32 + v
		bits_left = bits_left + 5
		if bits_left >= 8 then
			bits_left = bits_left - 8
			local div = 2 ^ bits_left
			out[#out + 1] = string.char(math.floor(buffer / div) % 256)
			buffer = buffer % div
		end
	end
	return table.concat(out)
end

local function generate(secret, offset, period)
	local key     = base32_decode(secret)
	local counter = math.floor(os.time() / (period or 30)) + (offset or 0)
	local hash    = hmac_sha1(key, pack_int64(counter))
	if #hash < 20 then
		error("totp: hmac returned " .. #hash .. " bytes (expected 20)")
	end
	local off = band(string.byte(hash, -1), 0x0F)
	local b1  = band(string.byte(hash, off + 1), 0x7F)
	local b2  = string.byte(hash, off + 2)
	local b3  = string.byte(hash, off + 3)
	local b4  = string.byte(hash, off + 4)
	local bin = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
	return string.format("%06d", bin % 1000000)
end

function M.verify(secret, token)
	if type(secret) ~= "string" or type(token) ~= "string" or #token ~= 6 then
		return false
	end
	-- Accept codes from previous, current, and next time windows for clock drift tolerance
	return token == generate(secret, -1) or
	       token == generate(secret, 0) or
	       token == generate(secret, 1)
end

-- Exposed for diagnostics. Lets you run, e.g.:
--   lua -e 'print(require("luci.twofa.totp").generate("JBSWY3DPEHPK3PXP", 0))'
M.generate = generate

-- Debug function to diagnose TOTP generation issues
function M.debug_generate(secret, offset, period)
	local key = base32_decode(secret)
	print("[DEBUG] Secret (Base32): " .. secret)
	print("[DEBUG] Key length: " .. #key .. " bytes")
	print("[DEBUG] Key (hex): " .. (key:gsub(".", function(c)
		return string.format("%02x", string.byte(c))
	end)))

	local counter = math.floor(os.time() / (period or 30)) + (offset or 0)
	print("[DEBUG] Counter (T): " .. counter)

	local packed = pack_int64(counter)
	print("[DEBUG] Counter (packed hex): " .. (packed:gsub(".", function(c)
		return string.format("%02x", string.byte(c))
	end)))

	local hash = hmac_sha1(key, packed)
	print("[DEBUG] HMAC-SHA1 length: " .. #hash)
	print("[DEBUG] HMAC-SHA1 (hex): " .. (hash:gsub(".", function(c)
		return string.format("%02x", string.byte(c))
	end)))

	local off = band(string.byte(hash, -1), 0x0F)
	print("[DEBUG] Offset: " .. off)

	local b1 = band(string.byte(hash, off + 1), 0x7F)
	local b2 = string.byte(hash, off + 2)
	local b3 = string.byte(hash, off + 3)
	local b4 = string.byte(hash, off + 4)

	print("[DEBUG] Bytes: " .. b1 .. " " .. b2 .. " " .. b3 .. " " .. b4)

	local bin = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
	print("[DEBUG] Binary value: " .. bin)

	local code = string.format("%06d", bin % 1000000)
	print("[DEBUG] Final code: " .. code)

	return code
end

return M
