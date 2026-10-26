local ns = select(2, ...)
local L = ns.L

-- A row's "Why is this here?" (UI:WhyLines, UI:WhyHere): what the last search read (UI.whyQ) said of it. Moved out of
-- Search.lua as it was.

local UI = ns.UI

----------------------------------------------------------------------
-- "Why is this here?" (0.66.11, the player): a row's menu says why the last search listed it: which typed words it
-- matched and where, the filters it passed, the sort's value for it, and for an upgrade what it gains under .weights.
----------------------------------------------------------------------
--- The stats an upgrade changes, in words: "+7 str, +4 sta, -2 agi".
local function StatDiff(mine, worn)
	local keys, seen = {}, {}
	for k in pairs(mine or {}) do keys[#keys + 1] = k; seen[k] = true end
	for k in pairs(worn or {}) do if not seen[k] then keys[#keys + 1] = k end end
	local function D(k) return ((mine or {})[k] or 0) - ((worn or {})[k] or 0) end
	-- (the gains first, the biggest first; then what it gives up)
	table.sort(keys, function(a, b) local da, db = D(a), D(b) if da ~= db then return da > db end return a < b end)
	local out = {}
	for _, k in ipairs(keys) do
		local d = D(k)
		if math.abs(d) > 1e-9 then
			local n = math.floor(math.abs(d) * 10 + 0.5) / 10
			out[#out + 1] = (d > 0 and "+" or "-") .. tostring(n):gsub("%.0$", "") .. " " .. k
		end
	end
	return table.concat(out, ", ")
end

--- Why row `e` is in the last search's list: lines to show (the first says which row).
function UI:WhyLines(e)
	local E, F, A = ns.Easy, ns.Filters, ns.Aggregate
	local lines = {}
	local name = ns.Plain(tostring(e and e.name or "?"))
	lines[1] = L["Why %s is here:"]:format(name)
	local function Say(t) lines[#lines + 1] = "  " .. t end
	if type(e) ~= "table" then return lines end
	local kind = e.kind
	if kind and E and E.KindNoun then Say(L["it's one of %s"]:format(E.KindNoun(kind))) end
	local q = self.whyQ
	local also = rawget(e, "_also") -- (a row "| also" added: none of the search's words or filters brought it)
	if also then
		Say(L["added by | also %s"]:format(also))
	elseif q and q.answer then
		Say(L["your question \"%s\" lists it"]:format(q.answer))
	elseif q then
		-- the words typed: where each is in it
		local lname = ns.Lower(name)
		local ltext = rawget(e, "_ltext") or ns.Lower(tostring(e.text or ""))
		local ldetail = ns.Lower(ns.Plain(tostring(e.detail or "")))
		for _, tok in ipairs(q.tokens or {}) do
			if type(tok) == "string" and tok ~= "" then
				local where
				if lname:find(tok, 1, true) then where = L["in its name"]
				elseif ldetail:find(tok, 1, true) then where = L["in its details"]
				elseif ltext:find(tok, 1, true) then where = L["in what it's about (its other words)"]
				else where = L["a close spelling of a word in it"] end
				Say(L["\"%s\": %s"]:format(tok, where))
			end
		end
		-- the filters it passed
		for _, f in ipairs(q.filters or {}) do
			local spec = q.specOf and q.specOf[f]
			if spec then
				local said = E and E.SayFilter and E.SayFilter(spec)
				Say(said and L["passed %s (%s)"]:format(spec, said) or L["passed %s"]:format(spec))
			end
		end
		-- the sort: its value for this row
		if q.sortField and F and F.SortList and A and A.FIELDS then
			for _, part in ipairs(F.SortList(q.sortField)) do
				local base = part:gsub("^%-", "")
				local fd = A.FIELDS[base]
				local ok, v = false, nil
				-- (its words before its number: a quality's "Epic", not 4; a name, its own; review)
				if base == "name" then ok, v = true, name
				elseif fd and fd.text then ok, v = pcall(fd.text, e, fd)
				elseif fd and fd.num then ok, v = pcall(fd.num, e) end
				local shown = ok and v ~= nil and v ~= "" and (fd and fd.money and type(v) == "number" and ns.Money and ns.Money(v) or tostring(v)) or L["none"]
				Say(L["sorted by %s: %s"]:format(fd and fd.label or (base == "name" and L["name"]) or base, shown))
			end
		elseif q.sortBest then
			Say(L["sorted by the biggest upgrades first"])
		elseif q.sortNear then
			Say((q.sortFar and L["sorted farthest first"] or L["sorted nearest first"]) .. ((e.detail and e.detail ~= "") and (": " .. ns.Plain(tostring(e.detail))) or ""))
		end
	end
	-- an upgrade: what it gains, and by which weights
	local g = F and F.fitMade and F.GainOf and F.GainOf(e)
	if g then
		local one = (g.vs and g.vs[1]) or g
		local role = g.role and F.ROLE_SAY and F.ROLE_SAY[g.role] or g.role
		if one.byLevel or g.byLevel then
			Say(L["an upgrade by item level: %s over %s"]:format(tostring(one.ilvl or g.ilvl), tostring(one.wLvl or g.wLvl)))
		elseif g.empty then
			Say(L["an upgrade: nothing worn in its slot"])
		else
			local diff = StatDiff(g.kinds, one.worn or g.worn)
			Say(L["an upgrade: %s over %s, worth %s by %s weights"]:format(diff ~= "" and diff or "?", one.name or L["what you wear"],
				tostring(math.floor((g.gain or 0) * 10 + 0.5) / 10), role or L["your class's"]))
		end
		if g.capped then Say(L["hit past your cap counted for nothing"]) end
	end
	-- the steps after the search
	local agg = self.aggregate
	if agg and agg.first then Say(L["among the first %d"]:format(agg.first)) end
	return lines
end

--- A row's "Why is this here?": said in chat.
function UI:WhyHere(e)
	for _, l in ipairs(self:WhyLines(e)) do ns:Print(l) end
end
