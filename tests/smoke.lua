debug.sethook(function() error("INSTRUCTION LIMIT HIT\n" .. debug.traceback(), 2) end, "", 20000000)
-- Minimal WoW API stub, enough to load every file and exercise collect/search/activate.
local log = {}
local function note(...) log[#log + 1] = table.concat({ ... }, " ") end

local function Obj(kind)
	local o = { __kind = kind, scripts = {}, text = "" }
	return setmetatable(o, { __index = function(t, k)
		if type(k) == "string" and k:match("^%l") then return nil end -- plain fields, not methods
		if k == "SetText" then return function(self, s) self.text = s or ""; local f = self.scripts.OnTextChanged; if f then f(self) end end end
		if k == "GetText" then return function(self) return self.text end end
		if k == "SetScript" then return function(self, n, f) self.scripts[n] = f end end
		if k == "GetScript" then return function(self, n) return self.scripts[n] end end
		if k == "IsShown" or k == "IsVisible" then return function(self) return self.shown ~= false and self.shown or false end end
		if k == "Show" then return function(self) self.shown = true end end
		if k == "Hide" then return function(self) self.shown = false end end
		if k == "GetChildren" or k == "GetRegions" or k == "EnumerateValidItems" then return function() end end
		if k == "HookScript" then return function(self, n, f) self.scripts[n] = f end end
		if k == "EnableKeyboard" then return function(self, v) self.kb = v end end
		if k == "SetPropagateKeyboardInput" then return function(self, v) self.propagate = v end end
		if k == "ClearFocus" then return function(self) self.focused = false end end
		if k == "SetFocus" then return function(self) self.focused = true end end
		if k == "GetName" then return function(self) return self.__name end end
		if k == "GetCursorPosition" then return function(self) return #(self.text or "") end end
		if k == "GetStringWidth" then return function(self) return #(self.text or "") * 7 end end
		if k == "GetWidth" then return function(self) return self.w or 400 end end
		if k == "SetSize" then return function(self, w, hh) self.w, self.h = w, hh end end
		if k == "SetWidth" then return function(self, w) self.w = w end end
		if k == "SetHeight" then return function(self, hh) self.h = hh end end
		if k == "GetHeight" then return function(self) return self.h or 0 end end
		if k == "SetBackdrop" then return function(self, bd) self.backdrop = bd end end
		if k == "SetAlpha" then return function(self, a) self.alpha = a end end
		if k == "GetAlpha" then return function(self) return self.alpha or 1 end end
		if k == "SetAttribute" then return function(self, a, v) self.attrs = self.attrs or {}; self.attrs[a] = v end end
		if k == "GetAttribute" then return function(self, a) return self.attrs and self.attrs[a] end end
		if k == "SetColorTexture" then return function(self, r, g, b, a) self.color = { r, g, b, a } end end
		if k == "SetMaxLetters" then return function(self, n) self.maxLetters = n end end
		if k == "EnableMouse" then return function(self, v) self.mouse = v end end
		if k == "SetTextColor" then return function(self, r, g, b, a) self.textColor = { r, g, b, a }; return self end end
		if k == "SetBackdropColor" then return function(self, r, g, b, a) self.bgColor = { r, g, b, a } end end
		if k == "SetShown" then return function(self, v) self.shown = v and true or false end end
		if k == "SetScale" then return function(self, v) self.scale = v end end
		if k == "HasFocus" then return function(self) return self.focused == true end end
		if k == "SetChecked" then return function(self, v) self.checked = v end end
		if k == "GetChecked" then return function(self) return self.checked end end
		if k == "SetValue" then return function(self, v) self.value = v end end
		if k == "GetValue" then return function(self) return self.value or 0 end end
		if k == "SetPoint" then return function(self, ...) self.lastPoint = { ... } end end
		if k == "IsForbidden" then return function() return false end end
		if k == "GetObjectType" then return function() return "Frame" end end
		if k == "GetPoint" then return function() return "TOP", nil, "TOP", 0, 0 end end
		if k == "GetOwner" then return function() return nil end end
		if type(k) == "string" and k:match("^Create") then
			return function() return Obj(k) end
		end
		return function(self, ...) return self end
	end })
end

local timers = {}
local timerSeq = 0
local clock = 0
_G.C_Timer = { After = function(d, f) timerSeq = timerSeq + 1; timers[#timers + 1] = { due = clock + (d or 0), n = timerSeq, f = f } end }
-- virtual clock: jump to the earliest due timer and run everything due by then
local function Flush()
	if #timers == 0 then return end
	table.sort(timers, function(a, b) if a.due ~= b.due then return a.due < b.due end return a.n < b.n end)
	clock = timers[1].due
	local run, keep = {}, {}
	for _, x in ipairs(timers) do
		if x.due <= clock then run[#run + 1] = x else keep[#keep + 1] = x end
	end
	timers = keep
	for _, x in ipairs(run) do x.f() end
end

_G.CreateFrame = function(kind, name) local o = Obj(kind); if name then o.__name = name; _G[name] = o end; return o end
_G.UIParent = Obj("UIParent")
_G.GameTooltip = Obj("GameTooltip")
_G.UISpecialFrames = {}
_G.tinsert = table.insert
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and _G.CopyTable(v) or v end return c end
local now = 0
_G.GetTime = function() now = now + 0.001; return now end
_G.IsControlKeyDown = function() return false end
_G.IsShiftKeyDown = function() return false end
_G.IsAltKeyDown = function() return false end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.CreateFont = function(name) local o = Obj("Font"); _G[name] = o; return o end
_G.GetBindingKey = function() return nil end
_G.ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" }, [4] = { hex = "|cffa335ee" } }
_G.print = function(...) note("PRINT", ...) end

_G.C_AddOns = {
	IsAddOnLoaded = function() return true end, LoadAddOn = function() end,
	GetAddOnMetadata = function() return "0.1.0" end,
	GetNumAddOns = function() return 2 end,
	GetAddOnInfo = function(i) return "Addon" .. i, "|cff00ff00Cool Addon " .. i .. "|r", "notes" end,
}
_G.Enum = { BagIndex = { ReagentBag = 5 }, SpellBookSpellBank = { Player = 0 },
	SpellBookItemType = { Spell = 1, FutureSpell = 2, Flyout = 4 } }

-- items
local bags = { [0] = { { itemID = 6948, itemName = "Hearthstone", iconFileID = 134414, stackCount = 1, quality = 1,
	hyperlink = "|cffffffff|Hitem:6948|h[Hearthstone]|h|r" }, { itemID = 2589, itemName = "Linen Cloth", iconFileID = 1, stackCount = 20, quality = 1, hyperlink = "|Hitem:2589|h[Linen Cloth]|h" } } }
_G.C_Container = {
	GetContainerNumSlots = function(b) return bags[b] and #bags[b] or 0 end,
	GetContainerItemInfo = function(b, s) return bags[b] and bags[b][s] end,
}
_G.C_Item = { GetItemInfoInstant = function() return 1, "Miscellaneous", "Junk" end, GetItemInfo = function() return "x", "l", 1 end }
_G.GetInventorySlotInfo = function(n) return 1 end
_G.GetInventoryItemLink = function(_, id) return nil end
_G.GetInventoryItemTexture = function() return 1 end
_G.IsBagOpen = function() return false end
_G.OpenAllBags = function() note("OpenAllBags") end

-- spells
_G.C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 1 end,
	GetSpellBookSkillLineInfo = function() return { name = "General", itemIndexOffset = 0, numSpellBookItems = 2 } end,
	GetSpellBookItemInfo = function(i) return { spellID = 100 + i, itemType = 1, isPassive = i == 2 } end,
}
_G.C_Spell = { GetSpellName = function(id) return ({ [1111] = "Deflection", [1112] = "Cruelty", [1113] = "Piercing Howl" })[id] end, GetSpellTexture = function() return 1 end, GetSpellInfo = function(id) return { name = id == 101 and "Fireball" or "Arcane Intellect", iconID = 1 } end,
	GetSpellLink = function(id) return "|Hspell:" .. id .. "|h[x]|h" end, PickupSpell = function(id) note("PickupSpell", id) end }

-- quests
local quests = {
	{ title = "Elwynn Forest", isHeader = true },
	{ title = "Wolves Across the Border", questID = 33, level = 5 },
}
_G.C_QuestLog = {
	GetNumQuestLogEntries = function() return #quests end, GetInfo = function(i) return quests[i] end,
	GetQuestObjectives = function() return { { text = "Kill 10 Timber Wolves" } } end,
}
_G.GetQuestLogQuestText = function() return "The wolves have been threatening the farmers.", "Slay the wolves." end
_G.C_SuperTrack = { SetSuperTrackedQuestID = function(id) note("SuperTrack", id) end }
_G.WorldMapFrame = Obj("WorldMapFrame"); _G.ToggleWorldMap = function() note("ToggleWorldMap"); WorldMapFrame.shown = true end
_G.QuestMapFrame_OpenToQuestDetails = function(id) note("OpenQuestDetails", id) end
_G.C_QuestLog_SelectStub = true
_G.QuestMapFrame = Obj("QuestMapFrame"); QuestMapFrame.shown = true

-- misc
_G.GetNumMacros = function() return 1, 0 end
_G.GetMacroInfo = function(i) return "Heal Macro", 1, "#showtooltip\n/cast Flash Heal" end
_G.C_CurrencyInfo = { GetCurrencyListSize = function() return 3 end,
	GetCurrencyListInfo = function(i) if i == 3 then return { name = "Honor", iconFileID = 1, quantity = 0 } end return i == 1 and { isHeader = true, name = "Hdr" } or { name = "Valor", iconFileID = 1, quantity = 5, maxQuantity = 100 } end }
_G.C_MountJournal = { GetMountIDs = function() return { 1, 2 } end,
	GetMountInfoByID = function(id) return "Mount" .. id, 900 + id, 1, false, true, 0, id == 1, false, nil, false, id == 1 end,
	SummonByID = function(id) note("Summon", id) end }
_G.GetCategoryList = function() return { 1 } end
_G.GetCategoryNumAchievements = function() return 2 end
_G.GetAchievementInfo = function(_, i) if i == 2 then return 8, "Level 20", 10, false, 1, 1, 1, "Reach level 20.", 0, 1 end return 7, "Level 10", 10, true, 1, 1, 1, "Reach level 10.", 0, 1 end
_G.GetAchievementLink = function() return "|Hachievement:7|h[Level 10]|h" end
_G.ToggleCharacter = function(t) note("ToggleCharacter", t) end

-- chat
local sent
_G.DEFAULT_CHAT_FRAME = { editBox = Obj("EditBox") }
_G.ChatEdit_ChooseBoxForSend = function() return DEFAULT_CHAT_FRAME.editBox end
_G.ChatEdit_ActivateChat = function() end
_G.ChatEdit_SendText = function(eb) note("CHAT", eb:GetText()) end
_G.ChatEdit_DeactivateChat = function() end
_G.ChatFrame_OpenChat = function(t) note("OPENCHAT", t) end
_G.SLASH_FOO1 = "/foo"; _G.SLASH_FOO2 = "/foobar"; _G.SLASH_RELOAD1 = "/reload"; _G.SLASH_RELOAD2 = "/rl"
_G.SlashCmdList = {}

local bound = {}
_G.GetBindingKey = function(action) for k, v in pairs(bound) do if v == action then return k end end end
_G.GetBindingAction = function(key) return bound[key] or "" end
_G.SetBinding = function(key, action) bound[key] = action; return true end
_G.SaveBindings = function() end
_G.GetCurrentBindingSet = function() return 1 end


-- professions / tradeskill stubs
_G.time = os.time
_G.UnitName = function() return "Tester" end
_G.GetRealmName = function() return "Realm" end
local inCombat = false
_G.InCombatLockdown = function() return inCombat end
local bindings = {}
_G.SetOverrideBindingClick = function(_, _, key, btn) bindings[key] = btn end
_G.SetOverrideBinding = function(_, _, key, cmd) bindings[key] = cmd end
_G.SetOverrideBindingSpell = function(_, _, key, spell) bindings[key] = "SPELL:" .. spell end
_G.BINDING_NAME_TOGGLECHARACTER0 = "Character Info"
_G.BINDING_NAME_TOGGLECHARACTER2 = "Reputation"
_G.BINDING_NAME_TOGGLETALENTS = "Talents"
_G.BINDING_NAME_TOGGLEQUESTLOG = "Quest Log"
_G.ClearOverrideBindings = function() for k in pairs(bindings) do bindings[k] = nil end end
_G.ChatEdit_InsertLink = function(l) note("INSERTLINK", l); return false end
_G.C_Item.GetItemNameByID = function(id) return id == 100 and "Flint" or nil end
_G.C_Item.RequestLoadItemDataByID = function() end
_G.GetProfessions = function() return 1, 2 end
_G.GetProfessionInfo = function(i)
	if i == 1 then return "Alchemy", 11, 100, 300, 0, 0, 171 end
	return "Cooking", 12, 50, 75, 0, 0, 185
end
local tsState = { prof = { id = 171, name = "Alchemy" }, linked = false }
local RECIPES = {
	[171] = { ids = { 11, 12, 13 }, info = {
		[11] = { name = "Elixir of Strength", icon = 1, learned = true, categoryID = 1 },
		[12] = { name = "Mana Well", icon = 2, learned = true, categoryID = 1 },
		[13] = { name = "Greater Mana Potion", icon = 3, learned = false, categoryID = 1 } } },
	[185] = { ids = { 21 }, info = { [21] = { name = "Basic Campfire", icon = 4, learned = true, categoryID = 2 } } },
	[356] = { ids = { 31 }, info = { [31] = { name = "Fish Bowl", icon = 5, learned = true, categoryID = 3 } } },
}
_G.C_TradeSkillUI = {
	GetBaseProfessionInfo = function() return { professionID = tsState.prof.id, professionName = tsState.prof.name } end,
	GetAllRecipeIDs = function() return RECIPES[tsState.prof.id] and RECIPES[tsState.prof.id].ids or {} end,
	GetRecipeInfo = function(id) for _, r in pairs(RECIPES) do if r.info[id] then return r.info[id] end end end,
	GetCategoryInfo = function(c) return { name = ({ "Elixirs", "Campfires", "Fishing" })[c] } end,
	GetRecipeSchematic = function(id)
		if id == 11 then return { reagentSlotSchematics = { { quantityRequired = 2, reagents = { { itemID = 100 } } } } } end
		return { reagentSlotSchematics = {} }
	end,
	GetRecipeLink = function(id) return "|Henchant:" .. id .. "|h[x]|h" end,
	OpenRecipe = function(id) note("OpenRecipe", id); return true end,
	OpenTradeSkill = function(line)
		note("OpenTradeSkill", line)
		if line == 171 then tsState.prof = { id = 171, name = "Alchemy" }
		elseif line == 185 then tsState.prof = { id = 185, name = "Cooking" } end
		return true
	end,
	CloseTradeSkill = function() note("CloseTradeSkill") end,
	IsTradeSkillLinked = function() return tsState.linked end,
}
local function FlushAll() for _ = 1, 3000 do if #timers == 0 then break end Flush() end end

-- talents (C_Traits tree, three tabs)
_G.C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end, GetCombatConfigIDForSpecGroup = function() return 500 end }
_G.C_Traits = {
	GetConfigInfo = function(id) return id == 500 and { treeIDs = { 77 } } or nil end,
	GetGroupDisplayInfoByTreeID = function() return { { groupID = 1, displayName = "Arms", orderIndex = 1 }, { groupID = 2, displayName = "Fury", orderIndex = 2 } } end,
	GetTreeNodes = function() return { 1001, 1002, 1003 } end,
	GetNodeInfo = function(_, id)
		if id == 1001 then return { isVisible = true, posX = 1, ranksPurchased = 3, maxRanks = 5, groupIDs = { 1 }, entryIDs = { 11 } } end
		if id == 1002 then return { isVisible = true, posX = 2, ranksPurchased = 0, maxRanks = 3, groupIDs = { 2 }, entryIDs = { 12 } } end
		if id == 1003 then return { isVisible = true, posX = 3, ranksPurchased = 1, maxRanks = 1, groupIDs = { 2 }, activeEntry = { entryID = 13 } } end
	end,
	GetEntryInfo = function(_, e) return { definitionID = e + 100 } end,
	GetDefinitionInfo = function(d) return { spellID = d + 1000 } end,
}

-- load in TOC order
local ns = {}
for line in io.lines("Terminal/Terminal.toc") do
	if line:match("%.lua$") then
		local path = "Terminal/" .. line:gsub("\\", "/")
		local chunk = assert(loadfile(path))
		chunk("Terminal", ns)
	end
end
io.write("[loaded all files]\n")
assert(_G.Terminal == ns, "global namespace exported")

-- fire lifecycle events through the captured handler
local handler
-- Core registers its frame first; find any frame with OnEvent via a fresh CreateFrame capture
-- (Core stored it as eventFrame upvalue) -> re-drive through ns by simulating via SlashCmdList
_G.TerminalDB = nil
-- Simulate ADDON_LOADED manually: Core's frame is not reachable, so re-run the init logic's effect.
-- We can reach it because Obj frames keep scripts: scan registry via debug.
local function findHandler()
	local i = 1
	while true do
		local name, val = debug.getupvalue(ns.WatchEvent, i)
		if not name then break end
		if name == "eventFrame" then return val end
		i = i + 1
	end
end
local ef = findHandler()
assert(ef and ef.scripts.OnEvent, "event frame handler found")
ef.scripts.OnEvent(ef, "ADDON_LOADED", "Terminal")
assert(ns.db and ns.db.freq, "saved variables initialised")
ef.scripts.OnEvent(ef, "PLAYER_LOGIN")

io.write("[events fired]\n")
local fails = 0
local function check(c, m) if not c then fails = fails + 1; io.write("FAIL: " .. m .. "\n") end end

-- providers all collect without error and produce entries
for _, id in ipairs(ns.providerOrder) do
	local entries = ns:GetEntries(ns.providers[id])
	io.write(("provider %-13s %d entries\n"):format(id, #entries))
	check(not ns.providers[id]._warned, id .. " provider threw an error")
	check(#entries > 0 or id == "camp" or id == "gameoptions" or id == "maps" or id == "equipmentset" or id == "reputation" or id == "skills" or id == "consumables" or id == "mats", id .. " produced no entries") -- camp: only objects you can make; options: needs the Settings panel
end

io.write("[providers collected]\n")
local UI = ns.UI
local function top(q) local r = UI:Search(q); return r[1] and r[1].name, r end

check(top("heart") == "Hearthstone", "item search: heart -> Hearthstone")
check(top("timber wolves") == "Wolves Across the Border", "quest found by objective text")
check(top("farmers") == "Wolves Across the Border", "quest found by description text")
check(top("fireb") == "Fireball", "spell search")
check(top("heal mac") == "Heal Macro", "macro search")
check(top("valor") == "Valor", "currency search")
check(top("level 10") == "Level 10", "achievement search (lazy provider, non-empty query)")
check(top("@mount mount1") == "Mount1", "mount via @kind")
check((select(2, top("@mount"))[1] or {}).name == "Mount1", "@kind with empty query lists that kind")
check(#UI:Search("@mount") == 1, "uncollected mounts excluded")
check(top("char") == "Character Info", "panel search")

io.write("[searches done]\n")
-- explicit providers excluded from plain search
local plain = UI:Search("foo")
for _, e in ipairs(plain) do check(e.kind ~= "slash", "slash entries leaked into plain search") end

io.write("[plain search ok]\n")
-- slash mode
UI:Open("/rl now")
local r = UI:WordSearch(ns:GetEntries(ns.providers.slash), "/rl now")
check(r[1] and r[1].name == "/rl" or r[1].name == "/reload", "slash fuzzy match")
check(UI.args == "now", "slash args captured: " .. tostring(UI.args))
r[1].activate(r[1], UI.args)
check(log[#log]:match("^CHAT /re?l"), "slash command executed: " .. tostring(log[#log]))

io.write("[slash ok]\n")
-- command mode
local cmds = UI:WordSearch(UI:CommandEntries(), "hel")
check(cmds[1] and cmds[1].name == "help", "command search: help")
local out = cmds[1].activate(cmds[1], "")
check(type(out) == "table" and #out > 3, "help returns output lines")

do -- typing . lists commands; Enter runs one and its answer goes to chat as system text
	local said = {}
	local chat = _G.DEFAULT_CHAT_FRAME
	_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg, r, g, b) said[#said + 1] = { msg, r, g, b } end }
	_G.ChatTypeInfo = { SYSTEM = { r = 1, g = 1, b = 0 } }
	UI:Open(".hel")
	check(UI.mode == "cmd" and UI.results and true or UI.mode == "cmd", "a leading . is command mode")
	local res = UI:WordSearch(UI:CommandEntries(), "hel")
	check(res[1].name == "help", ". lists commands")
	UI:Open(".help")
	UI:Activate(1)
	check(#said > 3 and said[1][2] == 1 and said[1][3] == 1 and said[1][4] == 0, "command output printed to chat in system colour")
	check(not UI:IsShown(), "terminal closes; output isn't shown as results")
	UI:Open(">help")
	check(UI.mode ~= "cmd", "> is no longer the command prefix")
	UI:Hide()
	_G.DEFAULT_CHAT_FRAME = chat
end
do -- the highlight pulses twice, then fades: gone after 1.6 s
	local H = ns.Highlight
	check(math.abs(H.TOTAL - 1.6) < 0.001, "lasts 1.6 s in all")
	check(H.AlphaAt(0) == 1 and math.abs(H.AlphaAt(0.3) - 0.25) < 0.01 and math.abs(H.AlphaAt(0.6) - 1) < 0.01, "first pulse: bright, dim, bright")
	check(math.abs(H.AlphaAt(0.9) - 0.25) < 0.01 and math.abs(H.AlphaAt(1.2) - 1) < 0.01, "second pulse")
	check(math.abs(H.AlphaAt(1.4) - 0.5) < 0.01 and H.AlphaAt(1.61) == nil, "then it fades out and ends")
	local now = 100
	local realGT = _G.GetTime
	_G.GetTime = function() return now end
	local target = Obj("Frame"); target.shown = true
	local g = H:Show(target, 30)
	check(g and g.shown ~= false, "highlight shown")
	now = 101; g.scripts.OnUpdate(g)
	check(g.shown ~= false, "still showing after 1 s, even when asked for 30 s")
	now = 101.7; g.scripts.OnUpdate(g)
	check(g.shown == false, "gone after the two pulses and the fade")
	_G.GetTime = realGT
end
do -- calculator: the answer is the top result
	local Cc = ns.Calc
	local function ev(t) return (Cc.Evaluate(t)) end
	local cases = {
		{ "3*45", "135" }, { "2+3*4", "14" }, { "(2+3)*4", "20" }, { "2^10", "1024" }, { "=2^10", "1024" }, { "2^20", "1,048,576" },
		{ "12.5%*800", "100" }, { "50% of 800", "400" }, { "3 x 45", "135" }, { "10/4", "2.5" },
		{ "3*45g", "135g" }, { "3 x 45g 20s", "135g 60s" }, { "=123456c", "12g 34s 56c" }, { "1g/4", "25s" },
		{ "2k/8", "250" }, { "sqrt(16)+1", "5" }, { "max(3, 9)*2", "18" }, { "-5+2", "-3" }, { "100000*3", "300,000" },
		{ "90g/30g", "3" }, { "1/3", "0.333333" },
	}
	for _, c in ipairs(cases) do
		check(ev(c[1]) == c[2], "calc " .. c[1] .. " = " .. tostring(ev(c[1])) .. " (want " .. c[2] .. ")")
	end
	for _, t in ipairs({ "45", "heart", "mount1", "char info", "1/0", "3*", "os.exit()", "=", "@quest 3*4", "x" }) do
		check(ev(t) == nil, "not a sum: " .. t .. " -> " .. tostring(ev(t)))
	end
	check(ev("=45") == "45", "a single value with =")
	-- the game's string.format("%d") overflows past 2^31: big answers must not use it
	local realFormat = string.format
	string.format = function(f, ...)
		local v = ...
		if f:find("%%d") and type(v) == "number" and math.abs(v) > 2147483647 then error("integer overflow attempting to store " .. v) end
		return realFormat(f, ...)
	end
	local okBig, big = pcall(ev, "900000*810000000")
	local okMoney, bigMoney = pcall(ev, "=72900000000000000c")
	local okSci, sci = pcall(ev, "10^16+1")
	string.format = realFormat
	check(okBig and big == "729,000,000,000,000", "big answers: " .. tostring(big))
	check(okMoney and bigMoney == "7,290,000,000,000g", "big gold amounts: " .. tostring(bigMoney))
	check(okSci and sci == "1e+16", "huge answers in short form: " .. tostring(sci))
	local r = UI:Search("3*45g")
	check(r[1] and r[1].kind == "calc" and r[1].name == "= 135g" and r[1].detail == "3*45g", "answer is the first result: " .. tostring(r[1] and r[1].name))
	check(UI:Search("heart")[1].kind ~= "calc", "ordinary searches have no calculator row")
	local said = {}
	local chat = _G.DEFAULT_CHAT_FRAME
	_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) said[#said + 1] = m end }
	UI:Open("12.5% * 800"); UI:Activate(1)
	check(said[1] == "12.5% * 800 = 100" and not UI:IsShown(), "Enter prints the sum and answer in chat: " .. tostring(said[1]))
	local opened
	local saveOpen = _G.ChatFrame_OpenChat
	_G.ChatFrame_OpenChat = function(t) opened = t end
	r = UI:Search("3*45")
	r[1].secondary(r[1])
	check(opened == "135", "Shift+Enter puts the answer in the chat box")
	_G.ChatFrame_OpenChat = saveOpen
	_G.DEFAULT_CHAT_FRAME = chat
end
io.write("[command ok]\n")
-- activation paths shouldn't throw
for _, q in ipairs({ "heart", "timber", "fireb", "char", "valor", "mount1" }) do
	local e = UI:Search(q)[1]
	local ok, err = pcall(e.activate, e, "")
	check(ok, "activate " .. q .. ": " .. tostring(err))
	if e.secondary then
		ok, err = pcall(e.secondary, e, "")
		check(ok, "secondary " .. q .. ": " .. tostring(err))
	end
end
Flush(); Flush(); Flush()

io.write("[activations ok]\n")
-- UI renders every mode without error
for _, q in ipairs({ "", ".", ". help", "/", "/foo", "heart", "@quest", "zzzzzz", "@bogus", ".bind" }) do
	local ok, err = pcall(UI.Open, UI, q)
	check(ok, "UI:Open('" .. q .. "'): " .. tostring(err))
end
Flush()
io.write("[ui modes ok]\n")
-- usage ranking: picking Linen Cloth repeatedly should lift it above others on an empty-ish search
io.write("[pre-bump]\n")
for i = 1, 5 do ns:Bump("items:2589") end
io.write("[bumped]\n")
local fr = UI:Search("")
io.write("[searched, n=" .. #fr .. "]\n")
check(UI:Search("")[1].name == "Linen Cloth", "frequent items surface on empty query")

for _, l in ipairs(log) do if l:match("^PRINT") then io.write(l, "\n") end end

-- TOC declares the WoW Forever interface number
local toc = io.open("Terminal/Terminal.toc"):read("*a")
check(toc:match("## Interface:[^\n]*16001"), "TOC lists Interface 16001")

-- default keybind: ` is free on first login
check(bound["`"] == "TERMINAL_TOGGLE", "first login binds `")
-- second login does not rebind or reprint
local before = #log
ef.scripts.OnEvent(ef, "PLAYER_LOGIN")
check(#log == before, "binding only attempted once")
-- fallback: ` already used by something else -> CTRL-`
bound = {}; bound["`"] = "SOMETHINGELSE"
_G.GetBindingKey = function(action) for k, v in pairs(bound) do if v == action then return k end end end
_G.GetBindingAction = function(key) return bound[key] or "" end
_G.SetBinding = function(key, action) bound[key] = action; return true end
ns.db.bindingTerminal = nil
ef.scripts.OnEvent(ef, "PLAYER_LOGIN")
check(bound["`"] == "SOMETHINGELSE", "existing ` binding left alone")
check(bound["CTRL-`"] == "TERMINAL_TOGGLE", "falls back to CTRL-`")
-- after the rename: the key WoWTerm had is taken over
bound = {}; bound["`"] = "WOW" .. "TERM_TOGGLE"
ns.db.bindingTerminal = nil
ef.scripts.OnEvent(ef, "PLAYER_LOGIN")
check(bound["`"] == "TERMINAL_TOGGLE", "the old WoWTerm key binding moves to Terminal")
check(SlashCmdList.TERMINAL and SLASH_TERMINAL1 == "/term" and SLASH_TERMINAL2 == nil, "/term is the slash command")
-- user's own existing toggle binding is respected
bound = { ["F9"] = "TERMINAL_TOGGLE" }
ns.db.bindingDone = nil
ef.scripts.OnEvent(ef, "PLAYER_LOGIN")
check(bound["`"] == nil and bound["CTRL-`"] == nil, "does not add a second binding if one exists")

-- opening via the key must not leave the ` character in the box
UI:Open("`hea")
check(UI.edit:GetText() == "hea", "leading backtick stripped, got: '" .. UI.edit:GetText() .. "'")
UI:Open("~~hea")
check(UI.edit:GetText() == "hea", "leading tildes stripped")
UI:Open("a`b")
check(UI.edit:GetText() == "a`b", "backtick inside a query is kept")
-- pressing ` while the box has focus closes the terminal
UI:Open("")
check(UI:IsShown(), "terminal open")
UI.edit.scripts.OnKeyDown(UI.edit, "`")
check(not UI:IsShown(), "` closes the terminal while focused")


----------------------------------------------------------------------
-- professions + camping
----------------------------------------------------------------------
io.write("[professions tests]\n")
local P = ns.Professions
local function names(list) local t = {} for _, e in ipairs(list) do t[e.name] = e end return t end

-- before any scan: placeholder entry offers to index
ns.providers.recipes._dirty = true
local pre = names(ns:GetEntries(ns.providers.recipes))
check(pre["Index my recipes (scan professions)"], "placeholder shown before recipes are indexed")

-- snapshot the open Alchemy window
P.Snapshot(); FlushAll()
local store = ns.db.recipes["Tester-Realm"]
check(store and store[171] and #store[171].list == 2, "alchemy snapshot keeps only the 2 learned recipes")
check(store[171].list[1].reagents and store[171].list[1].reagents[1][1] == 100, "reagents captured")
check(store[171].list[1].cat == "Elixirs", "category name captured")

local rec = names(ns:GetEntries(ns.providers.recipes))
check(rec["Elixir of Strength"] and not rec["Greater Mana Potion"], "unlearned recipes are never listed")
check(not rec["Mana Well"], "camp objects are not duplicated in the recipes provider")
check(not rec["Index my recipes (scan professions)"], "placeholder gone once indexed")
check(not store[171].list[3], "unlearned recipes aren't stored")

-- search: by name, by reagent, by category
local function has(q, name) for _, e in ipairs(UI:Search(q)) do if e.name == name then return true end end return false end
check(UI:Search("elixir str")[1].name == "Elixir of Strength", "recipe by name")
check(has("flint", "Elixir of Strength"), "recipe found by reagent name")
check(has("@recipe flint", "Elixir of Strength") and #UI:Search("@recipe flint") == 1, "@recipe filter by reagent")
check(has("elixirs", "Elixir of Strength"), "recipe found by category")

-- camping
local camp = names(ns:GetEntries(ns.providers.camp))
check(camp["Mana Well"].detail:find("Known"), "Mana Well known from index: " .. camp["Mana Well"].detail)
check(camp["Mana Well"].color == "|cff40ff40", "known camp objects are green")
check(not camp["Sharpening Wheel"] and not camp["Fermenter"] and not camp["Basic Campfire"], "camp objects you can't make aren't listed")
check(not has("strength", "Sharpening Wheel"), "...nor found by their buff")
check(has("mana regeneration", "Mana Well"), "a known camp object is found by its buff")
check(has("strength", "Elixir of Strength"), "...alongside the matching recipe")
check(UI:Search("@camp mana")[1].name == "Mana Well", "@camp filter")
check(not has("campfire", "Journeyman Campfire"), "fires you can't build aren't listed")
check(has("blessing of wisdom", "Mana Well"), "found by the class buff it overlaps")

-- activation opens the recipe
local n0 = #log
-- a profession window with clickable recipe rows
_G.ProfessionsFrame = Obj("Frame"); ProfessionsFrame.shown = false
local rowMana = Obj("Button"); rowMana.shown = true; rowMana.text = "Mana Well"
rowMana.Click = function() note("ROWCLICK Mana Well") end
local rowElixir = Obj("Button"); rowElixir.shown = true; rowElixir.text = "Elixir of Strength [3]"
rowElixir.Click = function() note("ROWCLICK Elixir") end
ProfessionsFrame.GetChildren = function() return rowMana, rowElixir end
local baseOTS = C_TradeSkillUI.OpenTradeSkill
C_TradeSkillUI.OpenTradeSkill = function(line) local r = baseOTS(line); ProfessionsFrame.shown = true; return r end
local function seen(text, from) for i = (from or 1), #log do if log[i] == text then return true end end return false end
local m0 = #log
camp["Mana Well"].activate(camp["Mana Well"]); FlushAll()
check(seen("OpenTradeSkill 171", m0 + 1) and not seen("OpenRecipe", m0 + 1) and seen("ROWCLICK Mana Well", m0 + 1), "camp activate opens the profession and selects the recipe")
m0 = #log
rec["Elixir of Strength"].activate(rec["Elixir of Strength"]); FlushAll()
check(not seen("OpenTradeSkill 171", m0 + 1), "profession already showing: not reopened")
check(not seen("OpenRecipe", m0 + 1) and seen("ROWCLICK Elixir", m0 + 1), "recipe selected by clicking its row (count after the name is fine)")
-- a recipe further down the list: the list is scrolled to it (no protected OpenRecipe)
ProfessionsFrame.GetChildren = function() return rowMana end -- Elixir's row not built yet
ProfessionsFrame.CraftingPage = { RecipeList = { ScrollBox = { ScrollToElementDataByPredicate = function(_, pred)
	local hit = pred({ GetData = function() return { recipeInfo = { recipeID = 11 } } end })
	note("SCROLLTO " .. tostring(hit))
	if hit then ProfessionsFrame.GetChildren = function() return rowMana, rowElixir end end
end } } }
m0 = #log
rec["Elixir of Strength"].activate(rec["Elixir of Strength"]); FlushAll()
check(seen("SCROLLTO true", m0 + 1) and seen("ROWCLICK Elixir", m0 + 1) and not seen("OpenRecipe", m0 + 1), "off-screen recipe: list scrolled to it, then its row clicked")
ProfessionsFrame.CraftingPage = nil
-- a camp object opens like its recipe: its profession is cast by the game on Enter, then the
-- recipe is selected (Fish Bowl lives in Bait and Tackle, not Fishing)
do
	local hit = ns.Professions.NameIndex()["mana well"]
	hit.pdata.spell = "Alchemy"
	ns.providers.camp._dirty = true
	local ce = names(ns:GetEntries(ns.providers.camp))["Mana Well"]
	check(ce.secure and ce.secure.spell == "Alchemy" and ce.after and ce.recipeID == 12, "camp object armed to cast its profession")
	local mm = #log
	ce.after(ce); FlushAll()
	check(seen("ROWCLICK Mana Well", mm + 1), "after the cast, the camp object's recipe is selected")
	hit.pdata.spell = nil
	ns.Professions.lastSpell = nil
	-- indexed twice (Fish Bowl: under Fishing, and under the Bait and Tackle window): the
	-- copy a spell opens wins, whichever is seen first
	local store = ns.Professions.Store and ns.Professions.Store() or nil
	check(store ~= nil, "profession store reachable")
	if store then
		store["spell:Bait and Tackle"] = { name = "Bait and Tackle", spell = "Bait and Tackle", list = { { id = 99, name = "Mana Well", learned = true } } }
		local h2 = ns.Professions.NameIndex()["mana well"]
		check(h2.pdata.spell == "Bait and Tackle" and h2.r.id == 99, "the spell-opened copy of a recipe wins")
		ns.providers.camp._dirty = true
		local ce2 = names(ns:GetEntries(ns.providers.camp))["Mana Well"]
		check(ce2.secure and ce2.secure.spell == "Bait and Tackle", "camp object casts the window it really lives in")
		store["spell:Bait and Tackle"] = nil
	end
	ns.providers.camp._dirty = true
end
ProfessionsFrame.shown = false
C_TradeSkillUI.OpenTradeSkill = baseOTS
rec["Elixir of Strength"].secondary(rec["Elixir of Strength"])
check(log[#log - 1] == "INSERTLINK |Henchant:11|h[x]|h" or log[#log]:match("^INSERTLINK"), "secondary links the recipe")
check(rec["Elixir of Strength"]:getLink() == "|Henchant:11|h[x]|h", "getLink works")
-- an unscanned object tells you what to do instead of erroring
local okc = camp["Fermenter"] == nil
check(okc, "unscanned camp objects aren't offered")
FlushAll()

-- cooking snapshot flips the campfire to known
tsState.prof = { id = 185, name = "Cooking" }
P.Snapshot(); FlushAll()
camp = names(ns:GetEntries(ns.providers.camp))
check(camp["Basic Campfire"].detail:find("Known"), "Basic Campfire known after cooking snapshot")
check(camp["Journeyman Campfire"] == nil, "fires not learned stay hidden")

-- > camp summary
local cc = UI:WordSearch(UI:CommandEntries(), "camp")
check(cc[1] and cc[1].name == "camp", "camp command found")
local lines = cc[1].activate(cc[1], "")
local joined = table.concat(lines, "\n")
check(joined:find("Alchemy: Mana Well", 1, true), "camp summary lists known alchemy object")
check(joined:find("Cooking: Basic Campfire", 1, true), "camp summary lists known fire")
check(joined:find("Blacksmithing: profession not learned", 1, true), "camp summary notes missing profession")

-- linked / foreign trade skill windows must never be indexed
tsState.prof = { id = 356, name = "Fishing" }; tsState.linked = true
P.Snapshot(); FlushAll()
check(ns.db.recipes["Tester-Realm"][356] == nil, "linked trade skill is not indexed")
tsState.linked = false

-- recipes belong to a character: another character's index isn't searched
ns.db.recipes["Other-Realm"] = { [171] = { name = "Alchemy", list = { { id = 99, name = "Other Chars Potion", learned = true } } } }
ns.providers.recipes._dirty = true
check(not names(ns:GetEntries(ns.providers.recipes))["Other Chars Potion"], "other characters' recipes excluded")

-- profession entries and commands
check(has("alchemy", "Alchemy"), "profession entry searchable")
local pe = names(ns:GetEntries(ns.providers.professions))
check(pe["Alchemy"].detail == "100 / 300", "profession rank shown")
pe["Alchemy"].activate(pe["Alchemy"])
check(log[#log] == "OpenTradeSkill 171", "profession activate opens its window")
local pc = UI:WordSearch(UI:CommandEntries(), "profs")
local pl = pc[1].activate(pc[1], "")
check(table.concat(pl, "\n"):find("Alchemy 100/300 - 2 recipes indexed", 1, true), "profs command: " .. table.concat(pl, " | "))

-- scan walks every profession and finishes
local before = #log
P.Scan(); FlushAll()
local seen = {}
for i = before + 1, #log do if log[i]:match("^OpenTradeSkill") then seen[log[i]] = true end end
check(seen["OpenTradeSkill 171"] and seen["OpenTradeSkill 185"], "scan opened every profession")
local finished = false
for i = before + 1, #log do if log[i]:find("scan finished", 1, true) then finished = true end end
check(finished, "scan reports completion")
check(log[#log - 1] == "CloseTradeSkill" or log[#log]:find("scan finished", 1, true), "scan closes the window")

-- every search mode still renders with the new providers
for _, q in ipairs({ "@camp", "@recipe", "@prof", "camp", "mana", ".camp", ".scan" }) do
	check(pcall(UI.Open, UI, q), "UI:Open('" .. q .. "') with professions loaded")
end
FlushAll()



----------------------------------------------------------------------
-- keyboard capture + one-press opening through the game's keybinding commands
----------------------------------------------------------------------
io.write("[keys + secure tests]\n")
local S = ns.Secure
local F = _G.TerminalFrame
local function logHas(text, from) for i = (from or 1), #log do if log[i] == text then return true end end return false end
_G.CharacterMicroButton = Obj("Button")
_G.CharacterFrame = Obj("CharacterFrame"); CharacterFrame.shown = false
_G.ReputationFrame = Obj("ReputationFrame"); ReputationFrame.shown = false
local function key(k, char) F.scripts.OnKeyDown(F, k); if char then F.scripts.OnChar(F, char) end end
local function typeText(s) for ch in s:gmatch(".") do key(ch == " " and "SPACE" or ch:upper(), ch) end end
local function query() return UI.edit:GetText() end
local function withCtrl(fn) _G.IsControlKeyDown = function() return true end; fn(); _G.IsControlKeyDown = function() return false end end
local mark

do
	UI:Open("")
	check(UI.keys == true, "terminal reads keys itself out of combat")
	check(F.kb == true and F.propagate == false, "frame captures the keyboard, keys don't reach the game")
	check(UI.edit.focused ~= true, "text box isn't focused in key-capture mode")
	F.scripts.OnChar(F, "`")
	check(query() == "", "the opening ` keystroke isn't typed")
	typeText("char info")
	check(query() == "char info", "typed text lands in the query: '" .. query() .. "'")
	key("BACKSPACE"); check(query() == "char inf", "backspace")
	key("LEFT"); key("LEFT"); typeText("x"); check(query() == "char ixnf", "typing at the caret after LEFT: " .. query())
	key("HOME"); typeText(">"); check(query() == ">char ixnf", "HOME moves the caret to the start")
	key("END"); withCtrl(function() key("BACKSPACE") end); check(query() == ">char ", "ctrl+backspace deletes a word: '" .. query() .. "'")
	withCtrl(function() key("U") end); check(query() == "", "ctrl+U clears")
	key("E", "\195\169"); check(query() == "\195\169", "multi-byte character typed")
	key("BACKSPACE"); check(query() == "", "backspace removes a whole UTF-8 character")
	key("LSHIFT"); check(F.propagate == true, "modifier keys pass through to the game")
	key("ESCAPE"); check(not UI:IsShown() and F.propagate == false, "Escape closes (and isn't passed on)")
	UI:Open(""); key("`"); check(not UI:IsShown(), "` closes")
end

do
	-- selecting text in the drawn prompt: shift+arrows, Ctrl+A, word jumps, replace on type
	local function withShift(fn) _G.IsShiftKeyDown = function() return true end; fn(); _G.IsShiftKeyDown = function() return false end end
	local function sel() local lo, hi = UI:SelRange(); return lo and (query():sub(lo + 1, hi)) or nil end
	UI:Open("")
	typeText("hello big world")
	check(sel() == nil and not UI.selText.shown, "no selection to begin with")
	withShift(function() key("LEFT"); key("LEFT"); key("LEFT") end)
	check(sel() == "rld" and UI.selText.shown == true, "shift+left selects, and the band shows: " .. tostring(sel()))
	withShift(function() key("RIGHT") end)
	check(sel() == "ld", "shift+right shrinks it back: " .. tostring(sel()))
	key("LEFT"); check(sel() == nil and UI.cursor == 13, "left collapses the selection to its left end: " .. UI.cursor)
	key("END"); withShift(function() key("HOME") end)
	check(sel() == "hello big world", "shift+home selects to the start")
	key("RIGHT"); check(sel() == nil and UI.cursor == 15, "right collapses to the right end")
	withCtrl(function() key("A") end)
	check(sel() == "hello big world" and UI.keys == true and UI.edit.focused ~= true, "ctrl+A selects all and stays in the drawn prompt")
	typeText("x"); check(query() == "x" and sel() == nil, "typing replaces the selection: " .. query())
	UI:SetQuery("hello big world", 15)
	withCtrl(function() key("LEFT") end); check(UI.cursor == 10, "ctrl+left jumps a word: " .. UI.cursor)
	withCtrl(function() withShift(function() key("LEFT") end) end); check(sel() == "big ", "ctrl+shift+left selects a word: " .. tostring(sel()))
	key("BACKSPACE"); check(query() == "hello world" and sel() == nil and UI.cursor == 6, "backspace deletes the selection: " .. query())
	withCtrl(function() key("RIGHT") end); check(UI.cursor == 11, "ctrl+right jumps to the end of the word")
	UI:SetQuery("hello world", 5)
	withShift(function() key("RIGHT"); key("RIGHT") end)
	key("DELETE"); check(query() == "helloorld", "delete removes the selection: " .. query())
	-- no suggestion while text is selected; the band follows the caret
	UI:SetQuery(".hel", 4)
	withCtrl(function() key("A") end)
	check(UI:Completion() == nil, "no completion while selecting")
	check(UI.selText.shown and UI.anchorX == 0, "the band shows with its start at the left")
	for _ = 1, 30 do UI.motion.scripts.OnUpdate(UI.motion, 0.05) end -- the caret glides to the end, the band with it
	check(UI.selText.w == UI.caretTo and UI.caretTo == 28, "the band follows the caret and spans the selected text: w=" .. tostring(UI.selText.w) .. " caretTo=" .. tostring(UI.caretTo))
	-- clicking in hands over to the real box, with the selection carried across
	local highlighted
	UI.edit.HighlightText = function(_, a, b) highlighted = { a, b } end
	withCtrl(function() key("C") end)
	check(UI.keys == false and highlighted and highlighted[1] == 0 and highlighted[2] == 4, "ctrl+C hands over to the real box with the selection highlighted")
	check(UI.anchor == nil and not UI.selText.shown, "and the drawn selection goes away")
	UI.edit.HighlightText = nil
	UI:Hide()
	-- shift+arrows while held repeat and keep extending
	UI:Open(""); typeText("abcdef")
	_G.IsShiftKeyDown = function() return true end
	key("LEFT"); key("LEFT"); key("LEFT")
	_G.IsShiftKeyDown = function() return false end
	check(sel() == "def", "selection from a series of shift+left presses: " .. tostring(sel()))
	UI:Hide()
end

do
	-- clicking and dragging in the prompt moves Terminal's own cursor (it keeps its style)
	local function sel() local lo, hi = UI:SelRange(); return lo and (query():sub(lo + 1, hi)) or nil end
	local mouseX = 0
	_G.GetCursorPosition = function() return mouseX end
	UI:Open(""); typeText("hello world")
	UI.edit.GetLeft = function() return 100 end
	UI.edit.GetEffectiveScale = function() return 1 end
	local H = UI.hit
	check(H and H.shown == true and H.mouse == true, "a mouse-catching frame covers the prompt while Terminal reads keys")
	local function down(x, shift) mouseX = x; if shift then _G.IsShiftKeyDown = function() return true end end; H.scripts.OnMouseDown(H, "LeftButton"); _G.IsShiftKeyDown = function() return false end end
	local function drag(x) mouseX = x; H.scripts.OnUpdate(H, 0.01) end
	local function up() H.scripts.OnMouseUp(H, "LeftButton") end
	down(100 + 7 * 5 + 2); up()
	check(UI.cursor == 5 and sel() == nil and UI.keys == true and UI.edit.focused ~= true, "a click puts the cursor between characters and stays in the drawn prompt: " .. tostring(UI.cursor))
	check(UI.caret.shown == true, "the cursor is still Terminal's own")
	down(100 + 14); drag(100 + 7 * 4); drag(100 + 7 * 7 + 1); up()
	check(sel() == "llo w" and UI.keys == true, "dragging selects: " .. tostring(sel()))
	down(100 + 7 * 3); up()
	check(sel() == nil and UI.cursor == 3, "a plain click drops the selection")
	down(100 + 7 * 9, true); up()
	check(sel() == "lo wor" and UI.cursor == 9, "shift+click extends it from the cursor: " .. tostring(sel()))
	down(100 + 700); up()
	check(UI.cursor == 11, "a click past the end goes to the end")
	down(100 - 30); up()
	check(UI.cursor == 0, "a click left of the text goes to the start")
	typeText("x"); check(query() == "xhello world", "typing goes in at the clicked spot: " .. query())
	-- while dragging, the cursor stays solid; moving the mouse outside the drag does nothing
	drag(100 + 7 * 2); check(UI.cursor == 1, "no drag without a press")
	-- hands over to the real box only for the clipboard
	withCtrl(function() key("C") end)
	check(UI.keys == false and H.shown == false, "Ctrl+C hands over to the real box and the click frame steps aside so it can be clicked")
	UI:Hide()
	check(H.shown == false, "closing hides the click frame")
	_G.GetCursorPosition = nil
end

do
	-- one Enter: bound to the game's keybinding command, and the press is passed on
	UI:Open("character info")
	mark = #log
	key("ENTER")
	check(S.armed == "TOGGLECHARACTER0" and S.mode == "binding", "Enter is bound to the Character keybinding command")
	check(bindings["ENTER"] == "TOGGLECHARACTER0" and bindings["NUMPADENTER"] == "TOGGLECHARACTER0", "...before the key is passed on")
	check(F.propagate == true, "the same Enter press goes on to the game (one press opens)")
	check(not logHas("ToggleCharacter PaperDollFrame", mark + 1), "window not opened from our own code")
	check(_G.TerminalProxyCharacterMicroButton == nil, "no proxy button needed when the command exists")
	FlushAll()
	check(not UI:IsShown(), "terminal closes once the game has run the binding")
	check(S.armed == nil and next(bindings) == nil, "Enter binding cleared afterwards")

	-- plain entries handle Enter themselves
	UI:Open("hearthstone"); mark = #log; key("ENTER")
	check(F.propagate == false and logHas("OpenAllBags", mark + 1) and not UI:IsShown(), "plain entries activate directly and keep Enter")

	-- reputation: its own tab command, then the after step checks the tab
	UI:Open("reputation"); mark = #log; key("ENTER")
	check(S.armed == "TOGGLECHARACTER2", "reputation uses the reputation tab command")
	FlushAll()
	check(logHas("ToggleCharacter ReputationFrame", mark + 1), "after: makes sure the reputation tab shows")

	-- already open: nothing to press
	CharacterFrame.shown = true
	UI:Open("character info"); key("ENTER")
	check(S.armed == nil and next(bindings) == nil and not UI:IsShown(), "already open: closes and points, no binding")
	CharacterFrame.shown = false

	-- client without the command: the proxy button is the fallback
	_G.BINDING_NAME_TOGGLECHARACTER0 = nil
	UI:Open("character info"); key("ENTER")
	check(S.armed == "CharacterMicroButton" and S.mode == "button" and bindings["ENTER"] == "TerminalProxyCharacterMicroButton", "no command: secure button fallback")
	local proxy = _G.TerminalProxyCharacterMicroButton
	FlushAll()
	check(UI:IsShown() and S.armed == nil, "button mode waits for the click, the give-up timer still frees Enter")
	UI:Open("character info"); key("ENTER")
	proxy.scripts.PostClick(proxy); FlushAll()
	check(not UI:IsShown(), "button mode finishes on the click")
	-- neither command nor button: direct fallback
	local savedBtn = _G.CharacterMicroButton
	_G.CharacterMicroButton = nil
	UI:Open("character info"); mark = #log; key("ENTER")
	check(logHas("ToggleCharacter PaperDollFrame", mark + 1) and S.armed == nil and F.propagate == false, "no command and no button: direct fallback")
	_G.CharacterMicroButton = savedBtn
	_G.BINDING_NAME_TOGGLECHARACTER0 = "Character Info"

	-- mouse: click arms, Enter finishes
	UI:Open("character info")
	UI:Activate(1)
	check(S.armed == "TOGGLECHARACTER0" and UI:IsShown(), "a mouse click arms and waits for Enter")
	key("ENTER"); check(F.propagate == true, "then Enter goes to the game's binding")
	FlushAll(); check(not UI:IsShown(), "and the terminal closes")

	-- typing after arming disarms
	UI:Open("character info"); key("ENTER"); typeText("x")
	check(S.armed == nil and next(bindings) == nil, "typing again disarms")
	FlushAll()
	check(UI:IsShown(), "a stale finish doesn't close the terminal")
	UI:Hide()

	-- equipped items and quests take the same path
	_G.GetInventoryItemLink = function() return "|Hitem:1|h[Fancy Helm]|h" end
	ns.providers.items._dirty = true
	UI:Open("fancy helm"); key("ENTER")
	check(S.armed == "TOGGLECHARACTER0" and F.propagate == true, "equipped item opens the character window in one press")
	FlushAll()
	_G.GetInventoryItemLink = function() return nil end
	ns.providers.items._dirty = true

	QuestMapFrame.shown = false
	C_QuestLog.SetSelectedQuest = function(id) note("SelectQuest", id) end
	_G.ForeverClassicUIQuestLog = Obj("Frame"); ForeverClassicUIQuestLog.shown = false
	local qrow = Obj("Button"); qrow.shown = true; qrow.text = "[2] Wolves Across the Border"
	qrow.Click = function() note("QUESTROW click") end
	ForeverClassicUIQuestLog.GetChildren = function() return qrow end
	UI:Open("wolves across"); mark = #log; key("ENTER")
	check(S.armed == "TOGGLEQUESTLOG" and F.propagate == true, "quest opens the quest log in one press")
	ForeverClassicUIQuestLog.shown = true -- what the game's binding just did
	FlushAll()
	check(logHas("SelectQuest 33", mark + 1) and logHas("QUESTROW click", mark + 1), "after: the quest is selected in the log (party prefix in the row is fine)")
	check(not logHas("OpenQuestDetails 33", mark + 1) and not logHas("ToggleWorldMap", mark + 1), "the protected map isn't touched")
	ForeverClassicUIQuestLog.shown = false
	-- the map's quest list: highlight only, no clicks in the protected map
	local shown
	local origShow = ns.Highlight.Show
	ns.Highlight.Show = function(self, t, d) shown = t; return origShow(self, t, d) end
	local mrow = Obj("Button"); mrow.shown = true; mrow.text = "Wolves Across the Border"
	mrow.Click = function() note("MAPROW click") end
	QuestMapFrame.shown = true
	QuestMapFrame.GetChildren = function() return mrow end
	-- the map's quest panel showing the details: Terminal only points at them, it never
	-- opens them itself (that left the map's focused quest tainted: pins failed in combat)
	QuestMapFrame.DetailsFrame = Obj("Frame"); QuestMapFrame.DetailsFrame.shown = true
	mark = #log
	UI:Open("wolves across"); key("ENTER"); FlushAll()
	check(shown == QuestMapFrame.DetailsFrame and not logHas("OpenQuestDetails 33", mark + 1), "map quest panel: the details are pointed at, never opened from Terminal's code")
	check(not logHas("MAPROW click", mark + 1), "nothing in the map is clicked")
	-- no details showing: the map's list is scrolled to the quest and its row pointed at
	QuestMapFrame.DetailsFrame.shown = false
	local scrolledTo
	_G.QuestScrollFrame = { ScrollBox = { ScrollToElementDataByPredicate = function(_, pred) scrolledTo = pred({ GetData = function() return { questID = 33 } end }) end } }
	shown = nil
	mark = #log
	UI:Open("wolves across"); key("ENTER"); FlushAll()
	check(not logHas("OpenQuestDetails 33", mark + 1) and scrolledTo == true, "no details: the map's list is scrolled to the quest")
	check(shown == mrow and not logHas("MAPROW click", mark + 1), "in the map's quest list the quest is pointed at, never clicked")
	-- this client without a classic log: the quest key opens the map's quest panel, so Enter
	-- runs the game's own macro that opens the quest's details (even with the map open)
	local savedClassic = _G.ForeverClassicUIQuestLog
	_G.ForeverClassicUIQuestLog = nil
	QuestMapFrame.DetailsFrame.shown = true
	WorldMapFrame.shown = true
	mark = #log
	UI:Open("wolves across"); key("ENTER")
	local mp = _G.TerminalMacroProxy
	check(S.armed == "MACRO" and mp and mp.attrs.macrotext == "/run QuestMapFrame_OpenToQuestDetails(33)" and bindings["ENTER"] == "TerminalMacroProxy",
		"map quest log: Enter runs the game's macro for the quest's details: " .. tostring(mp and mp.attrs.macrotext))
	mp.scripts.PostClick(mp, "LeftButton", true); FlushAll()
	check(not UI:IsShown() and not logHas("OpenQuestDetails 33", mark + 1), "and Terminal's own code never calls it")
	check(UI.ClickFor(UI:Search("wolves across")[1], false) == "/run QuestMapFrame_OpenToQuestDetails(33)", "a click runs the same macro")
	_G.ForeverClassicUIQuestLog = savedClassic
	WorldMapFrame.shown = false
	local D = ns.Debug
	_G.QuestScrollFrame = nil
	QuestMapFrame.DetailsFrame = nil
	for i = #D.events, 1, -1 do D.events[i] = nil end
	for i = #D.trace, 1, -1 do D.trace[i] = nil end
	ns.Highlight.Show = origShow
	QuestMapFrame.GetChildren = nil
end

do
	-- a mouse click on a result that opens a game window: the game runs its /click lines
	_G.QuestLogMicroButton = _G.QuestLogMicroButton or Obj("Button")
	QuestMapFrame.shown = false
	_G.ForeverClassicUIQuestLog = Obj("Frame"); ForeverClassicUIQuestLog.shown = false
	local qrow = Obj("Button"); qrow.shown = true; qrow.text = "[2] Wolves Across the Border"
	qrow.Click = function() note("QUESTROW click") end
	ForeverClassicUIQuestLog.GetChildren = function() return qrow end
	local r1 = UI.rows[1]
	r1.GetLeft = function() return 120 end
	r1.GetBottom = function() return 400 end
	r1.GetHeight = function() return 22 end
	r1.GetEffectiveScale = function() return 1 end
	UIParent.GetEffectiveScale = function() return 1 end
	UI:Open("wolves across")
	r1.scripts.OnEnter(r1)
	local c = UI.catcher
	check(c and c.shown and c.attrs.type1 == "macro" and c.attrs.macrotext1 == "/click QuestLogMicroButton",
		"pointer over a quest: the click catcher lies over its row, set to open the quest log")
	local q = UI.Results()[1]
	local wantShift = (q.secondary and not q.secondarySecure) and "" or "macro"
	check(c and c.attrs["shift-type1"] == wantShift, "shift-click: no secure action when the secondary is Terminal's own (it runs after the click)")
	check(c and c.lastPoint and c.lastPoint[4] == 120 and c.lastPoint[5] == 400, "the catcher sits over the row")
	mark = #log
	ForeverClassicUIQuestLog.shown = true -- what the game's click just did
	c.scripts.PostClick(c, "LeftButton")
	FlushAll()
	check(not UI:IsShown() and S.armed == nil and next(bindings) == nil, "clicked: the terminal closes, nothing is left armed for Enter")
	check(logHas("QUESTROW click", mark + 1), "and the quest is pointed at in the log, as after Enter")
	check(not c.shown, "the catcher goes away with the terminal")
	-- shift-click on a quest: its own secondary runs after the click (no window macro)
	ForeverClassicUIQuestLog.shown = false
	UI:Open("wolves across"); r1.scripts.OnEnter(r1)
	local qe = UI.Results()[1]
	local realSecondary = rawget(qe, "secondary")
	qe.secondary = function() note("QSECONDARY") end
	_G.IsShiftKeyDown = function() return true end
	mark = #log
	c.scripts.PostClick(c, "LeftButton")
	_G.IsShiftKeyDown = function() return false end
	qe.secondary = realSecondary
	FlushAll()
	check(logHas("QSECONDARY", mark + 1), "shift-click with Terminal's own secondary: it runs")
	UI:Hide(); FlushAll()
	ForeverClassicUIQuestLog.shown = true
	-- already open: no catcher, the row's own click just points at it
	UI:Open("wolves across"); r1.scripts.OnEnter(r1)
	check(not c.shown, "window already open: the row's own click handles it")
	UI:Hide(); FlushAll()
	ForeverClassicUIQuestLog.shown = false
	-- a result that doesn't open a window: no catcher
	UI:Open(".help"); r1.scripts.OnEnter(r1)
	check(not c.shown, "plain results keep the row's own click")
	UI:Hide(); FlushAll()
	-- in combat nothing is placed
	inCombat = true
	UI:Open("wolves across"); r1.scripts.OnEnter(r1)
	check(not c.shown, "in combat: no catcher")
	inCombat = false
	UI:Hide(); FlushAll()
	-- Reputation and Skills tabs: the micro button, then the tab with that label
	_G.CharacterFrameTab3 = Obj("Button"); CharacterFrameTab3.text = "Reputation"
	_G.CharacterFrameTab4 = Obj("Button"); CharacterFrameTab4.text = "Skills"
	local cf = _G.CharacterFrame; local wasShown = cf and cf.shown
	if cf then cf.shown = false end
	check(S.REP_CLICK() == "/click CharacterMicroButton\n/click CharacterFrameTab3", "reputation click: micro button, then the Reputation tab: " .. tostring(S.REP_CLICK()))
	check(S.ClickMacro({ binding = "TOGGLECHARACTER1", click = S.SKILLS_CLICK }) == "/click CharacterMicroButton\n/click CharacterFrameTab4", "skills click: the Skills tab")
	if cf then cf.shown = true; check(S.REP_CLICK() == "/click CharacterFrameTab3", "window open: just the tab"); cf.shown = wasShown end
	-- this client: the window's mode tabs, unnamed, found by the page they open
	local savedCF = _G.CharacterFrame
	local repTab = Obj("Button"); repTab.frameName = "ReputationFrame"
	local dollTab = Obj("Button"); dollTab.frameName = "PaperDollFrame"
	_G.CharacterFrame = Obj("Frame"); CharacterFrame.shown = false
	CharacterFrame.ModeTabs = { Tabs = { dollTab, repTab } }
	local m = S.REP_CLICK()
	local clicker = _G.TerminalClickReputationFrame
	check(m == "/click CharacterMicroButton\n/click TerminalClickReputationFrame LeftButton false" and clicker and clicker.attrs.type == "click"
		and clicker.attrs.clickbutton == repTab, "mode tabs: a secure button clicks the unnamed Reputation tab: " .. tostring(m))
	repTab.__name = "CharacterFrameModeTab2"; _G.CharacterFrameModeTab2 = repTab
	check(S.REP_CLICK() == "/click CharacterMicroButton\n/click CharacterFrameModeTab2", "a named mode tab is clicked by its name")
	_G.CharacterFrameModeTab2 = nil
	-- this client: the tab is a plain frame (no Click), so the macro runs what the key runs
	local frameTab = { frameName = "ReputationFrame" }
	CharacterFrame.ModeTabs = { Tabs = { dollTab, frameTab } }
	check(S.REP_CLICK() == '/run ToggleCharacter("ReputationFrame", true)', "an unclickable tab: the macro runs ToggleCharacter: " .. tostring(S.REP_CLICK()))
	_G.CharacterFrame = savedCF
	check(S.ClickMacro({ spell = "Smelting" }) == "/cast Smelting", "a profession spell is cast")
	check(S.ClickMacro({ binding = "TOGGLEQUESTLOG" }) == nil, "a command with no button: no click route (Enter is armed instead)")
	_G.CharacterFrameTab3, _G.CharacterFrameTab4 = nil, nil
	UIParent.GetEffectiveScale = nil
	ForeverClassicUIQuestLog.GetChildren = nil
end

do
	-- combat: propagation is off-limits, so the text box takes over
	UI:Open("character info")
	inCombat = true
	F.propagate = "untouched"
	key("A")
	check(F.propagate == "untouched" and UI.keys == false and UI.edit.focused == true, "a key in combat switches to the text box without touching propagation")
	S.OnCombat()
	check(F.kb == false, "keyboard capture off in combat")
	mark = #log
	UI.edit.scripts.OnEnterPressed(UI.edit)
	check(not logHas("ToggleCharacter PaperDollFrame", mark + 1), "in combat: Enter on a window does nothing (no direct opener)")
	UI:Open("x")
	check(UI.keys == false, "opening in combat uses the text box")
	inCombat = false
	S.OnRegen()
	check(UI.keys == true, "back to key capture after combat")
	UI:Hide()
end

do
	-- a client that never sends OnChar to frames
	UI.charChecked = false
	UI:Open("")
	key("Q")
	FlushAll()
	check(UI.noChar == true and UI.keys == false and UI.edit.focused == true, "no OnChar: falls back to the text box")
	check(query() == "q", "the key that revealed it is still typed: " .. query())
	UI:Open("character info")
	check(UI.keys == false, "stays in text-box mode")
	UI.edit.scripts.OnEnterPressed(UI.edit)
	check(S.armed == "TOGGLECHARACTER0" and UI.legacyArm and F.kb == true, "first Enter arms and listens for the next")
	F.scripts.OnKeyDown(F, "ENTER")
	check(F.propagate == true, "second Enter goes to the game's binding")
	FlushAll()
	check(not UI:IsShown(), "and the terminal closes")
	UI:Open("character info")
	UI.edit.scripts.OnEnterPressed(UI.edit)
	F.scripts.OnKeyDown(F, "A")
	check(S.armed == nil and UI.edit.focused == true and F.kb == false, "typing instead disarms and refocuses the box")
	UI.noChar = false; UI.charChecked = true
	UI:Hide()
end

----------------------------------------------------------------------
-- secondary professions
----------------------------------------------------------------------
io.write("[secondary professions]\n")
do
	-- Forever: GetProfessions() = prof1, prof2, first aid, fishing, cooking (with gaps)
	_G.GetProfessions = function() return 1, nil, 3, nil, 2 end
	_G.GetProfessionInfo = function(i)
		if i == 1 then return "Alchemy", 11, 100, 300, 0, 0, 171 end
		if i == 2 then return "Cooking", 12, 50, 75, 0, 0, 185 end
		if i == 3 then return "First Aid", 13, 40, 75, 0, 0, 129 end
		if i == 4 then return "Fishing", 14, 30, 75, 0, 0, 356 end
		if i == 5 then return "Herbalism", 15, 10, 75, 0, 0, 182 end
	end
	RECIPES[129] = { ids = { 41, 42 }, info = {
		[41] = { name = "Linen Bandage", icon = 6, learned = true, categoryID = 4 },
		[42] = { name = "First Aid Kit", icon = 7, learned = true, categoryID = 4 } } }
	-- the window's own info comes back blank; the recipes' skill line still identifies it
	tsState.prof = { id = 129, name = "" }
	C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionID = 0, professionName = "" } end
	C_TradeSkillUI.GetTradeSkillLineForRecipe = function(id) if id == 41 or id == 42 then return 129, "First Aid", 129 end end
	P.Snapshot(); FlushAll()
	local st = ns.db.recipes["Tester-Realm"]
	check(st[129] and st[129].name == "First Aid" and #st[129].list == 2 and st[129].fromList, "first aid indexed despite blank profession info")
	check(has("linen bandage", "Linen Bandage"), "first aid recipe searchable")
	check(names(ns:GetEntries(ns.providers.camp))["First Aid Kit"].detail:find("Known"), "first aid camp object known")

	-- nothing identifies the window at all: a scan knows what it opened
	C_TradeSkillUI.GetTradeSkillLineForRecipe = nil
	_G.GetProfessions = function() return 1, 5, 3, 4, 2 end
	C_TradeSkillUI.OpenTradeSkill = function(line) note("OpenTradeSkill", line); tsState.prof = { id = line, name = "" }; return true end
	st["oldkey"] = { name = "Cooking", list = {} } -- an older copy stored under another key
	st[999] = { name = "Mystery", list = { { id = 77, name = "Odd Thing", learned = true } } }
	mark = #log
	P.Scan(); FlushAll()
	check(st[356] and st[356].name == "Fishing", "fishing indexed by the scan with no profession info")
	check(st[185] and st[185].name == "Cooking" and st.oldkey == nil, "cooking indexed once; the older copy is dropped")
	check(names(ns:GetEntries(ns.providers.camp))["Fish Bowl"].detail:find("Known"), "fishing camp object known")
	local readMiss = false
	for i = mark + 1, #log do if log[i]:find("nothing to craft yet in: Herbalism", 1, true) then readMiss = true end end
	check(readMiss and st[182] and #st[182].list == 0, "a profession with nothing to craft counts as read, and is named once")
	ns.providers.recipes._dirty = true
	check(has("odd thing", "Odd Thing"), "indexed recipes show even if the profession list doesn't name them")
	local pl = UI:WordSearch(UI:CommandEntries(), "profs")
	local plines = table.concat(pl[1].activate(pl[1], ""), "\n")
	check(plines:find("First Aid 40/75 - 2 recipes indexed", 1, true) and plines:find("Fishing 30/75 - 1 recipes indexed", 1, true), "profs lists secondary professions: " .. plines)

	-- unlearning: only entries tied to the profession list are pruned
	_G.GetProfessions = function() return 1, nil, 3, nil, 2 end -- fishing gone
	P.Prune()
	check(st[356] == nil, "a dropped profession's index is pruned")
	check(st[999] ~= nil and st[129] ~= nil, "unrelated and still-known indexes are kept")
end

----------------------------------------------------------------------
-- theme
----------------------------------------------------------------------
io.write("[theme tests]\n")
do
	local Th = ns.Theme
	local function cmd(line) local c = UI:WordSearch(UI:CommandEntries(), line); return c[1].activate(c[1], UI.args) end
	UI:Open("")
	check(UI.promptFS:GetText() == "|cff6db8ff>|r", "prompt is > by default: " .. tostring(UI.promptFS:GetText()))
	cmd("theme dracula")
	check(Th.Get().preset == "dracula" and Th.Get().bg == "282a36", "> theme dracula applies the preset")
	local bgc = F.bgColor
	check(bgc and math.abs(bgc[1] - 0x28 / 255) < 0.01 and math.abs(bgc[4] - 0.97) < 0.01, "background colour applied live")
	cmd("set accent #FF79C6")
	check(Th.Get().accent == "ff79c6" and Th.Get().preset == "custom", "> set accent (# and caps) works and marks custom")
	local bad = cmd("set accent zzz")
	check(bad[1]:find("Can't set accent", 1, true), "bad colour rejected: " .. bad[1])
	cmd("set rows 99"); check(Th.Get().rows == 20, "rows clamped to 20")
	cmd("set rows 14")
	local fs = Th.Get().fontSize
	local shown = math.min(14, #UI.Results())
	check(F.h == math.max(50, fs + 36) + shown * math.max(22, fs + 12) + UI.footerH, "frame height: header, one row per result (up to the rows setting), footer: " .. tostring(F.h))
	-- footer: wide enough, one line; narrow, the hints wrap onto a second line instead of
	-- running into the result count
	local Th2 = ns.Theme
	local function widthCheck(w)
		Th2.Set("width", w)
		return UI.footerH, UI.hintCount, UI.hints and UI.hints:GetText() or ""
	end
	local saveW = Th2.Get().width
	local hW, nW, tW = widthCheck(1100)
	local hN, nN, tN = widthCheck(420)
	check(hW == hN, "the footer stays one line at any width: " .. tostring(hW) .. " / " .. tostring(hN))
	check(nW >= 4 and nN < nW and nN >= 1, "narrow: the less useful hints are left out (" .. tostring(nW) .. " -> " .. tostring(nN) .. ")")
	check(tN:find("Enter", 1, true) and not tN:find("calc", 1, true), "Enter stays, calc goes first: " .. tN)
	check(not tW:find("|", 1, true) or tW:find("|cff", 1, true), "no pipe separators, keys coloured")
	Th2.Set("width", saveW)
	cmd("set width 800"); check(F.w == 800, "width applied")
	cmd("set scale 1.234"); check(Th.Get().scale == 1.25 and F.scale == 1.25, "scale rounded to step and applied")
	cmd("set match 0f0"); check(Th.Get().match == "00ff00" and ns.Fuzzy.matchColor == "|cff00ff00", "3-digit hex expands; matcher uses the colour")
	cmd("set promptText $"); check(UI.promptFS:GetText() == "|cff" .. Th.Get().prompt .. "$|r", "prompt text customisable")
	local long = cmd("set promptText abcdef"); check(long[1]:find("at most", 1, true), "prompt length limited")
	cmd("set promptText >")
	cmd("set hints off"); check(Th.Get().hints == false, "hints off")
	cmd("set font ari"); check(Th.Get().font == "arial", "font by prefix")
	local listing = cmd("set"); check(#listing == #Th.ORDER + 1, "> set lists every setting")
	check(table.concat(cmd("theme"), "\n"):find("Dracula", 1, true), "> theme lists presets")
	check(not Th.PRESETS.paper and not Th.PRESETS.parchment, "no Paper or Parchment theme")
	cmd("theme forever")
	cmd("set bg f4f0e6"); cmd("set text 141414"); cmd("set dim 4d4d4d")
	check(Th.IsLight(), "a light background counts as a light theme")
	-- light themes: game colours made for dark backgrounds are darkened to stay readable
	local fixed = Th.FixColors("|cff1eff00Green Item|r |cff7fd6a8Map|r |cffffd200hint|r")
	check(not fixed:find("1eff00", 1, true) and not fixed:find("7fd6a8", 1, true) and not fixed:find("ffd200", 1, true), "light theme darkens bright colours: " .. fixed)
	local function contrast(hex)
		local function lin(c) return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
		local function lum(h) local r, g, b = Th.RGB(h) return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) end
		return (lum(Th.Get().bg) + 0.05) / (lum(hex) + 0.05)
	end
	check(contrast(Th.Readable("1eff00")) >= 4.5 and contrast(Th.Readable("ffd200")) >= 4.5, "darkened colours reach readable contrast")
	local saved = ns.db.theme
	ns.db.theme = { preset = "paper", bg = "f4f0e6", v = 3, rows = 7 }
	check(Th.Get().preset == "forever" and Th.Get().bg == "47331f" and Th.Get().rows == 7, "a saved Paper theme falls back to Forever")
	ns.db.theme = saved
	cmd("theme forever")
	local function ratio(a, b)
		local function lin(c) return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
		local function lum(h) local r, g, b2 = Th.RGB(h) return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b2) end
		local x, y = lum(a), lum(b)
		if x < y then x, y = y, x end
		return (x + 0.05) / (y + 0.05)
	end
	for _, id in ipairs({ "forever", "foreverblue" }) do
		local P = Th.PRESETS[id]
		check(P.bg == "47331f" and not Th.IsLight(), id .. " uses the scroll brown")
		check(ratio(P.text, P.bg) >= 7 and ratio(P.dim, P.bg) >= 4.5 and ratio(P.prompt, P.bg) >= 4.5, id .. " text, details and prompt readable on brown")
	end
	ns.db.theme = { preset = "forever", bg = "000000", rows = 9, v = 2 }
	check(Th.Get().bg == "47331f" and Th.Get().rows == 9 and Th.Get().v == 3, "black Forever from 0.7.0 moves to the brown")
	ns.db.theme = { preset = "forever", bg = "112233", v = 2 }
	check(Th.Get().bg == "112233", "a tuned background is kept")
	ns.db.theme = nil
	cmd("theme forever")
	check(Th.FixColors("|cff1eff00x|r") == "|cff1eff00x|r", "dark themes leave game colours alone")
	UI:Open(""); UI:Hide()
	check(_G.TerminalFrame.backdrop and _G.TerminalFrame.backdrop.edgeFile:find("Tooltip"), "Forever uses the classic frame")
	-- an old saved default (midnight, from before Forever) moves to the new default; a picked theme stays
	local saveTheme = ns.db.theme
	ns.db.theme = { preset = "midnight", bg = "0d0f14", rows = 12 }
	check(Th.Get().preset == "forever" and Th.Get().frame == "classic" and Th.Get().rows == 12, "old default theme upgraded, layout kept")
	ns.db.theme = { preset = "dracula", bg = "282a36" }
	check(Th.Get().preset == "dracula" and Th.Get().frame == "flat", "a theme the player picked is kept")
	ns.db.theme = saveTheme
	-- the prompt has its own, slightly darker background
	for id, P in pairs(Th.PRESETS) do
		local function lum(h) local r, g, b2 = Th.RGB(h) return r + g + b2 end
		check(P.promptBg and P.promptBg ~= P.bg and lum(P.promptBg) < lum(P.bg), id .. ": prompt background darker than results: " .. tostring(P.promptBg))
	end
	-- the database-site themes: listed, readable (results and prompt), and applied by name
	local themeList = table.concat(cmd("theme"), "\n")
	for _, id in ipairs({ "wowhead", "allakhazam", "thottbot", "mmochampion" }) do
		local P = Th.PRESETS[id]
		check(P and themeList:find(P.label, 1, true), id .. " is listed by .theme")
		check(ratio(P.text, P.bg) >= 7 and ratio(P.dim, P.bg) >= 4.5 and ratio(P.prompt, P.bg) >= 4.5 and ratio(P.match, P.bg) >= 4.5,
			id .. " text, details, prompt and matches readable")
		check(ratio(P.text, P.promptBg) >= 4.5 and ratio(P.prompt, P.promptBg) >= 4.5, id .. " typing readable on the prompt background")
	end
	cmd("theme mmochampion"); check(Th.Get().preset == "mmochampion" and Th.Get().bg == "050805" and not Th.IsLight(), ".theme mmochampion: the black and green one")
	cmd("theme thottbot"); check(Th.Get().preset == "thottbot" and Th.IsLight(), ".theme thottbot: the white one")
	cmd("theme allakhazam"); check(Th.IsLight() and Th.Get().promptBg == "e0d2ab", "Allakhazam is a light theme with its own prompt background")
	cmd("theme forever")
	UI:Open(""); UI:Hide()
	local pt = UI.promptBg
	local er, eg, eb = Th.RGB(Th.Get().promptBg)
	check(pt and pt.color and math.abs(pt.color[1] - er) < 0.01 and math.abs(pt.color[3] - eb) < 0.01, "prompt area painted with promptBg")
	cmd("set promptBg 101010"); check(Th.Get().promptBg == "101010" and Th.Get().preset == "custom", ".set promptBg")
	cmd("set bg 404040"); check(Th.Get().promptBg == "101010", "a hand-set prompt background stays when bg changes")
	cmd("theme forever"); cmd("set bg 505050"); check(Th.Get().promptBg == Th.Darken("505050", 0.7), "an untouched prompt background follows bg")
	local saved2 = ns.db.theme
	ns.db.theme = { preset = "dracula", bg = "282a36", v = 3 }
	check(Th.Get().promptBg == Th.Darken("282a36", 0.7), "older saved themes get a darker prompt background")
	ns.db.theme = saved2
	cmd("theme forever")
	cmd("set frame flat"); check(Th.Get().frame == "flat" and _G.TerminalFrame.backdrop.edgeSize == 1, "> set frame flat")
	cmd("set frame classic"); check(Th.Get().frame == "classic", "> set frame classic")
	cmd("theme reset")
	check(Th.Get().preset == "forever" and Th.Get().frame == "classic" and Th.Get().rows == 10 and Th.Get().promptText == ">", "> theme reset restores defaults")

	local O = ns.Options
	check(O and O.panel, "options panel built")
	O.Refresh()
	local sl = O.widgets.rows
	sl.scripts.OnValueChanged(sl, 12)
	check(Th.Get().rows == 12, "rows slider changes the setting")
	O.syncing = true; sl.scripts.OnValueChanged(sl, 5); O.syncing = false
	check(Th.Get().rows == 12, "slider updates during sync don't write back")
	local menu, list = O.widgets.themeMenu, O.widgets.themeList
	check(not list:IsShown(), "theme list starts closed")
	menu.scripts.OnClick(menu)
	check(list:IsShown(), "the theme dropdown opens")
	O.themeItems.matrix.scripts.OnClick(O.themeItems.matrix)
	check(Th.Get().preset == "matrix" and not list:IsShown(), "picking from the dropdown applies the theme and closes it")
	check(menu:GetText() == "Matrix", "dropdown shows the current theme: " .. tostring(menu:GetText()))
	check(O.themeItems.matrix.text:GetText():find("Matrix", 1, true) and O.themeItems.matrix.text:GetText():find("|cffffd100", 1, true), "current theme marked in the list")
	O.widgets.font.scripts.OnClick(O.widgets.font)
	check(Th.Get().font == "arial", "font button cycles fonts")
	local oc = cmd("options")
	check(type(oc) == "table" and oc[1]:find("isn't available", 1, true), "> options explains when there is no settings panel")
	check(has("dracula", "Theme: Dracula"), "themes are searchable")
	local te
	for _, e in ipairs(UI:Search("dracula")) do if e.name == "Theme: Dracula" then te = e end end
	te.activate(te); FlushAll()
	check(Th.Get().preset == "dracula", "picking a theme from search applies it")
	cmd("theme reset")
end


----------------------------------------------------------------------
-- only owned / learned things; recipe id sources; index notice; profdebug
----------------------------------------------------------------------
io.write("[owned-only + indexing tests]\n")
do
	local function cmd(line) local c = UI:WordSearch(UI:CommandEntries(), line); return c[1].activate(c[1], UI.args) end
	local function logFind(text) for i = 1, #log do if log[i]:find(text, 1, true) then return true end end return false end
	check(top("level 10") == "Level 10" and not has("level 20", "Level 20"), "only earned achievements are listed")
	check(has("valor", "Valor") and not has("honor", "Honor"), "only currencies you hold are listed")
	check(logFind("indexed First Aid: 2 known recipes."), "a newly indexed profession is announced in chat")
	check(not logFind("indexed Fishing"), "a scan doesn't announce each profession")

	-- Forever: GetAllRecipeIDs can be empty while GetFilteredRecipeIDs answers; learned may be nil
	RECIPES[129].ids = { 41, 42, 43, 44, 45 }
	RECIPES[129].info[43] = { name = "Heavy Linen Bandage", icon = 8, categoryID = 4, learned = true }
	RECIPES[129].info[44] = { name = "Runecloth Bandage", icon = 9, categoryID = 4, learned = false }
	RECIPES[129].info[45] = { name = "Silk Bandage", icon = 10, categoryID = 4 } -- learned missing: counts as known
	C_TradeSkillUI.GetAllRecipeIDs = function() return {} end
	C_TradeSkillUI.GetFilteredRecipeIDs = function() return RECIPES[tsState.prof.id] and RECIPES[tsState.prof.id].ids or {} end
	C_TradeSkillUI.GetTradeSkillLineForRecipe = function(id) if id >= 41 and id <= 45 then return 129, "First Aid", 129 end end
	tsState.prof = { id = 129, name = "" }
	P.Snapshot(); FlushAll()
	local st = ns.db.recipes["Tester-Realm"]
	check(st[129] and #st[129].list == 4, "recipes read from GetFilteredRecipeIDs when GetAllRecipeIDs is empty")
	check(has("heavy linen", "Heavy Linen Bandage"), "Heavy Linen Bandage is found")
	check(has("silk band", "Silk Bandage"), "recipes without a learned flag count as known")
	check(not has("runecloth", "Runecloth Bandage"), "explicitly unlearned recipes stay out")
	check(logFind("indexed First Aid: 4 known recipes."), "re-index with more recipes is announced")

	local dbg = table.concat(cmd("profdebug"), "\n")
	check(dbg:find("GetAllRecipeIDs: 0   GetFilteredRecipeIDs: 5", 1, true) and dbg:find("First recipe: Linen Bandage", 1, true) and dbg:find("First Aid=4", 1, true),
		"profdebug reports what the window offers: " .. dbg)
end

----------------------------------------------------------------------
-- talents
----------------------------------------------------------------------
io.write("[talent tests]\n")
do
	local tl = names(ns:GetEntries(ns.providers.talents))
	check(tl["Deflection"] and tl["Piercing Howl"], "talents with points are listed")
	check(tl["Cruelty"] and tl["Cruelty"].taken == false, "talents without points are listed too")
	check(tl["Deflection"].detail == "Arms  |cff40ff40Taken|r 3/5", "taken, tree and rank shown: " .. tostring(tl["Deflection"].detail))
	check(tl["Cruelty"].detail == "Fury  |cff8a8a8aNot taken|r 0/3" and tl["Cruelty"].color == "|cffa0a0a0", "not-taken talents are marked and greyed")
	check(has("deflect", "Deflection") and has("@talent fury", "Piercing Howl"), "talents searchable by name and by tree")

	local shownTarget
	local origShow = ns.Highlight.Show
	ns.Highlight.Show = function(self, target, d) shownTarget = target; return origShow(self, target, d) end

	_G.TalentMicroButton = Obj("Button")
	_G.ClassicUIForeverTalents = Obj("Frame"); ClassicUIForeverTalents.shown = false
	UI:Open("piercing howl"); key("ENTER")
	check(S.armed == "TOGGLETALENTS" and F.propagate == true, "a talent opens the talent window in one press")
	local nodeBtn = Obj("Button"); nodeBtn.shown = true; nodeBtn.talent = { nodeID = 1003 }
	ClassicUIForeverTalents.shown = true
	ClassicUIForeverTalents.GetChildren = function() return nodeBtn end
	FlushAll()
	check(shownTarget == nodeBtn, "the talent's node is highlighted in the tree")

	-- window already open, Blizzard-style button (GetNodeID)
	shownTarget = nil
	local rb = Obj("Button"); rb.shown = true; rb.GetNodeID = function() return 1001 end
	ClassicUIForeverTalents.GetChildren = function() return nodeBtn, rb end
	UI:Open("deflection"); key("ENTER"); FlushAll()
	check(S.armed == nil and shownTarget == rb, "already open: no click, node highlighted (GetNodeID buttons too)")

	-- the Talents panel uses the same secure path
	ClassicUIForeverTalents.shown = false
	UI:Open("talents"); key("ENTER")
	check(S.armed == "TOGGLETALENTS", "the Talents panel opens through the Talents keybinding")
	UI:Hide()
	ns.Highlight.Show = origShow
end

----------------------------------------------------------------------
-- tooltip + options preview
----------------------------------------------------------------------
io.write("[tooltip + preview tests]\n")
do
	local Th = ns.Theme
	local function cmd(line) local c = UI:WordSearch(UI:CommandEntries(), line); return c[1].activate(c[1], UI.args) end
	_G.ShoppingTooltip1 = Obj("GameTooltip")
	ShoppingTooltip1.GetOwner = function() return _G.TerminalTooltip end
	ShoppingTooltip1.shown = true
	UI:Open("hearthstone")
	local Tt = _G.TerminalTooltip
	check(Tt and Tt.shown == true, "item tooltip shown in the terminal's own tooltip")
	check(Tt.supportsItemComparison == false, "comparison tooltips are switched off")
	check(ShoppingTooltip1.shown == false, "any comparison tooltip it owns is hidden")
	local bgc = Tt.bgColor
	local r0 = Th.RGB(Th.Get().bg)
	check(bgc and math.abs(bgc[1] - r0) < 0.01, "tooltip uses the terminal's background")
	check(Tt.lastPoint and Tt.lastPoint[1] == "TOPLEFT", "tooltip to the right of the terminal by default")
	-- terminal near the right edge: tooltip goes left
	F.GetEffectiveScale = function() return 1 end
	F.GetRight = function() return 1900 end
	UIParent.GetRight = function() return 1920 end
	UIParent.GetEffectiveScale = function() return 1 end
	UI:Open("hearthstone")
	check(Tt.lastPoint and Tt.lastPoint[1] == "TOPRIGHT", "no room on the right: tooltip on the left")
	F.GetEffectiveScale, F.GetRight, UIParent.GetRight, UIParent.GetEffectiveScale = nil, nil, nil, nil
	UI:Hide()
	check(Tt.shown == false, "tooltip hides with the terminal")

	local O = ns.Options
	O.Refresh()
	local pv = O.preview
	check(pv.prompt:GetText() == "|cff6db8ff>|r", "example shows the prompt")
	check(pv.label:GetText():find("|cffffffffH", 1, true), "example colours matched letters")
	check(pv.w == 196 and pv.h == 52, "example is small enough to fit the panel")
	cmd("theme dracula")
	check(math.abs(pv.bgColor[1] - 0x28 / 255) < 0.01, "preview follows the theme live")
	check(pv.prompt:GetText() == "|cff50fa7b>|r" and pv.label:GetText():find("|cffff79c6H", 1, true), "example prompt and match colours update")
	check(O.widgets.prompt_1 == nil and O.PROMPT_PICKS == nil, "no quick-pick buttons for the prompt, only the text box")
	check(O.widgets.promptText.maxLetters == 3, "the prompt box takes at most 3 characters")
	check(Th.DEFAULTS.promptText == ">", "the prompt is > by default")
	local box = O.widgets.promptText
	box:SetText("@")
	box.scripts.OnEnterPressed(box)
	check(Th.Get().promptText == "@", "any character typed into the prompt box works")
	check(Th.Set("promptText", "abc") and not Th.Set("promptText", "abcd"), "three characters fit, four don't")
	Th.Set("promptText", ">")
	-- cursor style is a dropdown
	local CM, CL = O.widgets.cursor, O.widgets.cursorList
	check(CL.shown ~= true and CM:GetText() == "Blinking line", "the cursor dropdown shows the current style: " .. tostring(CM:GetText()))
	CM.scripts.OnClick(CM)
	check(CL.shown == true, "clicking it opens the list")
	local TM = O.widgets.themeMenu
	TM.scripts.OnClick(TM)
	check(O.widgets.themeList.shown == true and CL.shown == false, "opening another dropdown closes this one")
	TM.scripts.OnClick(TM)
	local n = 0
	for _ in pairs(O.cursorItems) do n = n + 1 end
	check(n == 4 and O.cursorItems["solid-box"].text.text == "Solid box", "four styles listed")
	CM.scripts.OnClick(CM)
	local it = O.cursorItems["solid-box"]
	it.scripts.OnClick(it)
	check(Th.Get().cursor == "solid-box" and CL.shown == false and CM:GetText() == "Solid box", "picking a style applies it, closes the list and updates the button")
	check(O.cursorItems["solid-box"].text.text:find("|cffffd100", 1, true) and not O.cursorItems["solid-line"].text.text:find("|cff", 1, true), "the current style is marked")
	-- blink speed slider
	local bs = O.widgets.blinkRate
	check(bs and bs.value == 0.8 and bs.valueText.text == "0.8/s", "blink speed slider shows 0.8/s by default")
	bs.scripts.OnValueChanged(bs, 2)
	check(Th.Get().blinkRate == 2, "the slider sets the blink speed")
	Th.Set("cursor", "blinking-line"); Th.Set("blinkRate", 0.8)
	cmd("theme reset")
end


----------------------------------------------------------------------
-- stray tooltip, unlearned purge, login auto-index
----------------------------------------------------------------------
io.write("[purge + tooltip + autoscan tests]\n")
do
	local Th = ns.Theme
	-- changing the theme while the terminal is closed must not pop its tooltip up
	UI:Open("hearthstone")
	UI:Hide()
	Th.ApplyPreset("matrix")
	check(_G.TerminalTooltip.shown == false, "no tooltip while the terminal is closed, even when the theme changes")
	Th.Reset()

	-- older saved data with unlearned recipes: hidden and purged
	local st = ns.db.recipes["Tester-Realm"]
	st[164] = { name = "Blacksmithing", list = {
		{ id = 9001, name = "Obsidian Reaver", learned = false },
		{ id = 9002, name = "Copper Mace", learned = true },
	} }
	ns.providers.recipes._dirty = true
	check(not has("obsidian", "Obsidian Reaver"), "old unlearned recipes are not listed")
	check(has("copper mace", "Copper Mace"), "old learned recipes still are")
	check(#st[164].list == 1, "unlearned recipes are purged from saved data")

	-- quiet index a few seconds after login
	local loginFrame
	for _, f in pairs(_G) do end
	local i = 1
	while true do
		local n, v = debug.getupvalue(P.Scan, i)
		if not n then break end
		i = i + 1
	end
	-- find the login handler: the frame registered for PLAYER_ENTERING_WORLD
	_G.ProfessionsFrame = Obj("Frame"); ProfessionsFrame.shown = false
	local alphas = {}
	ProfessionsFrame.SetAlpha = function(self, a) alphas[#alphas + 1] = a end
	local mark2 = #log
	P.scanBusy = false
	P.Scan(true); FlushAll()
	local loud = false
	for j = mark2 + 1, #log do if log[j]:find("scanning", 1, true) or log[j]:find("scan finished", 1, true) then loud = true end end
	check(not loud, "the login scan is quiet")
	check(alphas[1] == 0 and alphas[#alphas] == 1, "the profession window is invisible during the login scan and restored after")
	check(P.scanBusy == false, "scan finished")
	inCombat = true
	mark2 = #log
	P.Scan(true)
	check(#log == mark2, "no scan (and no message) in combat")
	inCombat = false
	check(Th.Get().autoScan == true, "auto-index at login is on by default")
	local c = UI:WordSearch(UI:CommandEntries(), "set")
	UI.args = "autoScan off"
	c[1].activate(c[1], "autoScan off")
	check(Th.Get().autoScan == false, "> set autoScan off turns it off")
	Th.Set("autoScan", "on")
end


----------------------------------------------------------------------
-- key repeat, talent tabs, recipe opening, sturdy scans
----------------------------------------------------------------------
io.write("[repeat + talents2 + recipe-open tests]\n")
do
	local R = UI._repeat
	-- earlier tests press keys without ever letting go; start from a clean slate
	UI.nativeRepeat = false
	R.key = nil
	UI:Open("")
	typeText("abcdef")
	key("BACKSPACE")
	check(query() == "abcde", "backspace deletes once on press")
	check(R.key == "BACKSPACE", "holding starts a repeat")
	R.scripts.OnUpdate(R, 0.2); check(query() == "abcde", "nothing during the initial delay")
	R.scripts.OnUpdate(R, 0.25); check(query() == "abcd", "then it repeats")
	R.scripts.OnUpdate(R, 0.05); check(query() == "abc", "...steadily")
	F.scripts.OnKeyUp(F, "BACKSPACE")
	R.scripts.OnUpdate(R, 1); check(query() == "abc" and R.key == nil, "key-up stops it")
	key("LEFT"); R.scripts.OnUpdate(R, 0.45); key("X", "x")
	check(query() == "axbc", "held arrow keys repeat too: " .. query())
	F.scripts.OnKeyUp(F, "LEFT")
	-- a client that repeats keys itself: ours steps aside
	key("BACKSPACE"); key("BACKSPACE")
	check(UI.nativeRepeat == true and R.key == nil, "native key repeat detected; own repeat off")
	check(query() == "bc", "each native repeat deletes once: " .. query())
	UI.nativeRepeat = false
	UI:Hide()

	-- talents: window on another tree, the tab is clicked first
	local shownTarget
	local origShow = ns.Highlight.Show
	ns.Highlight.Show = function(self, target, d) shownTarget = target; return origShow(self, target, d) end
	local W = _G.ClassicUIForeverTalents
	W.shown = true
	local furyBtn = Obj("Button"); furyBtn.shown = true; furyBtn.talent = { nodeID = 1003 }
	local tabFury = Obj("Button"); tabFury.shown = true; tabFury.text = "Fury"
	tabFury.Click = function() W.GetChildren = function() return tabFury, furyBtn end end
	W.GetChildren = function() return tabFury end -- showing Arms: no Fury buttons yet
	UI:Open("piercing howl"); key("ENTER"); FlushAll()
	check(shownTarget == furyBtn, "the talent's tree tab is opened, then its node highlighted")
	-- not-taken talent highlights the same way
	shownTarget = nil
	local crBtn = Obj("Button"); crBtn.shown = true; crBtn.talent = { nodeID = 1002 }
	W.GetChildren = function() return tabFury, furyBtn, crBtn end
	UI:Open("cruelty"); key("ENTER"); FlushAll()
	check(shownTarget == crBtn, "a talent you haven't taken is highlighted too")
	-- a talent window Terminal doesn't know by name
	W.shown = false
	local other = Obj("Frame"); other.shown = true; other.__name = "CamelotTalentFrame"
	local oBtn = Obj("Button"); oBtn.shown = true; oBtn.GetNodeID = function() return 1001 end
	other.GetChildren = function() return oBtn end
	UIParent.GetChildren = function() return other end
	shownTarget = nil
	UI:Open("deflection"); key("ENTER"); FlushAll()
	check(shownTarget == oBtn, "any visible talent window is searched")
	local dbg = table.concat(UI:WordSearch(UI:CommandEntries(), "talentdebug")[1].activate(nil, ""), "\n")
	check(dbg:find("Window: CamelotTalentFrame", 1, true) and dbg:find("Talent buttons visible: 1", 1, true), "talentdebug reports the window: " .. dbg)
	UIParent.GetChildren = nil
	ns.Highlight.Show = origShow

	-- Charred Wolf Meat: Enter opens Cooking on that recipe
	local st = ns.db.recipes["Tester-Realm"]
	table.insert(st[185].list, { id = 22, name = "Charred Wolf Meat", learned = true })
	ns.providers.recipes._dirty = true
	_G.ProfessionsFrame = Obj("Frame"); ProfessionsFrame.shown = false
	local row = Obj("Button"); row.shown = true; row.text = "Charred Wolf Meat"
	row.Click = function() note("ROWCLICK Charred Wolf Meat") end
	ProfessionsFrame.GetChildren = function() return row end
	local ots = C_TradeSkillUI.OpenTradeSkill
	C_TradeSkillUI.OpenTradeSkill = function(line) local r = ots(line); ProfessionsFrame.shown = true; return r end
	tsState.prof = { id = 171, name = "Alchemy" }
	local m1 = #log
	UI:Open("charred wolf"); key("ENTER"); FlushAll()
	local function seen(text) for i = m1 + 1, #log do if log[i] == text then return true end end return false end
	check(seen("OpenTradeSkill 185"), "Cooking is opened")
	check(not seen("OpenRecipe") and seen("ROWCLICK Charred Wolf Meat"), "Charred Wolf Meat is selected in it (OpenRecipe, protected, never called)")
	C_TradeSkillUI.OpenTradeSkill = ots

	-- a scan that hits an error part-way still finishes and leaves the window visible
	local alphas = {}
	ProfessionsFrame.shown = false
	ProfessionsFrame.SetAlpha = function(_, a) alphas[#alphas + 1] = a end
	local gri = C_TradeSkillUI.GetRecipeInfo
	C_TradeSkillUI.GetRecipeInfo = function(id) if id == 31 then error("boom") end return gri(id) end
	P.scanBusy = false
	P.Scan(true); FlushAll()
	check(P.scanBusy == false and alphas[#alphas] == 1, "an error mid-scan doesn't leave the profession window invisible")
	C_TradeSkillUI.GetRecipeInfo = gri
	-- and nothing else inherits an invisible window
	alphas = {}
	ProfessionsFrame.shown = true
	P.OpenProfession(185)
	check(alphas[1] == 1, "opening a profession always makes its window visible")
end


----------------------------------------------------------------------
-- Enter follows the player's own key (addon overrides included)
----------------------------------------------------------------------
io.write("[effective binding tests]\n")
do
	local S = ns.Secure
	local F = _G.TerminalFrame
	local savedKey, savedAction = _G.GetBindingKey, _G.GetBindingAction
	_G.GetBindingKey = function(cmd) if cmd == "TOGGLETALENTS" then return "N" end return savedKey(cmd) end
	_G.GetBindingAction = function(k, override)
		if k == "N" then return override and "CLICK ClassicUIForeverTalentsBindKey:LeftButton" or "TOGGLETALENTS" end
		return savedAction(k, override)
	end
	_G.ClassicUIForeverTalents.shown = false
	UI:Open("cruelty"); F.scripts.OnKeyDown(F, "ENTER")
	check(S.armed == "CLICK ClassicUIForeverTalentsBindKey:LeftButton" and bindings["ENTER"] == S.armed,
		"Enter does what the player's Talents key does (ClassicUIForever's window): " .. tostring(S.armed))
	FlushAll()
	-- no key bound: the plain command
	_G.GetBindingKey = function(cmd) if cmd == "TOGGLETALENTS" then return nil end return savedKey(cmd) end
	UI:Open("cruelty"); F.scripts.OnKeyDown(F, "ENTER")
	check(S.armed == "TOGGLETALENTS", "without a key of their own, the game's command is used")
	FlushAll()
	_G.GetBindingKey, _G.GetBindingAction = savedKey, savedAction
end


----------------------------------------------------------------------
-- talent tabs in the game's window, finishing after the terminal closed; addons
----------------------------------------------------------------------
io.write("[talent tabs + addons tests]\n")
do
	local F = _G.TerminalFrame
	local function key(k) F.scripts.OnKeyDown(F, k) end
	local shown
	local origShow = ns.Highlight.Show
	ns.Highlight.Show = function(self, t, d) shown = t; return origShow(self, t, d) end
	_G.ClassicUIForeverTalents.shown = false
	local W = Obj("Frame"); W.shown = false; W.__name = "PlayerTalentFrame"; _G.PlayerTalentFrame = W
	local node = Obj("Button"); node.shown = true; node.GetNodeID = function() return 1002 end
	local tab = Obj("Button"); tab.shown = true; tab.text = "Fury (5)"
	tab.Click = function() W.GetChildren = function() return tab, node end end
	W.GetChildren = function() return tab end
	UI:Open("cruelty"); key("ENTER")
	W.shown = true -- the binding opened it, on another tree
	FlushAll()
	check(shown == node, "a tab labelled 'Fury (5)' is clicked, then the talent highlighted")

	shown = nil; W.shown = false
	local tab2 = Obj("Button"); tab2.shown = true
	tab2.Click = function() W.GetChildren = function() return node end end
	_G.PlayerTalentFrameTab2 = tab2
	W.GetChildren = function() return end
	UI:Open("cruelty"); key("ENTER"); W.shown = true; FlushAll()
	check(shown == node, "unlabelled tabs: the numbered tab for the tree is used (PlayerTalentFrameTab2)")

	shown = nil; W.shown = false
	W.GetChildren = function() return node end
	UI:Open("cruelty"); key("ENTER"); W.shown = true
	UI:Hide() -- the opening window closed the terminal before the finish step
	FlushAll()
	check(shown == node, "highlight still happens if the opening window closed the terminal first")
	W.shown = false
	_G.PlayerTalentFrameTab2, _G.PlayerTalentFrame = nil, nil
	ns.Highlight.Show = origShow

	-- addons: options panels and minimap buttons
	local opened, clicked
	_G.Settings = { OpenToCategory = function(id) opened = id; return true end }
	_G.SettingsPanel = Obj("Frame")
	local cat = { GetName = function() return "Cool Addon 1" end, GetID = function() return 42 end }
	SettingsPanel.GetAllCategories = function() return { cat } end
	local objs = {
		Addon2 = { OnClick = function() clicked = "Addon2" end, icon = 5 },
		["Broker Clock"] = { OnClick = function() clicked = "Clock" end, label = "Clock" },
	}
	local ldb = { DataObjectIterator = function() return next, objs end }
	_G.LibStub = setmetatable({}, { __call = function(_, name) if name == "LibDataBroker-1.1" then return ldb end end })
	_G.Minimap = Obj("Frame")
	local mm = Obj("Button"); mm.__name = "Addon1MinimapButton"
	mm.Click = function() clicked = "Addon1 minimap" end
	Minimap.GetChildren = function() return mm end
	ns.providers.addons._dirty = true
	local a = names(ns:GetEntries(ns.providers.addons))
	check(a["Cool Addon 1"] and a["Cool Addon 1"].detail == "Minimap button  |  Shift: options", "addon with a minimap button and options: " .. tostring(a["Cool Addon 1"] and a["Cool Addon 1"].detail))
	a["Cool Addon 1"].activate(a["Cool Addon 1"])
	check(clicked == "Addon1 minimap" and opened == nil, "Enter clicks its minimap button")
	a["Cool Addon 1"].secondary(a["Cool Addon 1"])
	check(opened == 42, "Shift+Enter opens its options panel")
	check(a["Cool Addon 2"] and a["Cool Addon 2"].detail == "Minimap button", "addon with only a minimap button (LibDataBroker)")
	a["Cool Addon 2"].activate(a["Cool Addon 2"])
	check(clicked == "Addon2", "Enter does what its minimap button does")
	check(a["Clock"] and a["Clock"].detail == "Minimap button", "other minimap buttons are listed too")
	a["Clock"].activate(a["Clock"])
	check(clicked == "Clock", "...and work")
	check(has("cool addon", "Cool Addon 1"), "addons are found in a plain search")
	_G.Settings, _G.SettingsPanel, _G.LibStub, _G.Minimap = nil, nil, nil, nil
	ns.providers.addons._dirty = true
end


----------------------------------------------------------------------
-- profession spells that open their own window (Smelting); the game's options
----------------------------------------------------------------------
io.write("[trade spells + game options tests]\n")
do
	local S = ns.Secure
	local F = _G.TerminalFrame
	local function key(k) F.scripts.OnKeyDown(F, k) end
	local function seen(text, from) for i = (from or 1), #log do if log[i] == text then return true end end return false end
	-- Mining owns two spells in the book; one of them (Smelting) opens a crafting window
	_G.GetProfessions = function() return 1, 6, 3, nil, 2 end
	local gpi = _G.GetProfessionInfo
	_G.GetProfessionInfo = function(i)
		if i == 6 then return "Mining", 16, 60, 150, 2, 50, 186 end
		return gpi(i)
	end
	C_TradeSkillUI.CanTradeSkillShowCraftingUI = function(id) return id == 151 end
	local gsn = C_Spell.GetSpellName
	C_Spell.GetSpellName = function(id) if id == 151 then return "Smelting" elseif id == 152 then return "Find Minerals" end return gsn(id) end
	ns.providers.professions._dirty = true
	local pe = names(ns:GetEntries(ns.providers.professions))
	check(pe["Smelting"] and pe["Smelting"].detail == "Mining", "Smelting is listed under Mining")
	check(not pe["Find Minerals"], "spells that don't open a crafting window aren't")
	check(has("smelt", "Smelting"), "Smelting is searchable")

	-- Enter casts it, through Enter itself
	UI:Open("smelting"); key("ENTER")
	check(S.armed == "SPELL Smelting" and bindings["ENTER"] == "SPELL:Smelting" and F.propagate == true, "Enter casts Smelting on the same press")
	FlushAll()
	check(not UI:IsShown(), "terminal closes")

	-- the Smelting window opens: its recipes are indexed apart from Mining
	RECIPES[186] = { ids = { 61, 62 }, info = {
		[61] = { name = "Smelt Copper", icon = 11, learned = true, categoryID = 5 },
		[62] = { name = "Smelt Iron", icon = 12, learned = false, categoryID = 5 } } }
	tsState.prof = { id = 186, name = "Mining" }
	C_TradeSkillUI.GetTradeSkillLineForRecipe = function(id) if id == 61 or id == 62 then return 186, "Mining", 186 end end
	P.Snapshot(); FlushAll()
	local st = ns.db.recipes["Tester-Realm"]
	check(st["spell:Smelting"] and st["spell:Smelting"].name == "Smelting" and st["spell:Smelting"].parent == "Mining" and st["spell:Smelting"].spell == "Smelting",
		"the window Smelting opened is indexed as Smelting (under Mining)")
	check(has("smelt copper", "Smelt Copper") and not has("smelt iron", "Smelt Iron"), "its learned recipes are searchable")

	-- a Smelting recipe reopens through the spell, then is selected
	_G.ProfessionsFrame = Obj("Frame"); ProfessionsFrame.shown = false
	local row = Obj("Button"); row.shown = true; row.text = "Smelt Copper"
	row.Click = function() note("ROWCLICK Smelt Copper") end
	ProfessionsFrame.GetChildren = function() return row end
	local m = #log
	UI:Open("smelt copper"); key("ENTER")
	check(S.armed == "SPELL Smelting", "a Smelting recipe is opened by casting Smelting")
	ProfessionsFrame.shown = true -- the cast opened it
	FlushAll()
	check(seen("ROWCLICK Smelt Copper", m + 1), "...and the recipe is selected")
	ProfessionsFrame.shown = false
	_G.GetProfessionInfo = gpi

	-- the game's options: pages, sub-pages and settings
	local opened = {}
	_G.Settings = { OpenToCategory = function(id, name) opened[#opened + 1] = tostring(id) .. ":" .. tostring(name); return true end }
	_G.SettingsPanel = Obj("Frame"); SettingsPanel.shown = false
	local function Cat(name, id, inits, subs)
		return { GetName = function() return name end, GetID = function() return id end,
			GetSubcategories = function() return subs or {} end, inits = inits }
	end
	local function Init(name, tip) return { GetName = function() return name end, data = { name = name, tooltip = tip } } end
	local adv = Cat("Advanced", 8, { Init("Anti-Aliasing", "Smooths jagged edges."), Init("Shadow Quality") })
	local gfx = Cat("Graphics", 7, { Init("Display Mode") }, { adv })
	local acc = Cat("Accessibility", 9, { Init("Colorblind Mode") })
	local addonCat = Cat("Cool Addon 1", 42, {})
	SettingsPanel.GetAllCategories = function() return { gfx, acc, addonCat } end
	SettingsPanel.GetLayout = function(_, cat) return { GetInitializers = function() return cat.inits end } end
	ns.providers.gameoptions._dirty = true
	local go = names(ns:GetEntries(ns.providers.gameoptions))
	check(go["Graphics"] and go["Advanced"] and go["Accessibility"], "options pages are listed (sub-pages too)")
	check(go["Anti-Aliasing"] and go["Anti-Aliasing"].detail == "Graphics > Advanced", "settings show where they live: " .. tostring(go["Anti-Aliasing"] and go["Anti-Aliasing"].detail))
	check(not go["Cool Addon 1"], "addons' own pages are left to the AddOn index")
	check(has("anti alias", "Anti-Aliasing") and has("colorblind", "Colorblind Mode") and has("jagged", "Anti-Aliasing"), "settings found by name or by their tooltip")
	check(#UI:Search("") == 0 or not names(UI:Search(""))["Anti-Aliasing"], "options aren't dumped on an empty search")

	-- open the page and point at the setting
	local hl
	local origShow = ns.Highlight.Show
	ns.Highlight.Show = function(self, t, d) hl = t; return origShow(self, t, d) end
	local srow = Obj("Frame"); srow.shown = true; srow.text = "Anti-Aliasing"
	SettingsPanel.GetChildren = function() return srow end
	SettingsPanel.shown = true
	go["Anti-Aliasing"].activate(go["Anti-Aliasing"]); FlushAll()
	check(opened[#opened] == "8:Anti-Aliasing", "its page opens (asking to scroll to it): " .. tostring(opened[#opened]))
	check(hl == srow, "the setting is highlighted")
	-- not on screen: the options window's own search brings it up
	hl = nil
	SettingsPanel.GetChildren = function() return end
	local typed
	SettingsPanel.SearchBox = Obj("EditBox")
	SettingsPanel.SearchBox.SetText = function(_, t) typed = t; SettingsPanel.GetChildren = function() return srow end end
	go["Anti-Aliasing"].activate(go["Anti-Aliasing"]); FlushAll()
	check(typed == "Anti-Aliasing" and hl == srow, "a setting off screen is brought up with the options search")
	ns.Highlight.Show = origShow
	_G.Settings, _G.SettingsPanel = nil, nil
end


----------------------------------------------------------------------
-- quest items bring their quest along
----------------------------------------------------------------------
io.write("[quest item tests]\n")
do
	-- an item the game knows belongs to a quest (quest item / quest starter)
	table.insert(bags[0], { itemID = 5001, itemName = "Dusty Letter", iconFileID = 1, stackCount = 1, quality = 1, hyperlink = "|Hitem:5001|h[Dusty Letter]|h" })
	-- an item named by a quest objective
	table.insert(bags[0], { itemID = 5002, itemName = "Intact Limbs", iconFileID = 1, stackCount = 2, quality = 1, hyperlink = "|Hitem:5002|h[Intact Limbs]|h" })
	C_Container.GetContainerItemQuestInfo = function(b, s)
		local it = bags[b] and bags[b][s]
		if it and it.itemID == 5001 then return { questID = 33, isQuestItem = true } end
		return {}
	end
	C_QuestLog.GetTitleForQuestID = function(id) return id == 33 and "Wolves Across the Border" or nil end
	quests[3] = { title = "Bone Collector", questID = 44, level = 6 }
	local gqo = C_QuestLog.GetQuestObjectives
	C_QuestLog.GetQuestObjectives = function(id)
		if id == 44 then return { { text = "Intact Limbs: 2/8", type = "item" } } end
		return gqo(id)
	end
	ns.providers.items._dirty = true
	ns.providers.quests._dirty = true
	local r = UI:Search("dusty letter")
	check(r[1] and r[1].name == "Dusty Letter", "the item comes first")
	check(r[2] and r[2].name == "Wolves Across the Border", "its quest appears right below it: " .. tostring(r[2] and r[2].name))
	local it = names(ns:GetEntries(ns.providers.items))
	check(it["Dusty Letter"].detail:find("^Quest"), "quest items are marked in their row: " .. it["Dusty Letter"].detail)
	check(it["Intact Limbs"].questID == 44, "an item named by a quest objective is linked to that quest")
	r = UI:Search("intact limbs")
	check(r[1] and r[1].name == "Intact Limbs" and r[2] and r[2].name == "Bone Collector", "Intact Limbs brings Bone Collector along")
	check(has("bone collector", "Intact Limbs"), "searching the quest's name finds its items too")
	check(not names(UI:Search("@item dusty letter"))["Wolves Across the Border"], "@item keeps to items")
	C_QuestLog.GetQuestObjectives = gqo
end


do -- the game blocks addon-opened profession windows
	local P, D = ns.Professions, ns.Debug
	local baseOTS, baseSpell = C_TradeSkillUI.OpenTradeSkill, C_Spell.GetSpellInfo
	local calls = 0
	C_TradeSkillUI.OpenTradeSkill = function(line)
		calls = calls + 1
		D.frame.scripts.OnEvent(D.frame, "ADDON_ACTION_BLOCKED", "Terminal", "UNKNOWN()")
	end
	local realPrint, printed = _G.print, {}
	_G.print = function(...) local t = {}; for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end; printed[#printed + 1] = table.concat(t, " ") end
	ns.db.noDirectOpen = nil
	for _, pd in pairs(TerminalDB.recipes and TerminalDB.recipes or {}) do end
	check(P.DirectOpen(171) == false and ns.db.noDirectOpen == true, "a blocked direct open is detected and remembered")
	check(P.DirectOpen(171) == false and calls == 1, "after a block the protected call is never made again")
	local idxBefore = 0
	P.Scan(); FlushAll()
	check(calls == 1, "scan makes no protected call once blocked")
	check(table.concat(printed, "\n"):find("doesn't let addons open profession windows", 1, true), "scan explains what to do instead")
	P.OpenRecipe(12, 171, "Mana Well"); FlushAll()
	check(calls == 1, "opening a recipe makes no protected call once blocked")
	-- login scan stays off until direct opening has been seen to work
	ns.db.noDirectOpen = nil
	local before = calls
	local theme = ns.Theme.Get(); theme.autoScan = true
	-- (login handler is driven by PLAYER_ENTERING_WORLD + a 6 s timer)
	-- recipes and professions are opened by casting, where casting opens a crafting window
	C_TradeSkillUI.CanTradeSkillShowCraftingUI = function(id) return id == 9185 end
	C_Spell.GetSpellInfo = function(n) if n == "Cooking" then return { name = n, spellID = 9185 } elseif n == "Alchemy" then return { name = n, spellID = 9171 } end end
	check(P.OpenSpell("Cooking") == "Cooking" and P.OpenSpell("Alchemy") == nil, "only crafting-window spells are cast")
	P.MarkDirty()
	local pe = names(ns:GetEntries(ns.providers.professions))
	check(pe["Cooking"].secure and pe["Cooking"].secure.spell == "Cooking", "Cooking opens through its spell on Enter")
	check(pe["Alchemy"].secure == nil, "a profession whose spell doesn't open a window isn't cast")
	local re = names(ns:GetEntries(ns.providers.recipes))
	check(re["Basic Campfire"] == nil or re["Basic Campfire"].secure == nil or re["Basic Campfire"].secure.spell == "Cooking", "cooking recipes cast Cooking")
	C_TradeSkillUI.OpenTradeSkill, C_Spell.GetSpellInfo = baseOTS, baseSpell
	C_TradeSkillUI.CanTradeSkillShowCraftingUI = nil
	ns.db.noDirectOpen = nil
	_G.print = realPrint
	for i = #D.events, 1, -1 do D.events[i] = nil end
	for i = #D.trace, 1, -1 do D.trace[i] = nil end
end

do -- world map locations
	local MAPS = {
		[946] = { mapID = 946, name = "Cosmic", mapType = 0, parentMapID = 0 },
		[947] = { mapID = 947, name = "Azeroth", mapType = 1, parentMapID = 946 },
		[13] = { mapID = 13, name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
		[37] = { mapID = 37, name = "Elwynn Forest", mapType = 3, parentMapID = 13 },
		[1581] = { mapID = 1581, name = "The Deadmines", mapType = 4, parentMapID = 37 },
	}
	local pinned = false
	C_Map = {
		HasUserWaypoint = function() return pinned end,
		ClearUserWaypoint = function() note("ClearWaypoint"); pinned = false end,
		GetMapInfo = function(id) return MAPS[id] end,
		GetMapChildrenInfo = function(id)
			local out = {}
			for mid, m in pairs(MAPS) do if mid ~= id and (id == 946 or id == 947 or m.parentMapID == id or id == 13) and mid ~= 946 and mid ~= 947 then out[#out + 1] = m end end
			return out
		end,
		GetBestMapForUnit = function() return 37 end,
		CanSetUserWaypointOnMap = function() return true end,
		SetUserWaypoint = function(p) note("Waypoint", p.uiMapID, p.position.x); pinned = true end,
	}
	_G.UiMapPoint = nil
	_G.CreateVector2D = function(x, y) return { x = x, y = y } end
	C_SuperTrack.SetSuperTrackedUserWaypoint = function(b) note("TrackWaypoint", tostring(b)) end
	C_AreaPoiInfo = {
		GetAreaPOIForMap = function(id) return id == 37 and { 7001 } or {} end,
		GetAreaPOIInfo = function(_, id) return { name = "Goldshire", position = { x = 0.42, y = 0.65 } } end,
	}
	C_TaxiMap = { GetTaxiNodesForMap = function(id) return id == 37 and { { nodeID = 2, name = "Stormwind, Elwynn", position = { x = 0.5, y = 0.5 } } } or {} end }
	_G.C_EncounterJournal = { GetDungeonEntrancesForMap = function(id) return id == 37 and { { areaPoiID = 6001, name = "The Deadmines", position = { x = 0.4, y = 0.7 } } } or {} end }
	_G.BINDING_NAME_TOGGLEWORLDMAP = "World Map"
	ns.providers.maps._dirty = true
	local es = ns:GetEntries(ns.providers.maps)
	local byName = names(es)
	check(not ns.providers.maps._warned, "maps provider ran clean")
	check(byName["Elwynn Forest"] and byName["Elwynn Forest"].detail == "Zone  Eastern Kingdoms", "zone listed with its continent: " .. tostring(byName["Elwynn Forest"] and byName["Elwynn Forest"].detail))
	check(not byName["Cosmic"] and not byName["Azeroth"], "cosmic/world roots aren't listed")
	check(byName["Goldshire"] and byName["Goldshire"].pos.x == 0.42, "point of interest indexed with its position")
	check(byName["Stormwind, Elwynn"] and byName["Stormwind, Elwynn"].detail:find("Flight point"), "flight point indexed")
	check(byName["The Deadmines"], "dungeon indexed")
	check(UI:Search("goldshire")[1].name == "Goldshire", "fuzzy finds a point of interest")
	check(UI:Search("@map elwynn")[1].name == "Elwynn Forest", "@map filter")
	local g = byName["Goldshire"]
	check(g.secure.binding == "TOGGLEWORLDMAP", "map opens through the game's own map key")
	-- the game's macro opens and switches the map; Terminal's code never writes the map
	-- (SetMapID from Terminal left the map tainted: its pins failed in combat)
	WorldMapFrame.shown = true
	local switched = {}
	WorldMapFrame.SetMapID = function(_, id) switched[#switched + 1] = id end
	local MAPMACRO = "/run if not WorldMapFrame:IsShown() then ToggleWorldMap() end WorldMapFrame:SetMapID(37)"
	local rg = ns.Secure.Resolve(g.secure, g)
	check(rg and rg.macro == MAPMACRO, "Enter runs the game's macro that switches the map: " .. tostring(rg and rg.macro))
	check(g.isOpen(g) == false, "with the map open the macro still runs (it switches the map)")
	local mark = #log
	g.after(g)
	check(#switched == 0, "after: Terminal never switches the map itself")
	check(logHas("Waypoint 37 0.42", mark + 1) and logHas("TrackWaypoint true", mark + 1), "waypoint placed and tracked")
	local z = byName["Elwynn Forest"]; mark = #log
	z.after(z)
	check(#switched == 0 and not logHas("Waypoint 37 0.42", mark + 1), "a zone sets no waypoint (the macro switched the map)")
	-- a pin that is already set is replaced by the chosen place, zone or point
	pinned = true; mark = #log
	z.after(z)
	check(logHas("ClearWaypoint", mark + 1) and logHas("Waypoint 37 0.5", mark + 1), "existing pin: cleared, and the zone is pinned at its middle")
	pinned = true; mark = #log
	g.after(g)
	check(logHas("ClearWaypoint", mark + 1) and logHas("Waypoint 37 0.42", mark + 1), "existing pin: cleared, and the point is pinned")
	pinned = false; mark = #log
	z.after(z)
	check(not logHas("ClearWaypoint", mark + 1) and not logHas("Waypoint 37 0.5", mark + 1), "no pin set: a zone doesn't get one")
	pinned = true; mark = #log
	z.secondary(z)
	check(logHas("ClearWaypoint", mark + 1) and logHas("Waypoint 37 0.5", mark + 1), "Shift+Enter on a zone also replaces an existing pin")
	pinned = false
	-- Shift+Enter: waypoint without opening anything
	mark = #log
	g.secondary(g)
	check(logHas("Waypoint 37 0.42", mark + 1) and not logHas("ToggleWorldMap", mark + 1), "secondary sets a waypoint only")
	local D, n = ns.Debug, 0
	WorldMapFrame.SetMapID = function() n = n + 1 end
	ns.db.blockedCalls = nil
	-- in combat the map is left alone (its pins are protected), the waypoint still works, and a
	-- block seen in combat is not remembered as permanent
	local realCombat = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	n = 0; mark = #log
	g.activate(g)
	FlushAll()
	check(n == 0 and not logHas("ToggleWorldMap", mark + 1), "in combat: map neither opened nor switched")
	check(logHas("Waypoint 37 0.42", mark + 1), "in combat: waypoint still set")
	g.after(g)
	check(n == 0, "in combat: after() doesn't switch the map either")
	local viaGuard = ns.Professions.Guarded("X", function() D.frame.scripts.OnEvent(D.frame, "ADDON_ACTION_BLOCKED", "Terminal", "UNKNOWN()") end)
	check(viaGuard == false and not (ns.db.blockedCalls and ns.db.blockedCalls.X), "a block seen in combat isn't remembered")
	_G.InCombatLockdown = realCombat
	ns.db.blockedCalls = nil
	for i = #D.events, 1, -1 do D.events[i] = nil end
	for i = #D.trace, 1, -1 do D.trace[i] = nil end
	C_Map, C_TaxiMap, C_AreaPoiInfo, _G.C_EncounterJournal = nil, nil, nil, nil
	ns.providers.maps._dirty = true
end

do -- combat: Enter on window-opening entries does nothing
	local acted = {}
	ns:RegisterProvider("combattest", {
		label = "CT", explicit = true, aliases = { "combattest" }, noCombat = true,
		collect = function() return { { name = "Zzcombat window", activate = function() acted[#acted + 1] = "window" end },
			{ name = "Zzcombat plain", noCombat = false, activate = function() acted[#acted + 1] = "plain" end } } end,
	})
	local realCombat = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	local mark = #log
	UI:Open("@combattest zzcombat window"); UI:Activate(1)
	check(#acted == 0, "combat: a noCombat entry does nothing")
	check(UI.IsShown and true, "terminal stays")
	UI:Open("@combattest zzcombat plain"); UI:Activate(1)
	check(acted[1] == "plain", "combat: an entry that is safe still runs")
	UI:Open("wolves across"); UI:Activate(1)
	check(not ns.Secure.armed and not logHas("ToggleQuestLog", mark + 1), "combat: secure entries aren't armed or opened")
	_G.InCombatLockdown = realCombat
	UI:Hide()
	UI:Open("@combattest zzcombat window"); UI:Activate(1)
	check(acted[2] == "window", "out of combat the same entry runs")
	UI:Hide()
end

do -- AtlasLoot and Questie integrations
	local I = ns.Integrations
	check(I and not I.loot.on and not I.npc.on and ns.providers.loot == nil and ns.providers.npc == nil, "nothing registered without the addons")
	local iname = { [1001] = "Cruel Barb", [1002] = "Red Defias Mask" }
	local baseName, baseIcon = C_Item.GetItemNameByID, C_Item.GetItemIconByID
	C_Item.GetItemNameByID = function(id) return iname[id] end
	C_Item.GetItemIconByID = function(id) return 134 end
	local requested = {}
	local baseReq = C_Item.RequestLoadItemDataByID
	C_Item.RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end
	local sel = {}
	local function selector(n) return { SetSelected = function(self, ...) sel[#sel + 1] = n .. "=" .. tostring((select(1, ...))) end } end
	local btn = Obj("Button"); btn.shown = true; btn.ItemID = 1002
	local content = {
		items = { {}, {} },
		GetName = function() return "The Deadmines" end,
		GetNameForItemTable = function(_, i) return i == 1 and "Edwin VanCleef" or "Mr. Smite" end,
	}
	local storage = { GetDifficultys = function() return { { name = "Normal" } } end, DEADMINES = content }
	_G.AtlasLoot = {
		Loader = { GetLootModuleList = function() return { module = { { addonName = "ALDungeons" } }, custom = {} } end,
			LoadModule = function(_, a) note("ALLoad", a) end },
		ItemDB = { Storage = { ALDungeons = storage },
			GetItemTable = function(_, addon, c, boss, d) return boss == 1 and { { 1, 1001 }, { 2, 1002 }, { 3, "INV_Misc_Note_01" } } or { { 1, 1001 } } end },
		GUI = { frame = Obj("Frame"), ItemFrame = { frame = { ItemButtons = { btn } } } },
	}
	AtlasLoot.GUI.frame.moduleSelect, AtlasLoot.GUI.frame.subCatSelect = selector("module"), selector("content")
	AtlasLoot.GUI.frame.boss, AtlasLoot.GUI.frame.difficulty = selector("boss"), selector("diff")
	AtlasLoot.GUI.frame.shown = false
	-- an AtlasLoot table without AtlasLoot's own addon loaded (disabled; a plugin left behind) is ignored
	local baseLoaded = C_AddOns.IsAddOnLoaded
	C_AddOns.IsAddOnLoaded = function(n) return n ~= "AtlasLootClassic" and n ~= "AtlasLoot" and n ~= "AtlasLootForever" end
	I.Setup()
	check(not I.loot.on and ns.providers.loot == nil, "no @loot when AtlasLoot itself isn't loaded")
	C_AddOns.IsAddOnLoaded = baseLoaded
	_G.Questie = {
		API = { isReady = true },
	}
	local QINFO = {
		[33] = { name = "Wolves Across the Border", questLevel = 5 },
		[501] = { name = "The Defias Brotherhood", questLevel = 14, startedBy = { { 12 } } },
		[502] = { name = "Red Linen Goods", questLevel = 12, startedBy = { nil, { 555 } } },
	}
	local saveLogIdx, saveDone = C_QuestLog.GetLogIndexForQuestID, C_QuestLog.IsQuestFlaggedCompleted
	C_QuestLog.GetLogIndexForQuestID = function(id) return id == 33 and 2 or nil end
	C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == 502 end
	local QDB = { NPCPointers = { [10] = true, [11] = true, [12] = true },
		QuestPointers = { [33] = true, [501] = true, [502] = true },
		QueryQuestSingle = function(id, f) return QINFO[id] and QINFO[id][f] end,
		QueryNPCSingle = function(id, f) return ({ [10] = "Edwin VanCleef", [11] = "Defias Pillager", [12] = "Marshal McBride" })[id] end,
		GetNPC = function(_, id) if id == 12 then return { spawns = { [9] = { { 50, 40 } } } } end end }
	local QZ = { GetUiMapIdByAreaId = function(_, z) return z == 9 and 37 or nil end, GetDungeonLocation = function() return nil end }
	local QM = { ShowNPC = function(_, id) note("QuestieShowNPC", id) end }
	_G.QuestieLoader = { ImportModule = function(_, n) return ({ QuestieDB = QDB, ZoneDB = QZ, QuestieMap = QM })[n] end }

	I.Setup(); FlushAll()
	check(I.loot.on and I.npc.on, "both detected")
	check(logHas("ALLoad ALDungeons") and I.loot.done and #I.loot.rows == 2, "AtlasLoot module loaded and indexed, one row per item and instance: " .. #I.loot.rows)
	local es = names(ns:GetEntries(ns.providers.loot))
	check(es["Cruel Barb"] and es["Red Defias Mask"] and not es["INV_Misc_Note_01"], "named item rows only")
	check(es["Cruel Barb"].detail == "Edwin VanCleef  The Deadmines", "detail: boss and instance")
	check(UI:Search("red defias")[1].name == "Red Defias Mask", "AtlasLoot items found in plain search")
	check(UI:Search("@loot cruel")[1].name == "Cruel Barb", "@loot filter")
	-- items whose names the game hasn't sent yet are asked for, and appear when they arrive
	iname[1002] = nil; ns.providers.loot._dirty = true
	for _, r in ipairs(I.loot.rows) do if r.itemID == 1002 then r.name = nil; r._lname = nil end end -- as if never named
	check(not names(ns:GetEntries(ns.providers.loot))["Red Defias Mask"], "unnamed items wait")
	iname[1002] = "Red Defias Mask"; ns.providers.loot._dirty = true
	check(names(ns:GetEntries(ns.providers.loot))["Red Defias Mask"], "and appear once named")
	-- Enter opens AtlasLoot on that boss and points at the item
	local e = names(ns:GetEntries(ns.providers.loot))["Red Defias Mask"]
	local hl0 = #log
	e.activate(e); FlushAll()
	check(AtlasLoot.GUI.frame.shown or AtlasLoot.GUI.frame:IsShown(), "AtlasLoot window shown")
	check(table.concat(sel, ","):find("module=ALDungeons,content=DEADMINES,boss=1,diff=1", 1, true), "selected module, instance, boss, difficulty: " .. table.concat(sel, ","))
	-- Questie
	check(I.npc.list and #I.npc.list == 3, "Questie NPC names indexed: " .. tostring(I.npc.list and #I.npc.list))
	check(ns.providers.npc.explicit, "NPCs only with @npc")
	check(#UI:Search("marshal mcbride") == 0 or UI:Search("marshal mcbride")[1].kind ~= "npc", "NPCs not in plain search")
	local r = UI:Search("@npc marshal")
	check(r[1] and r[1].name == "Marshal McBride", "@npc finds the NPC")
	local n = r[1]
	check(n.secure and n.secure.binding == "TOGGLEWORLDMAP", "NPC opens the map through the game's map key")
	-- the map is open: Questie's marker, the map switch and the pin
	C_Map = { HasUserWaypoint = function() return false end, ClearUserWaypoint = function() end,
		CanSetUserWaypointOnMap = function() return true end,
		SetUserWaypoint = function(p) note("Waypoint", p.uiMapID, p.position.x, p.position.y) end }
	_G.CreateVector2D = function(x, y) return { x = x, y = y } end
	C_SuperTrack.SetSuperTrackedUserWaypoint = function() end
	local switched = {}
	WorldMapFrame.SetMapID = function(_, id) switched[#switched + 1] = id end
	local mark = #log
	n.after(n)
	check(logHas("QuestieShowNPC 12", mark + 1), "Questie marks the NPC on the map")
	check(#switched == 0 and logHas("Waypoint 37 0.5 0.4", mark + 1), "the NPC is pinned; Terminal doesn't switch the map itself")
	local rn = ns.Secure.Resolve(n.secure, n)
	check(rn and rn.macro and rn.macro:find("SetMapID(37)", 1, true), "the game's macro switches the map to the NPC's zone")
	mark = #log
	n.secondary(n)
	check(logHas("Waypoint 37 0.5 0.4", mark + 1) and not logHas("QuestieShowNPC", mark + 1), "Shift+Enter only pins")
	-- combat: nothing is touched
	local realCombat = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	mark = #log
	UI:Open("@npc marshal"); UI:Activate(1)
	check(not logHas("QuestieShowNPC", mark + 1) and not ns.Secure.armed, "in combat the NPC entry does nothing")
	_G.InCombatLockdown = realCombat
	UI:Hide()
	-- Questie's quests (@questie) are kept apart from the quest log (@questlog)
	check(ns:ResolveProvider("questie").id == "questie" and ns:ResolveProvider("questlog").id == "quests", "@questie and @questlog are separate")
	check(ns.providers.questie.explicit, "Questie's quests only with @questie")
	check(I.qdb.list and #I.qdb.list == 3, "Questie quests indexed: " .. tostring(I.qdb.list and #I.qdb.list))
	ns.providers.questie._dirty = true
	local qs = names(ns:GetEntries(ns.providers.questie))
	check(qs["The Defias Brotherhood"] and qs["The Defias Brotherhood"].detail == "Lv 14", "level shown: " .. tostring(qs["The Defias Brotherhood"] and qs["The Defias Brotherhood"].detail))
	check(qs["Red Linen Goods"].detail:find("done", 1, true), "completed quests are marked done")
	local w = qs["Wolves Across the Border"]
	check(w.detail:find("in log", 1, true) and w.secure and w.secure.binding == "TOGGLEQUESTLOG", "a quest you're on opens the quest log")
	check(w.questID == nil, "Questie entries don't drag log quests along")
	local plainHit = false
	for _, x in ipairs(UI:Search("defias brotherhood")) do if x.kind == "questie" then plainHit = true end end
	check(not plainHit, "Questie quests aren't in plain search")
	r = UI:Search("@questie defias")
	check(r[1] and r[1].name == "The Defias Brotherhood", "@questie finds a quest by name")
	local q = r[1]
	check(q.secure and q.secure.binding == "TOGGLEWORLDMAP", "a quest you don't have opens the map on its giver")
	mark = #log
	q.after(q)
	check(logHas("QuestieShowNPC 12", mark + 1) and logHas("Waypoint 37 0.5 0.4", mark + 1), "quest giver shown and pinned")
	local said = {}
	local basePrint = ns.Print
	ns.Print = function(_, m) said[#said + 1] = m end
	qs["Red Linen Goods"].activate(qs["Red Linen Goods"])
	ns.Print = basePrint
	check(said[1] and said[1]:find("started by an object", 1, true), "quests started by an object say so: " .. tostring(said[1]))
	r = UI:Search("@questlog wolves")
	check(r[1] and r[1].kind == "quests", "@questlog searches the quest log")
	check(ns:ResolveProvider("questie").id ~= "npc", "@questie no longer means NPCs")
	C_QuestLog.GetLogIndexForQuestID, C_QuestLog.IsQuestFlaggedCompleted = saveLogIdx, saveDone
	-- big lists are compact: shared functions, not copies per entry
	local npcEntry = names(ns:GetEntries(ns.providers.npc))["Marshal McBride"]
	check(rawget(npcEntry, "activate") == nil and npcEntry.activate and rawget(npcEntry, "detail") == nil and npcEntry.detail == "NPC  #12", "NPC entries are compact (shared functions, detail worked out when read)")
	check(npcEntry.kind == "npc" and npcEntry.freqKey == "npc:12", "compact entries still know their kind")
	-- idle big lists are freed, and rebuilt when next searched
	ns.providers.npc._usedAt = -10000
	ns:DropIdle(1000)
	check(ns.providers.npc._entries == nil and I.npc.list == nil, "an NPC list nobody searched for 10 minutes is freed")
	local again = ns:GetEntries(ns.providers.npc)
	FlushAll()
	again = names(ns:GetEntries(ns.providers.npc))
	check(again["Marshal McBride"], "and rebuilt on the next @npc search")
	local cmd = ns.commands.integrations.run()
	check(table.concat(cmd, "\n"):find("AtlasLoot: found") and table.concat(cmd, "\n"):find("Questie: found. 3 NPCs"), "integrations command: " .. table.concat(cmd, " | "))
	-- clean up
	ns.providers.loot, ns.providers.npc, ns.providers.questie = nil, nil, nil
	for i, id in ipairs(ns.providerOrder) do if id == "loot" or id == "npc" then table.remove(ns.providerOrder, i) end end
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "loot" or ns.providerOrder[i] == "npc" or ns.providerOrder[i] == "questie" then table.remove(ns.providerOrder, i) end end
	_G.AtlasLoot, _G.Questie, _G.QuestieLoader, C_Map = nil, nil, nil, nil
	C_Item.GetItemNameByID, C_Item.GetItemIconByID, C_Item.RequestLoadItemDataByID = baseName, baseIcon, baseReq
	I.loot.on, I.npc.on = false, false
end

do -- Questie's always-visible frames don't count as an open quest log
	local fq = Obj("Frame"); fq.__name = "Questie_BaseFrame"; fq.shown = true
	local ft = Obj("Frame"); ft.__name = "QuestieTrackerFrame"; ft.shown = true
	local fw = Obj("Frame"); fw.__name = "QuestWatchFrame"; fw.shown = true
	local fl = Obj("Frame"); fl.__name = "QuestLogExFrame"; fl.shown = false; _G.QuestLogExFrame = fl
	local fo = Obj("Frame"); fo.__name = "QuestChoiceSomething"; fo.shown = true -- any other "Quest" frame
	QuestMapFrame.shown = false; ForeverClassicUIQuestLog.shown = false -- leftovers of the earlier quest tests
	UIParent.GetChildren = function() return fq, ft, fw, fl, fo end
	ns.providers.quests._dirty = true
	local q = names(ns:GetEntries(ns.providers.quests))["Wolves Across the Border"]
	check(q and q.isOpen() == false, "Questie's tracker (or any other Quest-named frame) doesn't make the quest log look open")
	fl.shown = true
	check(q.isOpen() == true, "a real quest window does")
	fl.shown = false
	UI:Open("wolves across"); key("ENTER")
	check(S.armed == "TOGGLEQUESTLOG", "Enter on a quest arms the quest log key even with Questie's frames on screen")
	_G.QuestLogExFrame = nil; UI:Hide(); S.Disarm()
	UIParent.GetChildren = nil
end

do -- history: the empty terminal shows what was picked last, newest first
	ns.db.recent = {}
	local items = ns:GetEntries(ns.providers.items)
	local a, b, c = items[1], items[2], items[3]
	for i = 1, 30 do ns:Bump(a.freqKey) end -- an old favourite
	ns:Bump(b.freqKey); ns:Bump(c.freqKey)
	local r = UI:Search("")
	check(r[1] == c and r[2] == b and r[3] == a, "newest pick first, then the older one, then favourites: " .. tostring(r[1] and r[1].name) .. "," .. tostring(r[2] and r[2].name) .. "," .. tostring(r[3] and r[3].name))
	ns:Bump(b.freqKey)
	r = UI:Search("")
	check(r[1] == b and r[2] == c, "picking something again moves it to the top")
	local seen = 0
	for _, e in ipairs(r) do if e == b then seen = seen + 1 end end
	check(seen == 1 and #ns.db.recent == 3, "each thing once in the history: " .. #ns.db.recent)
	for i = 1, 60 do ns:Bump("items:fake" .. i) end
	check(#ns.db.recent == 40, "history is capped: " .. #ns.db.recent)
	ns.db.recent = {}
end

do -- equipment sets: searchable by name or @equipmentset; Enter equips, Shift+Enter lists
	local used = {}
	local SETS = {
		[1] = { "Tank Gear", 111, 1, false, 3, 1, 2, 0 },
		[2] = { "Fishing", 222, 2, true, 2, 2, 0, 0 },
		[3] = { "Old Raid Set", 333, 3, false, 4, 0, 2, 2 },
	}
	_G.C_EquipmentSet = {
		GetEquipmentSetIDs = function() return { 1, 2, 3 } end,
		GetEquipmentSetInfo = function(id) return unpack(SETS[id]) end,
		UseEquipmentSet = function(id) used[#used + 1] = id; return true end,
		GetItemIDs = function(id) return { [1] = 501, [16] = 502 } end,
	}
	local saveCount = C_Item.GetItemCount
	C_Item.GetItemCount = function(itemID) return itemID == 501 and 1 or 0 end
	ns.providers.equipmentset._dirty = true
	local r = UI:Search("tank gear")
	check(r[1] and r[1].kind == "equipmentset" and r[1].name == "Tank Gear", "set found by name in plain search")
	check(ns:ResolveProvider("EquipmentSet").id == "equipmentset" and ns:ResolveProvider("set").id == "equipmentset", "@EquipmentSet and @set pick equipment sets")
	r = UI:Search("@equipmentset")
	check(#r == 3, "@equipmentset lists every set: " .. #r)
	local es = names(ns:GetEntries(ns.providers.equipmentset))
	check(es["Fishing"].detail == "Set  Equipped" and es["Old Raid Set"].detail == "Set  2 missing" and es["Tank Gear"].detail == "Set  1/3 worn", "set state shown")
	local said = {}
	local basePrint = ns.Print
	ns.Print = function(_, m) said[#said + 1] = m end
	UI:Open("tank gear"); UI:Activate(1)
	check(used[1] == 1 and said[#said]:find("Equipping Tank Gear", 1, true), "Enter equips the set")
	es["Fishing"].activate(es["Fishing"])
	check(#used == 1 and said[#said]:find("already equipped", 1, true), "an equipped set isn't re-equipped")
	local realCombat = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	UI:Open("tank gear"); UI:Activate(1)
	check(#used == 1, "in combat Enter does nothing")
	_G.InCombatLockdown = realCombat
	ns.Print = basePrint
	local out = {}
	local baseOut = ns.Output
	ns.Output = function(_, lines) for _, l in ipairs(lines) do out[#out + 1] = l end end
	es["Tank Gear"].secondary(es["Tank Gear"])
	ns.Output = baseOut
	local joined = table.concat(out, "\n")
	check(out[1] == "Tank Gear:" and joined:find("Head:", 1, true) and joined:find("Main hand:.-%(missing%)"), "without a character key, Shift+Enter lists the items, marking missing ones: " .. joined)
	-- Shift+Enter: the game itself presses the character micro button, the right-pane arrow
	-- (only when that pane is closed) and the Equipment Manager tab, as one macro; Terminal then
	-- only points at the set. (Clicking those from Terminal's code tainted the window.)
	_G.CharacterFrame = _G.CharacterFrame or Obj("Frame"); CharacterFrame.shown = false
	_G.PaperDollFrame = _G.PaperDollFrame or Obj("Frame"); PaperDollFrame.shown = false
	local pane = Obj("Frame"); pane.shown = false
	PaperDollFrame.EquipmentManagerPane = pane
	local setRow = Obj("Button"); setRow.shown = true; setRow.setID = 1
	local otherRow = Obj("Button"); otherRow.shown = true; otherRow.setID = 2
	pane.GetChildren = function() return otherRow, setRow end
	local rightPane = Obj("Frame"); rightPane.shown = false
	rightPane.GetParent = function() return CharacterFrame end
	local function tab(n)
		local t = Obj("Button"); t.__name = "PaperDollSidebarTab" .. n; t.shown = true
		t.GetName = function(self) return self.__name end
		t.GetParent = function() return rightPane end
		t.Click = function() note("ADDON CLICKED TAB" .. n) end
		_G["PaperDollSidebarTab" .. n] = t
		return t
	end
	tab(1); tab(2); tab(3)
	_G.GetPaperDollSideBarFrame = function(i) if i == 2 then return pane end end
	local toggle = Obj("Button"); toggle.__name = "CharacterFrameRightPaneToggleButton"; toggle.shown = true
	toggle.GetName = function(self) return self.__name end
	toggle.Click = function() note("ADDON CLICKED TOGGLE") end
	CharacterFrame.RightPaneToggleButton = toggle
	local pointed
	local origShow = ns.Highlight.Show
	ns.Highlight.Show = function(self, t, d) pointed = t; return origShow(self, t, d) end
	local realShift = _G.IsShiftKeyDown
	_G.IsShiftKeyDown = function() return true end
	local function press() -- what the game does with the armed macro
		CharacterFrame.shown, PaperDollFrame.shown, rightPane.shown, pane.shown = true, true, true, true
		local p = _G.TerminalMacroProxy
		p.scripts.PostClick(p, "LeftButton", true)
		FlushAll()
	end
	-- closed window, right pane closed
	local mark = #log
	UI:Open("tank gear"); key("ENTER")
	local mp = _G.TerminalMacroProxy
	check(ns.Secure.armed == "MACRO" and mp and mp.attrs.macrotext == "/click CharacterMicroButton\n/click CharacterFrameRightPaneToggleButton\n/click PaperDollSidebarTab2",
		"Shift+Enter arms a macro: micro button, right-pane arrow, Equipment Manager tab: " .. tostring(mp and mp.attrs and mp.attrs.macrotext))
	check(#used == 1, "Shift+Enter doesn't equip the set")
	check(mp.attrs.useOnKeyDown == true and mp.attrs.type == "macro", "the macro runs on key down, like the game's own bindings")
	mp.scripts.PostClick(mp, "LeftButton", false) -- a stray key-up click must not unbind Enter early
	check(ns.Secure.armed == "MACRO", "a key-up click doesn't finish (or unbind) the macro")
	press()
	check(pointed == setRow, "after the game's clicks, the set is pointed at")
	local addonClicks = false
	for i = mark + 1, #log do if log[i]:find("ADDON CLICKED", 1, true) then addonClicks = true end end
	check(not addonClicks, "Terminal itself clicks nothing in the character window")
	-- right pane already open: the arrow is left alone (it would close the pane)
	CharacterFrame.shown, PaperDollFrame.shown, pane.shown = false, false, false
	rightPane.shown = true
	UI:Open("tank gear"); key("ENTER")
	check(mp.attrs.macrotext == "/click CharacterMicroButton\n/click PaperDollSidebarTab2", "right pane open: no arrow click: " .. tostring(mp.attrs.macrotext))
	press()
	-- the window remembers its pane state while closed (rightPaneCollapsed): that decides,
	-- even when the pane's own frames report hidden (the second-time half-open bug)
	CharacterFrame.shown, PaperDollFrame.shown, pane.shown = false, false, false
	rightPane.shown = false
	CharacterFrame.rightPaneCollapsed = false
	UI:Open("tank gear"); key("ENTER")
	check(mp.attrs.macrotext == "/click CharacterMicroButton\n/click PaperDollSidebarTab2", "pane remembered open: the arrow is left alone: " .. tostring(mp.attrs.macrotext))
	ns.Secure.Disarm(); UI:Hide()
	CharacterFrame.rightPaneCollapsed = true
	rightPane.shown = true
	UI:Open("tank gear"); key("ENTER")
	check(mp.attrs.macrotext == "/click CharacterMicroButton\n/click CharacterFrameRightPaneToggleButton\n/click PaperDollSidebarTab2", "pane remembered closed: the arrow is clicked: " .. tostring(mp.attrs.macrotext))
	ns.Secure.Disarm(); UI:Hide()
	CharacterFrame.rightPaneCollapsed = nil
	local realCVar = _G.GetCVar
	_G.GetCVar = function(n) if n == "characterFrameCollapsed" then return "0" end return realCVar and realCVar(n) end
	rightPane.shown = false
	UI:Open("tank gear"); key("ENTER")
	check(not mp.attrs.macrotext:find("Toggle", 1, true), "the characterFrameCollapsed setting is used when the field isn't there")
	ns.Secure.Disarm(); UI:Hide()
	_G.GetCVar = realCVar
	rightPane.shown = true
	press()
	-- the window is open on another page: no micro button click (it would close it)
	pane.shown = false
	UI:Open("tank gear"); key("ENTER")
	check(mp.attrs.macrotext == "/click PaperDollSidebarTab2", "window open: only the tab: " .. tostring(mp.attrs.macrotext))
	press()
	-- already on the sets page: straight to the set
	pointed = nil
	UI:Open("tank gear"); key("ENTER"); FlushAll()
	check(pointed == setRow and not ns.Secure.armed, "sets page already showing: just points at the set")
	-- the tab is found by its pane, whatever its position
	_G.GetPaperDollSideBarFrame = function(i) if i == 3 then return pane end end
	pane.shown = false
	UI:Open("tank gear"); key("ENTER")
	check(mp.attrs.macrotext:find("PaperDollSidebarTab3", 1, true), "the Equipment Manager tab is the one showing its pane")
	ns.Secure.Disarm(); UI:Hide()
	-- in combat, nothing
	CharacterFrame.shown, PaperDollFrame.shown, pane.shown = false, false, false
	_G.InCombatLockdown = function() return true end
	pointed = nil
	UI:Open("tank gear"); UI:Activate(1, { secondary = true }); FlushAll()
	check(pointed == nil and not ns.Secure.armed, "in combat Shift+Enter does nothing")
	_G.InCombatLockdown = realCombat
	_G.IsShiftKeyDown = realShift
	ns.Highlight.Show = origShow
	PaperDollFrame.EquipmentManagerPane = nil
	CharacterFrame.RightPaneToggleButton = nil
	_G.PaperDollSidebarTab1, _G.PaperDollSidebarTab2, _G.PaperDollSidebarTab3, _G.GetPaperDollSideBarFrame = nil, nil, nil, nil
	UI:Hide(); ns.Secure.Disarm()
	C_Item.GetItemCount = saveCount
	_G.C_EquipmentSet = nil
	ns.providers.equipmentset._dirty = true
end
do -- reputations: searchable, with standing and progress; collapsed headers read too
	local FACTIONS = {
		{ name = "Alliance", isHeader = true, isCollapsed = false },
		{ name = "Stormwind", factionID = 72, reaction = 6, currentReactionThreshold = 9000, nextReactionThreshold = 21000, currentStanding = 12000 },
		{ name = "Classic", isHeader = true, isCollapsed = true },
		{ name = "Argent Dawn", factionID = 529, reaction = 7, currentReactionThreshold = 21000, nextReactionThreshold = 42000, currentStanding = 30000, isWatched = true },
		{ name = "Timbermaw Hold", factionID = 576, reaction = 2, currentReactionThreshold = -6000, nextReactionThreshold = -3000, currentStanding = -4500 },
	}
	local function visible()
		local out, hide = {}, false
		for _, f in ipairs(FACTIONS) do
			if f.isHeader then out[#out + 1] = f; hide = f.isCollapsed
			elseif not hide then out[#out + 1] = f end
		end
		return out
	end
	local watched
	_G.C_Reputation = {
		GetNumFactions = function() return #visible() end,
		GetFactionDataByIndex = function(i) return visible()[i] end,
		ExpandFactionHeader = function(i) visible()[i].isCollapsed = false end,
		CollapseFactionHeader = function(i) visible()[i].isCollapsed = true end,
		SetWatchedFactionByID = function(id) watched = id end,
	}
	_G.FACTION_STANDING_LABEL2, _G.FACTION_STANDING_LABEL6, _G.FACTION_STANDING_LABEL7 = "Hostile", "Honored", "Revered"
	ns.providers.reputation._dirty = true
	local reps = names(ns:GetEntries(ns.providers.reputation))
	check(reps["Stormwind"] and reps["Stormwind"].detail == "Honored  3000/12000", "standing and progress shown: " .. tostring(reps["Stormwind"] and reps["Stormwind"].detail))
	check(reps["Argent Dawn"] and reps["Argent Dawn"].detail == "Revered  9000/21000  watched", "factions under a collapsed header are read too")
	check(reps["Timbermaw Hold"] and reps["Timbermaw Hold"].detail:find("Hostile", 1, true), "low standings too")
	check(not reps["Alliance"], "plain headers aren't listed")
	check(FACTIONS[3].isCollapsed == true, "the collapsed header is collapsed again after reading")
	check(ns:ResolveProvider("reputation").id == "reputation" and ns:ResolveProvider("rep").id == "reputation", "@reputation and @rep")
	local r = UI:Search("revered")
	check(r[1] and r[1].name == "Argent Dawn", "searchable by standing")
	r = UI:Search("@rep stormwind")
	check(r[1] and r[1].name == "Stormwind" and r[1].secure and r[1].secure.binding == "TOGGLECHARACTER2", "Enter opens the Reputation tab through the game's key")
	r[1].secondary(r[1])
	check(watched == 72, "Shift+Enter watches the faction")
	-- after the tab opens: the faction's row is pointed at
	_G.ReputationFrame = Obj("Frame"); ReputationFrame.shown = true
	local row = Obj("Button"); row.shown = true; row.factionID = 72
	ReputationFrame.GetChildren = function() return row end
	local pointed
	local origShow = ns.Highlight.Show
	ns.Highlight.Show = function(self, t) pointed = t; return origShow(self, t) end
	reps["Stormwind"].after(reps["Stormwind"]); FlushAll()
	check(pointed == row, "the faction's row is pointed at")
	ns.Highlight.Show = origShow
	_G.ReputationFrame, _G.C_Reputation = nil, nil
	ns.providers.reputation._dirty = true
end
do -- performance: fast scoring, lazy highlights, top results, narrowing, one search per frame
	local Fz = ns.Fuzzy
	local pairsToCheck = {
		{ "hli", "Heavy Linen Bandage" }, { "fire", "Fireball" }, { "fire", "Greater Fire Protection Potion" },
		{ "lb", "Linen Bandage" }, { "xyz", "Hearthstone" }, { "stone", "Hearthstone" }, { "hs", "Hearthstone" },
		{ "ab", "a b a b" }, { "wolf", "Charred Wolf Meat" }, { "zz", "z" },
	}
	for _, c in ipairs(pairsToCheck) do
		local fast = Fz.score(c[1], c[2])
		local full = Fz.match(c[1], c[2])
		check((fast == nil) == (full == nil), "same matches as before: " .. c[1] .. " / " .. c[2])
		if fast and full and not c[2]:lower():find(c[1], 1, true) then
			check(math.abs(fast - full) < 1e-9, "same score for scattered matches: " .. c[1] .. " / " .. c[2] .. " " .. tostring(fast) .. " vs " .. tostring(full))
		end
	end
	check(Fz.score("fire", "Fireball") > Fz.score("fire", "Greater Fire Protection Potion"), "a match at the start still ranks first")
	-- highlights worked out only for rows on screen
	local saveRows = ns.Theme.Get().rows
	ns.Theme.Set("rows", "4")
	UI:Open("e")
	local res = UI.Results()
	check(#res > 4, "enough results for the test")
	check(res[1]._pos ~= nil and res[#res]._pos == nil, "matched letters are worked out for the rows shown, not for all " .. #res)
	-- narrowing: one more letter rescans only the last matches, same results as a fresh search
	UI:Open("ch")
	UI:SetQuery("cha", 3)
	check(UI.lastSearchNarrowed, "typing one more letter narrows the previous matches")
	local narrowed = {}
	for i, x in ipairs(UI.Results()) do narrowed[i] = x end
	UI.lastScan = nil
	UI:SetQuery("cha", 3); UI:Refresh()
	local freshList = UI.Results()
	local same = #narrowed == #freshList
	for i = 1, math.min(#narrowed, #freshList) do if narrowed[i] ~= freshList[i] then same = false end end
	check(same and not UI.lastSearchNarrowed, "narrowed results are exactly the fresh ones")
	ns.providers.items._dirty = true
	UI:SetQuery("char", 4)
	check(not UI.lastSearchNarrowed, "a list that changed meanwhile is searched in full again")
	-- the best 100 of many matches, in order (heap instead of a full sort)
	local many = {}
	for i = 1, 600 do many[i] = { name = "Test thing " .. i, key = i, text = "perftest" } end
	ns:RegisterProvider("perftest", { label = "Perf", aliases = { "perftest" }, collect = function() return many end })
	local r = UI:Search("@perftest thing")
	check(#r == 100, "top 100 kept: " .. #r)
	local ordered = true
	for i = 2, #r do if r[i - 1]._score < r[i]._score or (r[i - 1]._score == r[i]._score and r[i - 1]._lname > r[i]._lname) then ordered = false end end
	check(ordered, "in order")
	local all = {}
	for _, e in ipairs(ns:GetEntries(ns.providers.perftest)) do all[#all + 1] = e end
	table.sort(all, function(a, b) if a._score ~= b._score then return a._score > b._score end return a._lname < b._lname end)
	check(all[1] == r[1] and all[100] == r[100], "the same 100 a full sort gives")
	check(ns.providers.perftest._entries[1].text == nil and ns.providers.perftest._entries[1]._ltext == "perftest", "searchable text kept once, in lowercase")
	ns.providers.perftest = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "perftest" then table.remove(ns.providerOrder, i) end end
	-- typing faster than a frame: one search for the burst
	local realGT = _G.GetTime
	_G.GetTime = function() return 4242 end
	UI.refreshedAt = nil
	UI:SetQuery("hea", 3)
	local first = UI.Results()[1]
	UI:SetQuery("hearth", 6)
	check(UI.refreshQueued, "a second search in the same frame waits for the next frame")
	_G.GetTime = realGT
	FlushAll()
	check(not UI.refreshQueued and UI.Results()[1] and UI.Results()[1].name == "Hearthstone", "and then runs once with the latest text")
	-- events right after a collect still count, a moment later
	local P = ns.providers.items
	ns:GetEntries(P)
	P._dirty = false
	ef.scripts.OnEvent(ef, "BAG_UPDATE_DELAYED")
	check(P._dirty == false, "within the guard: not yet")
	FlushAll()
	check(P._dirty == true, "a bag change right after a search isn't lost")
	-- .mem
	local m = ns.commands.mem.run()
	check(m[1]:find("Terminal memory", 1, true) and table.concat(m, "\n"):find("entries in all", 1, true), ".mem reports memory and entries: " .. m[1])
	ns.Theme.Set("rows", tostring(saveRows))
	UI:Hide()
end
do -- bag sub-kinds: @consumable and @mats
	local saveInst = C_Item.GetItemInfoInstant
	local saveBag = bags[0]
	C_Item.GetItemInfoInstant = function(id)
		if id == 8001 then return id, "Consumable", "Potion", nil, nil, 0, 1 end
		if id == 8002 then return id, "Trade Goods", "Cloth", nil, nil, 7, 5 end
		if id == 8003 then return id, "Consumable", "Food & Drink", nil, nil, 0, 5 end
		return id, "Miscellaneous", "Junk", nil, nil, 15, 0
	end
	local function item(id, nm, n) return { itemID = id, itemName = nm, iconFileID = 1, stackCount = n or 1, quality = 1, hyperlink = "|Hitem:" .. id .. "|h[" .. nm .. "]|h" } end
	bags[0] = { item(8001, "Minor Healing Potion", 5), item(8002, "Linen Cloth", 20), item(8003, "Tough Jerky", 3), item(8004, "Broken Fang") }
	ns.providers.items._dirty = true
	ns.providers.consumables._dirty = true
	ns.providers.mats._dirty = true
	local cons = names(ns:GetEntries(ns.providers.consumables))
	check(cons["Minor Healing Potion"] and cons["Tough Jerky"] and not cons["Linen Cloth"] and not cons["Broken Fang"], "@consumable: potions and food only")
	check(cons["Minor Healing Potion"].detail == "Potion  x5  Backpack", "sub-type, count and bag shown: " .. tostring(cons["Minor Healing Potion"].detail))
	local mats = names(ns:GetEntries(ns.providers.mats))
	check(mats["Linen Cloth"] and not mats["Minor Healing Potion"], "@mats: crafting materials only")
	check(ns:ResolveProvider("consumable").id == "consumables" and ns:ResolveProvider("craftingmats").id == "mats" and ns:ResolveProvider("potion").id == "consumables", "@consumable, @craftingmats, @potion")
	local r = UI:Search("@consumable heal")
	check(r[1] and r[1].name == "Minor Healing Potion" and r[1].kind == "consumables", "@consumable search")
	local plain = UI:Search("linen cloth")
	local kinds = {}
	for _, x in ipairs(plain) do if x.name == "Linen Cloth" then kinds[#kinds + 1] = x.kind end end
	check(#kinds == 1 and kinds[1] == "items", "plain search shows it once, as an Item: " .. table.concat(kinds, ","))
	local itemEntry = names(ns:GetEntries(ns.providers.items))["Linen Cloth"]
	check(itemEntry.kind == "items", "the Item entry keeps its own kind")
	C_Item.GetItemInfoInstant = saveInst
	bags[0] = saveBag
	ns.providers.items._dirty, ns.providers.consumables._dirty, ns.providers.mats._dirty = true, true, true
end
do -- skills: searchable with rank; collapsed groups read too
	local LINES = {
		{ name = "Weapon Skills", isHeader = true, isExpanded = true },
		{ name = "Swords", rank = 120, maxRank = 130, modifier = 5, skillID = 43, description = "Allows the use of swords." },
		{ name = "Languages", isHeader = true, isExpanded = false },
		{ name = "Orcish", rank = 300, maxRank = 300, skillID = 109 },
	}
	local function visible()
		local out, hide = {}, false
		for _, l in ipairs(LINES) do
			if l.isHeader then out[#out + 1] = l; hide = not l.isExpanded
			elseif not hide then out[#out + 1] = l end
		end
		return out
	end
	_G.C_SkillInfo = {
		GetNumSkillLines = function() return #visible() end,
		GetSkillLineInfo = function(i) return visible()[i] end,
		ExpandSkillHeader = function(i) visible()[i].isExpanded = true end,
		CollapseSkillHeader = function(i) visible()[i].isExpanded = false end,
	}
	ns.providers.skills._dirty = true
	local sk = names(ns:GetEntries(ns.providers.skills))
	check(sk["Swords"] and sk["Swords"].detail == "120/130 (+5)  Weapon Skills", "rank, bonus and group shown: " .. tostring(sk["Swords"] and sk["Swords"].detail))
	check(sk["Orcish"] and sk["Orcish"].detail == "300/300  Languages", "skills in a collapsed group are read too")
	check(LINES[3].isExpanded == false, "the collapsed group is collapsed again")
	check(not sk["Languages"], "group headers aren't listed")
	check(ns:ResolveProvider("skill").id == "skills" and ns:ResolveProvider("skills").id == "skills", "@skill and @skills")
	local r = UI:Search("swords")
	check(r[1] and r[1].name == "Swords" and r[1].kind == "skills", "found by name")
	check(r[1].secure and r[1].secure.binding == "TOGGLECHARACTER1", "Enter opens the Skills tab through the game's key")
	local out = {}
	local baseOut = ns.Output
	ns.Output = function(_, lines) for _, l in ipairs(lines) do out[#out + 1] = l end end
	r[1].secondary(r[1])
	ns.Output = baseOut
	check(out[1] == "Swords: 120/130 (+5)  (Weapon Skills)" and out[2] and out[2]:find("swords", 1, true), "Shift+Enter prints rank and description: " .. table.concat(out, " | "))
	_G.SkillsFrame = Obj("Frame"); SkillsFrame.shown = true
	local row = Obj("Button"); row.shown = true; row.text = "Swords"
	SkillsFrame.GetChildren = function() return row end
	local pointed
	local origShow = ns.Highlight.Show
	ns.Highlight.Show = function(self, t) pointed = t; return origShow(self, t) end
	sk["Swords"].after(sk["Swords"]); FlushAll()
	check(pointed == row, "the skill's row is pointed at on the Skills tab")
	ns.Highlight.Show = origShow
	_G.SkillsFrame, _G.C_SkillInfo = nil, nil
	ns.providers.skills._dirty = true
end
do -- motion: fade/drift in and out, gliding selection, rows fading in
	local Th = ns.Theme
	Th.Get().animations = true
	local M = UI.motion
	local t0 = 500
	local realGT = _G.GetTime
	local clock = t0
	_G.GetTime = function() return clock end
	local function step(dt) clock = clock + dt; if M.shown ~= false then M.scripts.OnUpdate(M, dt) end end
	local F = _G.TerminalFrame
	UI:Hide(); for _ = 1, 20 do step(0.05) end -- start from closed
	UI:Open("heart")
	check(F.alpha == 0 and UI:IsShown(), "opening starts transparent")
	step(0.09)
	check(F.alpha > 0.5 and F.alpha < 1, "fading in: " .. tostring(F.alpha))
	step(0.2)
	check(F.alpha == 1 and UI.phase == nil, "fully in after the fade")
	-- typing: rows that stay just change text; new rows fade in; the terminal grows and
	-- shrinks to fit instead of repainting
	UI:SetQuery("hearthstone", 11); step(0.5)
	local few = #UI.Results()
	local hFew = F.h
	local rr = UI.rows
	UI:SetQuery("e", 1)
	local many = math.min(#UI.Results(), ns.Theme.Get().rows)
	check(many > few, "a broader search shows more rows (" .. few .. " -> " .. many .. ")")
	check(rr[1].fadeAt == nil and (rr[1].alpha or 1) == 1, "a row that stays isn't faded out and back in")
	check(rr[few + 1].fadeAt and (rr[few + 1].alpha or 1) == 0, "a new row starts invisible")
	check(F.h == hFew, "the terminal doesn't jump to the new size")
	step(0.03)
	check(F.h > hFew and F.h < UI.heightTo, "it grows toward it: " .. F.h .. " -> " .. UI.heightTo)
	check(rr[few + 1].alpha > 0 and (rr[many].alpha or 0) <= rr[few + 1].alpha, "new rows fade in one after another")
	step(0.6)
	check(math.abs(F.h - UI.heightTo) < 0.01 and rr[many].alpha == 1, "then everything sits at its new size")
	local hMany = F.h
	UI:SetQuery("hearthstone", 11)
	check(rr[many].leaving and rr[many]:IsShown(), "rows no longer needed fade out rather than vanish")
	step(0.03)
	check(F.h < hMany and F.h > UI.heightTo, "and the terminal shrinks over them")
	step(0.6)
	check(not rr[many]:IsShown() and math.abs(F.h - hFew) < 0.01, "back to the smaller size, extra rows gone")
	-- selection glides
	UI:Open("e")
	step(0.5)
	local y0 = UI.selY
	UI:Move(1)
	check(UI.selTo ~= y0 and UI.selY == y0, "selection band starts where it was")
	step(0.02)
	check(UI.selY ~= y0 and UI.selY ~= UI.selTo, "and glides toward the new row")
	step(0.5)
	check(math.abs(UI.selY - UI.selTo) < 0.01, "arrives at the selected row")
	-- closing: closed at once for everything else, fading only for the eye
	UI:Hide()
	check(not UI:IsShown() and F.shown == true and F.kb == false and not UI.keys, "closing: counts as closed and lets go of the keyboard at once")
	step(0.06)
	check(F.alpha < 1 and F.alpha > 0, "fading out")
	step(0.2)
	check(F.shown == false and F.alpha == 1, "hidden after the fade, back at rest")
	-- reopening mid-fade picks up where it was
	UI:Open("heart"); step(0.3)
	UI:Hide(); step(0.04)
	UI:Open("heart")
	check(UI:IsShown() and F.shown == true and UI.phase == "open" and not UI.closing, "reopening mid-fade goes straight back in")
	step(0.3)
	-- animations off: everything snaps
	Th.Set("animations", "off")
	UI:Hide()
	check(F.shown == false, "animations off: closes at once")
	UI:Open("heart")
	check(F.alpha == 1 and UI.phase == nil, "animations off: opens at once")
	Th.Set("animations", "on")
	UI:Hide(); for _ = 1, 10 do step(0.05) end
	_G.GetTime = realGT
end
do -- Tab completion, shell style
	local function q() return UI.edit:GetText() end
	local function tab(text)
		UI:Open(text)
		key("TAB")
		return q()
	end
	check(tab(".th") == ".theme ", "command name: " .. q())
	check(tab(".theme dr") == ".theme dracula ", "command argument: " .. q())
	check(tab(".set anim") == ".set animations ", "setting name: " .. q())
	check(tab(".set frame cl") == ".set frame classic ", "setting value: " .. q())
	check(tab(".deb") == ".debug " and tab(".debug cl") == ".debug clear ", "debug subcommands: " .. q())
	check(tab("@equ") == "@equip", "several kinds (@equipped, @equipment...): Tab fills in what they share: " .. q())
	check(tab("@equipm") == "@equipment", "then further: " .. q())
	check(tab("@rep") == "@rep", "nothing more shared: unchanged: " .. q())
	check(tab("@reput") == "@reputation", "@reputation(s): " .. q())
	check(tab("@outf") == "@outfit", "@outfit(s): " .. q())
	check(tab("@questd") == "@questdb " or tab("@flig") == "@flight ", "a single kind completes, with a space: " .. q())
	check(tab("/rel") == "/reload ", "slash command: " .. q())
	UI:Open("hearth")
	check(UI.ghost.shown ~= false and UI.ghost:GetText() == "stone", "the rest of the selected result shows faintly: " .. tostring(UI.ghost:GetText()))
	key("TAB")
	check(q() == "Hearthstone", "Tab completes to the selected result's name: " .. q())
	check(not UI.ghost:IsShown(), "nothing left to suggest")
	UI:Open("@item hearth")
	key("TAB")
	check(q() == "@item Hearthstone", "a leading @kind is kept: " .. q())
	UI:Open("hearth")
	key("RIGHT")
	check(q() == "Hearthstone", "Right arrow at the end takes the suggestion too")
	-- nothing to complete: Tab moves down the list, as before
	UI:Open("e")
	local before = UI.selIndex and UI.selIndex() or nil
	key("TAB")
	check(q() == "e", "nothing to complete: text unchanged")
	UI:Hide()
end
do -- classic quest log: the quest is selected (and scrolled to) the way a click does
	local picked
	local saveIdx = C_QuestLog.GetLogIndexForQuestID
	C_QuestLog.GetLogIndexForQuestID = function(id) return id == 33 and 2 or nil end
	_G.QuestLog_SetSelection = function(i) picked = i end
	local q = names(ns:GetEntries(ns.providers.quests))["Wolves Across the Border"]
	q.after(q); FlushAll()
	check(picked == 2, "quest selected in the classic quest log by its log index")
	_G.QuestLog_SetSelection = nil
	C_QuestLog.GetLogIndexForQuestID = saveIdx
end
do -- quest items are tied to their quests without any other addon
	local saveBag0, saveQuests = bags[0], {}
	for i = 1, #quests do saveQuests[i] = quests[i] end
	local saveObj, saveText, saveInst, saveSecret, saveQI = C_QuestLog.GetQuestObjectives, GetQuestLogQuestText, C_Item.GetItemInfoInstant, _G.issecretvalue, C_Container.GetContainerItemQuestInfo
	C_Container.GetContainerItemQuestInfo = nil
	for i = #quests, 1, -1 do quests[i] = nil end
	quests[1] = { title = "Westfall", isHeader = true }
	quests[2] = { title = "Bone Collector", questID = 44 }
	quests[3] = { title = "Sharpening Blades", questID = 55 }
	quests[4] = { title = "Lost Ledger", questID = 66 }
	quests[5] = { title = "Darthalia\226\128\153s Orders", questID = 77 }
	quests[6] = { title = "Cartography", questID = 88 }
	quests[7] = { title = "Scout Support", questID = 99 }
	local OBJ = { [44] = { { text = "Bring me 8 Bone Saw Fragments", type = "monster" } },
		[55] = { { text = "Moonstone Shard: 0/4", type = "item" } },
		[66] = { { text = "SECRET", type = "item" } },
		[99] = { { text = "Scout the road: 0/3", type = "monster" } },
		[88] = { { text = "Piece together the frayed scrap of a map", type = "object" } },
		[77] = { { text = "Deliver Darthalia\226\128\153s Orders to Thrall", type = "object" } } }
	C_QuestLog.GetQuestObjectives = function(id) return OBJ[id] end
	_G.issecretvalue = function(v) return v == "SECRET" end
	GetQuestLogQuestText = function(i)
		if i == 7 then return "Darthalia needs scouts to report on the road.", "" end
		if i == 4 then return "Find the old ledger in the cellar. Also bring linen cloth.", "" end
		return "Nothing of note.", ""
	end
	C_Item.GetItemInfoInstant = function(id)
		if id == 7003 or id == 7006 then return id, "Quest", "Quest", nil, nil, 12 end
		return id, "Miscellaneous", "Junk", nil, nil, 15
	end
	local function item(id, nm) return { itemID = id, itemName = nm, iconFileID = 1, stackCount = 1, quality = 1, hyperlink = "|Hitem:" .. id .. "|h[" .. nm .. "]|h" } end
	bags[0] = { item(7001, "Bone Saw Fragment"), item(7002, "Moonstone Shard"), item(7003, "Old Ledger"), item(2589, "Linen Cloth"), item(7004, "Darthalia's Orders"), item(7005, "Frayed Map Scrap"), item(7006, "Darthalia's Writ"), item(7007, "Sealed Parchment") }
	ns.providers.items._dirty = true
	ns.providers.quests._dirty = true
	local it = names(ns:GetEntries(ns.providers.items))
	check(it["Bone Saw Fragment"].questID == 44, "name inside an objective's text (singular vs plural): " .. tostring(it["Bone Saw Fragment"].questID))
	check(it["Moonstone Shard"].questID == 55, "item objective by name")
	check(it["Old Ledger"].questID == 66, "quest-class item found in the quest's description (secret objective ignored)")
	check(it["Linen Cloth"].questID == nil, "an ordinary item named in a description isn't tied to the quest")
	local r = UI:Search("bone saw")
	check(r[1].name == "Bone Saw Fragment" and r[2] and r[2].name == "Bone Collector", "search brings the quest along: " .. tostring(r[2] and r[2].name))
	r = UI:Search("old ledger")
	check(r[1].name == "Old Ledger" and r[2] and r[2].name == "Lost Ledger", "quest-class item brings its quest")
	r = UI:Search("linen")
	check(r[1].name == "Linen Cloth" and not (r[2] and r[2].name == "Lost Ledger"), "no quest dragged in right after an ordinary item")
	check(it["Darthalia's Orders"] and it["Darthalia's Orders"].questID == 77, "curly vs straight apostrophe still ties the item to its quest")
	r = UI:Search("darthalias orders")
	check(r[1].name == "Darthalia's Orders" and r[2] and r[2].questID == 77 and r[2].kind == "quests", "item first, its quest right below: " .. tostring(r[1].name) .. " / " .. tostring(r[2] and r[2].name))
	check(UI.linked[r[2]] == r[1], "the quest row is marked as brought along by the item (drawn with an arrow)")
	check(it["Frayed Map Scrap"] and it["Frayed Map Scrap"].questID == 88, "all words of the item name found in one quest's objective")
	local w = it["Darthalia's Writ"]
	check(w and not w.questID and w.guessIDs and #w.guessIDs >= 1, "no sure quest: the likeliest ones are suggested")
	local hasScout = false
	for _, id in ipairs(w.guessIDs or {}) do if id == 99 then hasScout = true end end
	check(hasScout, "the suggestion includes the quest whose text mentions Darthalia")
	r = UI:Search("darthalia's writ")
	local pos = {}
	for i, x in ipairs(r) do pos[x.name] = i end
	check(pos["Darthalia's Writ"] and pos["Scout Support"] and pos["Scout Support"] > pos["Darthalia's Writ"] and pos["Scout Support"] <= pos["Darthalia's Writ"] + 2, "suggested quest sits right under the item")
	check(UI.linkedGuess[r[pos["Scout Support"]]] == true, "a suggestion is marked as a guess (drawn as 'maybe needs')")
	check(it["Linen Cloth"].guessIDs == nil, "ordinary items get no suggestions")
	-- Questie knows better than the log text
	check(it["Sealed Parchment"].questID == nil, "no link without Questie")
	_G.Questie = { API = { isReady = true } }
	_G.QuestieLoader = { ImportModule = function(_, n) return n == "QuestieDB" and {
		QueryQuestSingle = function(id, f) if id == 99 and f == "requiredSourceItems" then return { 7007 } end end,
	} or nil end }
	ns.providers.items._dirty = true
	it = names(ns:GetEntries(ns.providers.items))
	check(it["Sealed Parchment"].questID == 99, "Questie: the quest needs this item")
	_G.Questie, _G.QuestieLoader = nil, nil
	check(not ns.commands.questitems, "no > questitems command")
	-- restore
	bags[0] = saveBag0
	for i = #quests, 1, -1 do quests[i] = nil end
	for i = 1, #saveQuests do quests[i] = saveQuests[i] end
	C_QuestLog.GetQuestObjectives, GetQuestLogQuestText, C_Item.GetItemInfoInstant, _G.issecretvalue, C_Container.GetContainerItemQuestInfo = saveObj, saveText, saveInst, saveSecret, saveQI
	ns.providers.items._dirty = true
	ns.providers.quests._dirty = true
end

do -- OpenRecipe blocked once, then left alone
	local P, D = ns.Professions, ns.Debug
	local base, n = C_TradeSkillUI.OpenRecipe, 0
	C_TradeSkillUI.OpenRecipe = function() n = n + 1; D.frame.scripts.OnEvent(D.frame, "ADDON_ACTION_BLOCKED", "Terminal", "UNKNOWN()") end
	ns.db.blockedCalls = nil
	check(P.Guarded("OpenRecipe", C_TradeSkillUI.OpenRecipe, 1) == false and ns.db.blockedCalls.OpenRecipe, "blocked OpenRecipe remembered")
	P.Guarded("OpenRecipe", C_TradeSkillUI.OpenRecipe, 1)
	check(n == 1, "OpenRecipe not called again after a block")
	C_TradeSkillUI.OpenRecipe = base
	ns.db.blockedCalls = nil
	for i = #D.events, 1, -1 do D.events[i] = nil end
	for i = #D.trace, 1, -1 do D.trace[i] = nil end
end

do -- debug / blocked-action recording
	local D = ns.Debug
	check(D and D.frame and D.frame.scripts.OnEvent, "debug frame listens")
	local cv, cvlog = { taintLog = "0", scriptErrors = "0" }, {}
	_G.GetCVar = function(n) return cv[n] end
	_G.ConsoleExec = function(c) local n, v = c:match("^(%S+) (%S+)$"); cv[n] = v; cvlog[#cvlog + 1] = c end
	_G.debugstack = function() return "Interface\\AddOns\\Terminal\\UI.lua:700: in function Activate\nsecond line" end
	local real, printed = _G.print, {}
	_G.print = function(...) local t = {}; for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end; printed[#printed + 1] = table.concat(t, " ") end
	local function out() return table.concat(printed, "\n") end
	local function fire(addon, fn) D.frame.scripts.OnEvent(D.frame, "ADDON_ACTION_FORBIDDEN", addon, fn) end

	ns:Trace("DIRECT activate: Charred Wolf Meat")
	fire("Terminal", "ToggleTalentFrame()")
	check(#D.events == 1 and D.events[1].addon == "Terminal", "event recorded")
	check(table.concat(D.events[1].recent, "\n"):find("DIRECT activate: Charred Wolf Meat", 1, true), "event carries what Terminal was doing")
	check(out():find("Type /term .debug log", 1, true), "own blocked action prints a short pointer even with debug off")
	check(not out():find("trace:", 1, true), "no live trace printing when debug is off")

	printed = {}
	ns.commands.debug.run("on")
	check(ns.db.debug == true and cv.taintLog == "2" and cv.scriptErrors == "1", "debug on sets taintLog 2 + scriptErrors")
	printed = {}
	ns:Trace("secure: armed Enter -> TOGGLEQUESTLOG")
	check(out():find("trace: secure: armed", 1, true), "live trace line while debug is on")
	printed = {}
	fire("SomeOtherAddon", "SomeProtectedFunc()")
	check(out():find("SomeOtherAddon", 1, true) and out():find("SomeProtectedFunc", 1, true), "other addons' events print in debug mode")
	check(out():find("Stack:", 1, true), "stack included")
	local lines = ns.commands.debug.run("log")
	local CB = ns.CopyBox
	check(table.concat(lines, "\n"):find("opened in a window", 1, true), "log says it opened a window: " .. table.concat(lines, "|"))
	check(CB.Text():find("2 blocked-action event", 1, true) and CB.Text():find("Terminal trace", 1, true) and CB.Text():find("Terminal 0.", 1, true),
		"the log window holds the events, the trace and the version: " .. CB.Text():sub(1, 160))
	check(CB.frame.shown == true and CB.edit.text == CB.Text(), "the window shows the text in its text box")
	-- all selected once it has focus, so Ctrl+C copies everything
	local hl = 0
	CB.edit.HighlightText = function() hl = hl + 1 end
	FlushAll()
	check(CB.edit.focused == true and hl >= 1, "the text box takes focus with everything selected")
	-- read-only: typing is put back
	CB.edit.text = "oops"; CB.edit.scripts.OnTextChanged(CB.edit, true)
	check(CB.edit.text == CB.Text(), "typing into the log window is undone")
	CB.edit.scripts.OnEscapePressed(CB.edit)
	check(CB.frame.shown == false, "Esc closes the log window")
	CB.edit.HighlightText = nil
	local brief = ns.commands.debug.run("")
	check(table.concat(brief, "\n"):find("blocked-action", 1, true) and not CB.frame.shown, ".debug alone stays in chat")
	-- real flows leave a trace
	local ok = pcall(function() ns.UI:Search("heart") end)
	ns.commands.debug.run("off")
	check(ns.db.debug == false and cv.taintLog == "0" and cv.scriptErrors == "0", "debug off restores the cvars")
	ns.commands.debug.run("clear")
	check(#D.events == 0 and #D.trace == 0, "clear empties both")
	check(ns.commands.taint == nil and ns.commands.debug.aliases[1] == "taintdebug", "aliases declared")
	_G.print = real
end

-- text cursor styles
do
	local Th = ns.Theme
	local function ratio(a, b)
		local function lin(c) return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
		local function lum(h) local r, g, b2 = Th.RGB(h) return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b2) end
		local x, y = lum(a), lum(b)
		if x < y then x, y = y, x end
		return (x + 0.05) / (y + 0.05)
	end
	local function cmd(line) local c = UI:WordSearch(UI:CommandEntries(), line); return c[1].activate(c[1], UI.args) end
	local function idle(n) for _ = 1, n do now = now + 0.05; UI.motion.scripts.OnUpdate(UI.motion, 0.05) end end
	local function setCursor(c) Th.Set("cursor", c); if UI:IsShown() then UI:UpdateCaret() end end

	check(Th.Get().cursor == "blinking-line", "default cursor is the blinking line")
	cmd("set cursor solid-box"); check(Th.Get().cursor == "solid-box", ".set cursor solid-box")
	cmd("set cursor blinking-box"); check(Th.Get().cursor == "blinking-box", ".set cursor blinking-box")
	cmd("set cursor nonsense"); check(Th.Get().cursor == "blinking-box", "an unknown cursor is refused")
	check(#Th.CURSOR_ORDER == 4 and Th.CURSOR_LABELS["solid-line"] == "Solid line", "four cursor styles with labels")
	cmd("set cursor blinking-line")

	-- the letter under a box is drawn in a colour that reads on the accent, in every theme
	for _, id in ipairs(Th.PRESET_ORDER) do
		local P = Th.PRESETS[id]
		local c = Th.OnColor(P.accent, P.bg)
		check(ratio(c, P.accent) >= 4.5 or ratio(c, P.accent) >= math.max(ratio("000000", P.accent), ratio("ffffff", P.accent)) - 0.01,
			id .. " box text colour is the best available on the accent: " .. c)
	end
	check(Th.OnColor("ffffff", "000000") == "000000", "dark text on a white box")
	check(Th.OnColor("101010", "ffffff") == "ffffff", "light text on a dark box")
	check(Th.OnColor("808080", "ffffff") ~= "ffffff", "the preferred colour is dropped when it can't be read")

	UI:Open(""); typeText("hello")
	for _ = 1, 3 do key("LEFT") end -- caret between "he" and "llo"
	local C, CC = UI.caret, UI.caretChar
	setCursor("blinking-line"); idle(40)
	check(C.w == 2 and CC.shown == false, "a line is 2 wide and draws no letter")
	local lo, hi = 1, 0
	for i = 1, 60 do idle(1); local a = C:GetAlpha(); lo = math.min(lo, a); hi = math.max(hi, a) end
	check(lo < 0.4 and lo > 0 and hi > 0.95, "a line fades softly and never vanishes: " .. lo .. ".." .. hi)

	setCursor("solid-line"); idle(40)
	for i = 1, 40 do idle(1); check(C:GetAlpha() == 1, "a solid line never changes") end
	check(UI.motion.shown == false, "a solid cursor lets the motion loop rest")

	setCursor("solid-box"); idle(40)
	check(C.w == 7 and CC.shown == true and CC.text == "l", "a box is one letter wide and redraws the letter under it: " .. tostring(CC.text))
	local oc = Th.OnColor(Th.Get().accent, Th.Get().bg)
	local r, g, b = Th.RGB(oc)
	check(CC.textColor and math.abs(CC.textColor[1] - r) < 0.01 and math.abs(CC.textColor[3] - b) < 0.01, "in the contrast colour")
	check(ratio(oc, Th.Get().accent) >= 3, "which reads on the box")
	for i = 1, 40 do idle(1); check(C:GetAlpha() == 1 and CC:GetAlpha() == 1, "a solid box stays on") end
	check(UI.motion.shown == false, "and rests")
	key("LEFT"); check(CC.text == "e", "the box moves and shows the next letter")
	key("HOME"); check(CC.text == "h", "the letter at the start")
	key("END"); check(CC.text == "" or CC.shown == false, "no letter at the end of the text: '" .. tostring(CC.text) .. "'")
	check(C.w >= 6, "an empty box still has width")

	setCursor("blinking-box"); idle(40)
	local off, on = false, false
	for i = 1, 80 do idle(1); local a = C:GetAlpha(); if a == 0 then off = true end; if a == 1 then on = true end; check(CC:GetAlpha() == a, "the letter blinks with the box") end
	check(off and on, "a blinking box goes fully off and fully on")
	typeText("x"); check(C:GetAlpha() == 1, "typing makes the box solid again")

	-- blink speed: twice the rate, about twice the blinks in the same time
	local function blinks(rate)
		Th.Set("blinkRate", rate); UI:UpdateCaret(); idle(30)
		local n, prev = 0, nil
		for _ = 1, 100 do
			idle(1)
			local on = C:GetAlpha() > 0.5
			if prev ~= nil and on ~= prev then n = n + 1 end
			prev = on
		end
		return n
	end
	setCursor("blinking-box")
	local slow, fast = blinks(0.8), blinks(2.4)
	check(slow >= 3 and fast >= slow * 2, "a higher blink speed blinks faster: " .. slow .. " vs " .. fast)
	check(Th.Set("blinkRate", 9) and Th.Get().blinkRate == 3 and Th.Set("blinkRate", 0) and Th.Get().blinkRate == 0.2, "blink speed is kept between 0.2 and 3")
	cmd("set blinkRate 1.5"); check(Th.Get().blinkRate == 1.5, ".set blinkRate")
	Th.Set("blinkRate", 0.8)

	-- at the end of a ".command" the box sits on the first letter of the suggestion
	UI:SetQuery(".hel", 4); setCursor("solid-box")
	check(CC.shown == true and CC.text ~= "" and CC.textColor[4] < 1, "the suggestion's first letter shows in the box, dimmed: '" .. tostring(CC.text) .. "'")
	UI:Hide()
	check(C.shown == false and CC.shown == false, "closing hides the cursor")
	Th.Set("cursor", "blinking-line")
end

io.write(fails == 0 and "ALL SMOKE TESTS PASSED\n" or (fails .. " FAILURES\n"))
