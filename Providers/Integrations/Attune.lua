local ns = select(2, ...)
local L = ns.L
local H = ns.Highlight
local I = ns.Integrations
local Safe, Str, Lower = ns.Safe, ns.Str, ns.Lower
local AddOnVersion = I._.AddOnVersion

----------------------------------------------------------------------
-- Attune (0.50.2, the player's ask): its attunements, dungeon quest lines, keys and class quests become @attune
-- (@attunement), each with how far along you are and your next step, as Attune records them (Attune_DB: the steps it
-- has seen you do). Enter opens Attune's window on it and points at it; Shift+Enter puts it in the chat box. Only what
-- Attune itself lists for you: your faction's, your class's class quests (every class's with Attune's own option for
-- that), the retired ones only when Attune shows them.
--
--   <attunement> > steps   its steps first to last (each quest line in turn), each saying whether it's done or next;
--                          Enter opens Attune on that step (Search/Attune.lua)
--   <quest> > attunement   the attunements a quest, item or NPC is a step of
--   Simple mode            "my attunements", "raid attunements", "keys", "class quests", "how do i get into mc"
--
-- Attune's tables are read, never written: Attune_Data (the attunements and their steps), AttuneLang (their names, in
-- the client's language), Attune_DB.toons (each character's steps done, by "First Last", the way WoW Forever names
-- characters; your alts are the ones marked as yours). Its window is opened through /attune and its own tree.
----------------------------------------------------------------------

local AT = {}
ns.Attune = AT
local attune = { on = false }
I.attune = attune

local function Data()
	local d = _G.Attune_Data
	return type(d) == "table" and type(d.attunes) == "table" and type(d.steps) == "table" and d or nil
end
local function DB()
	local d = _G.Attune_DB
	return type(d) == "table" and d or nil
end
--- AttuneLang's text for a key, or nil when it has none (its locale gives the key itself back for a missing one).
local function Lang(key)
	local t = _G.AttuneLang
	if type(t) ~= "table" or key == nil then return nil end
	local ok, v = pcall(function() return t[key] end)
	if ok and type(v) == "string" and v ~= "" and v ~= key then return v end
end
--- AttuneLang's text, the key itself when that's the text (its group names: "KEYS" is "KEYS" in English).
local function LangRaw(key)
	local t = _G.AttuneLang
	local ok, v = pcall(function() return t and t[key] end)
	return ok and type(v) == "string" and v or key
end
AT.Lang = Lang

--- Attune is loaded, with its data.
local function Present()
	local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
	if isLoaded then
		local ok, yes = pcall(isLoaded, "Attune")
		if ok and not yes then return false end
	end
	return Data() ~= nil
end
AT.Present = Present

----------------------------------------------------------------------
-- The data, read once: each attunement's steps in order
----------------------------------------------------------------------

AT.GROUPS = { DUNGEONS = "dungeon", KEYS = "key", RAIDS = "raid", MISC = "misc" }
AT.GROUP_LABEL = { dungeon = L["Dungeon quests"], key = L["Key"], raid = L["Raid attunement"], misc = L["Attunement"],
	class = L["Class quest"] }

local function GroupOf(a)
	if type(a.CLASS) == "string" and a.CLASS ~= "" then return "class" end
	for word, g in pairs(AT.GROUPS) do
		if a.GROUP == LangRaw(word) or a.GROUP == word then return g end
	end
	return "misc"
end

-- a step Attune shows in this version of the game (its own test when it has one: steps can be for some patches only)
local function ShowStep(s)
	local f = _G.showPatchStep
	if type(f) == "function" then
		local ok, yes = pcall(f, s)
		if ok then return yes and true or false end
	end
	return s.VALIDFROM == nil and s.VALIDTO == nil
end

