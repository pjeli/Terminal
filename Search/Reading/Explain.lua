local ns = select(2, ...)
local L = ns.L

-- .explain: an Advanced line said in plain words (Easy.Explain), its vocabulary (the bar's words for some filters:
-- E.LevelSay, E.TimeSay, E.SinceSay), and UI.LooksAdvanced. Moved out of Easy.lua (now Simple.lua) as it was.

local E = ns.Easy
local Lower = ns.Lower

----------------------------------------------------------------------
-- An Advanced line read back in plain words (0.66.9, the player: "the explain; reverse Alt+`"): .explain <line>, or the
-- last line you ran. "@npc is:vendor sells:arrow faction:friendly sort:distance" -> "Friendly vendors that sell arrow,
-- nearest first". For lines pasted by others, old aliases, and learning the syntax.
----------------------------------------------------------------------
local KIND_NOUN = { npc = L["NPCs"], items = L["items"], gear = L["gear you wear"], quests = L["quests in your log"],
	questie = L["quests"], spells = L["spells"], classspells = L["class spells"], talents = L["talents"], loot = L["dungeon loot"],
	mail = L["mail"], auctions = L["auctions"], lootlog = L["loot you saw drop"], combatlog = L["combat log lines"],
	history = L["lines you ran"], buyback = L["items you sold to vendors"], mailbox = L["mailboxes"], forge = L["forges"], anvil = L["anvils"],
	cookingfire = L["cooking fires"], moonwell = L["moonwells"], flight = L["flight paths"],
	recipes = L["recipes"], professions = L["professions"], stored = L["your alts' and bank's items"], bank = L["your bank"],
	mounts = L["mounts"], pets = L["pets"], toys = L["toys"], achievements = L["achievements"], maps = L["zones"],
	consumables = L["consumables"], mats = L["crafting mats"], reputation = L["reputations"], currency = L["currencies"],
	macros = L["macros"], keybinds = L["key bindings"], durability = L["your gear's durability"], calendar = L["calendar events"],
	lockouts = L["lockouts"], group = L["your group"], guild = L["your guild"], friends = L["your friends"], shared = L["friends' items"],
	-- (as typed, when the list isn't loaded: Questie's, the game objects')
	quest = L["quests in your log"], item = L["items"], spell = L["spells"], mount = L["mounts"], drop = L["loot you saw drop"] }
local IS_SAY = { vendor = L["vendors"], trainer = L["trainers"], classtrainer = L["class trainers"], proftrainer = L["profession trainers"],
	innkeeper = L["innkeepers"], banker = L["bankers"], repair = L["repairers"], flightmaster = L["flight masters"],
	auctioneer = L["auctioneers"], questgiver = L["quest givers"], stablemaster = L["stable masters"], spirithealer = L["spirit healers"],
	battlemaster = L["battlemasters"], weaponmaster = L["weapon masters"], upgrade = L["upgrades for you"] }
local IS_ADJ = { boe = L["bind on equip"], soulbound = L["soulbound"], usable = L["usable"], equippable = L["equippable"],
	done = L["done"], todo = L["not done yet"], complete = L["complete"], ready = L["ready"], craftable = L["craftable"],
	skillup = L["giving skill"], known = L["known"], unknown = L["not known yet"], learnable = L["learnable now"],
	unread = L["unread"], expiring = L["running out"], enchanted = L["enchanted"], unenchanted = L["unenchanted"],
	favorite = L["favorite"], tracked = L["tracked"], untracked = L["untracked"], online = L["online"], offline = L["offline"],
	dead = L["dead"], grey = L["grey"], sold = L["sold"], listed = L["listed"], mine = L["yours"] }
local SORT_SAY = { distance = L["nearest first"], ["-distance"] = L["farthest first"], name = L["A to Z"], ["-name"] = L["Z to A"],
	level = L["lowest level first"], ["-level"] = L["highest level first"], ilvl = L["highest item level first"],
	["-ilvl"] = L["lowest item level first"], quality = L["best quality first"], ["-quality"] = L["worst quality first"],
	value = L["most valuable first"], ["-value"] = L["cheapest first"], count = L["the most first"], ["-count"] = L["the fewest first"],
	best = L["biggest upgrades first"], plan = L["the recipes that still give skill, by how often your mats make them"],
	damage = L["biggest hits first"], line = L["line by line"], owner = L["by owner"], slots = L["most slots first"],
	["-slots"] = L["fewest slots first"], ahvalue = L["highest AH value first"], ahprice = L["highest AH price first"] }
--- A sort: word ("sort:quality,-level") said: "best quality first, then highest level first"; nil when it isn't one.
local function SortSay(word)
	local F = ns.Filters
	local so = F and F.SortOf and F.SortOf(word)
	local said = {}
	for i, part in ipairs(so and F.SortList(so) or {}) do said[i] = SORT_SAY[part] or part end
	return #said > 0 and table.concat(said, ", " .. L["then"] .. " ") or nil
end
local TIME_SAY = { today = L["today"], yesterday = L["yesterday"], week = L["this week"], month = L["this month"], login = L["this session"] }

--- A range as words: "20-30" -> "20-30", "<25" -> "under 25", ">=25" -> "25 or more", "20+" -> "20 or more".
local function RangeSay(v)
	local op, n = v:match("^([<>]=?)(.+)$")
	if op == "<" then return L["under %s"]:format(n) end
	if op == "<=" then return L["%s or less"]:format(n) end
	if op == ">" then return L["over %s"]:format(n) end
	if op == ">=" then return L["%s or more"]:format(n) end
	local plus = v:match("^(.+)%+$")
	if plus then return L["%s or more"]:format(plus) end
	return v
end
--- lvl:me+3 as words: "3 levels above yours"; else the range's.
local function LevelSay(v)
	if not v:find("me", 1, true) then return L["level %s"]:format(RangeSay(v)) end
	local function One(x)
		if x == "me" then return L["your level"] end
		local sign, n = x:match("^me([%+%-])(%d+)$")
		if sign == "+" then return L["%s above yours"]:format(n == "1" and L["a level"] or L["%s levels"]:format(n)) end
		if sign == "-" then return L["%s below yours"]:format(n == "1" and L["a level"] or L["%s levels"]:format(n)) end
		if x == "me+" then return L["your level or above"] end
		return x
	end
	local a, b = v:match("^(.-)%.%.(.+)$")
	if a then return L["from %s to %s"]:format(One(a), One(b)) end
	local op, rest = v:match("^([<>]=?)(.+)$")
	if op == "<" then return L["below %s"]:format(One(rest)) end
	if op == ">" then return L["above %s"]:format(One(rest)) end
	if op == "<=" then return L["%s or below"]:format(One(rest)) end
	if op == ">=" then return L["%s or above"]:format(One(rest)) end
	return One(v)
end
local TimeSay
TimeSay = function(v)
	local t = TIME_SAY[v]
	if t then return t end
	local n, unit = v:match("^(%d+%.?%d*)(%a+)$")
	-- (one of them: "1 day", not "1 days"; review)
	local units = n == "1" and { m = L["minute"], h = L["hour"], d = L["day"], w = L["week"] }
		or { m = L["minutes"], h = L["hours"], d = L["days"], w = L["weeks"] }
	local u = unit and units[unit:sub(1, 1)]
	return n and u and L["%s %s"]:format(n, u) or v
end
--- since:'s value said: "in the last 3 days", "in the last hour", "since yesterday" (`upper`: as a label starts).
local function SinceSay(v, upper)
	local n, unit = v:match("^(%d+%.?%d*)(%a+)$")
	if n then
		-- (one of them, a phrase of its own: "in the last hour", which other languages say otherwise than "%s" + "hour")
		local u = unit:sub(1, 1)
		if n == "1" then
			local one = upper and ({ m = L["In the last minute"], h = L["In the last hour"], d = L["In the last day"], w = L["In the last week"] })[u]
				or ({ m = L["in the last minute"], h = L["in the last hour"], d = L["in the last day"], w = L["in the last week"] })[u]
			if one then return one end
		end
		return (upper and L["In the last %s"] or L["in the last %s"]):format(TimeSay(v))
	end
	return (upper and L["Since %s"] or L["since %s"]):format(TimeSay(v))
end

E.LevelSay, E.TimeSay, E.SinceSay = LevelSay, TimeSay, SinceSay -- (the bar's words for them: Bar.lua's SpecLabel)

--- One filter (key:value) said: { noun = ..., adj = ..., after = ... } (where it goes in the sentence).
local function FilterSay(key, val)
	local v = val:gsub('"', ""):gsub("_", " ")
	if key == "is" then
		if IS_SAY[v] then return { noun = IS_SAY[v] } end
		return { adj = IS_ADJ[v] or v }
	elseif key == "q" or key == "quality" then
		local plus = v:find("%+$")
		v = v:gsub("%+$", "")
		return { adj = plus and L["%s or better"]:format(v) or v }
	elseif key == "lvl" or key == "level" then return { after = LevelSay(v) }
	elseif key == "ilvl" or key == "itemlevel" then return { after = L["item level %s"]:format(RangeSay(v)) }
	elseif key == "value" or key == "worth" then return { after = L["worth %s"]:format(RangeSay(v)) }
	elseif key == "slots" then return { after = L["with %s slots"]:format(RangeSay(v)) }
	elseif key == "dura" or key == "durability" then return { after = L["at %s%% durability"]:format(RangeSay(v)) }
	elseif key == "count" or key == "qty" then return { after = L["%s of them"]:format(RangeSay(v)) }
	elseif key == "type" then return { noun = v }
	elseif key == "slot" then return { after = L["for the %s slot"]:format(v) }
	elseif key == "stat" or key == "stats" then return { after = L["with %s"]:format(v) }
	elseif key == "in" or key == "zone" or key == "where" then return { after = L["in %s"]:format(v) }
	elseif key == "on" or key == "who" then return { after = L["on %s"]:format(v) }
	elseif key == "faction" then return { adj = v == "friendly" and L["friendly"] or L["friendly to the %s"]:format(v) }
	elseif key == "sells" or key == "sold" then return { after = L["that sell %s"]:format(v) }
	elseif key == "trainer" then return { after = L["who teach %s"]:format(v) }
	elseif key == "near" then return { after = L["within %s yards"]:format(RangeSay(v)) }
	elseif key == "reward" or key == "rewards" then return { after = L["rewarding %s"]:format(v) }
	elseif key == "standing" or key == "rep" then return { after = L["at %s"]:format(RangeSay(v)) }
	elseif key == "since" then return { after = SinceSay(v) }
	elseif key == "older" or key == "before" then return { after = v:find("^%d") and L["older than %s"]:format(TimeSay(v)) or L["from before %s"]:format(TimeSay(v)) }
	elseif key == "class" then return { after = L["of the %s class"]:format(v) }
	elseif key == "when" then return { after = L["on the calendar %s"]:format(TIME_SAY[v] or v) }
	-- (what a spell does, 0.68.8)
	elseif key == "cast" then
		if v == "instant" then return { adj = L["instant"] } end
		if v == "channeled" or v == "channelled" or v == "channel" then return { adj = L["channeled"] } end
		return { after = L["with a cast of %s sec"]:format(RangeSay(v)) }
	elseif key == "cost" then
		if v == "0" or v == "none" or v == "free" or v == "nothing" then return { after = L["that cost nothing"] } end
		if v:match("^%a+$") then return { after = L["that cost %s"]:format(v) } end
		return { after = L["costing %s"]:format(RangeSay(v)) }
	elseif key == "range" then
		if v == "melee" then return { after = L["at melee range"] } end
		if v == "self" or v == "none" or v == "0" then return { after = L["on yourself"] } end
		return { after = L["with a range of %s yards"]:format(RangeSay(v)) }
	elseif key == "cd" or key == "cooldown" then
		if v == "0" or v == "none" then return { after = L["with no cooldown"] } end
		return { after = L["with a cooldown of %s sec"]:format(RangeSay(v)) }
	elseif key == "do" then return { verb = L["Enter: %s"]:format(v) }
	end
	return { after = key .. ":" .. val }
end

--- One filter word said ("q:rare+" -> "rare or better", "-is:boe" -> "not bind on equip"), or nil when it's no filter.
function E.SayFilter(word)
	if type(word) ~= "string" then return nil end
	local lw = Lower(word)
	local neg = lw:match("^[-!]") and true or false
	if neg then lw = lw:sub(2) end
	local key, val = lw:match("^(%a+):(.+)$")
	if not key then return nil end
	if key == "sort" then
		return SortSay(lw)
	end
	local t = {}
	for part in val:gmatch("[^|]+") do
		local k2, v2 = part:match("^(%a+):(.+)$")
		local say = FilterSay(k2 or key, v2 or part)
		t[#t + 1] = say.noun or say.adj or say.after or say.verb
	end
	local out = table.concat(t, " " .. L["or"] .. " ")
	return neg and L["not %s"]:format(out) or out
end
--- What a list's rows are, in words: "NPCs", "your bank" (its label when there's none).
function E.KindNoun(id)
	if type(id) ~= "string" then return nil end
	local p = ns.providers[id]
	return KIND_NOUN[id] or (p and p.label and Lower(tostring(p.label))) or id
end

--- An Advanced line said in plain words, or nil when there's nothing to say.
function E.Explain(line)
	if type(line) ~= "string" or not line:find("%S") then return nil end
	local parts = {}
	local tail = {}
	-- (the line as the search reads it, Phrase.lua: its send, its steps, a chain's ">", its words and "quoted phrases";
	-- Explain reads none of them itself)
	local r = ns.Phrase.ReadLine(line, { simple = false })
	local send = r.send
	if send then
		local to = send.channel or ""
		tail[#tail + 1] = (send.all and L["every one sent to %s"] or L["sent to %s"]):format(to ~= "" and to or L["chat"])
	end
	local A = ns.Aggregate
	local steps = r.steps and r.steps.list
	-- (the search's own words: before the steps, else the send)
	local last = (r.steps and r.steps.from or r.sendEnd or (#r.toks + 1)) - 1
	local chain
	for k = 1, last do
		local t = r.toks[k]
		if t.class == "op" and t.text == ">" then
			-- (to the end of the search's text: before the steps, else the send, else the line's end, spaces and all)
			local stop = r.steps and #r.steps.query or (send and send.at - 1) or #r.line
			chain = (r.line:sub(t.e + 1, stop):gsub("^%s+", ""))
			last = k - 1
			break
		end
	end
	local words, phrases = {}, {}
	for k = 1, last do
		local t = r.toks[k]
		if t.class == "quoted" then
			if t.value ~= "" then phrases[#phrases + 1] = t.value end
		else
			words[#words + 1] = t.value
		end
	end
	local nouns, kindNouns, adjs, after, orders, plain, verbs = {}, {}, {}, {}, {}, {}, {}
	for _, w in ipairs(words) do
		local lw = Lower(w)
		local neg = lw:match("^[-!]") and true or false
		if neg then lw = lw:sub(2) end
		if lw:sub(1, 1) == "@" then
			local name = lw:sub(2)
			local p = ns:ResolveProvider(name)
			kindNouns[#kindNouns + 1] = (p and KIND_NOUN[p.id]) or KIND_NOUN[name] or (p and Lower(tostring(p.label or p.id))) or name
		else
			local key, val = lw:match("^(%a+):(.+)$")
			local F = ns.Filters
			if key and key == "sort" then
				local said = SortSay(lw)
				if said then orders[#orders + 1] = said end
			elseif key and F and F.IsKey and F.IsKey(key) then
				-- (a | b: either said)
				local alts = {}
				for part in val:gmatch("[^|]+") do
					local k2, v2 = part:match("^(%a+):(.+)$")
					alts[#alts + 1] = FilterSay(k2 or key, v2 or part)
				end
				local first = alts[1]
				local function Join(field)
					local t = {}
					for _, a in ipairs(alts) do if a[field] then t[#t + 1] = a[field] end end
					return #t > 0 and table.concat(t, " " .. L["or"] .. " ") or nil
				end
				local say
				for _, field in ipairs({ "noun", "adj", "after", "verb" }) do
					local j = Join(field)
					if j then say = say or {}; say[field] = j end
				end
				say = say or first
				if neg then
					after[#after + 1] = L["not %s"]:format(say.noun or say.adj or say.after or lw)
				else
					if say.noun then nouns[#nouns + 1] = say.noun end
					if say.adj then adjs[#adjs + 1] = say.adj end
					if say.after then after[#after + 1] = say.after end
					if say.verb then verbs[#verbs + 1] = say.verb end
				end
			elseif neg then
				after[#after + 1] = L["without \"%s\""]:format(lw)
			else
				plain[#plain + 1] = w
			end
		end
	end
	for _, ph in ipairs(phrases or {}) do plain[#plain + 1] = '"' .. ph .. '"' end
	-- the sentence: [adjectives] [nouns], [matching words], [the rest], [order]
	-- (what the filters say they are, "vendors", "upgrades", is more than the list they're in: NPCs, items)
	if #nouns == 0 then nouns = kindNouns end
	local noun = #nouns > 0 and table.concat(nouns, " " .. L["and"] .. " ") or L["everything"]
	local head = (#adjs > 0 and (table.concat(adjs, ", ") .. " ") or "") .. noun
	if #plain > 0 then head = L["%s matching %s"]:format(head, table.concat(plain, " ")) end
	parts[1] = head
	for _, a in ipairs(after) do parts[#parts + 1] = a end
	for _, o in ipairs(orders) do parts[#parts + 1] = o end
	for _, v in ipairs(verbs) do parts[#parts + 1] = v end
	if chain then parts[#parts + 1] = L["then: %s"]:format(chain) end
	for _, st in ipairs(steps or {}) do
		local s = A.ParseStep(st)
		if s.other then
			local other = E.Explain(s.other)
			other = other and Lower(other:sub(1, 1)) .. other:sub(2) or s.other
			parts[#parts + 1] = (s.except and L["leaving out %s"] or L["and also %s"]):format(other)
		elseif s.first then parts[#parts + 1] = L["the first %d"]:format(s.first)
		elseif s.op == "count" then parts[#parts + 1] = L["counted"]
		elseif s.op == "group" then parts[#parts + 1] = L["grouped by %s"]:format(s.by)
		elseif s.op == "sum" or s.op == "avg" then
			local how = (s.op == "sum" and L["the %s summed up"] or L["the average %s"]):format(s.field)
			parts[#parts + 1] = s.by and L["%s by %s"]:format(how, s.by) or how
		elseif s.where then parts[#parts + 1] = L["only %s %s"]:format(s.where, s.value)
		else parts[#parts + 1] = "| " .. st end
	end
	for _, t in ipairs(tail) do parts[#parts + 1] = t end
	return ns.UpperFirst(table.concat(parts, ", "))
end

--- Does the line hold Advanced syntax (an @kind, a key:value, a "|" step, a ">" chain)?
function ns.UI.LooksAdvanced(text)
	if type(text) ~= "string" or text:find("^%s*[%./]") then return false end
	for w in text:gmatch("%S+") do if E.IsAdvancedWord(w) then return true end end
	return false
end

ns:RegisterCommand("explain", {
	desc = L["An Advanced line read back in plain words: .explain @npc is:vendor sells:arrow sort:distance (nothing after it: the last line you ran)"],
	run = function(args)
		args = tostring(args or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if args == "" then
			local lines = ns.HistoryLines and ns:HistoryLines() or {}
			for _, l in ipairs(lines) do
				if not l:find("^%s*[%./]") then args = l break end
			end
			-- (a line in plain words: explained as Advanced writes it, not word for word; review)
			local looks = ns.UI and ns.UI.LooksAdvanced
			if args ~= "" and looks and not looks(args) then args = E.ToAdvanced(args) or args end
			if args == "" then return { L["Which line? .explain @npc is:vendor sort:distance"] } end
		end
		local said = E.Explain(args)
		if not said then return { L["Which line? .explain @npc is:vendor sort:distance"] } end
		return { args, "  " .. said }
	end,
})
