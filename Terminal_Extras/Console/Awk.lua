-- (Terminal Extras, a load-on-demand addon of its own: Terminal's namespace is its public table, _G.Terminal)
local ns = _G.Terminal
if not ns then return end
local L = ns.L

-- awk in the console (branch console-dev): the real language's everyday part, over what's piped in or files.
-- Rules (pattern { action }, BEGIN, END; a /regex/ alone matches $0), fields ($0 $1 $NF, -F), NR NF, variables and
-- arrays (for (k in a), k in a, delete), arithmetic, comparisons, ~ !~, && || !, ?:, concatenation, assignments,
-- ++ --, if/else, while, for, break, continue, next, exit, print, printf, and length substr index split tolower toupper
-- int sprintf. A tsh extension: on an ls -l line, its columns are variables too (dist, zone, name, path...): awk
-- 'dist < 300 { print name }'. Comparing, a value with a number in front counts as that number (312yd is 312).
-- `print` alone prints the line as it came (colours and ls -l's columns kept, for the next pipe).
-- Nothing here yields: a program runs a line inside a pcall (next, exit, break and continue are errors caught there).

local SH, FS = ns.Shell, ns.ConsoleFS
local AWK = {}
SH.Awk = AWK

AWK.LOOP_MAX = 100000 -- (a loop that never ends stops here)

----------------------------------------------------------------------
-- Values
----------------------------------------------------------------------

local function Num(v)
	if type(v) == "number" then return v end
	if type(v) ~= "string" then return 0 end
	return tonumber(v:match("^%s*([%+%-]?%d*%.?%d+[eE][%+%-]?%d+)") or v:match("^%s*([%+%-]?%d*%.?%d+)") or "") or 0
end

local function LooksNum(v)
	return type(v) == "number" or (type(v) == "string" and v:match("^%s*[%+%-]?%.?%d") ~= nil)
end

local function Str(v)
	if type(v) == "number" then
		if v == math.floor(v) and math.abs(v) < 1e15 then return ("%.0f"):format(v) end
		return ("%.6g"):format(v)
	end
	if v == nil or type(v) == "table" then return "" end
	return v
end

local function Truth(v)
	if type(v) == "number" then return v ~= 0 end
	return v ~= nil and v ~= ""
end

local function Compare(a, b, op)
	local x, y
	if LooksNum(a) and LooksNum(b) then x, y = Num(a), Num(b) else x, y = Str(a), Str(b) end
	if op == "<" then return x < y elseif op == "<=" then return x <= y elseif op == ">" then return x > y
	elseif op == ">=" then return x >= y elseif op == "==" then return x == y else return x ~= y end
end

AWK.Num, AWK.Str = Num, Str

----------------------------------------------------------------------
-- Reading the program
----------------------------------------------------------------------

local KEYWORDS = { BEGIN = true, END = true, ["if"] = true, ["else"] = true, ["while"] = true, ["for"] = true,
	["in"] = true, print = true, printf = true, next = true, exit = true, ["break"] = true, ["continue"] = true,
	delete = true }
local OPS2 = { ["&&"] = true, ["||"] = true, ["=="] = true, ["!="] = true, ["<="] = true, [">="] = true, ["!~"] = true,
	["++"] = true, ["--"] = true, ["+="] = true, ["-="] = true, ["*="] = true, ["/="] = true, ["%="] = true, ["^="] = true }
local ESCAPES = { n = "\n", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/", r = "\r" }

local function Oops(msg) error({ awk = msg }, 0) end

--- The program's tokens: { t = "num" | "str" | "regex" | "name" | "kw" | "op" | "nl" | "eof", v }.
function AWK.Lex(src)
	local toks, i, n = {}, 1, #src
	local function Push(t, v) toks[#toks + 1] = { t = t, v = v } end
	local function RegexHere() -- (a / where a value can't end: a regex, not a division)
		local last = toks[#toks]
		if not last then return true end
		if last.t == "num" or last.t == "str" or last.t == "name" or last.t == "regex" then return false end
		if last.t == "op" and (last.v == ")" or last.v == "]" or last.v == "$" or last.v == "++" or last.v == "--") then return false end
		return true
	end
	while i <= n do
		local c = src:sub(i, i)
		if c == " " or c == "\t" or c == "\r" then
			i = i + 1
		elseif c == "\\" and src:sub(i + 1, i + 1) == "\n" then
			i = i + 2
		elseif c == "\n" or c == ";" then
			Push("nl", c)
			i = i + 1
		elseif c == "#" then
			i = src:find("\n", i, true) or (n + 1)
		elseif c:match("%d") or (c == "." and src:sub(i + 1, i + 1):match("%d")) then
			local num = src:match("^%d*%.?%d+[eE][%+%-]?%d+", i) or src:match("^%d+%.?%d*", i) or src:match("^%.%d+", i)
			Push("num", tonumber(num))
			i = i + #num
		elseif c == '"' then
			local j, buf = i + 1, {}
			while j <= n and src:sub(j, j) ~= '"' do
				local ch = src:sub(j, j)
				if ch == "\\" and j < n then
					local e = src:sub(j + 1, j + 1)
					buf[#buf + 1] = ESCAPES[e] or ("\\" .. e)
					j = j + 2
				else
					buf[#buf + 1] = ch
					j = j + 1
				end
			end
			if j > n then return nil, L["a string never closed"] end
			Push("str", table.concat(buf))
			i = j + 1
		elseif c == "/" and RegexHere() then
			local j, buf = i + 1, {}
			while j <= n and src:sub(j, j) ~= "/" do
				local ch = src:sub(j, j)
				if ch == "\\" and src:sub(j + 1, j + 1) == "/" then buf[#buf + 1] = "/" j = j + 2
				elseif ch == "\\" then buf[#buf + 1] = src:sub(j, j + 1) j = j + 2
				else buf[#buf + 1] = ch j = j + 1 end
			end
			if j > n then return nil, L["a /regex/ never closed"] end
			Push("regex", table.concat(buf))
			i = j + 1
		elseif c:match("[%a_]") then
			local w = src:match("^[%w_]+", i)
			Push(KEYWORDS[w] and "kw" or "name", w)
			i = i + #w
		else
			local two = src:sub(i, i + 1)
			if OPS2[two] then
				Push("op", two)
				i = i + 2
			elseif ("{}()[],$+-*/%^!<>=~?:"):find(c, 1, true) then
				Push("op", c)
				i = i + 1
			else
				return nil, L["unexpected '%s'"]:format(c)
			end
		end
	end
	Push("eof")
	return toks
end

local BUILTINS = {}

--- The program as closures: { begins = { fn }, rules = { { pattern, action } }, ends = { fn } }, or nil and the error.
function AWK.Compile(src)
	local toks, lexErr = AWK.Lex(src)
	if not toks then return nil, lexErr end
	local pos = 1
	local function Peek() return toks[pos] end
	local function Is(t, v) local k = toks[pos] return k.t == t and (v == nil or k.v == v) end
	local function Accept(t, v) if Is(t, v) then pos = pos + 1 return toks[pos - 1] end end
	local function Expect(t, v)
		local k = Accept(t, v)
		if not k then
			local at = toks[pos]
			Oops(L["syntax error near '%s'"]:format(tostring(at.t == "eof" and "end" or at.t == "nl" and "newline" or at.v)))
		end
		return k
	end
	local function SkipNl() while Is("nl", "\n") do pos = pos + 1 end end
	local function SkipSeps() while Accept("nl") do end end

	local Expr, Statement

	local function Array(R, name)
		local a = R.vars[name]
		if type(a) ~= "table" then a = {} R.vars[name] = a end
		return a
	end

	local function Primary()
		local k = Peek()
		if Accept("num") or Accept("str") then
			local v = k.v
			return { f = function() return v end }
		end
		if Accept("regex") then
			local m = SH.Matcher(k.v, { case = true })
			return { f = function(R) return m(Str(R.Field(0))) and 1 or 0 end, regex = m }
		end
		if Accept("op", "(") then
			local e = Expr()
			Expect("op", ")")
			return { f = e.f }
		end
		if Accept("op", "$") then
			local ie
			if Accept("op", "(") then ie = Expr() Expect("op", ")") else ie = Primary() end
			local lv = {
				get = function(R) return R.Field(Num(ie.f(R))) end,
				set = function(R, v) R.SetField(Num(ie.f(R)), v) end,
			}
			return { f = lv.get, lv = lv }
		end
		if Is("name") then
			local name = Peek().v
			pos = pos + 1
			if BUILTINS[name] then
				local args = {}
				if Accept("op", "(") then
					if not Accept("op", ")") then
						repeat args[#args + 1] = Expr() until not Accept("op", ",")
						Expect("op", ")")
					end
				elseif name ~= "length" then
					Oops(L["%s needs ( )"]:format(name))
				end
				local b = BUILTINS[name]
				return { f = function(R) return b(R, args) end }
			end
			if Accept("op", "[") then
				local ix = Expr()
				Expect("op", "]")
				local lv = {
					get = function(R) local v = Array(R, name)[Str(ix.f(R))] if v == nil then return "" end return v end,
					set = function(R, v) Array(R, name)[Str(ix.f(R))] = v end,
				}
				return { f = lv.get, lv = lv, array = name }
			end
			local lv = { get = function(R) return R.Get(name) end, set = function(R, v) R.Set(name, v) end }
			return { f = lv.get, lv = lv, name = name }
		end
		Oops(L["syntax error near '%s'"]:format(tostring(k.t == "eof" and "end" or k.v or k.t)))
	end

	local function Postfix()
		local e = Primary()
		if e.lv and (Is("op", "++") or Is("op", "--")) then
			local step = Peek().v == "++" and 1 or -1
			pos = pos + 1
			local lv = e.lv
			return { f = function(R) local old = Num(lv.get(R)) lv.set(R, old + step) return old end }
		end
		return e
	end

	local Unary
	local function Power()
		local base = Postfix()
		if Accept("op", "^") then
			local ex = Unary() -- (right to left: 2^3^2 is 2^9)
			return { f = function(R) return Num(base.f(R)) ^ Num(ex.f(R)) end }
		end
		return base
	end

	Unary = function()
		if Accept("op", "!") then
			local e = Unary()
			return { f = function(R) return Truth(e.f(R)) and 0 or 1 end }
		end
		if Accept("op", "-") then
			local e = Unary()
			return { f = function(R) return -Num(e.f(R)) end }
		end
		if Accept("op", "+") then
			local e = Unary()
			return { f = function(R) return Num(e.f(R)) end }
		end
		if Is("op", "++") or Is("op", "--") then
			local step = Peek().v == "++" and 1 or -1
			pos = pos + 1
			local e = Unary()
			if not e.lv then Oops(L["++ and -- need a variable"]) end
			local lv = e.lv
			return { f = function(R) local v = Num(lv.get(R)) + step lv.set(R, v) return v end }
		end
		return Power()
	end

	local function Mul()
		local e = Unary()
		while Is("op", "*") or Is("op", "/") or Is("op", "%") do
			local op = Peek().v
			pos = pos + 1
			local a, b = e, Unary()
			if op == "*" then e = { f = function(R) return Num(a.f(R)) * Num(b.f(R)) end }
			elseif op == "/" then
				e = { f = function(R)
					local y = Num(b.f(R))
					if y == 0 then Oops(L["division by zero"]) end
					return Num(a.f(R)) / y
				end }
			else
				e = { f = function(R)
					local x, y = Num(a.f(R)), Num(b.f(R))
					if y == 0 then Oops(L["division by zero"]) end
					return math.fmod(x, y)
				end }
			end
		end
		return e
	end

	local function Add()
		local e = Mul()
		while Is("op", "+") or Is("op", "-") do
			local op = Peek().v
			pos = pos + 1
			local a, b = e, Mul()
			if op == "+" then e = { f = function(R) return Num(a.f(R)) + Num(b.f(R)) end }
			else e = { f = function(R) return Num(a.f(R)) - Num(b.f(R)) end } end
		end
		return e
	end

	-- (two values side by side are joined: print $1 "-" $2)
	local function StartsValue()
		local k = Peek()
		return k.t == "num" or k.t == "str" or k.t == "name" or (k.t == "op" and (k.v == "$" or k.v == "(" or k.v == "!"))
	end
	local function Concat()
		local e = Add()
		while StartsValue() and not (Is("kw", "in")) do
			local a, b = e, Add()
			e = { f = function(R) return Str(a.f(R)) .. Str(b.f(R)) end }
		end
		return e
	end

	local function Compare_()
		local e = Concat()
		local k = Peek()
		if k.t == "op" and (k.v == "<" or k.v == "<=" or k.v == ">" or k.v == ">=" or k.v == "==" or k.v == "!=") then
			pos = pos + 1
			local op = k.v
			local a, b = e, Concat()
			e = { f = function(R) return Compare(a.f(R), b.f(R), op) and 1 or 0 end }
		end
		return e
	end

	local function Match()
		local e = Compare_()
		while Is("op", "~") or Is("op", "!~") do
			local negate = Peek().v == "!~"
			pos = pos + 1
			local a, b = e, Compare_()
			local fixed = b.regex
			e = { f = function(R)
				local m = fixed or SH.Matcher(Str(b.f(R)), { case = true })
				local hit = m(Str(a.f(R))) ~= nil
				if negate then hit = not hit end
				return hit and 1 or 0
			end }
		end
		return e
	end

	local function In()
		local e = Match()
		if Accept("kw", "in") then
			local arr = Expect("name").v
			local key = e
			e = { f = function(R) return Array(R, arr)[Str(key.f(R))] ~= nil and 1 or 0 end }
		end
		return e
	end

	local function And()
		local e = In()
		while Accept("op", "&&") do
			SkipNl()
			local a, b = e, In()
			e = { f = function(R) return (Truth(a.f(R)) and Truth(b.f(R))) and 1 or 0 end }
		end
		return e
	end

	local function Or()
		local e = And()
		while Accept("op", "||") do
			SkipNl()
			local a, b = e, And()
			e = { f = function(R) return (Truth(a.f(R)) or Truth(b.f(R))) and 1 or 0 end }
		end
		return e
	end

	local function Ternary()
		local c = Or()
		if Accept("op", "?") then
			local a = Ternary()
			Expect("op", ":")
			local b = Ternary()
			return { f = function(R) if Truth(c.f(R)) then return a.f(R) end return b.f(R) end }
		end
		return c
	end

	local ASSIGN = { ["="] = true, ["+="] = true, ["-="] = true, ["*="] = true, ["/="] = true, ["%="] = true, ["^="] = true }
	local function Assign()
		local e = Ternary()
		local k = Peek()
		if e.lv and k.t == "op" and ASSIGN[k.v] then
			pos = pos + 1
			local op, lv, rhs = k.v, e.lv, Assign()
			return { f = function(R)
				local v = rhs.f(R)
				if op ~= "=" then
					local x, y = Num(lv.get(R)), Num(v)
					if op == "+=" then v = x + y elseif op == "-=" then v = x - y elseif op == "*=" then v = x * y
					elseif op == "/=" then if y == 0 then Oops(L["division by zero"]) end v = x / y
					elseif op == "%=" then if y == 0 then Oops(L["division by zero"]) end v = math.fmod(x, y)
					else v = x ^ y end
				end
				lv.set(R, v)
				return v
			end }
		end
		return e
	end
	Expr = Assign

	local function StatementEnd()
		local k = Peek()
		return k.t == "nl" or k.t == "eof" or (k.t == "op" and k.v == "}")
	end

	local function Block()
		Expect("op", "{")
		local list = {}
		SkipSeps()
		while not Accept("op", "}") do
			if Is("eof") then Oops(L["a { never closed"]) end
			list[#list + 1] = Statement()
			SkipSeps()
		end
		return function(R) for _, s in ipairs(list) do s(R) end end
	end

	local function ExprList()
		local args = {}
		if Is("op", "(") then -- print("a", "b"): the list in brackets
			local save = pos
			pos = pos + 1
			local ok = pcall(function()
				repeat args[#args + 1] = Expr() until not Accept("op", ",")
				Expect("op", ")")
			end)
			if ok and StatementEnd() then return args end
			pos, args = save, {}
		end
		if not StatementEnd() then
			repeat args[#args + 1] = Expr() until not Accept("op", ",")
		end
		return args
	end

	local BREAK, CONTINUE = { loop = "break" }, { loop = "continue" }
	-- a loop's body: break and continue are errors thrown to it
	local function Loop(body, R)
		local ok, e = pcall(body, R)
		if ok then return true end
		if e == BREAK then return false end
		if e == CONTINUE then return true end
		error(e, 0)
	end

	Statement = function()
		SkipSeps()
		if Is("op", "{") then return Block() end
		if Accept("kw", "if") then
			Expect("op", "(")
			local c = Expr()
			Expect("op", ")")
			SkipNl()
			local yes = Statement()
			local save = pos
			SkipSeps()
			local no
			if Accept("kw", "else") then SkipNl() no = Statement() else pos = save end
			return function(R)
				if Truth(c.f(R)) then yes(R) elseif no then no(R) end
			end
		end
		if Accept("kw", "while") then
			Expect("op", "(")
			local c = Expr()
			Expect("op", ")")
			SkipNl()
			local body = Statement()
			return function(R)
				local n = 0
				while Truth(c.f(R)) do
					n = n + 1
					if n > AWK.LOOP_MAX then Oops(L["a loop that never ended"]) end
					if not Loop(body, R) then break end
				end
			end
		end
		if Accept("kw", "for") then
			Expect("op", "(")
			if Is("name") and toks[pos + 1].t == "kw" and toks[pos + 1].v == "in" and toks[pos + 2].t == "name"
				and toks[pos + 3].t == "op" and toks[pos + 3].v == ")" then
				local var, arr = toks[pos].v, toks[pos + 2].v
				pos = pos + 4
				SkipNl()
				local body = Statement()
				return function(R)
					local keys = {}
					for k in pairs(Array(R, arr)) do keys[#keys + 1] = k end
					table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
					for _, k in ipairs(keys) do
						R.Set(var, k)
						if not Loop(body, R) then break end
					end
				end
			end
			local init = not Is("nl", ";") and Expr() or nil
			Expect("nl", ";")
			local cond = not Is("nl", ";") and Expr() or nil
			Expect("nl", ";")
			local step = not Is("op", ")") and Expr() or nil
			Expect("op", ")")
			SkipNl()
			local body = Statement()
			return function(R)
				if init then init.f(R) end
				local n = 0
				while not cond or Truth(cond.f(R)) do
					n = n + 1
					if n > AWK.LOOP_MAX then Oops(L["a loop that never ended"]) end
					if not Loop(body, R) then break end
					if step then step.f(R) end
				end
			end
		end
		if Accept("kw", "break") then return function() error(BREAK, 0) end end
		if Accept("kw", "continue") then return function() error(CONTINUE, 0) end end
		if Accept("kw", "next") then return function() error({ next = true }, 0) end end
		if Accept("kw", "exit") then return function() error({ exit = true }, 0) end end
		if Accept("kw", "delete") then
			local name = Expect("name").v
			if Accept("op", "[") then
				local ix = Expr()
				Expect("op", "]")
				return function(R) Array(R, name)[Str(ix.f(R))] = nil end
			end
			return function(R) R.vars[name] = {} end
		end
		if Accept("kw", "print") then
			local args = ExprList()
			return function(R)
				if #args == 0 then R.PrintRecord() return end
				local parts = {}
				for i, a in ipairs(args) do parts[i] = Str(a.f(R)) end
				R.Write(table.concat(parts, Str(R.Get("OFS"))) .. "\n")
			end
		end
		if Accept("kw", "printf") then
			local args = ExprList()
			if #args == 0 then Oops(L["printf needs a format"]) end
			return function(R)
				local vals = {}
				for i = 2, #args do vals[#vals + 1] = args[i].f(R) end
				R.Write(AWK.Sprintf(Str(args[1].f(R)), vals))
			end
		end
		local e = Expr()
		return function(R) e.f(R) end
	end

	local prog = { begins = {}, rules = {}, ends = {} }
	local ok, err = pcall(function()
		SkipSeps()
		while not Is("eof") do
			if Accept("kw", "BEGIN") then
				SkipNl()
				prog.begins[#prog.begins + 1] = Block()
			elseif Accept("kw", "END") then
				SkipNl()
				prog.ends[#prog.ends + 1] = Block()
			else
				local pattern = not Is("op", "{") and Expr() or nil
				local action = Is("op", "{") and Block() or nil
				prog.rules[#prog.rules + 1] = { pattern = pattern, action = action }
			end
			SkipSeps()
		end
	end)
	if not ok then return nil, type(err) == "table" and err.awk or tostring(err) end
	return prog
end

----------------------------------------------------------------------
-- What it can call
----------------------------------------------------------------------

--- printf's and sprintf's formats: %s %d %i %f %g %e %x %o %c %% with flags and widths.
function AWK.Sprintf(fmt, vals)
	local i = 0
	return (fmt:gsub("%%([%-%+ #0]*%d*%.?%d*)([%a%%])", function(flags, conv)
		if conv == "%" then return "%" end
		i = i + 1
		local v = vals[i]
		if conv == "d" or conv == "i" then
			local n = Num(v)
			n = n < 0 and math.ceil(n) or math.floor(n)
			return ("%" .. flags:gsub("%.%d*", "") .. ".0f"):format(n) -- (not %d: it overflows past 2^31 here)
		elseif conv == "s" then return ("%" .. flags .. "s"):format(Str(v))
		elseif conv == "c" then
			local s = type(v) == "number" and string.char(math.max(0, math.min(255, math.floor(v)))) or Str(v):sub(1, 1)
			return ("%" .. flags .. "s"):format(s)
		elseif conv == "x" or conv == "X" or conv == "o" then return ("%" .. flags .. conv):format(math.floor(Num(v)))
		elseif conv == "f" or conv == "g" or conv == "e" or conv == "G" or conv == "E" then return ("%" .. flags .. conv):format(Num(v))
		end
		return "%" .. flags .. conv
	end))
end

BUILTINS.length = function(R, a) return #Str(a[1] and a[1].f(R) or R.Field(0)) end
BUILTINS.substr = function(R, a)
	local s = Str(a[1] and a[1].f(R))
	local m = math.floor(Num(a[2] and a[2].f(R) or 1) + 0.5)
	local n = a[3] and math.floor(Num(a[3].f(R)) + 0.5) or #s
	local from, to = math.max(1, m), math.min(#s, m + n - 1)
	if to < from then return "" end
	return s:sub(from, to)
end
BUILTINS.index = function(R, a) return Str(a[1].f(R)):find(Str(a[2].f(R)), 1, true) or 0 end
BUILTINS.tolower = function(R, a) return ns.Lower(Str(a[1].f(R))) end
BUILTINS.toupper = function(R, a) return (Str(a[1].f(R)):upper()) end
BUILTINS.int = function(R, a) local n = Num(a[1].f(R)) return n < 0 and math.ceil(n) or math.floor(n) end
BUILTINS.sprintf = function(R, a)
	local vals = {}
	for i = 2, #a do vals[#vals + 1] = a[i].f(R) end
	return AWK.Sprintf(Str(a[1] and a[1].f(R)), vals)
end
-- split(s, arr[, sep]): the array is the second argument's name
BUILTINS.split = function(R, a)
	local s = Str(a[1].f(R))
	local name = a[2] and (a[2].name or a[2].array)
	if not name then Oops(L["split needs an array"]) end
	local arr = {}
	R.vars[name] = arr
	local sep = a[3] and Str(a[3].f(R)) or nil
	local n = 0
	for _, part in ipairs(R.Split(s, sep)) do n = n + 1 arr[tostring(n)] = part end
	return n
end

----------------------------------------------------------------------
-- Running it
----------------------------------------------------------------------

--- Runs a compiled program over lines. `opts`: fs (the -F separator), vars (-v), out(line), check() (between lines:
--- the shell's, it may yield). The status (0, or 2 and err(text) on an error).
function AWK.Run(prog, lines, opts)
	local R = { vars = {}, NR = 0 }
	for k, v in pairs(opts.vars or {}) do R.vars[k] = v end
	R.vars.OFS = R.vars.OFS or " "
	local sep = opts.fs
	if sep == "\\t" or sep == "t" then sep = "\t" end
	local pending = ""
	function R.Write(text)
		pending = pending .. text
		while true do
			local nl = pending:find("\n", 1, true)
			if not nl then break end
			opts.out(SH.Literal(pending:sub(1, nl - 1)))
			pending = pending:sub(nl + 1)
		end
	end
	function R.Split(s, by)
		local out = {}
		by = by or sep
		if not by or by == " " then
			for w in s:gmatch("%S+") do out[#out + 1] = w end
		else
			for part in (s .. by):gmatch("(.-)" .. by:gsub("%p", "%%%0")) do out[#out + 1] = part end
		end
		return out
	end
	local function Parts()
		if not R.parts then R.parts = R.Split(R.line) end
		return R.parts
	end
	function R.Field(i)
		i = math.floor(i)
		if i == 0 then return R.line or "" end
		if i < 0 then Oops(L["no field $%d"]:format(i)) end
		return Parts()[i] or ""
	end
	function R.SetField(i, v)
		i = math.floor(i)
		R.modified = true
		if i == 0 then R.line, R.parts = Str(v), nil return end
		local parts = Parts()
		for j = #parts + 1, i - 1 do parts[j] = "" end
		parts[i] = Str(v)
		R.line = table.concat(parts, Str(R.vars.OFS))
	end
	function R.Get(name)
		local v = R.vars[name]
		if v ~= nil then return v end
		if name == "NR" then return R.NR end
		if name == "NF" then return R.line and #Parts() or 0 end
		if name == "FS" then return sep or " " end
		-- (the tsh extension: an ls -l line's columns, by name)
		local long = R.long
		if long and (FS.COLUMN_INDEX[name] or name == "path") then
			local c = long[name]
			if c == "-" then return "" end
			return c
		end
		return ""
	end
	function R.Set(name, v)
		if name == "NF" then
			local parts = Parts()
			for j = #parts, Num(v) + 1, -1 do parts[j] = nil end
			R.SetField(1, parts[1] or "")
			return
		end
		R.vars[name] = v
	end
	function R.PrintRecord()
		if R.modified then opts.out(SH.Literal(R.line)) else opts.out(R.raw) end
	end

	local function Guard(fn)
		local ok, e = pcall(fn, R)
		if ok then return true end
		if type(e) == "table" and e.next then return true end
		if type(e) == "table" and e.exit then return false, "exit" end
		return false, type(e) == "table" and (e.awk or (e.loop and L["break or continue outside a loop"])) or tostring(e)
	end

	local stop
	for _, b in ipairs(prog.begins) do
		local ok, why = Guard(b)
		if not ok then
			if why ~= "exit" then opts.err(why) return 2 end
			stop = true
			break
		end
	end
	if not stop and (#prog.rules > 0 or #prog.ends > 0) then
		for i, raw in ipairs(lines or {}) do
			R.NR, R.raw, R.line, R.parts, R.modified = i, raw, FS.Strip(raw), nil, false
			R.long = FS.ParseLong(raw)
			local ok, why = Guard(function()
				for _, rule in ipairs(prog.rules) do
					if not rule.pattern or Truth(rule.pattern.f(R)) then
						if rule.action then rule.action(R) else R.PrintRecord() end
					end
				end
			end)
			if not ok then
				if why ~= "exit" then opts.err(why) return 2 end
				break
			end
			if opts.check and i % 128 == 0 then opts.check() end
		end
	end
	R.line, R.parts, R.long = R.line or "", nil, nil
	for _, e in ipairs(prog.ends) do
		local ok, why = Guard(e)
		if not ok then
			if why ~= "exit" then opts.err(why) return 2 end
			break
		end
	end
	if pending ~= "" then opts.out(SH.Literal(pending)) end
	return 0
end

SH.Command("awk", {
	desc = L["awk: pattern { action } over each line (fields $1 $NF, NR, BEGIN/END, arrays, printf); ls -l's columns by name"],
	usage = "awk [-F sep] [-v var=value] 'program' [file...]",
	man = {
		L["The real awk's everyday part: patterns and actions, BEGIN and END, $0 $1 $NF, NR NF, variables and arrays,"],
		L["+ - * / % ^, < <= > >= == !=, ~ !~ /regex/, && || !, ?:, if/else, while, for, for (k in a), next, exit,"],
		L["print, printf, length substr index split tolower toupper int sprintf. -F: the field separator, -v: a variable."],
		L["tsh's own: on an ls -l line its columns are variables (dist zone name path...); 312yd compares as 312;"],
		L["print alone keeps the line as it came (for the next pipe)."],
		L["seq 10 | awk '$1 % 2 == 0'      ls -lR /npc | awk 'dist < 300 && role ~ /repair/ { print dist, name }'"],
		L["ls -l /item | awk '{ n += count } END { print n }'      awk -F: '{ print $2 }'"],
	},
	run = function(io)
		local opts, rest = SH.Opts(io.args, "F:v:")
		if not opts then io.err(rest) return 2 end
		-- (-v may come more than once: SH.Opts keeps the last; read them all here)
		local vars = {}
		for i, a in ipairs(io.args) do
			local v = a == "-v" and io.args[i + 1] or a:match("^%-v(.+)$")
			if v then
				local k, val = v:match("^([%a_][%w_]*)=(.*)$") -- (not "v and v:match(...)": and keeps one result)
				if k then vars[k] = val end
			end
		end
		local src = table.remove(rest, 1)
		if not src then io.err(L["usage: awk [-F sep] [-v var=value] 'program' [file...]"]) return 2 end
		local prog, err = AWK.Compile(src)
		if not prog then io.err(err) return 2 end
		local lines = {}
		if #rest > 0 or #prog.rules > 0 or #prog.ends > 0 then
			lines = SH.InputLines(io, rest)
			if not lines then
				if #prog.rules > 0 or #prog.ends > 0 then io.err(L["no input: give a file, or pipe something in"]) return 2 end
				lines = {}
			end
		end
		return AWK.Run(prog, lines, { fs = opts.F, vars = vars, out = io.out, err = io.err, check = function() io.sh:Check() end })
	end,
})