-- the steps a step follows ("20&30": both; "20|21": either), and whether either is enough
local function Follows(f)
	f = tostring(f or "0")
	local out = {}
	if f == "0" or f == "" then return out, false end
	for id in f:gmatch("[^&|%s]+") do if id ~= "0" then out[#out + 1] = id end end
	return out, f:find("|", 1, true) ~= nil
end
AT.Follows = Follows

local function Ids(v)
	local out = {}
	for id in tostring(v or ""):gmatch("%d+") do out[#out + 1] = tonumber(id) end
	return out
end

local function QuestName(id)
	local n = Lang("Q1_" .. id)
	if n then return n end
	local DB2 = ns.QuestieData and ns.QuestieData.DB and ns.QuestieData.DB()
	n = DB2 and Safe(DB2.QueryQuestSingle, id, "name")
	if Str(n) then return n end
	n = C_QuestLog and C_QuestLog.GetTitleForQuestID and Safe(C_QuestLog.GetTitleForQuestID, id)
	if Str(n) then return n end
	return L["Quest #%d"]:format(id)
end
local function ItemName(id)
	local n = Lang("I_" .. id)
	if n then return n end
	n = C_Item and C_Item.GetItemNameByID and Safe(C_Item.GetItemNameByID, id)
	if Str(n) and not ns.Secret(n) then return n end
	return L["Item #%d"]:format(id)
end
local function NpcName(id)
	local n = Lang("N1_" .. id)
	if n then return n end
	n = I.NpcField and I.NpcField(id, "name")
	if Str(n) then return n end
	return L["NPC #%d"]:format(id)
end

-- what each kind of step asks (lowercase: a part of the row's detail)
AT.VERB = { ["Pick Up"] = L["pick up"], ["Turn In"] = L["turn in"], Quest = L["quest"], Item = L["get"], Kill = L["kill"],
	Interact = L["talk to"], Click = L["use"], Level = L["level"], Rep = L["reputation"], Attune = L["attunement first"] }

local index -- { list = { attunement records }, byId = {}, byQuest = { qid = { aid } }, byItem, byNpc }

-- One step's record (Spacer and End steps have none: Attune's layout, and "done"); `s` its first step, `keys` the
-- done-map keys of it and the steps it stands for (the same quest for each race: "Heeding the Call" three times).
local function StepRecord(aid, s, D)
	local t = s.TYPE
	local rec = { aid = aid, step = s, id = tostring(s.ID), type = t, keys = { aid .. "-" .. tostring(s.ID) }, side = s.SIDE and true or nil }
	local ids = Ids(s.ID_WOWHEAD)
	if t == "Pick Up" or t == "Turn In" or t == "Quest" then
		rec.qids = ids
		rec.title = ids[1] and QuestName(ids[1]) or Str(s.STEP) or "?"
	elseif t == "Item" then
		rec.itemID = ids[1]
		rec.count = tonumber(s.COUNT) or 1
		rec.title = ids[1] and ItemName(ids[1]) or Str(s.STEP) or "?"
	elseif t == "Kill" or t == "Interact" then
		rec.npcID = ids[1]
		rec.title = ids[1] and NpcName(ids[1]) or Str(s.STEP) or "?"
	elseif t == "Attune" then
		rec.linkAttune = tostring(s.ID_WOWHEAD)
		rec.title = Str(s.STEP) or rec.linkAttune
	else
		rec.title = Str(s.STEP) or Lang(t) or t
	end
	if t == "Level" then rec.level = tonumber(s.ID_WOWHEAD) end
	-- (a reputation step's LOCATION is the faction's id; a level's is empty)
	local loc = t ~= "Rep" and Str(s.LOCATION) or nil
	rec.where = loc
	return rec
end

-- An attunement's steps in the order to do them: from each step that starts a line (or follows only the level), the
-- whole line before the next one, so the Deadmines' five quest lines read one after the other. A step comes after every
-- step it follows, "20|21" (either is enough) too: a chain split by race (Taming: Dun Morogh or Teldrassil) lists each
-- branch whole, then what both lead to. Attune draws them in columns (STAGE), every line side by side.
local function Order(list)
	local idx, stage = {}, {}
	for i, s in ipairs(list) do idx[s] = i; stage[s] = tonumber(s.STAGE) or 0 end
	table.sort(list, function(a, b)
		if stage[a] ~= stage[b] then return stage[a] < stage[b] end
		return idx[a] < idx[b]
	end)
	local byId = {}
	for _, s in ipairs(list) do
		local k = tostring(s.ID)
		if not byId[k] then byId[k] = s end
	end
	local pre, kids = {}, {}
	for _, s in ipairs(list) do
		local ids = Follows(s.FOLLOWS)
		local ps = {}
		for _, id in ipairs(ids) do
			local p = byId[id]
			if p and p ~= s then
				ps[#ps + 1] = p
				kids[p] = kids[p] or {}
				kids[p][#kids[p] + 1] = s
			end
		end
		pre[s] = ps
	end
	local out, emitted = {}, {}
	local function Ready(s)
		for _, p in ipairs(pre[s]) do if not emitted[p] then return false end end
		return true
	end
	local function Visit(s, depth)
		if emitted[s] or depth > 400 or not Ready(s) then return end
		emitted[s] = true
		out[#out + 1] = s
		for _, k in ipairs(kids[s] or {}) do Visit(k, depth + 1) end
	end
	for _, s in ipairs(list) do Visit(s, 0) end
	-- (a step following one that isn't there, or a loop in the data: last, in Attune's column order)
	for _, s in ipairs(list) do
		if not emitted[s] then emitted[s] = true; out[#out + 1] = s end
	end
	return out
end

local function Add(map, id, aid)
	if not id then return end
	local t = map[id]
	if not t then t = {}; map[id] = t end
	for _, x in ipairs(t) do if x == aid then return end end
	t[#t + 1] = aid
end

--- The attunements and their steps, read from Attune once (its data doesn't change in a session); nil without Attune.
function AT.Index()
	if index then return index end
	local D = Data()
	if not D then return nil end
	local started = _G.debugprofilestop and _G.debugprofilestop() or 0
	local raw = {} -- aid -> its steps Attune shows
	for _, s in ipairs(D.steps) do
		if type(s) == "table" and s.ID_ATTUNE and ShowStep(s) then
			local aid = tostring(s.ID_ATTUNE)
			raw[aid] = raw[aid] or {}
			raw[aid][#raw[aid] + 1] = s
		end
	end
	local idx = { list = {}, byId = {}, byQuest = {}, byItem = {}, byNpc = {} }
	for order, a in ipairs(D.attunes) do
		if type(a) == "table" and a.ID then
			local aid = tostring(a.ID)
			local rec = { a = a, id = aid, order = order, group = GroupOf(a), keys = {}, steps = {}, all = {} }
			local lo, hi = tostring(a.LEVELS or ""):match("^(%d+)%D*(%d*)")
			rec.minLevel, rec.maxLevel = tonumber(lo), tonumber(hi) or tonumber(lo)
			local list = raw[aid] or {}
			for _, s in ipairs(list) do
				rec.all[tostring(s.ID)] = s
				if s.TYPE ~= "Spacer" then rec.keys[#rec.keys + 1] = aid .. "-" .. tostring(s.ID) end
				if s.TYPE == "End" then rec.endKey = aid .. "-" .. tostring(s.ID) end
			end
			-- the steps a row stands for: in order, the same quest for each race once
			local merged = {}
			for _, s in ipairs(Order(list)) do
				if s.TYPE ~= "Spacer" and s.TYPE ~= "End" then
					local r = StepRecord(aid, s, D)
					local same = s.OR and merged[r.type .. "\001" .. r.title .. "\001" .. tostring(s.FOLLOWS)]
					if same then
						same.keys[#same.keys + 1] = r.keys[1]
						same.ids = same.ids or { same.id }
						same.ids[#same.ids + 1] = r.id
						for _, q in ipairs(r.qids or {}) do same.qids[#same.qids + 1] = q end
					else
						if s.OR then merged[r.type .. "\001" .. r.title .. "\001" .. tostring(s.FOLLOWS)] = r end
						rec.steps[#rec.steps + 1] = r
					end
				end
			end
			for _, r in ipairs(rec.steps) do
				for _, q in ipairs(r.qids or {}) do Add(idx.byQuest, q, aid) end
				Add(idx.byItem, r.itemID, aid)
				Add(idx.byNpc, r.npcID, aid)
			end
			idx.list[#idx.list + 1] = rec
			idx.byId[aid] = idx.byId[aid] or rec
		end
	end
	index = idx
	if _G.debugprofilestop then
		ns:Trace(("attune: %d attunements, %d steps read in %.0f ms"):format(#idx.list, #D.steps, _G.debugprofilestop() - started))
	end
	return idx
end
function AT.Forget() index = nil end -- (tests: Attune's data made again)

----------------------------------------------------------------------
-- Progress: Attune's record of each character's steps done
----------------------------------------------------------------------

local myKey
--- Attune's key for the character you're on ("First Last": WoW Forever's names, UnitName's two parts), and its record.
local function MyToon()
	local D = DB()
	local toons = D and D.toons
	if type(toons) ~= "table" then return nil end
	if myKey and type(toons[myKey]) == "table" then return toons[myKey], myKey end
	local first, last = Safe(UnitName, "player")
	if type(first) ~= "string" then return nil end
	if type(last) == "string" and last ~= "" and type(toons[first .. " " .. last]) == "table" then
		myKey = first .. " " .. last
		return toons[myKey], myKey
	end
	-- (UnitName without the second part: the one record of yours starting with the first)
	local found
	for k, t in pairs(toons) do
		if type(k) == "string" and type(t) == "table" and (k == first or k:sub(1, #first + 1) == first .. " ") then
			if found then return nil end
			found = k
		end
	end
	if found then myKey = found return toons[found], found end
end
AT.MyToon = MyToon
function AT.ForgetToon() myKey = nil end -- (tests)

local function MyClass() return select(2, Safe(UnitClass, "player")) end
local function MyFaction() return Safe(UnitFactionGroup, "player") end

--- Whether Attune tracks this attunement for that character: every one, a class quest only for its class.
local function Tracks(rec, toon, mine)
	local need = rec.a.CLASS
	if type(need) ~= "string" or need == "" then return true end
	local cls = mine and MyClass() or (toon and type(toon.class) == "string" and toon.class:upper())
	return cls == need
end

-- whether a step is done for this character (done map), a spacer once what it follows is (Attune fills those in when it
-- next looks), your own level steps as your level says now
local function StepDone(rec, sid, done, level, depth)
	local key = rec.id .. "-" .. sid
	if done[key] then return true end
	local s = rec.all[sid]
	if not s or (depth or 0) > 50 then return false end
	if s.TYPE == "Level" and level then return level >= (tonumber(s.ID_WOWHEAD) or 999) end
	if s.TYPE == "Spacer" then
		local ids, any = Follows(s.FOLLOWS)
		if #ids == 0 then return false end
		for _, f in ipairs(ids) do
			local d = StepDone(rec, f, done, level, (depth or 0) + 1)
			if any and d then return true end
			if not any and not d then return false end
		end
		return not any
	end
	return false
end

-- can this step be done now: not done, and what it follows is
local function StepNext(rec, s, done, level)
	if StepDone(rec, tostring(s.ID), done, level) then return false end
	local ids, any = Follows(s.FOLLOWS)
	if #ids == 0 then return true end
	for _, f in ipairs(ids) do
		local d = StepDone(rec, f, done, level)
		if any and d then return true end
		if not any and not d then return false end
	end
	return not any
end

local function Level() return ns.Num(Safe(UnitLevel, "player")) end

--- How far along a character is: percent (as Attune counts it: the steps done of all its steps, the end step done is
--- 100), steps done, steps; nil when Attune has no record (or doesn't track it for them: another class's quest).
function AT.Progress(rec, toon, mine)
	if not (rec and toon and type(toon.done) == "table") or #rec.keys == 0 or not Tracks(rec, toon, mine) then return nil end
	local done = toon.done
	local level = mine and Level() or nil
	local n = 0
	for _, k in ipairs(rec.keys) do
		local sid = k:sub(#rec.id + 2)
		if StepDone(rec, sid, done, level) then n = n + 1 end
	end
	local pct = math.floor(100 * n / #rec.keys)
	if (rec.endKey and done[rec.endKey]) or (type(toon.attuned) == "table" and (tonumber(toon.attuned[rec.id]) or 0) >= 100) then pct = 100 end
	return pct, n, #rec.keys
end

--- Your progress on it (Progress for the character you're on).
function AT.Mine(rec)
	local toon = MyToon()
	return AT.Progress(rec, toon, true)
end

--- The steps you can do next ({ step records }), in order.
function AT.NextSteps(rec)
	local toon = MyToon()
	if not (rec and toon and type(toon.done) == "table") or not Tracks(rec, toon, true) then return {} end
	local done, level, out, others = toon.done, Level(), {}, {}
	local QR = ns.QuestRewards
	for _, r in ipairs(rec.steps) do
		for _, sid in ipairs(r.ids or { r.id }) do
			local s = rec.all[sid]
			if s and StepNext(rec, s, done, level) then
				-- (a quest your race can't take, on a chain split by race: after the ones you can)
				local mine = true
				if r.qids and #r.qids > 0 and QR and QR.ForYou then
					mine = false
					for _, q in ipairs(r.qids) do if QR.ForYou(q) then mine = true break end end
				end
				if mine then out[#out + 1] = r else others[#others + 1] = r end
				break
			end
		end
	end
	for _, r in ipairs(others) do out[#out + 1] = r end
	return out
end

--- A step's state for you: "done", "next" or nil.
function AT.StepState(r)
	local rec = index and index.byId[r.aid]
	local toon = MyToon()
	if not (rec and toon and type(toon.done) == "table") or not Tracks(rec, toon, true) then return nil end
	local done, level = toon.done, Level()
	for _, sid in ipairs(r.ids or { r.id }) do
		if StepDone(rec, sid, done, level) then return "done" end
	end
	for _, sid in ipairs(r.ids or { r.id }) do
		local s = rec.all[sid]
		if s and StepNext(rec, s, done, level) then return "next" end
	end
	return nil
end

--- Your other characters' progress on it, as Attune last saw each: { { name, percent } }, those that started it.
function AT.Alts(rec)
	local D = DB()
	local _, mine = MyToon()
	local out = {}
	for k, t in pairs(D and type(D.toons) == "table" and D.toons or {}) do
		if k ~= mine and type(t) == "table" and t.owner == 1 then
			local pct = AT.Progress(rec, t, false)
			if pct and pct > 0 then out[#out + 1] = { tostring(k), pct, type(t.class) == "string" and t.class:upper() or nil } end
		end
	end
	table.sort(out, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
	return out
end

----------------------------------------------------------------------
-- Attune's window: opened on an attunement, pointing at it (or at one of its steps)
----------------------------------------------------------------------

local function MainFrame() return _G.Attune_MainFrame end
-- Attune's tree of attunements (an AceGUI TreeGroup in its window; its results page has none)
local function Tree()
	local f = MainFrame()
	local w = f and f.obj
	for _, c in ipairs(type(w) == "table" and type(w.children) == "table" and w.children or {}) do
		if type(c) == "table" and c.type == "TreeGroup" then return c end
	end
end
AT.Tree = Tree

local function PathOf(a) return tostring(a.EXPAC) .. "\001" .. tostring(a.GROUP) .. "\001" .. tostring(a.ID) end

--- Attune's window on this attunement (its tree picks it, as a click does), pointing at it, or at one of its steps
--- (`stepId`: the step's box in the chart).
function AT.Open(rec, stepId)
	local a = rec and rec.a
	if not a then return end
	local path = PathOf(a)
	_G.AttuneLastViewed = path -- (where its window opens: the first time, and from its results page)
	local before = MainFrame()
	if not (before and before:IsShown()) then
		local slash = _G.SlashCmdList and _G.SlashCmdList.Attune
		if type(slash) ~= "function" then
			ns:Print(L["Attune's window isn't ready yet."])
			return
		end
		local ok, err = pcall(slash, "")
		if not ok then ns:Trace("attune: /attune failed: " .. tostring(err)) end
	end
	local f = MainFrame()
	if not (f and f:IsShown()) then
		ns:Print(L["Attune's window didn't open."])
		return
	end
	local tree = Tree()
	local picked = false -- (Attune picked it itself: AttuneLastViewed, made the first time or back from its results page)
	if not tree then
		if type(_G.Attune_ToggleView) == "function" then pcall(_G.Attune_ToggleView) end
		tree, picked = Tree(), true
	elseif not before then
		picked = true
	end
	if tree then
		-- Attune picks AttuneLastViewed as one joined path, which doesn't unfold its group: a group you folded kept the
		-- row hidden, nothing to point at. Picked again by its parts (as a click on it would), unfolding them; the tree
		-- kept from before shows the last one picked anyway.
		local st = tree.status or tree.localstatus
		local open = type(st) == "table" and type(st.groups) == "table"
			and st.groups[tostring(a.EXPAC)] and st.groups[tostring(a.EXPAC) .. "\001" .. tostring(a.GROUP)]
		if not (picked and open) then
			local ok, err = pcall(tree.SelectByPath, tree, a.EXPAC, a.GROUP, a.ID)
			if not ok then ns:Trace("attune: select failed: " .. tostring(err)) end
		end
	end
	ns:Trace("attune: opened on " .. tostring(a.ID) .. (stepId and (" step " .. tostring(stepId)) or ""))
	H:When(function()
		local mf = MainFrame()
		if not (mf and mf:IsShown()) then return false end
		if stepId then
			local node = _G["Attune_Node_" .. tostring(stepId)]
			if node and node.IsVisible and node:IsVisible() then return node end
			return nil
		end
		local t = Tree()
		for _, b in ipairs(t and type(t.buttons) == "table" and t.buttons or {}) do
			if b.uniquevalue == path and b.IsVisible and b:IsVisible() then return b end
		end
	end, function(b) H:Show(b) end, 30, function()
		ns:Trace("attune: nothing to point at for " .. tostring(a.ID) .. (stepId and (" step " .. tostring(stepId)) or ""))
	end)
end

----------------------------------------------------------------------
-- Rows: @attune's (one per attunement) and its steps' (Search/Attune.lua's "> steps")
----------------------------------------------------------------------

local SEP = ns.DETAIL_SEP
local DONE_ICON = "Interface\\RAIDFRAME\\ReadyCheck-Ready"
local GOLD, DIM, WHITE, GREEN, YELLOW = { 1, 0.82, 0 }, { 0.6, 0.6, 0.6 }, { 1, 1, 1 }, { 0.25, 1, 0.25 }, { 1, 0.9, 0.3 }

local function RecOf(e) return index and index.byId[tostring(e.attuneId)] end

--- An attunement's words for chat: "Molten Core (Attune): 50%, next: Core Fragment".
local function ShareText(e)
	local rec = RecOf(e)
	local pct = rec and AT.Mine(rec)
	local nxt = rec and AT.NextSteps(rec)[1]
	local s = tostring(e.name) .. " (Attune)"
	if pct then s = s .. ": " .. (pct >= 100 and L["done"] or (pct .. "%")) end
	if nxt and pct and pct < 100 then s = s .. ", " .. L["next: %s"]:format(nxt.title) end
	return s
end

local function Detail(e)
	local rec = RecOf(e)
	if not rec then return "" end
	local parts = { AT.GROUP_LABEL[rec.group] or "" }
	local lv = Str(rec.a.LEVELS)
	if lv then parts[#parts + 1] = L["Lv %s"]:format(lv) end
	if #rec.keys == 0 then
		parts[#parts + 1] = L["no steps yet"]
		return table.concat(parts, SEP)
	end
	local pct = AT.Mine(rec)
	if pct and pct >= 100 then
		parts[#parts + 1] = L["done"]
	elseif pct then
		if pct > 0 then parts[#parts + 1] = pct .. "%" end
		local nxt = AT.NextSteps(rec)[1]
		if nxt then parts[#parts + 1] = L["next: %s"]:format(nxt.title) end
	elseif rec.group == "class" and rec.a.CLASS ~= MyClass() then
		parts[#parts + 1] = (ns.ClassHex(rec.a.CLASS) or "") .. (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[rec.a.CLASS] or rec.a.CLASS)
			.. (ns.ClassHex(rec.a.CLASS) and "|r" or "")
	end
	return table.concat(parts, SEP)
end

local function StepLine(r)
	local verb = AT.VERB[r.type] or ""
	if r.type == "Item" and (r.count or 1) > 1 then verb = L["get %d"]:format(r.count) end
	local where = r.where and (r.side and L["inside %s"]:format(r.where) or r.where)
	local s = r.title
	if verb ~= "" and r.type ~= "Level" and r.type ~= "Rep" then s = verb .. ": " .. s end
	return where and (s .. "  " .. "|cff999999(" .. where .. ")|r") or s
end
AT.StepLine = StepLine

local function Tooltip(e, t)
	local rec = RecOf(e)
	t:SetText(e.name, GOLD[1], GOLD[2], GOLD[3])
	if not rec then return end
	local a = rec.a
	local head = { AT.GROUP_LABEL[rec.group] }
	if Str(a.LEVELS) then head[#head + 1] = L["Level %s"]:format(a.LEVELS) end
	local size = tonumber(a.GROUPSIZE)
	if size and size > 1 then head[#head + 1] = L["%d players"]:format(size) end
	t:AddLine(table.concat(head, "  ·  "), DIM[1], DIM[2], DIM[3])
	-- (its own words: the raids' and keys' rules; the dungeons' and class quests' say the same for every one)
	if rec.group ~= "dungeon" and rec.group ~= "class" and Str(a.DESC) then t:AddLine(a.DESC, 0.8, 0.8, 0.8, true) end
	if #rec.keys == 0 then
		t:AddLine(L["Attune has no steps for it yet."], DIM[1], DIM[2], DIM[3], true)
	else
		local pct, n, of = AT.Mine(rec)
		if pct then
			local c = pct >= 100 and GREEN or WHITE
			t:AddDoubleLine(L["Progress"], pct >= 100 and L["done"] or L["%d%% (%d of %d steps)"]:format(pct, n, of),
				1, 1, 1, c[1], c[2], c[3])
			if pct < 100 then
				local nxt = AT.NextSteps(rec)
				if #nxt > 0 then
					t:AddLine(" ")
					t:AddLine(L["Next:"], GOLD[1], GOLD[2], GOLD[3])
					for i = 1, math.min(#nxt, 6) do t:AddLine("  " .. StepLine(nxt[i]), 1, 1, 1, true) end
					if #nxt > 6 then t:AddLine("  " .. L["and %d more"]:format(#nxt - 6), DIM[1], DIM[2], DIM[3]) end
				end
			end
		elseif rec.group == "class" and a.CLASS ~= MyClass() then
			t:AddLine(L["Another class's quest"], DIM[1], DIM[2], DIM[3])
		else
			t:AddLine(L["Attune hasn't recorded your progress yet (open it once)."], DIM[1], DIM[2], DIM[3], true)
		end
		t:AddDoubleLine(L["Steps"], tostring(#rec.steps), 1, 1, 1, 1, 1, 1)
		local alts = AT.Alts(rec)
		if #alts > 0 then
			local list = {}
			for i = 1, math.min(#alts, 6) do
				local hex = ns.ClassHex(alts[i][3])
				list[#list + 1] = (hex or "") .. alts[i][1] .. (hex and "|r" or "") .. " " .. (alts[i][2] >= 100 and L["done"] or (alts[i][2] .. "%"))
			end
			t:AddLine(L["Your alts: %s"]:format(table.concat(list, ", ")), DIM[1], DIM[2], DIM[3], true)
		end
	end
	t:AddLine(L["Enter: show in Attune    Shift+Enter: put it in the chat box"], DIM[1], DIM[2], DIM[3], true)
end

local function OpenRow(e) AT.Open(RecOf(e)) end
local function ToChatBox(e) ns.LinkInChat(ShareText(e)) end

AT.ROW = { activate = OpenRow, tooltip = Tooltip, secondary = ToChatBox, secondarySecure = ns.ChatBoxSpec(ShareText),
	secondaryIsOpen = ns.ChatBoxNeverOpen, shareLink = ShareText }
AT.ROW_LAZY = {
	detail = Detail,
	icon = function(t)
		local rec = RecOf(t)
		local pct = rec and AT.Mine(rec)
		return pct and pct >= 100 and DONE_ICON or (rec and rec.a.ICON) or "Interface\\Icons\\INV_Scroll_03"
	end,
	-- (lvl: reads a range: the levels Attune gives it)
	level = function(t) local rec = RecOf(t) return rec and rec.maxLevel end,
	minLevel = function(t) local rec = RecOf(t) return rec and rec.minLevel end,
	attuneId = function(t) return rawget(t, "key") end,
}

-- what Attune lists for you: your faction's; class quests your class's (every class's with its option); a retired one
-- only when it shows those
local function Visible(rec, faction, cls, D)
	local a = rec.a
	if a.DEPRECATED ~= nil and not (D and D.showDeprecatedAttunes) then return false end
	if a.FACTION ~= "Both" and faction and a.FACTION ~= faction then return false end
	if rec.group == "class" and not (D and D.showAllClassQuests) and a.CLASS ~= cls then return false end
	return true
end
AT.Visible = Visible

--- The row's name: Attune's, a key's with "key" after it ("Scholomance key": the dungeon's quests are "Scholomance").
local function RowName(rec)
	local n = Str(rec.a.NAME) or rec.id
	-- (another class's class quest, listed with Attune's option for every class's: its class said, "Sunken Temple Class
	-- Quest" is every class's name for theirs)
	if rec.group == "class" and rec.a.CLASS ~= MyClass() then
		local cls = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[rec.a.CLASS]) or rec.a.CLASS
		n = n .. " (" .. tostring(cls) .. ")"
	end
	if rec.group == "key" and not Lower(n):find(Lower(L["key"]), 1, true) and not Lower(n):find("key", 1, true) then
		n = L["%s key"]:format(n)
	end
	return n
end
AT.RowName = RowName

function AT.Row(rec)
	local words = { "attune attunement", rec.group == "key" and "key keys" or "", rec.group == "raid" and "raid" or "",
		rec.group == "dungeon" and "dungeon quests" or "", rec.group == "class" and "class quest quests" or "",
		Lower(AT.GROUP_LABEL[rec.group] or "") }
	if rec.group == "class" then
		words[#words + 1] = Lower(rec.a.CLASS)
		local loc = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[rec.a.CLASS]
		if loc then words[#words + 1] = Lower(loc) end
	end
	-- (what its steps name: "core fragment" finds Molten Core's)
	for _, r in ipairs(rec.steps) do
		if r.type ~= "Level" and r.type ~= "Rep" then words[#words + 1] = Lower(r.title) end
	end
	local row = setmetatable({ _compact = true, key = rec.id, name = RowName(rec), text = table.concat(words, " "),
		classFile = rec.group == "class" and rec.a.CLASS or nil, _rank = 0 }, AT.meta)
	return row
end

--- @attune's rows: what Attune lists for you, in its order.
function AT.Collect()
	local idx = AT.Index()
	if not (idx and AT.meta) then return {} end
	local D, faction, cls = DB(), MyFaction(), MyClass()
	local rows = {}
	for _, rec in ipairs(idx.list) do
		if Visible(rec, faction, cls, D) then rows[#rows + 1] = AT.Row(rec) end
	end
	local n = #rows
	for i, e in ipairs(rows) do e._rank = (n - i + 1) / (n + 1) * 0.5 end -- (Attune's order among equal matches)
	return rows
end

-- a step row: its quest's tooltip (Attune's names and objectives; the game's or Questie's rewards), its item's, its NPC's
local function StepTooltip(e, t)
	local r = e.stepRec
	local rec = r and index and index.byId[r.aid]
	if not (r and rec) then t:SetText(e.name) return end
	local state = AT.StepState(r)
	local qid = e.qid
	if qid then
		local D = Data()
		local q = D and type(D.quests) == "table" and D.quests[qid]
		local giver = D and type(D.questGivers) == "table" and D.questGivers[qid]
		local obj = Lang("Q2_" .. qid)
		local done = state == "done"
		-- (Attune's quest level is the one it needs: its own tooltip says "Requires level")
		ns.QuestTip.Draw(t, { id = qid, name = e.name, needs = type(q) == "table" and tonumber(q[1]) or nil, zone = r.where,
			lines = obj and { obj } or nil, giver = type(giver) == "table" and Str(giver[4]) or nil,
			status = done and L["Done"] or (state == "next" and L["Next"]) or nil,
			statusColour = done and GREEN or (state == "next" and YELLOW) or nil })
	elseif r.itemID and pcall(t.SetHyperlink, t, "item:" .. r.itemID) then
		if (r.count or 1) > 1 then t:AddLine(L["%d needed"]:format(r.count), 1, 1, 1) end
		if r.where then t:AddLine(r.where, DIM[1], DIM[2], DIM[3]) end
	else
		t:SetText(e.name, GOLD[1], GOLD[2], GOLD[3])
		local D = Data()
		local npc = r.npcID and D and type(D.npcs) == "table" and D.npcs[r.npcID]
		if type(npc) == "table" then
			local bits = {}
			if Str(npc[1]) then bits[#bits + 1] = L["Level %s"]:format(npc[1]) end
			if Str(npc[2]) then bits[#bits + 1] = npc[2] end
			if Str(npc[3]) then bits[#bits + 1] = npc[3] end
			if #bits > 0 then t:AddLine(table.concat(bits, " "), 1, 1, 1) end
		end
		local verb = AT.VERB[r.type]
		if verb and r.type ~= "Level" and r.type ~= "Rep" then t:AddLine(verb, 1, 1, 1) end
		if r.where then t:AddLine(r.side and L["inside %s"]:format(r.where) or r.where, DIM[1], DIM[2], DIM[3]) end
	end
	if not qid then
		if state == "done" then t:AddLine(L["Done"], GREEN[1], GREEN[2], GREEN[3])
		elseif state == "next" then t:AddLine(L["Next"], YELLOW[1], YELLOW[2], YELLOW[3]) end
	end
	t:AddLine(" ")
	t:AddLine(L["Step %d of %d of %s (Attune)"]:format(e.stepIndex or 0, #rec.steps, RowName(rec)), GOLD[1], GOLD[2], GOLD[3], true)
	t:AddLine(L["Enter: show in Attune    Shift+Enter: put it in the chat box"], DIM[1], DIM[2], DIM[3], true)
end

-- a step for chat: a quest's link, an item's, else its words; with its attunement
local function StepShare(e)
	local r = e.stepRec
	local rec = r and index and index.byId[r.aid]
	local what
	if e.qid and I.QuestieQuestLink then what = I.QuestieQuestLink(e.qid) end
	if not what and r and r.itemID then
		local info = C_Item and C_Item.GetItemInfo and select(2, Safe(C_Item.GetItemInfo, r.itemID))
		if Str(info) then what = info end
	end
	what = what or ("[" .. tostring(e.name) .. "]")
	return what .. (rec and (" (" .. RowName(rec) .. ")") or "")
end

local function OpenStep(e)
	local r = e.stepRec
	local rec = r and index and index.byId[r.aid]
	if not rec then return end
	-- (a step that's another attunement: that one)
	if r.linkAttune and index.byId[r.linkAttune] then return AT.Open(index.byId[r.linkAttune]) end
	AT.Open(rec, r.id)
end

AT.STEP = { activate = OpenStep, tooltip = StepTooltip, secondary = function(e) ns.LinkInChat(StepShare(e)) end,
	secondarySecure = ns.ChatBoxSpec(StepShare), secondaryIsOpen = ns.ChatBoxNeverOpen, shareLink = StepShare, isStep = true }
AT.STEP_LAZY = {
	detail = function(t)
		local r = t.stepRec
		local rec = index and index.byId[r.aid]
		local parts = { L["step %d of %d"]:format(t.stepIndex or 0, rec and #rec.steps or 0) }
		local verb = AT.VERB[r.type]
		if r.type == "Item" and (r.count or 1) > 1 then verb = L["get %d"]:format(r.count) end
		if verb and r.type ~= "Level" and r.type ~= "Rep" then parts[#parts + 1] = verb end
		if r.where then parts[#parts + 1] = r.side and L["inside %s"]:format(r.where) or r.where end
		local st = AT.StepState(r)
		if st == "done" then parts[#parts + 1] = "|cff40ff40" .. L["done"] .. "|r"
		elseif st == "next" then parts[#parts + 1] = "|cffffe066" .. L["next"] .. "|r" end
		return table.concat(parts, SEP)
	end,
	icon = function(t)
		local r = t.stepRec
		if AT.StepState(r) == "done" then return DONE_ICON end
		return Str(r.step.ICON) or "Interface\\Icons\\INV_Scroll_03"
	end,
	-- (the quest you can take of those the step stands for: the same quest for each race)
	qid = function(t)
		local qids = t.stepRec.qids
		if not qids or #qids == 0 then return nil end
		local QR = ns.QuestRewards
		for _, q in ipairs(qids) do
			if not (QR and QR.ForYou) or QR.ForYou(q) then return q end
		end
		return qids[1]
	end,
	itemID = function(t) return t.stepRec.itemID end,
	npcID = function(t) return t.stepRec.npcID end,
	linkAttune = function(t) return t.stepRec.linkAttune end,
	attuneId = function(t) return t.stepRec.aid end,
}

--- An attunement's step rows, first to last. `how`: what the chain says found them.
function AT.StepRows(rec, how)
	local out = {}
	if not (rec and AT.stepMeta) then return out end
	for i, r in ipairs(rec.steps) do
		out[#out + 1] = setmetatable({ _compact = true, key = rec.id .. "-" .. r.id, name = r.title, _lname = Lower(r.title),
			stepRec = r, stepIndex = i, pipeHow = how, _score = 1e6 - i }, AT.stepMeta)
	end
	return out
end

--- The attunement record a row stands for (an @attune row, or a step row: its own), or nil.
function AT.RecOf(e)
	if type(e) ~= "table" or e.kind ~= "attune" then return nil end
	return AT.Index() and index.byId[tostring(e.attuneId)]
end

----------------------------------------------------------------------
-- Setup (at login, with the other integrations: Setup.lua)
----------------------------------------------------------------------

local function SetupAttune()
	if attune.on or not Present() then return end
	attune.on = true
	ns:RegisterProvider("attune", {
		label = L["Attunement"],
		color = "ffe05a7a", -- (Attune's steps are drawn red)
		aliases = { "attune", "attunement", "attunements", "attunes" },
		-- (a step done: Attune marks it in its own handler of these; the rows read its record when drawn)
		events = { "QUEST_TURNED_IN", "QUEST_ACCEPTED", "PLAYER_LEVEL_UP" },
		guard = 1,
		collect = function()
			if not Present() then return {} end -- (Attune went away: no stale rows)
			return AT.Collect()
		end,
	})
	AT.meta = ns:CompactMeta(ns.providers.attune, AT.ROW, AT.ROW_LAZY)
	AT.stepMeta = ns:CompactMeta(ns.providers.attune, AT.STEP, AT.STEP_LAZY)
	-- (Attune's data read a moment after login, and the step names the questions look at: not on a keystroke)
	C_Timer.After(AT.WARM_AFTER, function()
		if AT.Index() and AT.Q and AT.Q.NamesStep then AT.Q.NamesStep("a b") end
	end)
end
AT.WARM_AFTER = 6 -- (s after login)
I._.SetupAttune = SetupAttune

--- .integrations' line about Attune.
function AT.Status()
	if not attune.on then return L["not found"] end
	local p = ns.providers.attune
	local rows = p and ns:GetEntries(p) or {}
	local done = 0
	for _, e in ipairs(rows) do
		local rec = RecOf(e)
		local pct = rec and AT.Mine(rec)
		if pct and pct >= 100 then done = done + 1 end
	end
	return L["found (%s). %d attunements, quest lines and keys for you, %d done"]:format(AddOnVersion("Attune"), #rows, done)
end
