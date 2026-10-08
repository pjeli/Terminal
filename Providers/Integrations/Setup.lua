local ns = select(2, ...)
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
	desc = "Show which other addons Terminal found (AtlasLoot, Questie)",
	run = function()
		local lines = { "Integrations:" }
		lines[#lines + 1] = "  AtlasLoot: " .. (loot.on
			and ("found (" .. tostring(LoadedCore() or "AtlasLoot") .. "). %d loot modules, %d indexed, %d items%s%s"):format(loot.modules, loot.loaded, #loot.rows, loot.done and "" or " (still loading)",
				(function()
					local n = I.LootWaiting()
					return n > 0 and (", %d waiting for their names from the server"):format(n) or ""
				end)())
			or "not found")
		local src = QD.Source()
		local found = src == "QuestieDB" and "QuestieDB found (without Questie)" or "found"
		lines[#lines + 1] = "  Questie: " .. (npc.on
			and (npc.list and ("%s. %d NPCs (@npc), %s quests (@questie)"):format(found, #npc.list, qdb.list and #qdb.list or "indexing")
				or (QuestieReady() and (found .. ", indexing NPCs...") or "found, waiting for Questie to finish loading"))
			or "not found")
		if ns.Stored then lines[#lines + 1] = "  Alts and banks: " .. ns.Stored.Status() end
		return lines
	end,
})