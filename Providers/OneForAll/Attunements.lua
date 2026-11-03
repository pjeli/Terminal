local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations
local OA = ns.OneForAll
local AT = ns.Attune

-- @attune without Attune (1.0.7, the player's ask): OneForAll's dungeon keys and raid attunements (DUNGEON_KEYS: the
-- Scarlet Key, the Skeleton Key, the Seal of Ascension... and Onyxia's Drakefire Amulet, each faction's chain), made
-- into the records Attune's part reads (Providers/Integrations/Attune.lua: AT.Index, AT.fallback), so the rows, "> steps",
-- "> attunement", "my keys", "how do i get into onyxia", is:done and the rest work as they do with Attune. Attune
-- installed: Attune's, never these (it has more of them, and your alts' progress).
--
-- How far along: the game's, as OneForAll's own window has it: the key or amulet in your bags, bank or keyring (all of it
-- done), else every step up to the last quest you've turned in. A step that isn't a quest ("Open Doan's Strongbox") is
-- done once a later one is, or the key is yours.

local K = {}
OA.Attunements = K
local Safe, Lower, Num, Str = ns.Safe, ns.Lower, ns.Num, ns.Str
local SEP = ns.DETAIL_SEP
local DONE_ICON = "Interface\\RAIDFRAME\\ReadyCheck-Ready"
local GOLD, DIM, GREEN, YELLOW = { 1, 0.82, 0 }, { 0.6, 0.6, 0.6 }, { 0.25, 1, 0.25 }, { 1, 0.9, 0.3 }
K.FRESH = 1 -- (s: what the game says you've done, read again after)

-- a raid by its name: Terminal's own instance list (Entrances.lua's I.INSTANCES: the third field)
local function IsRaid(name)
	for _, t in ipairs(I.INSTANCES or {}) do
		if t[2] == name then return t[3] == true end
	end
	return false
end

