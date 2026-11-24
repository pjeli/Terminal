local ns = select(2, ...)
local L = ns.L

-- Your layer (@layer; Simple mode: "what layer am i on", "my layer"; 1.1.13, the player's ask). It was read from the
-- creatures you met: the zone part of a creature's GUID ("Creature-0-<server>-<map>-<zone UID>-<npc id>-<spawn uid>")
-- was the same for every creature of one layer. WoW Forever's hotfix of November 20, 2026 hid it: every creature's GUID
-- now carries a different server and zone number, two standing side by side included, and Blizzard said layer-picking
-- addons would be stopped through API changes. So no addon can tell which layer you're on (1.8.3, the player: "double
-- check if layering values are undetectable anymore"); @layer and its question say so rather than give a number that
-- means nothing.

local LY = {}
ns.Layer = LY

--- What @layer says: why there's no layer to show.
function LY.NoneText()
	return L["WoW Forever hides your layer since its November 20, 2026 hotfix: creatures no longer carry it, so no addon can tell which one you're on."]
end

ns:RegisterProvider("layer", {
	label = L["Layer"],
	color = "ff9ad0c2", -- (a cool sea green: one of a kind among the lists)
	aliases = { "layer", "layers", "shard" },
	explicit = true, -- (only asked for: @layer, its question, the Character category)
	leadRow = ns.EmptyLead(function() return LY.NoneText() end, function() return true end),
	collect = function() return {} end,
})

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
