local ns = select(2, ...)

-- Calculator. Type arithmetic and the answer is the top result:
--   3*45            = 135
--   =2^10           = 1,024        (a leading = also works for a single value)
--   12.5% * 800     = 100          (% is "percent of")
--   50% of 800      = 400
--   3 x 45g 20s     = 135g 60s     (gold, silver, copper: g s c)
--   =123456c        = 12g 34s 56c
--   2k / 8          = 250          (k = thousand, m = million)
--   sqrt(2), floor(), ceil(), round(), abs(), min(a, b), max(a, b), pi
-- Enter prints the sum and answer in chat; Shift+Enter puts the answer in the chat box.
-- Hand-written parser: nothing typed here is ever run as Lua.

local C = {}
ns.Calc = C

local MONEY = { g = 10000, s = 100, c = 1 }
local SCALE = { k = 1e3, m = 1e6 }
local FUNCS = {
	sqrt = math.sqrt, floor = math.floor, ceil = math.ceil, abs = math.abs,
	round = function(x) return math.floor(x + 0.5) end,
	min = math.min, max = math.max,
}

local function Tokenize(s)
	local toks, i, n = {}, 1, #s
	while i <= n do
		local ch = s:sub(i, i)
		if ch:match("%s") then
			i = i + 1
		elseif ch:match("[%d%.]") then
			local num = s:match("^%d*%.?%d+", i) or s:match("^%d+%.?", i)
			if not num then return nil end
			i = i + #num
			local v = tonumber(num)
			if not v then return nil end
			-- a unit straight after the number (not the start of a word like "of")
			local u = s:sub(i, i):lower()
			local after = s:sub(i + 1, i + 1)
			if (MONEY[u] or SCALE[u]) and not after:match("%a") then
				i = i + 1
				if MONEY[u] then
					toks[#toks + 1] = { t = "num", v = v * MONEY[u], money = true }
				else
					toks[#toks + 1] = { t = "num", v = v * SCALE[u] }
				end
			else
				toks[#toks + 1] = { t = "num", v = v }
			end
		elseif ch:match("%a") then
			local w = s:match("^%a+", i):lower()
			i = i + #w
			if w == "x" then
				toks[#toks + 1] = { t = "op", v = "*" }
			elseif w == "of" then
				toks[#toks + 1] = { t = "op", v = "*" }
			elseif w == "pi" then
				toks[#toks + 1] = { t = "num", v = math.pi }
			elseif FUNCS[w] then
				toks[#toks + 1] = { t = "fn", v = w }
			else
				return nil -- any other word: not a sum
			end
		elseif ch:match("[%+%-%*/%^%%%(%),]") then
			toks[#toks + 1] = { t = "op", v = ch }
			i = i + 1
		elseif ch == "\195" and s:sub(i, i + 1) == "\195\151" then -- ×
			toks[#toks + 1] = { t = "op", v = "*" }
			i = i + 2
		else
			return nil
		end
	end
	return toks
end

-- values are { v = number, money = bool }
local function Parse(toks)
	local pos, binops = 1, 0
	local function peek() return toks[pos] end
	local function isop(o) local t = toks[pos] return t and t.t == "op" and t.v == o end
	local expr

	local function primary()
		local t = toks[pos]
		if not t then error("end") end
		if t.t == "num" then
			pos = pos + 1
			local val = { v = t.v, money = t.money }
			-- "45g 20s": adjacent money amounts add up
			while toks[pos] and toks[pos].t == "num" and toks[pos].money and val.money do
				val.v = val.v + toks[pos].v
				pos = pos + 1
			end
			return val
		elseif t.t == "fn" then
			pos = pos + 1
			if not isop("(") then error("(") end
			pos = pos + 1
			local args = { expr() }
			while isop(",") do pos = pos + 1; args[#args + 1] = expr() end
			if not isop(")") then error(")") end
			pos = pos + 1
			local nums = {}
			for k, a in ipairs(args) do nums[k] = a.v end
			return { v = FUNCS[t.v](unpack(nums)), money = args[1].money }
		elseif isop("(") then
			pos = pos + 1
			local v = expr()
			if not isop(")") then error(")") end
			pos = pos + 1
			return v
		elseif isop("-") then
			pos = pos + 1
			local v = primary()
			return { v = -v.v, money = v.money }
		elseif isop("+") then
			pos = pos + 1
			return primary()
		end
		error("unexpected")
	end

	local function postfix()
		local v = primary()
		while isop("%") do -- percent
			pos = pos + 1
			v = { v = v.v / 100, money = v.money }
		end
		return v
	end

	local function power()
		local base = postfix()
		if isop("^") then
			pos = pos + 1
			binops = binops + 1
			local e = power() -- right associative
			return { v = base.v ^ e.v, money = base.money }
		end
		return base
	end

	local function term()
		local v = power()
		while isop("*") or isop("/") do
			local o = peek().v
			pos = pos + 1
			binops = binops + 1
			local r = power()
			if o == "*" then
				v = { v = v.v * r.v, money = v.money or r.money }
			else
				if r.v == 0 then error("div0") end
				-- gold / gold is a plain ratio
				v = { v = v.v / r.v, money = v.money and not r.money }
			end
		end
		return v
	end

	function expr()
		local v = term()
		while isop("+") or isop("-") do
			local o = peek().v
			pos = pos + 1
			binops = binops + 1
			local r = term()
			v = { v = o == "+" and v.v + r.v or v.v - r.v, money = v.money or r.money }
		end
		return v
	end

	local v = expr()
	if pos <= #toks then error("trailing") end
	return v, binops
end

local function Group(int)
	local s = tostring(int)
	if #s <= 4 then return s end
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function FormatNumber(x)
	if x ~= x or x == math.huge or x == -math.huge then return nil end
	local neg = x < 0
	x = math.abs(x)
	local s
	if x == math.floor(x) and x < 1e15 then
		s = Group(string.format("%d", x))
	else
		s = string.format("%.6f", x):gsub("0+$", ""):gsub("%.$", "")
		local int, frac = s:match("^(%d+)(.*)$")
		if int then s = Group(int) .. frac end
	end
	return (neg and "-" or "") .. s
end

local function FormatMoney(copper)
	if copper ~= copper or copper == math.huge or copper == -math.huge then return nil end
	local neg = copper < 0
	copper = math.floor(math.abs(copper) + 0.5)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = Group(g) .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	return (neg and "-" or "") .. table.concat(parts, " ")
end

--- The answer to a sum, or nil when the text isn't one. A plain query needs at least one
--- operator ("3*45"); with a leading "=" a single value is fine ("=123456c").
function C.Evaluate(text)
	if type(text) ~= "string" then return nil end
	local s = text:gsub("^%s+", ""):gsub("%s+$", "")
	local forced = false
	if s:sub(1, 1) == "=" then
		forced, s = true, s:sub(2)
	end
	if s == "" or not s:find("%d") and not s:lower():find("pi") then return nil end
	local toks = Tokenize(s)
	if not toks or #toks == 0 then return nil end
	local ok, v, binops = pcall(Parse, toks)
	if not ok or type(v) ~= "table" then return nil end
	local hasPercent = s:find("%%")
	if not forced and binops == 0 and not hasPercent then return nil end
	local answer = v.money and FormatMoney(v.v) or FormatNumber(v.v)
	if not answer then return nil end
	return answer, s, v
end

--- The result row for the terminal, or nil.
function C.Entry(text)
	local answer, sum = C.Evaluate(text)
	if not answer then return nil end
	return {
		kind = "calc",
		kindLabel = "|cff9fd0ffCalc|r",
		name = "= " .. answer,
		_lname = answer,
		key = "calc",
		icon = "Interface\\Icons\\INV_Misc_Note_02",
		detail = sum,
		answer = answer,
		sum = sum,
		_pos = {},
		activate = function(e)
			ns:Output({ e.sum .. " = " .. e.answer })
		end,
		-- Shift+Enter: the answer into the chat box, ready to send
		secondary = function(e)
			if ChatFrame_OpenChat then
				ChatFrame_OpenChat(e.answer)
			elseif ChatEdit_ActivateChat and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox then
				ChatEdit_ActivateChat(DEFAULT_CHAT_FRAME.editBox)
				DEFAULT_CHAT_FRAME.editBox:Insert(e.answer)
			end
		end,
	}
end
