-- Terminal: Share's Crypto.lua (0.58.1, the share shell): SHA-256 and HMAC-SHA256 against the standard test vectors (FIPS 180-2, RFC 4231), on
-- both of its ways to do bit operations: plain arithmetic (this harness has no bit library) and the game's LuaBitOp,
-- whose answers are signed 32-bit numbers (a fake one here gives them signed, as the game's does).
local T = ...
local ns, check = T.ns, T.check

io.write("[crypto: SHA-256, HMAC]\n")

local VECTORS = {
	{ "", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" },
	{ "abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" },
	{ "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1" },
}

local function Run(C, how)
	for _, v in ipairs(VECTORS) do
		local got = C.Hex(C.SHA256(v[1]))
		check(got == v[2], how .. ": SHA-256(" .. ("%q"):format(v[1]:sub(1, 12)) .. "): " .. got)
	end
	local mac = C.Hex(C.HMAC("Jefe", "what do ya want for nothing?"))
	check(mac == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", how .. ": HMAC, RFC 4231 case 2: " .. mac)
	mac = C.Hex(C.HMAC(string.rep("\170", 131), "Test Using Larger Than Block-Size Key - Hash Key First"))
	check(mac == "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54", how .. ": HMAC, a key longer than a block (case 6): " .. mac)
end

Run(ns.Crypto, "plain arithmetic")

-- LuaBitOp's way: results signed (2^31 and up come back negative)
do
	local MOD = 4294967296
	local function signed(x) x = x % MOD; return x >= 2147483648 and x - MOD or x end
	local P = ns.Crypto -- (the plain-arithmetic answers, signed as LuaBitOp gives them)
	local fake = {
		band = function(a, b) return signed(P._band(a, b)) end,
		bor = function(a, b) return signed(P._bor(a, b)) end,
		bxor = function(a, b) return signed(P.bxor(a, b)) end,
		bnot = function(a) return signed(MOD - 1 - (a % MOD)) end,
		rshift = function(a, n) return signed(math.floor((a % MOD) / 2 ^ n)) end,
		lshift = function(a, n) return signed(((a % MOD) * 2 ^ n) % MOD) end,
	}
	local was = rawget(_G, "bit")
	_G.bit = fake
	local chunk = loadfile("Terminal_Share/Crypto.lua") or loadfile("Terminal/Terminal_Share/Crypto.lua")
	local mine = ns.Crypto
	local other = chunk("Terminal_Share", {})
	_G.bit = was
	ns.Crypto = mine -- (Share.lua's stays the one in use)
	check(other and other ~= mine, "loaded again, with a bit library")
	if other then Run(other, "LuaBitOp") end
	-- (a bit library whose answers are unsigned, 0 to 2^32-1: the same hashes, 0.59.0's quicker block either way)
	local unsigned = {
		band = function(a, b) return P._band(a, b) end, bor = function(a, b) return P._bor(a, b) end,
		bxor = function(a, b) return P.bxor(a, b) end, bnot = function(a) return MOD - 1 - (a % MOD) end,
		rshift = function(a, n) return math.floor((a % MOD) / 2 ^ n) end, lshift = function(a, n) return ((a % MOD) * 2 ^ n) % MOD end,
	}
	_G.bit = unsigned
	local third = chunk("Terminal_Share", {})
	_G.bit = was
	ns.Crypto = mine
	if third then Run(third, "unsigned bit library") end
end
