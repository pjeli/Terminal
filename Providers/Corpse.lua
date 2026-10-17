local ns = select(2, ...)
local L = ns.L

-- Your corpse (@corpse, @body; Simple mode: "where is my body", "my corpse", "corpse run", "where did i die", under
-- Places; 0.50.5, the player's ask): while you're dead, where your body lies, how far and which way (the arrow on the
-- row turns with you), and the nearest spirit healers (Questie's NPCs: "nearest spirit healer" works on its own too,
-- @npc is:spirithealer). Enter opens the map on it with a pin, Shift+Enter only pins it.
--
-- Where it is is the game's own answer (C_DeathInfo.GetCorpseMapPosition), asked of the map you're on and, when that
-- one doesn't say, the maps above it (a corpse in the next zone is on the continent's map). Inside an instance the
-- game doesn't say: the row says so.

local C = {}
ns.Corpse = C

local Safe, Num = ns.Safe, ns.Num
local I = ns.Integrations

C.HEALERS = 3 -- (the nearest spirit healers listed with it)
C.ICON = "Interface\\Icons\\Ability_Rogue_FeignDeath"

local function Dead() return Safe(UnitIsDeadOrGhost, "player") and true or false end

--- Where your corpse is: map id, x, y (0-1), or nil (you're alive, or the game doesn't say: an instance).
function C.Where()
	local DI = C_DeathInfo
	if not (DI and DI.GetCorpseMapPosition and C_Map and C_Map.GetBestMapForUnit) then return nil end
	local map = Safe(C_Map.GetBestMapForUnit, "player")
	for _ = 1, 6 do
		if not map then break end
		local pos = Safe(DI.GetCorpseMapPosition, map)
		if pos then
			local x, y = pos.x, pos.y
			if pos.GetXY then x, y = pos:GetXY() end
			x, y = Num(x), Num(y) -- (a secret value: not known)
			if x and y and (x > 0 or y > 0) then return map, x, y end
		end
		local info = C_Map.GetMapInfo and Safe(C_Map.GetMapInfo, map)
		map = type(info) == "table" and info.parentMapID and info.parentMapID ~= 0 and info.parentMapID or nil
	end
end

local function Tooltip(e, t)
	t:SetText(e.name, 1, 0.82, 0)
	if e.zone then t:AddLine(e.zone, 0.8, 0.8, 0.8) end
	local delay = _G.GetCorpseRecoveryDelay and Num(Safe(_G.GetCorpseRecoveryDelay))
	if delay and delay > 0 then t:AddLine(L["You can take it back in %d s."]:format(math.ceil(delay)), 1, 1, 1) end
	ns.KeyHints(t, L["Enter: show on map    Shift+Enter: set a waypoint"], 0.6, 0.6, 0.6, true)
end

--- Your corpse's row while you're dead and the game says where it lies, else nil.
function C.Row()
	if not Dead() then return nil end
	local map, x, y = C.Where()
	if not map then return nil end
	local px, py = x * 100, y * 100
	local cont, wx, wy
	if I and I.SpotXY then cont, wx, wy = I.SpotXY(map, { px, py }) end
	local zone = I and I.ZoneName and I.ZoneName(map) or nil
	local row = {
		key = "corpse", name = L["Your corpse"], icon = C.ICON, detail = zone or "", zone = zone,
		text = "corpse body dead death ghost graveyard run " .. ns.Lower(zone or ""),
		ui = map, px = px, py = py, wcont = cont, wx = wx, wy = wy, pinName = L["Your corpse"], tooltip = Tooltip,
	}
	return I and I.SpotRow and I.SpotRow(row) or row
end

ns:RegisterProvider("corpse", {
	label = L["Corpse"],
	color = "ff8a8aa8",
	aliases = { "corpse", "body" },
	events = { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "ZONE_CHANGED_NEW_AREA" },
	collect = function()
		local r = C.Row()
		return r and { r } or {}
	end,
})

----------------------------------------------------------------------
-- The question: "where is my body", "my corpse", "corpse run", "where did i die", "find my corpse"
----------------------------------------------------------------------

local FILL = {}
for w in ([[where wheres is my me i the a to find get back go show did died die run whats what way which how far]]):gmatch("%a+") do FILL[w] = true end

--- The question, or nil when the line isn't about your corpse.
function C.Question(text)
	local t = ns.QuestionText(text)
	if not t then return nil end
	t = t:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	if t == "where did i die" or t == "where i died" then return {} end
	local corpse, body, my = false, false, false
	for w in t:gmatch("%S+") do
		if w == "corpse" or w == "corpses" then corpse = true
		elseif w == "body" then body = true
		elseif w == "my" then my = true
		elseif not FILL[w] then return nil end -- (another word: a search, "corpse lily", "body armor")
	end
	if corpse or (body and my) then return {} end
	return nil
end

C.NOTE = L["Your corpse"]

local NoteRow = ns.NoteRow

-- the nearest spirit healers (Questie's NPCs), each as a nearest view
-- (the spirit healers among the NPC list, kept per list: the answer is asked on every keystroke of "corpse", and each
-- walked every NPC through the role test; only how far each is is worked out again. Review, 0.53.6)
local healers, healersOf
local function Healers(here)
	local p = ns.providers.npc
	local is = ns.Filters and ns.Filters._ and ns.Filters._.IS and ns.Filters._.IS.spirithealer
	if not (p and is and here and I and I.RowYards) then return {} end
	local list = ns:GetEntries(p)
	if healersOf ~= list then
		healers, healersOf = {}, list
		for _, e in ipairs(list) do if is(e) then healers[#healers + 1] = e end end
	end
	local found = {}
	for _, e in ipairs(healers) do
		local d = I.RowYards(e, here)
		if d then found[#found + 1] = { e, d } end
	end
	table.sort(found, function(a, b) return a[2] < b[2] end)
	local out = {}
	local view = ns.UI and ns.UI._Scan and ns.UI._Scan.NearView
	for i = 1, math.min(#found, C.HEALERS) do
		out[#out + 1] = view and view(found[i][1], found[i][2]) or found[i][1]
	end
	return out
end

function C.Answer()
	local rows = {}
	local here = I and I.Here and I.Here()
	if not Dead() then
		rows[1] = NoteRow(L["You're alive: no corpse to find."])
	else
		local r = C.Row()
		if r then
			local d = here and I.RowYards and I.RowYards(r, here)
			local view = ns.UI and ns.UI._Scan and ns.UI._Scan.NearView
			rows[1] = (d and view) and view(r, d) or r
		else
			rows[1] = NoteRow(L["The game doesn't say where your corpse is here (inside an instance it doesn't)."])
		end
	end
	for _, h in ipairs(Healers(here)) do rows[#rows + 1] = h end
	for i, e in ipairs(rows) do e._score = 1e7 - i end
	return rows, C.NOTE .. ((#rows > 1) and (ns.DETAIL_SEP .. L["and the nearest spirit healers"]) or "")
end

function C.ToAdvanced() return nil end -- (as said: the nearest spirit healers come too, which @corpse doesn't list; 0.55.7)
