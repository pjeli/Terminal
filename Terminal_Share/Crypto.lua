-- (Terminal: Share, an addon of its own: Terminal's namespace is its public table, _G.Terminal)
local ns = _G.Terminal
if not ns then return end

-- SHA-256 and HMAC-SHA256 (0.58.1, the share shell: friends' Terminals prove they know a shared password without sending
-- it; Share.lua). The game's bit library (LuaBitOp: results are signed 32-bit, so each is taken mod 2^32), or plain
-- Lua arithmetic where there's none (the test harness). Strings in and out are raw bytes; Hex for text.

local C = {}
ns.Crypto = C

local floor, char, byte, format, concat = math.floor, string.char, string.byte, string.format, table.concat
local MOD = 4294967296

local band, bor, bxor, rshift, lshift, bnot
local B = rawget(_G, "bit")
if type(B) == "table" and B.band and B.bxor and B.rshift and B.lshift then
	band = function(a, b) return B.band(a, b) % MOD end
	bor = function(a, b) return B.bor(a, b) % MOD end
	bxor = function(a, b) return B.bxor(a, b) % MOD end
	rshift = function(a, n) return B.rshift(a, n) % MOD end
	lshift = function(a, n) return B.lshift(a, n) % MOD end
	bnot = function(a) return B.bnot(a) % MOD end
else
	-- (four bits at a time from small tables)
	local AND, OR, XOR = {}, {}, {}
	for a = 0, 15 do
		for b = 0, 15 do
			local x, y, r_and, r_or, r_xor, bitv = a, b, 0, 0, 0, 1
			for _ = 1, 4 do
				local p, q = x % 2, y % 2
				if p == 1 and q == 1 then r_and = r_and + bitv end
				if p == 1 or q == 1 then r_or = r_or + bitv end
				if p ~= q then r_xor = r_xor + bitv end
				x, y, bitv = floor(x / 2), floor(y / 2), bitv * 2
			end
			AND[a * 16 + b], OR[a * 16 + b], XOR[a * 16 + b] = r_and, r_or, r_xor
		end
	end
	local function Op(t)
		return function(a, b)
			a, b = a % MOD, b % MOD
			local r, m = 0, 1
			for _ = 1, 8 do
				r = r + t[(a % 16) * 16 + (b % 16)] * m
				a, b, m = floor(a / 16), floor(b / 16), m * 16
			end
			return r
		end
	end
	band, bor, bxor = Op(AND), Op(OR), Op(XOR)
	rshift = function(a, n) return floor((a % MOD) / 2 ^ n) end
	lshift = function(a, n) return ((a % MOD) * 2 ^ n) % MOD end
	bnot = function(a) return MOD - 1 - (a % MOD) end
end
C.bxor, C._band, C._bor = bxor, band, bor -- (tests)

local function rrot(x, n) return bor(rshift(x, n), lshift(x, 32 - n)) end

local K = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local w = {}
local function Block(h, s, at)
	for j = 1, 16 do
		local a, b, c, d = byte(s, at + (j - 1) * 4, at + (j - 1) * 4 + 3)
		w[j] = ((a * 256 + b) * 256 + c) * 256 + d
	end
	for j = 17, 64 do
		local x, y = w[j - 15], w[j - 2]
		local s0 = bxor(bxor(rrot(x, 7), rrot(x, 18)), rshift(x, 3))
		local s1 = bxor(bxor(rrot(y, 17), rrot(y, 19)), rshift(y, 10))
		w[j] = (w[j - 16] + s0 + w[j - 7] + s1) % MOD
	end
	local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
	for j = 1, 64 do
		local S1 = bxor(bxor(rrot(e, 6), rrot(e, 11)), rrot(e, 25))
		local ch = bxor(band(e, f), band(bnot(e), g))
		local t1 = (hh + S1 + ch + K[j] + w[j]) % MOD
		local S0 = bxor(bxor(rrot(a, 2), rrot(a, 13)), rrot(a, 22))
		local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
		local t2 = (S0 + maj) % MOD
		hh, g, f, e, d, c, b, a = g, f, e, (d + t1) % MOD, c, b, a, (t1 + t2) % MOD
	end
	h[1], h[2], h[3], h[4] = (h[1] + a) % MOD, (h[2] + b) % MOD, (h[3] + c) % MOD, (h[4] + d) % MOD
	h[5], h[6], h[7], h[8] = (h[5] + e) % MOD, (h[6] + f) % MOD, (h[7] + g) % MOD, (h[8] + hh) % MOD
end

--- SHA-256 of a string: 32 raw bytes.
function C.SHA256(msg)
	msg = tostring(msg or "")
	local len = #msg
	local bits = len * 8
	local lenBytes = {}
	for i = 8, 1, -1 do lenBytes[i] = char(bits % 256); bits = floor(bits / 256) end
	local s = msg .. "\128" .. string.rep("\0", (55 - len) % 64) .. concat(lenBytes)
	local h = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
	for at = 1, #s, 64 do Block(h, s, at) end
	local out = {}
	for i = 1, 8 do
		local x = h[i]
		out[i] = char(floor(x / 16777216) % 256, floor(x / 65536) % 256, floor(x / 256) % 256, x % 256)
	end
	return concat(out)
end

--- Raw bytes as lowercase hex.
function C.Hex(s)
	return (tostring(s or ""):gsub(".", function(c) return format("%02x", byte(c)) end))
end

local function XorPad(key, pad)
	local out = {}
	for i = 1, 64 do out[i] = char(bxor(byte(key, i) or 0, pad)) end
	return concat(out)
end

--- HMAC-SHA256 of `msg` under `key`: 32 raw bytes.
function C.HMAC(key, msg)
	key = tostring(key or "")
	if #key > 64 then key = C.SHA256(key) end
	return C.SHA256(XorPad(key, 0x5c) .. C.SHA256(XorPad(key, 0x36) .. tostring(msg or "")))
end

--- A key from a password: SHA-256 iterated `rounds` times over it (a guess costs as many hashes), salted with what
--- it's for.
function C.Derive(password, salt, rounds)
	password = tostring(password or "")
	local k = C.SHA256(tostring(salt or "") .. "\0" .. password)
	for _ = 1, rounds or 1 do k = C.SHA256(k .. password) end
	return k
end

return C -- (tests: loaded again with a bit library)
