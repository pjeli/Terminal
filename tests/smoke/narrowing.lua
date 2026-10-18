-- A filter whose answer changes by itself (is:ready, near:) doesn't narrow from the rows the last keystroke kept (review,
-- 0.57.7): "@spell is:ready f" with Fireball on cooldown, then "fi" after it ended, still left Fireball out.
local T = ...
local ns, UI, check = T.ns, T.UI, T.check

io.write("[narrowing: a filter that changes by itself reads every row again]\n")
do
	local save = { cd = C_Spell.GetSpellCooldown, time = _G.GetTime, easy = ns.db.easyMode }
	ns.db.easyMode = false; ns.Easy.temp = nil
	local cd = {}
	C_Spell.GetSpellCooldown = function(id) return { startTime = cd[id] and 100 or 0, duration = cd[id] and 30 or 0, isEnabled = true } end
	_G.GetTime = function() return 110 end
	ns:RegisterProvider("benchspell", { label = "BS", aliases = { "benchspell" }, explicit = true,
		collect = function() return { { kind = "spells", name = "Fireball", spellID = 9001 }, { kind = "spells", name = "Fire Blast", spellID = 9002 } } end })
	for _, e in ipairs(ns:GetEntries(ns.providers.benchspell)) do e.kind = "spells" end
	local function Names(res)
		local t = {}
		for _, e in ipairs(res) do if e.name and not e.noActivate then t[#t + 1] = e.name end end
		table.sort(t)
		return table.concat(t, ", ")
	end
	UI.lastScan = nil
	cd[9001] = true
	local a = Names(UI:SearchText("@benchspell is:ready f"))
	cd[9001] = nil
	local b = Names(UI:SearchText("@benchspell is:ready fi"))
	check(a == "Fire Blast" and b == "Fire Blast, Fireball", "its cooldown over: Fireball found on the next keystroke: [" .. a .. "] then [" .. b .. "]")
	-- (a filter that doesn't change by itself still narrows)
	UI:SearchText("@benchspell f")
	UI:SearchText("@benchspell fi")
	check(UI.lastSearchNarrowed == true, "other filters still narrow from the last keystroke")
	ns.providers.benchspell = nil
	for i, id in ipairs(ns.providerOrder) do if id == "benchspell" then table.remove(ns.providerOrder, i) break end end
	ns:AliasesChanged()
	UI.lastScan = nil
	C_Spell.GetSpellCooldown, _G.GetTime, ns.db.easyMode = save.cd, save.time, save.easy
end
