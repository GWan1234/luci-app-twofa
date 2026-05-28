-- TOTP (RFC 6238) verifier.
--
-- The earlier version relied on `bit.lshift(buffer, 5)` silently wrapping at
-- 32 bits while base32-decoding the secret. Lua 5.3+ (which ImmortalWrt /
-- recent OpenWrt ships) raises "arithmetic overflow" on integer overflow
-- instead of wrapping, so a 16-char secret (16 * 5 = 80 bits) crashed at
-- iteration 7. This rewrite avoids that:
--
--   * base32_decode uses plain multiplication / floor-division and masks
--     `buffer` after each emitted byte, so it never exceeds 12 bits.
--   * pack_int64 uses `%` and `math.floor` instead of `bit.band` on a
--     potentially large counter value.
--   * The final 31-bit truncation in HOTP only needs to clear the high bit
--     of one byte, which fits safely in any sane integer width.

local nixio = require "nixio"

-- For the small 8-bit masks we still need a bit-AND. Try every flavour
-- that has been shipped on OpenWrt over the years.
local bit = nixio.bit
if not bit then
	local ok, b = pcall(require, "bit")
	if ok then bit = b end
end
if not bit then
	local ok, b = pcall(require, "bit32")
	if ok then bit = b end
end
assert(bit and bit.band, "totp: no bit module available (need nixio.bit, bit, or bit32)")

local M = {}

local function hex2bin(hex)
	return (hex:gsub("..", function(cc) return string.char(tonumber(cc, 16)) end))
end

-- Big-endian 8-byte counter. counter for TOTP fits in 32 bits for the next
-- ~70 years, but we still use `%` / `floor` so we never feed a number that
-- could exceed 2^31 to a 32-bit bit op.
local function pack_int64(num)
	local t = {}
	for i = 8, 1, -1 do
		t[i] = string.char(num % 256)
		num  = math.floor(num / 256)
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
		if not v then
			error("base32: invalid char at position " .. i)
		end
		-- buffer << 5 | v, but as integer arithmetic so it can't overflow
		-- a 32-bit register and trip Lua 5.3+'s overflow detection.
		buffer    = buffer * 32 + v
		bits_left = bits_left + 5
		if bits_left >= 8 then
			bits_left  = bits_left - 8
			local div  = 2 ^ bits_left
			out[#out + 1] = string.char(math.floor(buffer / div) % 256)
			buffer     = buffer % div  -- drop the emitted bits, keep buffer tiny
		end
	end
	return table.concat(out)
end

local function generate(secret, offset, period)
	local key     = base32_decode(secret)
	local counter = math.floor(os.time() / (period or 30)) + (offset or 0)
	local cp      = pack_int64(counter)
	local hash    = hex2bin(nixio.crypto.hmac("sha1", key, cp))
	if #hash < 20 then
		error("totp: hmac returned " .. #hash .. " bytes (expected 20)")
	end
	local off = bit.band(string.byte(hash, -1), 0x0F)
	-- 31-bit "dynamic truncation" per RFC 4226. Use byte-wise arithmetic
	-- to stay clear of any 32-bit-vs-64-bit weirdness.
	local b1  = bit.band(string.byte(hash, off + 1), 0x7F)
	local b2  = string.byte(hash, off + 2)
	local b3  = string.byte(hash, off + 3)
	local b4  = string.byte(hash, off + 4)
	local bin = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
	return string.format("%06d", bin % 1000000)
end

function M.verify(secret, token)
	if type(secret) ~= "string" or type(token) ~= "string" then return false end
	if #token ~= 6 then return false end
	-- Accept the current slot or the previous one (±30s clock skew tolerance).
	return token == generate(secret, 0) or token == generate(secret, -1)
end

-- Exposed for diagnostics: `lua -l luci.twofa.totp -e 'print(...generate...)'`
M.generate = generate

return M
