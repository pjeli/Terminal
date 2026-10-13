local ns = select(2, ...)
local L = ns.L
local I = ns.Integrations
local loot, npc, qdb = I.loot, I.npc, I.qdb
local LoadedCore = I.LoadedCore
local QD = ns.QuestieData
local QuestieReady = QD.Ready -- (the data can be read: QuestieDB loaded, and Questie ready if installed)
local SetupAtlasLoot, SetupQuestie = I._.SetupAtlasLoot, I._.SetupQuestie

----------------------------------------------------------------------
-- At login each integration whose addon is there starts; .integrations says what was found
----------------------------------------------------------------------

function I.Setup()
	SetupAtlasLoot()
	SetupQuestie()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() I.Setup() end)

ns:RegisterCommand("integrations", {
	desc = L["Show which other addons Terminal found (AtlasLoot, Questie)"],
	run = function()
		local lines = { L["Integrations:"] }
		lines[#lines + 1] = "  AtlasLoot: " .. (loot.on
			and L["found (%s). %d loot modules, %d indexed, %d items%s%s"]:format(tostring(LoadedCore() or "AtlasLoot"), loot.modules, loot.loaded, #loot.rows, loot.done and "" or (" " .. L["(still loading)"]),
				(function()
					local n = I.LootWaiting()
					return n > 0 and (", " .. L["%d waiting for their names from the server"]:format(n)) or ""
				end)())
			or L["not found"])
		local src = QD.Source()
		local found = src == "QuestieDB" and L["QuestieDB found (without Questie)"] or L["found"]
		lines[#lines + 1] = "  Questie: " .. (npc.on
			and (npc.list and L["%s. %d NPCs (@npc), %s quests (@questie)"]:format(found, #npc.list, qdb.list and #qdb.list or L["indexing"])
				or (QuestieReady() and L["%s, indexing NPCs..."]:format(found) or L["found, waiting for Questie to finish loading"]))
			or L["not found"])
		if ns.Stored then lines[#lines + 1] = "  " .. L["Alts and banks:"] .. " " .. ns.Stored.Status() end
		return lines
	end,
})