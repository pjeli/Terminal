local ns = select(2, ...)

-- Alt+`'s printers: a line as Advanced mode writes it (ns.LineToAdvanced, Easy.ToAdvanced), the query a search read
-- printed (ns.QueryToAdvanced), and the lists the rows shown come from (ns.ShownKinds, Easy.ShownKinds). Moved out of
-- Search.lua and Simple.lua as they were.

local Scan = ns.UI._Scan
local function EasyOn() return ns.Easy ~= nil and ns.Easy.On() end

--- The lists the rows a search shows come from (real results only: no category, hint, help, pick or completion row,
--- nor a row that asks something), as a set of list ids. Alt+` names only these: "use hearthstone" shows the
--- Hearthstone in your bags, so @item, not every list "use" looks in (@camp @item @toy).
function ns.ShownKinds(rows)
	local set = {}
	for _, e in ipairs(rows or {}) do
		if type(e) == "table" and not (e.noActivate or e.raw or e.completion or e.catId or e.syntaxRow or e.lead) then
			local k = e.kind -- (an action's view: its row's kind)
			if type(k) == "string" and ns.providers[k] then set[k] = true end
		end
	end
	return set
end

----------------------------------------------------------------------
-- The query printed: Advanced syntax for what a line asks (Alt+`, Advanced syntax typed after plain words, the right-
-- click menu's chat lines). 0.55.4, the search's rewrite: the line is read by the search's own steps and its query
-- written out, so what's printed is what's searched (Easy.lua's Convert read the words a second way, and drifted:
-- "vendor ratchet" said faction:friendly the search never asked for, a place needed other words the search didn't).
----------------------------------------------------------------------

--- `text` (plain words, maybe with Advanced syntax in it) as Advanced syntax, ending with a space to type on ("" for
--- nothing). category: Simple mode's category picked (its lists as @kinds); shown: the lists the rows shown come from
--- (E.ShownKinds), so an action or a category names only those ("use hearthstone": @item, not @camp @item @toy).
--- noGroup: leave the bar's group step out (the caller puts it after what follows).
function ns.QueryToAdvanced(text, category, shown, noGroup)
	-- (the line the search shown read a second time, a date's words as a name's, "Tonight We Dine": read so here too,
	-- UI:Search's secondLook; review: Alt+` wrote "we dine since:today", which finds nothing)
	local UIs = ns.UI
	local typed = (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
	local how = UIs and UIs.secondLook ~= nil and UIs.secondLook == typed and { noAlt = true } or nil
	text = ns.Easy and ns.Easy.English and ns.Easy.English(text) or text
	local asked = ns.QuestionToAdvanced(text)
	if asked then
		-- (a question: what Simple mode's bar picked after it, as its search takes them: Scan.AnswerView)
		local bar = ns.Easy and ns.Easy.On() and ns.Bar and ns.Bar.Active()
		if not bar then return asked end
		local line = asked:gsub("%s+$", "")
		for _, w in ipairs(bar.filters) do line = line .. " " .. w end
		if bar.sort then line = line .. " sort:" .. bar.sort end
		if bar.group and not noGroup then line = line .. " | group by " .. bar.group end
		return line .. " "
	end
	local scratch = {} -- (the steps say things to the window: not to this one)
	-- (the words read as plain words, whatever mode the terminal is in: Alt+` writes what Simple mode would search)
	local E = ns.Easy
	local was = E.reading
	E.reading = true
	local ok, q = pcall(function()
		local r = Scan.Parse(scratch, text, how)
		Scan.ActionAndPlace(scratch, r)
		Scan.Prepare(scratch, r)
		return r
	end)
	E.reading = was
	if not ok then error(q) end
	local out, seen = {}, {}
	local function Add(w) if w and w ~= "" and not seen[w] then seen[w] = true; out[#out + 1] = w end end
	local function KindWord(id) return ns:KindName(ns.providers[id]) end
	-- the lists: @kinds typed; an action's (those showing something; none showing: do:<word> stands for them all); a
	-- category's (those showing, else all of them); a trainer's word or "nearest": the NPCs
	local act = q.act
	local function AddKinds(set, all)
		local ids, n = {}, 0
		for k in pairs(set or {}) do if all or not shown or shown[k] then ids[#ids + 1] = k end end
		table.sort(ids)
		for _, k in ipairs(ids) do if ns.providers[k] then Add(KindWord(k)); n = n + 1 end end
		return n
	end
	if q.typedKinds then
		AddKinds(q.kinds, true)
	elseif act and act.map then
		local set = {}
		for k in pairs(act.map) do set[k] = true end
		AddKinds(set)
	elseif q.kindCat and ns.Easy.BY_ID[q.kindCat] and not (category and category ~= q.kindCat) then
		-- (a word naming the kind, "hogger quest": its category's lists, or the one it names; Query.lua's Scan.KindWord)
		local set = {}
		if q.kindOnly and ns.providers[q.kindOnly] then set[q.kindOnly] = true
		else for _, k in ipairs(ns.Easy.BY_ID[q.kindCat].kinds) do set[k] = true end end
		if AddKinds(set) == 0 then AddKinds(set, true) end
	elseif category and ns.Easy.BY_ID[category] then
		local set = {}
		for _, k in ipairs(ns.Easy.BY_ID[category].kinds) do set[k] = true end
		if AddKinds(set) == 0 then AddKinds(set, true) end
	end
	local nearest = act and act.nearest
	-- ("farthest innkeeper": sort:-distance; 0.65.7)
	local distWord
	if nearest and q.actWord then distWord = act.far and "sort:-distance" or "sort:distance" else distWord = q.sortFar and "sort:-distance" or "sort:distance" end
	-- (0.55.18) the words shown found nothing passing every everyday word, so the closest were listed (UI.softRelaxed,
	-- this very line): those words written as words, not as filters nothing passes ("linen cloth": not type:cloth)
	local relaxed = {}
	local UIr = ns.UI
	local function Trim(t) return (t:gsub("^%s+", ""):gsub("%s+$", "")) end
	if UIr and UIr.softRelaxed and UIr.edit and ns.Lower(Trim(UIr.edit:GetText() or "")) == ns.Lower(Trim(text)) then
		for i, f in ipairs(q.softs or {}) do relaxed[f] = q.softWords and q.softWords[i] or true end
	end
	-- (an everyday word for a kind of item, "sword": that kind, or the word in a name; written so, sword|type:sword, as
	-- type:sword alone left out what's named so without the item data saying it; 0.55.18)
	local softWord = {}
	for i, f in ipairs(q.softs or {}) do softWord[f] = q.softWords and q.softWords[i] end
	local specs, plainWords = {}, {}
	for _, f in ipairs(q.filters or {}) do
		local spec = q.specOf and q.specOf[f]
		local w = softWord[f]
		if spec and w and spec:find("^type:") and not w:find("[%s|]") then spec = w .. "|" .. spec end
		if relaxed[f] then
			if type(relaxed[f]) == "string" then plainWords[#plainWords + 1] = relaxed[f] end
		elseif spec then
			specs[#specs + 1] = spec
		end
	end
	table.sort(specs, function(a, b) -- (a place first: "in:ratchet is:vendor"; else as said)
		local pa, pb = a:find("^in:") ~= nil, b:find("^in:") ~= nil
		if pa ~= pb then return pa end
		return false
	end)
	local I = ns.Integrations
	if nearest then
		-- "nearest mailbox": its own list, not NPCs; "nearest unlearned flight master": the flight paths' (the words that
		-- only say flight path or flight master go, @flight says it)
		local okind = I and I.ObjectKind and I.ObjectKind(q.tokens)
		if okind and ns.providers[okind] then
			local line = { "@" .. okind }
			for _, sp in ipairs(specs) do line[#line + 1] = sp end
			line[#line + 1] = distWord
			return table.concat(line, " ") .. " "
		end
		local rest = I and I.FlightAsked and ns.providers.flight and I.FlightAsked(q.tokens, q.softWords, not ns.providers.npc)
		if rest then
			local SAID = { ["is:flight"] = true, ["is:flightmaster"] = true, ["is:flightpath"] = true }
			local line = { KindWord("flight") }
			for _, w in ipairs(rest) do line[#line + 1] = w end
			for _, sp in ipairs(specs) do if not SAID[sp] then line[#line + 1] = sp end end
			line[#line + 1] = distWord
			return table.concat(line, " ") .. " "
		end
	end
	if q.trainerAsked or nearest then Add(KindWord("npc") or "@npc") end
	-- what Enter does stays what was asked ("use hearthstone": do:use)
	if act and act.map and not nearest and q.actWord then Add("do:" .. q.actWord) end
	-- (each as it was typed: "Hogger", not the search's lowercase; FRONT_END.md 10.1)
	local typed = q.typedOf or {}
	for _, w in ipairs(q.tokens) do
		local as = typed[w] or w
		Add(q.exact and q.exact[w] and ('"' .. as .. '"') or as)
	end
	for _, w in ipairs(plainWords) do Add(w) end
	-- (a value of several words, read without its quotes, in:The Barrens: written with them again, in:"The Barrens";
	-- 0.55.16, the player's screenshot: Alt+` wrote in:The Barrens, which searched for "Barrens" as a word too)
	-- (each piece of a | or & list on its own, after its - or key: -"outlaw saber", type:dagger|"pirate saber"; review)
	local function Quoted(sp)
		if sp:find('"', 1, true) or not sp:find("%s") then return sp end
		return (sp:gsub("[^|&]+", function(piece)
			local neg, key, v = piece:match("^([-!]?)(%a+:)(.+)$")
			if not key then neg, v = piece:match("^([-!]?)(.+)$"); key = "" end
			if v and v:find("%s") then return neg .. key .. '"' .. v .. '"' end
			return piece
		end))
	end
	for i, sp in ipairs(specs) do specs[i] = Quoted(sp) end
	for _, sp in ipairs(specs) do Add(sp) end
	-- an NPC's role (trainer, vendor...) nearest: one who'll serve you (Scan.NearestStart)
	if nearest and Scan.RoleFriendly(q.softWords, q.strictWords) then Add("faction:friendly") end
	if nearest or q.sortNear then Add(distWord) end
	if q.sortPlan then Add("sort:plan") end
	if q.sortBest then Add("sort:best") end
	if q.sortField then Add("sort:" .. q.sortField) end
	local line = table.concat(out, " ")
	if q.group and not noGroup then line = line .. (line ~= "" and " " or "") .. "| group by " .. q.group end
	return line ~= "" and (line .. " ") or ""
end

--- A whole line as Advanced mode writes it (Alt+`, Easy.ToAdvanced): its query printed (ns.QueryToAdvanced), then what
--- the line's reading has after it, in the one order the search applies them (UI/Results.lua's TakeAggregate): the
--- comparison and top N said in words, the bar's Group, the steps; the send. A ">> party" or "| sum value" typed after
--- the words is kept as typed (review, 0.53.6: "hogger >> party" became "hogger party >> ", "cloth | sum value" "sum
--- value type:cloth | "); Simple mode's copy in words, "linen to csv", is the send it stands for, ">>> csv" (review: it
--- was written "linen csv", which copied nothing).
function ns.LineToAdvanced(text, category, shown, noGroup)
	local line = tostring(text or "")
	local r = ns.Phrase.ReadLine(line, { simple = EasyOn() })
	local t, tail = line, ""
	if r.send then t, tail = line:sub(1, r.send.at - 1), " " .. line:sub(r.send.at)
	elseif r.copy then t, tail = r.copy.query, " >>> " .. r.copy.how end
	if r.steps then
		t, tail = r.steps.query, " | " .. table.concat(r.steps.list, " | ") .. tail
	elseif r.top or r.setop then
		-- ("the 3 nearest mailboxes": "| first 3", 0.66.7; "but not in my bank": "| except @bank", 0.66.10)
		local add = (r.setop and (" | " .. r.setop.step) or "") .. (r.top and (" | first " .. r.top.n) or "")
		local bar = ns.Bar and ns.Bar.Active and ns.Bar.Active()
		if bar and bar.group and not noGroup then add = add .. " | group by " .. bar.group end
		t = r.query
		text, tail = t, add .. tail
	end
	local Print = ns.QueryToAdvanced
	if tail == "" then return Print(text, category, shown, noGroup) end
	return (Print(t, category, shown, noGroup or tail:find("|", 1, true) ~= nil):gsub("%s+$", "")) .. tail
end