--- Its keys and attunements, checked, one per item (the Scarlet Key opens two wings: one, with both): { { item, name,
--- required, summary, instances, raid, steps = { { quest, name, level, requires, faction, pickup, objective, turnin } } } },
--- or nil.
function K.Data()
	return OA.Part("keys", "DUNGEON_KEYS", L["@attune is unavailable."], function(raw)
		local names = {}
		for inst in pairs(raw) do
			if type(inst) == "string" then names[#names + 1] = inst end
		end
		table.sort(names)
		local out, byItem, bad = {}, {}, 0
		for _, inst in ipairs(names) do
			local list = raw[inst]
			for _, k in ipairs(type(list) == "table" and list or {}) do
				local item, name = type(k) == "table" and Num(k.item), type(k) == "table" and OA.Text(k.name)
				local steps = {}
				for _, s in ipairs(item and type(k.steps) == "table" and k.steps or {}) do
					local sn = type(s) == "table" and OA.Text(s.name)
					if sn then
						steps[#steps + 1] = { quest = Num(s.quest), name = sn, level = Num(s.level), requires = Num(s.requires),
							faction = (s.faction == "Alliance" or s.faction == "Horde") and s.faction or nil, pickup = OA.Text(s.pickup),
							objective = OA.Text(s.objective), turnin = OA.Text(s.turnin) }
					end
				end
				if item and name and #steps > 0 then
					local e = byItem[item]
					if e then
						e.instances[#e.instances + 1] = inst
						e.raid = e.raid or IsRaid(inst)
					else
						e = { item = item, name = name, required = k.required == true, summary = OA.Text(k.summary), instances = { inst },
							raid = IsRaid(inst), steps = steps, order = #out + 1 }
						byItem[item] = e
						out[#out + 1] = e
					end
				else
					bad = bad + 1
				end
			end
		end
		if #out == 0 then return nil, "OneForAll.DUNGEON_KEYS: no key in the shape expected (" .. bad .. " entries not)" end
		if bad > 0 then ns:Trace(("oneforall: %d keys not in the shape expected, left out"):format(bad)) end
		-- (the raids first, as Attune lists them; then the keys by their dungeon)
		table.sort(out, function(a, b)
			if a.raid ~= b.raid then return a.raid end
			return a.order < b.order
		end)
		return out
	end)
end

-- "Scarlet Monastery: Armory, Cathedral": the instances, a shared "X: " said once
local function Places(list)
	local pre = #list > 1 and list[1]:match("^(.-: )")
	if pre then
		local rest = {}
		for i, n in ipairs(list) do
			if n:sub(1, #pre) ~= pre then pre = nil break end
			rest[i] = n:sub(#pre + 1)
		end
		if pre then return pre .. table.concat(rest, ", ") end
	end
	return table.concat(list, ", ")
end

local index -- AT's index made of OneForAll's: { list, byId, byQuest, byItem, byNpc }
local where -- a done-map key ("<id>-<step>", "<id>-have") -> { rec, step number (0: the key itself) }

-- One key's record for a faction (nil: both, a chain with no faction's steps), as Attune.lua's records are: `a` the few
-- fields of Attune's it reads, `steps` in order, each after the one before.
local function Record(k, faction)
	local aid = "ofa" .. k.item .. (faction and ("-" .. faction:sub(1, 1)) or "")
	local mine = {}
	for _, s in ipairs(k.steps) do
		if not (faction and s.faction and s.faction ~= faction) then mine[#mine + 1] = s end
	end
	if #mine == 0 then return nil end
	local lo, hi
	for _, s in ipairs(mine) do
		if s.requires and (not lo or s.requires < lo) then lo = s.requires end
		if s.level and (not hi or s.level > hi) then hi = s.level end
	end
	-- ("Seal of Ascension (Upper Blackrock Spire key)": the dungeon it opens, and that it's a key when the name doesn't say)
	local places = Places(k.instances)
	if not k.raid and not Lower(k.name):find("key", 1, true) then places = L["%s key"]:format(places) end
	local icon = C_Item and C_Item.GetItemIconByID and Safe(C_Item.GetItemIconByID, k.item)
	local rec = { id = aid, group = k.raid and "raid" or "key", keys = {}, steps = {}, all = {}, item = k.item, oneForAll = k,
		minLevel = lo, maxLevel = hi or lo, endKey = aid .. "-have",
		a = { ID = aid, NAME = ("%s (%s)"):format(k.name, places), FACTION = faction or "Both", DESC = k.summary,
			LEVELS = lo and ((hi and hi ~= lo) and (lo .. "-" .. hi) or tostring(lo)) or nil,
			ICON = (type(icon) == "number" or Str(icon)) and icon or nil } }
	for i, s in ipairs(mine) do
		local sid = tostring(i)
		local st = { ID = sid, TYPE = s.quest and "Quest" or "Step", FOLLOWS = i > 1 and tostring(i - 1) or "0", STAGE = i }
		rec.all[sid] = st
		rec.keys[#rec.keys + 1] = aid .. "-" .. sid
		rec.steps[#rec.steps + 1] = { aid = aid, step = st, id = sid, type = st.TYPE, keys = { aid .. "-" .. sid }, title = s.name,
			qids = s.quest and { s.quest } or nil, where = s.pickup and (s.pickup:gsub("%s*%b()%s*$", "")), pickup = s.pickup,
			turnin = s.turnin, objective = s.objective, needs = s.requires, qlevel = s.level }
	end
	AT.Number(rec) -- ("step 3 of 16": one line of quests, numbered as Attune's are)
	return rec
end

local function Add(map, id, aid)
	if not id then return end
	local t = map[id]
	if not t then t = {}; map[id] = t end
	for _, x in ipairs(t) do if x == aid then return end end
	t[#t + 1] = aid
end

--- AT.Index's records, made of OneForAll's keys once; nil without them.
function K.Index()
	if index then return index end
	local data = K.Data()
	if not data then return nil end
	local idx = { list = {}, byId = {}, byQuest = {}, byItem = {}, byNpc = {} }
	where = {}
	local function Put(rec)
		if not rec then return end
		rec.order = #idx.list + 1
		idx.list[#idx.list + 1] = rec
		idx.byId[rec.id] = rec
		Add(idx.byItem, rec.item, rec.id)
		where[rec.endKey] = { rec, 0 }
		for i, r in ipairs(rec.steps) do
			where[r.keys[1]] = { rec, i }
			for _, q in ipairs(r.qids or {}) do Add(idx.byQuest, q, rec.id) end
		end
	end
	for _, k in ipairs(data) do
		local split = false
		for _, s in ipairs(k.steps) do if s.faction then split = true break end end
		if split then
			Put(Record(k, "Alliance"))
			Put(Record(k, "Horde"))
		else
			Put(Record(k))
		end
	end
	index = idx
	ns:Trace(("oneforall: %d keys and attunements read"):format(#idx.list))
	return idx
end

local function QuestDone(id)
	local f = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or _G.IsQuestFlaggedCompleted
	return f and Safe(f, id) == true or false
end
local function Have(id)
	local f = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
	return f and (Num(Safe(f, id, true)) or 0) > 0 or false
end

-- what the game says you've done, per record: { have = the key's yours, past = the last step done }, kept K.FRESH s
local snap, snapAt
local function Snapshot()
	local now = _G.GetTime and Num(Safe(_G.GetTime)) or 0
	if snap and snapAt and now - snapAt < K.FRESH then return snap end
	snap, snapAt = {}, now
	for _, rec in ipairs(index and index.list or {}) do
		local s = { have = Have(rec.item), past = 0 }
		for i, r in ipairs(rec.steps) do
			for _, q in ipairs(r.qids or {}) do
				if QuestDone(q) then s.past = i end
			end
		end
		snap[rec.id] = s
	end
	return snap
end
function K.ForgetDone() snap = nil end

-- the done map Attune.lua reads as a character's record (Attune_DB.toons[name].done)
local DONE = setmetatable({}, { __index = function(_, key)
	local w = where and where[key]
	local s = w and Snapshot()[w[1].id]
	if not s then return nil end
	if s.have then return true end
	return w[2] > 0 and w[2] <= s.past
end })
local TOON = { done = DONE }
--- The character you're on, as Attune's records are: its done map from the game.
function K.Toon() return TOON end

function K.Forget() index, where, snap = nil, nil, nil end -- (tests)

----------------------------------------------------------------------
-- Rows: their own Enter and tooltips (no Attune window to open); detail, icon and levels are Attune.lua's
----------------------------------------------------------------------

local function RecOf(e) return index and index.byId[tostring(e.attuneId)] end

local function Walk(text)
	local UI = ns.UI
	if UI and UI.WalkTo then UI:WalkTo(text) elseif UI and UI.SetQuery then UI:SetQuery(text, #text) end
end

local function StepsText(rec)
	local name = rec.oneForAll.name
	local E = ns.Easy
	if E and E.On and E.On() then return "steps for " .. Lower(name) end -- (Simple mode's phrase, Attunements.lua)
	return name .. " > steps"
end

local function StepLine(r)
	local s = r.qids and (L["quest"] .. ": " .. r.title) or r.title
	return r.where and (s .. "  |cff999999(" .. r.where .. ")|r") or s
end

local function ShareText(e)
	local rec = RecOf(e)
	local pct = rec and AT.Mine(rec)
	local nxt = rec and AT.NextSteps(rec)[1]
	local s = tostring(e.name)
	if pct then s = s .. ": " .. (pct >= 100 and L["done"] or (pct .. "%")) end
	if nxt and pct and pct < 100 then s = s .. ", " .. L["next: %s"]:format(nxt.title) end
	return s
end

local function Tooltip(e, t)
	local rec = RecOf(e)
	t:SetText(e.name, GOLD[1], GOLD[2], GOLD[3])
	if not rec then return end
	local head = { AT.GROUP_LABEL[rec.group] }
	if rec.a.LEVELS then head[#head + 1] = L["Level %s"]:format(rec.a.LEVELS) end
	t:AddLine(table.concat(head, SEP), DIM[1], DIM[2], DIM[3])
	if rec.a.DESC then t:AddLine(rec.a.DESC, 0.8, 0.8, 0.8, true) end
	local pct, n, of = AT.Mine(rec)
	if pct then
		local c = pct >= 100 and GREEN or { 1, 1, 1 }
		t:AddDoubleLine(L["Progress"], pct >= 100 and L["done"] or L["%d%% (%d of %d steps)"]:format(pct, n, of), 1, 1, 1, c[1], c[2], c[3])
		local nxt = pct < 100 and AT.NextSteps(rec) or {}
		if #nxt > 0 then
			t:AddLine(" ")
			t:AddLine(L["Next:"], GOLD[1], GOLD[2], GOLD[3])
			for i = 1, math.min(#nxt, 6) do t:AddLine("  " .. StepLine(nxt[i]), 1, 1, 1, true) end
		end
	end
	t:AddDoubleLine(L["Steps"], tostring(#rec.steps), 1, 1, 1, 1, 1, 1)
	ns.KeyHints(t, L["Enter: its steps    Shift+Enter: put it in the chat box"], DIM[1], DIM[2], DIM[3], true)
end

K.ROW = { activate = function(e) local rec = RecOf(e) if rec then Walk(StepsText(rec)) end end, staysOpen = true,
	tooltip = Tooltip, secondary = function(e) ns.LinkInChat(ShareText(e)) end, secondarySecure = ns.ChatBoxSpec(ShareText),
	secondaryIsOpen = ns.ChatBoxNeverOpen, shareLink = ShareText }

local function StepTooltip(e, t)
	local r = e.stepRec
	local rec = r and index and index.byId[r.aid]
	if not (r and rec) then t:SetText(e.name) return end
	local state = AT.StepState(r)
	local status = state == "done" and L["Done"] or (state == "next" and L["Next"]) or nil
	local colour = state == "done" and GREEN or (state == "next" and YELLOW) or nil
	if e.qid then
		ns.QuestTip.Draw(t, { id = e.qid, name = e.name, needs = r.needs, level = r.qlevel, lines = r.objective and { r.objective } or nil,
			giver = r.pickup, status = status, statusColour = colour })
		if r.turnin then t:AddLine(L["Turn in: %s"]:format(r.turnin), 1, 1, 1, true) end
	else
		t:SetText(e.name, GOLD[1], GOLD[2], GOLD[3])
		if r.objective then t:AddLine(r.objective, 1, 1, 1, true) end
		if r.pickup then t:AddLine(r.pickup, DIM[1], DIM[2], DIM[3], true) end
		if status then t:AddLine(status, colour[1], colour[2], colour[3]) end
	end
	t:AddLine(" ")
	t:AddLine(L["Step %s of %d of %s (OneForAll)"]:format(r.label or tostring(e.stepIndex or 0), rec.stages or #rec.steps, AT.RowName(rec)),
		GOLD[1], GOLD[2], GOLD[3], true)
	if e.qid then ns.KeyHints(t, L["Enter: show its Wowhead page    Shift+Enter: link it in chat"], DIM[1], DIM[2], DIM[3], true) end
end

local function StepShare(e)
	local r = e.stepRec
	local rec = r and index and index.byId[r.aid]
	local what = e.qid and I.QuestieQuestLink and I.QuestieQuestLink(e.qid) or ("[" .. tostring(e.name) .. "]")
	return what .. (rec and (" (" .. AT.RowName(rec) .. ")") or "")
end

-- Enter on a step: a quest's Wowhead page (as Questie's quests: the slim link bar); another step says what it asks
local function OpenStep(e)
	if e.qid and I.WOWHEAD_QUEST then
		ns:ShowText(L["Wowhead: %s"]:format(tostring(e.name)), I.WOWHEAD_QUEST:format(e.qid), { compact = true })
		return
	end
	local r = e.stepRec
	ns:Print(tostring(e.name) .. (r and r.objective and (": " .. r.objective) or ""))
end

K.STEP = { activate = OpenStep, tooltip = StepTooltip, secondary = function(e) ns.LinkInChat(StepShare(e)) end,
	secondarySecure = ns.ChatBoxSpec(StepShare), secondaryIsOpen = ns.ChatBoxNeverOpen, shareLink = StepShare, isStep = true }

OA.AddSetup(function()
	-- (Attune's own when it's installed: it has more, and your alts')
	if (I.attune and I.attune.on) or ns.providers.attune then return end
	if not K.Data() then return end
	K.on = true
	AT.fallback = K
	ns:RegisterProvider("attune", {
		label = L["Attunement"],
		color = "ffe05a7a",
		aliases = { "attune", "attunement", "attunements", "attunes" },
		events = { "QUEST_TURNED_IN", "QUEST_ACCEPTED", "PLAYER_LEVEL_UP", "BAG_UPDATE_DELAYED" },
		guard = 1,
		collect = function()
			K.ForgetDone()
			return AT.Collect()
		end,
	})
	AT.meta = ns:CompactMeta(ns.providers.attune, K.ROW, AT.ROW_LAZY)
	AT.stepMeta = ns:CompactMeta(ns.providers.attune, K.STEP, AT.STEP_LAZY)
	C_Timer.After(AT.WARM_AFTER, function()
		if AT.Index() and AT.Q and AT.Q.NamesStep then AT.Q.NamesStep("a b") end
	end)
end)
OA.AddStatus(function()
	if not K.on then return nil end
	return L["%d keys and raid attunements (@attune: Attune isn't installed)"]:format(index and #index.list or #(K.Data() or {}))
end)
