-- The parse corpus's readings (docs/FRONT_END.md, Phase 0): what each line of tests/parse_corpus.txt is read into in
-- Simple mode, written out one block a line and compared with tests/parse_golden.txt. Run by tests/smoke/parse_golden_*.lua
-- (every 8th line each, from its own first: one file's 20M-instruction budget holds about a quarter of the corpus,
-- and the number and date phrases, the dearest, sit together in it), made again by
-- `python tests/gen_parse_golden.py` (PARSE_GOLDEN_WRITE set: the blocks are kept for it, not compared).
--
-- A block is the reading, never the results: the question that took the line (its index in Scan.ANSWERS, and the words
-- it was asked with), the query's words, filters (strength, Advanced form, signature, word), sort, lists, action and
-- place, the send, the steps, the bar's picks, the category, Alt+`'s line and .explain's words for it.
local T, part, parts = ...
local ns, UI, check = T.ns, T.UI, T.check
local E, B, Scan = ns.Easy, ns.Bar, UI._Scan

local G = {}

--- The corpus: its lines in order (comments and blank lines left out).
function G.Corpus()
	local f = assert(io.open("Terminal/tests/parse_corpus.txt", "r"))
	local out = {}
	for line in f:lines() do
		line = line:gsub("\r$", "")
		if line ~= "" and not line:find("^#") then out[#out + 1] = line end
	end
	f:close()
	return out
end

--- The golden file's blocks: line -> its block's text (the lines after the "== line" header, joined).
function G.Golden()
	local f = io.open("Terminal/tests/parse_golden.txt", "r")
	if not f then return nil end
	local out, cur, body = {}, nil, nil
	for line in f:lines() do
		line = line:gsub("\r$", "")
		local head = line:match("^== (.*)$")
		if head then
			if cur then out[cur] = table.concat(body, "\n") end
			cur, body = head, {}
		elseif cur and line ~= "" then
			body[#body + 1] = line
		end
	end
	if cur then out[cur] = table.concat(body, "\n") end
	f:close()
	return out
end

local function Fields(t, keys)
	local out = {}
	for _, k in ipairs(keys) do
		local v = t[k]
		if v ~= nil and type(v) ~= "table" and type(v) ~= "function" then out[#out + 1] = k .. "=" .. tostring(v) end
	end
	return table.concat(out, " ")
end

local function Sorted(set)
	local out = {}
	for k in pairs(set or {}) do out[#out + 1] = tostring(k) end
	table.sort(out)
	return table.concat(out, " ")
end

-- what each filter was added with (Scan.AddFilter, wrapped while the corpus is read)
local how = setmetatable({}, { __mode = "k" })
-- the question that took the line: its index in Scan.ANSWERS, and the words it was asked with
local asked

--- One line read, as a block of "key: value" lines.
function G.Read(line)
	asked = nil
	B.Reset()
	UI.lastScan, UI.lastExtra = nil, nil
	ns.db.easyMode = true; UI:EasyChanged()
	UI:Open(""); UI:SetQuery(line, #line); T.FlushAll()
	local res = UI.Results()
	local out = {}
	local function Add(k, v) out[#out + 1] = k .. ": " .. ((v == nil or v == "") and "-" or tostring(v)) end
	Add("question", asked)
	local q = UI.whyQ
	if q and not q.answer then
		local toks = {}
		for _, t in ipairs(q.tokens or {}) do toks[#toks + 1] = (q.exact and q.exact[t]) and ('"' .. t .. '"') or t end
		Add("tokens", table.concat(toks, " "))
		for _, f in ipairs(q.filters or {}) do
			local h = how[f] or {}
			Add("filter", ("%s %s%s%s"):format(h.how or "?", tostring(q.specOf and q.specOf[f] or "(no spec)"),
				h.sig and ("  sig=" .. tostring(h.sig)) or "", h.word and ("  word=" .. tostring(h.word)) or ""))
		end
		Add("sort", Fields(q, { "sortField", "sortNear", "sortFar", "sortBest", "sortPlan" }))
		Add("kinds", Sorted(q.kinds))
		Add("action", q.act and (tostring(q.act.label) .. (q.actWord and ("  word=" .. tostring(q.actWord)) or "")) or nil)
	end
	Add("place", UI.place and tostring(UI.place.key or UI.place.name) or nil)
	Add("send", UI.sendTo and Fields(UI.sendTo, { "label", "chat", "target", "all", "copy", "quests", "pending", "bad", "query" }) or nil)
	local agg = UI.aggregate
	Add("steps", agg and (Fields(agg, { "text", "first", "bad", "topWords", "fromBar" })
		.. (agg.last and ("  last=" .. tostring(agg.last.op) .. (agg.last.by and (":" .. tostring(agg.last.by)) or "")) or "")) or nil)
	Add("group", UI.typedGroup and Fields(UI.typedGroup, { "id", "word", "rest" }) or nil)
	local picks = UI.typedPicks
	for _, p in ipairs(picks and picks.filters or {}) do Add("pick", Fields(p, { "spec", "word", "plain" })) end
	Add("pick sort", picks and picks.sort and Fields(picks.sort, { "id", "word", "drop" }) or nil)
	Add("category", UI.category and tostring(UI.category.id or UI.category) or nil)
	local adv = E.ToAdvanced(UI.edit:GetText(), UI.category, E.ShownKinds(res))
	Add("advanced", adv and ("%q"):format(adv))
	local ok, said = pcall(E.Explain, adv)
	Add("explain", ok and said and ("%q"):format(said) or ("ERROR " .. tostring(said)))
	UI:Hide(); T.FlushAll(); B.Reset()
	return table.concat(out, "\n")
end

--- This part of the corpus read: compared with the golden file, or (PARSE_GOLDEN_WRITE) kept for the generator.
function G.Run()
	local lines = G.Corpus()
	-- (every parts-th line, not a run of them: the number and date phrases cost the most, and sit together)
	io.write(("[parse golden %d/%d: every %dth corpus line from line %d]\n"):format(part, parts, parts, part))
	local wasEasy = ns.db.easyMode
	-- (a character of level 30, as plainnumbers.lua's: the harness has none, and "lvl:me+3" reads as a word without one,
	-- where the game always has a level)
	local unitLevel = _G.UnitLevel
	_G.UnitLevel = function() return 30 end
	local addFilter, ask = Scan.AddFilter, Scan.Ask
	Scan.AddFilter = function(q, f, h, sig, word, spec)
		if f then how[f] = { how = h, sig = sig, word = word } end
		return addFilter(q, f, h, sig, word, spec)
	end
	Scan.Ask = function(self, text)
		local rows, a = ask(self, text)
		if rows then
			for i, x in ipairs(Scan.ANSWERS) do if x == a then asked = i .. "  asked=" .. text end end
		end
		return rows, a
	end
	local golden = not _G.PARSE_GOLDEN_WRITE and G.Golden() or nil
	local write = _G.PARSE_GOLDEN_WRITE
	if write then _G.PARSE_GOLDEN_OUT = _G.PARSE_GOLDEN_OUT or {} end
	local differ = 0
	local ok, err = pcall(function()
		for i = part, #lines, parts do
			local line = lines[i]
			local block = G.Read(line)
			if write then
				_G.PARSE_GOLDEN_OUT[i] = { line = line, block = block }
			elseif not golden then
				check(false, "parse golden: tests/parse_golden.txt is missing (python tests/gen_parse_golden.py)")
				return
			else
				local want = golden[line]
				if want ~= block then
					differ = differ + 1
					if differ <= 12 then
						io.write(("--- %q\n  golden:\n    %s\n  now:\n    %s\n"):format(line,
							want and want:gsub("\n", "\n    ") or "(not in the golden file)", block:gsub("\n", "\n    ")))
					end
				end
				check(want == block, ("parse golden: %q is read differently (diff above, or python tests/gen_parse_golden.py if meant)"):format(line))
			end
		end
	end)
	Scan.AddFilter, Scan.Ask = addFilter, ask
	_G.UnitLevel = unitLevel
	ns.db.easyMode = wasEasy; UI:EasyChanged()
	B.Reset()
	if not ok then check(false, "parse golden: " .. tostring(err)) end
	if differ > 12 then io.write(("(%d more lines read differently)\n"):format(differ - 12)) end
end

return G
