local ns = select(2, ...)
local L = ns.L

-- Your layer (@layer; Simple mode: "what layer am i on", "my layer"; 1.1.13, the player's ask). WoW Forever's open
-- world runs on layers, and the game says nothing of which one you're on. Every creature's GUID carries it: a GUID is
-- "Creature-0-<server>-<map>-<zone UID>-<npc id>-<spawn uid>", and the zone UID is the same for every creature of one
-- layer of a map and differs between layers (how Forever's layer addons tell it: LayerTracker, Forever Layer Hop).
-- So the creatures you mouse over, target or see a nameplate of are read as they come (UnitGUID, the game's own; never
-- a secret one, which this client gives where a unit's identity is restricted), the latest kept. One row: the layer's
-- number (the server's, not a "layer 1, 2, 3"), where and from whom it was read, and when more than one has been seen
-- on this map since you logged in, which of them by number. In a dungeon or raid there are no layers: said so.
-- Nothing is saved: the numbers change as the servers restart.

local LY = {}
ns.Layer = LY

LY.KINDS = { Creature = true, Vehicle = true } -- (the GUID kinds that carry a layer: not players, pets, objects)
LY.UNITS = { "mouseover", "target", "focus" }

local cur -- { id = zone UID, map = the map field, name = whose GUID, zone = where, at = GetTime() }
local seen = {} -- map field -> { [zone UID] = true }, since login

--- The layer of a GUID: zone UID, map field (numbers), or nil (not a creature's, secret, or without one).
function LY.FromGUID(guid)
	if type(guid) ~= "string" or (ns.Secret and ns.Secret(guid)) then return nil end
	local kind, map, zoneUID = guid:match("^(%a+)%-[^%-]*%-[^%-]*%-([^%-]*)%-([^%-]*)%-")
	if not LY.KINDS[kind] then return nil end
	local id, m = tonumber(zoneUID), tonumber(map)
	if not id or id == 0 then return nil end
	return id, m
end

--- In a dungeon, raid, battleground or arena (no layers there)?
function LY.Instanced()
	local ok, inside, kind = pcall(IsInInstance)
	return ok and inside == true and kind ~= "none"
end

--- A unit seen (a token): its layer kept when it has one. True when the layer kept changed.
function LY.Saw(unit)
	if LY.Instanced() then return false end
	local ok, guid = pcall(UnitGUID, unit)
	if not ok then return false end
	local id, map = LY.FromGUID(guid)
	if not id then return false end
	local name = ns.Str and ns.Str(select(2, pcall(UnitName, unit))) or nil
	local zone = GetRealZoneText and ns.Str and ns.Str(select(2, pcall(GetRealZoneText))) or nil
	seen[map or 0] = seen[map or 0] or {}
	local fresh = not seen[map or 0][id]
	seen[map or 0][id] = true
	local changed = not cur or cur.id ~= id or cur.map ~= map
	if changed then
		ns:Trace(("layer: %s on map %s (from %s)%s"):format(id, tostring(map), tostring(name), cur and (" was " .. cur.id) or ""))
	end
	cur = { id = id, map = map, name = name, zone = zone, at = GetTime() }
	if changed or fresh then ns:Changed("layer") end
	return changed
end

--- The layer read last: { id, map, name, zone, at } or nil.
function LY.Current() return cur end

--- Of the layers seen on this map since login, which this is by number (1 = the lowest), and how many: n, of.
function LY.Rank(c)
	c = c or cur
	local ids = {}
	for id in pairs(c and seen[c.map or 0] or {}) do ids[#ids + 1] = id end
	table.sort(ids)
	for i, id in ipairs(ids) do if id == c.id then return i, #ids end end
	return nil, #ids
end

--- (tests: a new session)
function LY.Reset() cur, seen = nil, {} end

local function Ago(at) return ns.Ago(GetTime() - (at or GetTime())) end

--- What's said in chat: "Layer 2051 (Elwynn Forest)".
local function ShareText(e)
	local c = e.layer
	if not c then return e.name end
	return c.zone and L["Layer %s (%s)"]:format(c.id, c.zone) or L["Layer %s"]:format(c.id)
end
LY.ShareText = ShareText

local function Tooltip(e, t)
	t:SetText(e.name)
	local c = e.layer
	if c then
		if c.zone then t:AddLine(c.zone, 1, 1, 1) end
		t:AddLine(L["Read from %s, %s."]:format(tostring(c.name or L["a creature"]), Ago(c.at)), 0.8, 0.8, 0.8, true)
		local n, of = LY.Rank(c)
		if n and of > 1 then t:AddLine(L["%d of %d layers seen on this map since you logged in, by number."]:format(n, of), 0.8, 0.8, 0.8, true) end
	end
	t:AddLine(L["The number is the server's: the zone part of the creatures' GUIDs around you. It changes as the servers restart, and joining a group can move you to another layer."], 0.6, 0.6, 0.6, true)
	if ns.KeyHints then ns.KeyHints(t, L["Enter: show in chat    Shift+Enter: put in the chat box"], 0.6, 0.6, 0.6, true) end
end

local function Say(e) ns:Output({ ShareText(e) .. (e.detail and e.detail ~= "" and (ns.DETAIL_SEP .. e.detail) or "") }) end
local function ToChatBox(e) ns.LinkInChat(ShareText(e)) end
local CHATBOX = ns.ChatBoxSpec(ShareText)

--- Why there's no row: in a dungeon, or nothing met yet (the list's lead row, shown when it's asked for: a note in the
--- list itself would be searched by every Simple-mode line, its letters matching "toys").
function LY.NoneText()
	if LY.Instanced() then return L["No layers here: a dungeon, raid or battleground has none."] end
	return L["Layer not known yet: mouse over or target any creature, then ask again."]
end

--- The one row: the layer read last (none in a dungeon, or before any creature was met).
function LY.Rows()
	local c = cur
	if not c or LY.Instanced() then return {} end
	local n, of = LY.Rank(c)
	local parts = { L["from %s"]:format(tostring(c.name or L["a creature"])) .. ", " .. Ago(c.at) }
	if n and of > 1 then parts[#parts + 1] = L["%d of %d seen here"]:format(n, of) end
	return { {
		key = "layer", name = L["Layer %s"]:format(c.id), layer = c,
		detail = table.concat(parts, ns.DETAIL_SEP), text = "shard", -- (few letters: Simple mode searches it with every line)
		icon = "Interface\\Icons\\INV_Misc_Map_01",
		tooltip = Tooltip, activate = Say, staysOpen = false,
		secondary = ToChatBox, secondarySecure = CHATBOX, secondaryIsOpen = ns.ChatBoxNeverOpen,
		shareLink = ShareText,
	} }
end

ns:RegisterProvider("layer", {
	label = L["Layer"],
	color = "ff9ad0c2", -- (a cool sea green: one of a kind among the lists)
	aliases = { "layer", "layers", "shard" },
	explicit = true, -- (only asked for: @layer, its question, the Character category)
	refreshOnOpen = true, -- (its "12 s ago" moves on)
	leadRow = ns.EmptyLead(function() return LY.NoneText() end, function(p) return #(ns:GetEntries(p) or {}) == 0 end),
	collect = function() return LY.Rows() end,
})

-- the creatures you meet: mouse over, target, focus, nameplates
do
	local f = CreateFrame("Frame")
	for _, ev in ipairs({ "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "NAME_PLATE_UNIT_ADDED",
		"PLAYER_ENTERING_WORLD" }) do pcall(f.RegisterEvent, f, ev) end
	f:SetScript("OnEvent", function(_, event, unit)
		if event == "PLAYER_ENTERING_WORLD" then
			-- (a loading screen: another map or a fresh login; what was read before may be another layer's)
			cur = nil
			ns:Changed("layer")
			return
		end
		if event == "UPDATE_MOUSEOVER_UNIT" then LY.Saw("mouseover")
		elseif event == "PLAYER_TARGET_CHANGED" then LY.Saw("target")
		elseif event == "PLAYER_FOCUS_CHANGED" then LY.Saw("focus")
		elseif type(unit) == "string" then LY.Saw(unit) end
	end)
	LY.frame = f -- (tests)
end

----------------------------------------------------------------------
-- The question: "what layer am i on", "my layer", "which layer", "current layer", "layer"
----------------------------------------------------------------------
local ASK = {}
for w in ("what whats which am i im on in is my me current the this a which's tell show what's"):gmatch("%S+") do ASK[w] = true end
local STRONG = { layer = true, layers = true }

--- { } when the line asks which layer you're on, else nil.
function LY.Question(text)
	local t = ns.QuestionText and ns.QuestionText(text) or (type(text) == "string" and ns.Lower(text))
	if not t then return nil end
	local strong = false
	for w in t:gmatch("%S+") do
		if STRONG[w] then strong = true elseif not ASK[w] then return nil end
	end
	return strong and {} or nil
end
--- Its search: the list itself.
function LY.Line() return "@layer " end
function LY.Footer() return L["Your layer"] end
