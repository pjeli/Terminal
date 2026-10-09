-- (the runaway guard: the main run had grown to ~19.9M instructions by 0.44.10, so it gets 40M; each extra file 20M)
debug.sethook(function() error("INSTRUCTION LIMIT HIT\n" .. debug.traceback(), 2) end, "", 40000000)
-- Minimal WoW API stub, enough to load every file and exercise collect/search/activate.
local log = {}
local function note(...) log[#log + 1] = table.concat({ ... }, " ") end

_G.UNKNOWN_FRAME_METHODS = {} -- method names the mock answered with a no-op (printed at the end of the run)
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
		-- any other method is a silent no-op; its name is noted so the run can list what the mock doesn't know
		if type(k) == "string" and k:match("^%u") then UNKNOWN_FRAME_METHODS[k] = true end
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

-- console settings (@cvar)
local CVARS = { nameplateMaxDistance = { "41", "60", "Max distance nameplates are shown" }, ffxGlow = { "1", "1", "" },
	cameraDistanceMaxZoomFactor = { "2.6", "1.9", "" }, lockedOne = { "1", "1", "", true } }
_G.C_Console = { GetAllCommands = function()
	-- the command type isn't to be trusted on this client: settings are what has a value
	if CVARS_EMPTY then return {} end
	if CVARS_FAIL then error("not allowed") end
	return { { command = "nameplateMaxDistance", commandType = 3, category = 1, help = CVARS.nameplateMaxDistance[3] },
		{ command = "ffxGlow", category = 2, help = "" },
		{ command = "cameraDistanceMaxZoomFactor", commandType = 0, category = 5 },
		{ command = "lockedOne", commandType = 0 },
		{ command = "reloadui", commandType = 0, help = "a command, not a setting" } }
end }
_G.C_CVar = {
	GetCVarInfo = function(n) local c = CVARS[n] if c then return c[1], c[2], false, false, false, false, c[4] or false end end,
	GetCVar = function(n) return CVARS[n] and CVARS[n][1] end, GetCVarDefault = function(n) return CVARS[n] and CVARS[n][2] end,
}

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
		if id == 11 then return { outputItemID = 777, reagentSlotSchematics = { { quantityRequired = 2, reagents = { { itemID = 100 } } } } } end
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
-- (the tests before easy mode run in hard mode, the full command line; tests/smoke/easy.lua tries easy mode)
assert(ns.Easy and ns.Easy.On(), "a fresh install starts in easy mode")
ns.db.easyMode = false
ef.scripts.OnEvent(ef, "PLAYER_LOGIN")

io.write("[events fired]\n")
local fails = 0
local function check(c, m) if not c then fails = fails + 1; io.write("FAIL: " .. m .. "\n") end end

-- providers all collect without error and produce entries
for _, id in ipairs(ns.providerOrder) do
	local entries = ns:GetEntries(ns.providers[id])
	io.write(("provider %-13s %d entries\n"):format(id, #entries))
	check(not ns.providers[id]._warned, id .. " provider threw an error")
	check(#entries > 0 or id == "camp" or id == "stored" or id == "gameoptions" or id == "maps" or id == "equipmentset" or id == "reputation" or id == "skills" or id == "consumables" or id == "mats" or id == "gear" or id == "guild" or id == "friends" or id == "who" or id == "lootlog" or id == "combatlog" or id == "experience", id .. " produced no entries") -- camp: only objects you can make; options: needs the Settings panel
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
-- the first open after a /reload can be Alt+` (Advanced for one run): building the frame hides it, and that hide isn't a
-- close (0.44.10: its OnHide ended the run, so it opened in Simple mode). The game fires OnHide on a hide; the mock
-- doesn't, so the terminal's frame does here, while it's built.
do
	local cf, built = _G.CreateFrame, nil
	_G.CreateFrame = function(kind, name, ...)
		local f = cf(kind, name, ...)
		if name == "TerminalFrame" then
			built = f
			f.Hide = function(self)
				local was = self.shown ~= false -- (a new frame is shown in the game)
				self.shown = false
				if was and self.scripts.OnHide then self.scripts.OnHide(self) end
			end
		end
		return f
	end
	ns.db.easyMode = true
	UI:AdvancedOnce()
	_G.CreateFrame = cf
	if built then built.Hide = nil end
	check(UI:IsShown() and ns.Easy.temp ~= nil and not ns.Easy.On(), "the first open after a reload by Alt+`: Advanced for that run")
	UI:Hide(); UI:EndAdvancedOnce()
	ns.db.easyMode = false
end
-- slash mode
UI:Open("/rl now")
local r = UI:WordSearch(ns:GetEntries(ns.providers.slash), "/rl now")
check(r[1] and r[1].name == "/rl" or r[1].name == "/reload", "slash fuzzy match")
check(UI.args == "now", "slash args captured: " .. tostring(UI.args))
r[1].activate(r[1], UI.args)
check(log[#log]:match("^CHAT /re?l"), "slash command executed: " .. tostring(log[#log]))
do -- the slash list is re-read when an addon adds a command, not on every open
	local function hasSlash(n)
		ns.providers.slash._dirty = true
		for _, e in ipairs(ns:GetEntries(ns.providers.slash)) do if e.name == n then return true end end
	end
	local before = ns:GetEntries(ns.providers.slash)
	ns.providers.slash._dirty = true
	check(ns:GetEntries(ns.providers.slash)[1] == before[1], "nothing new: the same list is kept")
	_G.SLASH_NEWTHING1 = "/newthing"; SlashCmdList.NEWTHING = function() end
	check(hasSlash("/newthing"), "a command added by an addon shows up")
	_G.SLASH_NEWTHING1, SlashCmdList.NEWTHING = nil, nil
end

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
	-- a window filling in on its first show hides its parts for a moment: the highlight rides that out
	now = 200
	target.shown = true
	g = H:Show(target)
	now = 200.1; target.shown = false; g.scripts.OnUpdate(g)
	now = 200.2; g.scripts.OnUpdate(g)
	check(g.shown ~= false and g.target == target, "its target hidden for a moment: the highlight waits")
	now = 200.25; target.shown = true; g.scripts.OnUpdate(g)
	check(g.shown ~= false and g.alpha ~= 0, "and shows again when the target does")
	now = 200.3; target.shown = false; g.scripts.OnUpdate(g)
	now = 200.7; g.scripts.OnUpdate(g)
	check(g.shown == false, "a target that stays hidden (the window closed): it lets go")
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
	local e1, e2 = Cc.Entry("3*4"), Cc.Entry("5*6")
	check(e1.activate == e2.activate and e1.secondary == e2.secondary, "calc rows share their Enter/Shift+Enter functions (none made per keystroke)")
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
	-- (0.44.11: the same text every way: the sum and its answer; the game opens the box, this is combat's fallback)
	check(opened == "3*45 = 135" and r[1].secondarySecure, "Shift+Enter puts the sum and answer in the chat box: " .. tostring(opened))
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
check(#fr == 0, "the empty prompt lists nothing (just the bar)")
UI.showRecent = true -- (Down on the bare prompt)
fr = UI:Search("")
UI.showRecent = nil
check(fr[1] and fr[1].name == "Linen Cloth", "frequent items surface on empty query (Down)")

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
check(store[171].list[1].item == 777, "the item a recipe makes is kept (stat:/slot: filters on crafts)")
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
-- a recipe is pointed at (highlighted), never clicked: Terminal's click inside the window would taint the selection
local baseHShow = ns.Highlight.Show
ns.Highlight.Show = function(self, target, ...) if type(target) == "table" and target.text then note("ROWSHOW " .. target.text) end return baseHShow(self, target, ...) end
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
check(seen("OpenTradeSkill 171", m0 + 1) and not seen("OpenRecipe", m0 + 1) and seen("ROWSHOW Mana Well", m0 + 1) and not seen("ROWCLICK Mana Well", m0 + 1), "camp activate opens the profession and points at the recipe (never clicks it)")
m0 = #log
rec["Elixir of Strength"].activate(rec["Elixir of Strength"]); FlushAll()
check(not seen("OpenTradeSkill 171", m0 + 1), "profession already showing: not reopened")
check(not seen("OpenRecipe", m0 + 1) and seen("ROWSHOW Elixir of Strength [3]", m0 + 1) and not seen("ROWCLICK Elixir", m0 + 1), "recipe pointed at by its row (count after the name is fine), not clicked")
-- a recipe further down the list: the list is scrolled to it (no protected OpenRecipe)
ProfessionsFrame.GetChildren = function() return rowMana end -- Elixir's row not built yet
ProfessionsFrame.CraftingPage = { RecipeList = { ScrollBox = { ScrollToElementDataByPredicate = function(_, pred)
	local hit = pred({ GetData = function() return { recipeInfo = { recipeID = 11 } } end })
	note("SCROLLTO " .. tostring(hit))
	if hit then ProfessionsFrame.GetChildren = function() return rowMana, rowElixir end end
end } } }
m0 = #log
rec["Elixir of Strength"].activate(rec["Elixir of Strength"]); FlushAll()
check(seen("SCROLLTO true", m0 + 1) and seen("ROWSHOW Elixir of Strength [3]", m0 + 1) and not seen("OpenRecipe", m0 + 1), "off-screen recipe: list scrolled to it, then its row pointed at")
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
	check(seen("ROWSHOW Mana Well", mm + 1), "after the cast, the camp object's recipe is pointed at")
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

check(UI:WordSearch(UI:CommandEntries(), "camp")[1] == nil or UI:WordSearch(UI:CommandEntries(), "camp")[1].name ~= "camp", "no .camp command any more")
check(ns.commands.scan == nil, "no .scan command any more (professions index at login and from @recipe)")

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
check(pe["Alchemy"].detail == "100/300", "profession rank shown (as skills and reputation write it, 0.44.11)")
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
for i = before + 1, #log do if log[i]:find("Scan finished", 1, true) then finished = true end end
check(finished, "scan reports completion")
check(log[#log - 1] == "CloseTradeSkill" or log[#log]:find("Scan finished", 1, true), "scan closes the window")

-- every search mode still renders with the new providers
for _, q in ipairs({ "@camp", "@recipe", "@prof", "camp", "mana" }) do
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
	local function drag(x) mouseX = x; if H.scripts.OnUpdate then H.scripts.OnUpdate(H, 0.01) end end
	local function up() H.scripts.OnMouseUp(H, "LeftButton") end
	check(not H.scripts.OnUpdate, "nothing runs every frame over the prompt until you press the mouse")
	down(100 + 7 * 5 + 2)
	check(H.scripts.OnUpdate, "pressed: the drag is followed")
	up()
	check(not H.scripts.OnUpdate, "let go: it stops")
	check(UI.cursor == 5 and sel() == nil and UI.keys == true and UI.edit.focused ~= true, "a click puts the cursor between characters and stays in the drawn prompt: " .. tostring(UI.cursor))
	check(UI.caret.shown == true, "the cursor is still Terminal's own")
	-- closed mid-drag: the watcher stops at its next look instead of running on
	down(100 + 7 * 2)
	UI.dragging = false -- (what closing or a focus change does)
	H.scripts.OnUpdate(H, 0.01)
	check(not H.scripts.OnUpdate, "a drag ended some other way: the watcher removes itself")
	up()
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

	-- Shift+Enter on an item: the game uses it (a /use line on the secure macro button)
	UI:Open("hearthstone")
	local hs = UI.Results()[1]
	mark = #log
	_G.IsShiftKeyDown = function() return true end
	key("ENTER")
	_G.IsShiftKeyDown = function() return false end
	local up = _G.TerminalMacroProxy
	check(hs and hs.kind == "items" and S.armed == "MACRO" and up and up.attrs.macrotext == "/use item:" .. tostring(hs.itemID)
		and bindings["ENTER"] == "TerminalMacroProxy" and F.propagate == true,
		"Shift+Enter on an item: the same press goes to the game's /use: " .. tostring(up and up.attrs.macrotext))
	check(not logHas("OpenAllBags", mark + 1), "and the bags aren't opened instead")
	up.scripts.PostClick(up, "LeftButton", true); FlushAll()
	check(not UI:IsShown() and S.armed == nil and next(bindings) == nil, "used: the terminal closes, Enter is free again")
	check(UI.ClickFor(hs, true) == "/use item:" .. tostring(hs.itemID) and UI.ClickFor(hs, false) == nil,
		"Shift+click uses it too; a plain click still shows it in the bags")
	-- in combat the game can't be handed the press: say so, nothing else happens
	local realCombat = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	UI:Open("hearthstone"); mark = #log
	UI:Activate(nil, { secondary = true })
	_G.InCombatLockdown = realCombat
	local saidCantUse = false
	for i = mark + 1, #log do if log[i]:find("can't use Hearthstone", 1, true) then saidCantUse = true end end
	check(saidCantUse and not logHas("OpenAllBags", mark + 1) and S.armed == nil, "in combat: Terminal says it can't use it, and nothing else happens")
	mark = #log
	hs.secondary(hs) -- out of combat, when no secure button could be made
	local saidCombat = false
	for i = mark + 1, #log do if log[i]:find("In combat", 1, true) then saidCombat = true end end
	check(not saidCombat, "out of combat, failing to use an item doesn't claim you're in combat")
	UI:Hide(); FlushAll()

	-- reputation: its own tab command, then the after step checks the tab
	UI:Open("reputation"); mark = #log; key("ENTER")
	check(S.armed == "TOGGLECHARACTER2", "reputation uses the reputation tab command")
	FlushAll()
	check(not logHas("ToggleCharacter ReputationFrame", mark + 1), "after: Terminal's code never switches the character tab (taint)")

	-- the window open on another page: the game's key still runs (it switches page)
	_G.PaperDollFrame = _G.PaperDollFrame or Obj("Frame")
	CharacterFrame.shown = true; PaperDollFrame.shown = false; ReputationFrame.shown = true
	UI:Open("character info"); mark = #log; key("ENTER")
	check(S.armed == "TOGGLECHARACTER0" and not logHas("ToggleCharacter PaperDollFrame", mark + 1),
		"character window open on reputation: Enter still goes to the game's key, which switches page")
	FlushAll()
	-- the page itself showing: nothing to press
	PaperDollFrame.shown = true; ReputationFrame.shown = false
	UI:Open("character info"); key("ENTER")
	check(S.armed == nil and next(bindings) == nil and not UI:IsShown(), "already open: closes and points, no binding")
	CharacterFrame.shown = false; PaperDollFrame.shown = false

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
	-- Shift+Enter on a worn item uses it by its slot (a trinket), even with the character window open
	_G.PaperDollFrame = _G.PaperDollFrame or Obj("Frame")
	CharacterFrame.shown, PaperDollFrame.shown = true, true
	UI:Open("fancy helm")
	local helm = UI.Results()[1]
	_G.IsShiftKeyDown = function() return true end
	key("ENTER")
	_G.IsShiftKeyDown = function() return false end
	check(helm and helm.slotId and S.armed == "MACRO" and _G.TerminalMacroProxy.attrs.macrotext == "/use " .. helm.slotId,
		"Shift+Enter on a worn item: /use its slot: " .. tostring(_G.TerminalMacroProxy.attrs.macrotext))
	_G.TerminalMacroProxy.scripts.PostClick(_G.TerminalMacroProxy, "LeftButton", true); FlushAll()
	CharacterFrame.shown, PaperDollFrame.shown = false, false
	_G.GetInventoryItemLink = function() return nil end
	ns.providers.items._dirty = true

	-- @gear: the equipment among your items, in your bags or worn
	do
		local baseInstant = C_Item.GetItemInfoInstant
		C_Item.GetItemInfoInstant = function(x)
			if x == 2131 then return 2131, "Weapon", "One-Handed Swords", "INVTYPE_WEAPON", 1, 2, 7 end
			if x == 4500 then return 4500, "Container", "Bag", "INVTYPE_BAG", 1, 1, 0 end
			if x == 1 or (type(x) == "string" and x:find("Fancy Helm", 1, true)) then return 1, "Armor", "Plate", "INVTYPE_HEAD", 1, 4, 4 end
			return baseInstant(x)
		end
		_G.INVTYPE_WEAPON, _G.INVTYPE_HEAD = "One-Hand", "Head"
		local saveBag = bags[0]
		bags[0] = { saveBag[1], saveBag[2],
			{ itemID = 2131, itemName = "Worn Shortsword", iconFileID = 1, stackCount = 1, quality = 1, hyperlink = "|Hitem:2131|h[Worn Shortsword]|h" },
			{ itemID = 4500, itemName = "Traveler's Backpack", iconFileID = 1, stackCount = 1, quality = 1, hyperlink = "|Hitem:4500|h[Traveler's Backpack]|h" } }
		_G.GetInventoryItemLink = function(_, slot) if slot == 1 then return "|Hitem:1|h[Fancy Helm]|h" end end
		ns.providers.items._dirty = true; ns.providers.gear._dirty = true
		local gear = names(ns:GetEntries(ns.providers.gear))
		check(gear["Worn Shortsword"] and gear["Fancy Helm"], "@gear: equipment in your bags and worn")
		check(not gear["Hearthstone"] and not gear["Linen Cloth"] and not gear["Traveler's Backpack"], "not other items, nor bags")
		check(gear["Worn Shortsword"].detail:find("^One%-Hand") and gear["Fancy Helm"].detail:find("Equipped", 1, true),
			"its slot shown, and whether it's worn: " .. tostring(gear["Worn Shortsword"].detail) .. " / " .. tostring(gear["Fancy Helm"].detail))
		check(ns.providers.gear.explicit and ns:ResolveProvider("gear") == ns.providers.gear and ns:ResolveProvider("equipment") == ns.providers.equipmentset,
			"@gear only with its @kind (@equipment is the equipment sets)")
		check(names(ns:GetEntries(ns.providers.items))["Worn Shortsword"].kind == "items", "the Item rows keep their own kind")
		check(gear["Worn Shortsword"].detail:find("In Bag", 1, true), "gear in your bags says In Bag: " .. tostring(gear["Worn Shortsword"].detail))
		-- made again whenever the item list is: gear put in your bags after @gear was first built still shows
		-- (built at login before the bags had loaded, it used to show only what you wore)
		bags[0][5] = { itemID = 2131, itemName = "Worn Shortsword", iconFileID = 1, stackCount = 1, quality = 1, hyperlink = "|Hitem:2131|h[Worn Shortsword]|h" }
		bags[0][5].itemID, bags[0][5].itemName = 1, "Fancy Helm"
		bags[0][5].hyperlink = "|Hitem:1|h[Fancy Helm]|h"
		ns.providers.items._dirty = true -- (only the item list's own event)
		local again = ns:GetEntries(ns.providers.gear)
		local inBag = 0
		for _, g in ipairs(again) do if g.name == "Fancy Helm" and g.detail:find("In Bag", 1, true) then inBag = inBag + 1 end end
		check(inBag == 1, "the item list changed: @gear follows it (the helm in your bag shows too): " .. inBag)
		bags[0][5] = nil
		ns.providers.items._dirty = true
		-- Enter: like an Item result (your bags)
		UI:Open("@gear shortsword"); mark = #log; key("ENTER")
		check(logHas("OpenAllBags", mark + 1) or logHas("OpenBag", mark + 1) or logHas("OpenBackpack", mark + 1) or not UI:IsShown(),
			"Enter shows it in your bags, as an Item result does")
		-- Shift+Enter: the game equips it
		UI:Open("@gear shortsword")
		_G.IsShiftKeyDown = function() return true end
		key("ENTER")
		_G.IsShiftKeyDown = function() return false end
		check(S.armed == "MACRO" and _G.TerminalMacroProxy.attrs.macrotext == "/equip item:2131" and F.propagate == true,
			"Shift+Enter equips it: " .. tostring(_G.TerminalMacroProxy.attrs.macrotext))
		UI:Disarm(); UI:Hide()
		-- already worn: it says so
		local printed
		local basePrint = ns.Print
		ns.Print = function(_, m) printed = m end
		UI:Open("@gear fancy helm")
		_G.IsShiftKeyDown = function() return true end
		key("ENTER")
		_G.IsShiftKeyDown = function() return false end
		ns.Print = basePrint
		check(S.armed == nil and printed and printed:find("already equipped", 1, true), "Shift+Enter on worn gear: it's already equipped")
		UI:Disarm(); UI:Hide()
		-- equipping swaps places: the history keeps the piece you picked, wherever it is now (worn rows were known by
		-- their slot, bag rows by their item: the shield equipped from the history came back as the sword it replaced)
		C_Item.GetItemInfoInstant = function(x)
			if x == 2131 or (type(x) == "string" and x:find("Worn Shortsword", 1, true)) then return 2131, "Weapon", "One-Handed Swords", "INVTYPE_WEAPON", 1, 2, 7 end
			if x == 2129 or (type(x) == "string" and x:find("Large Round Shield", 1, true)) then return 2129, "Armor", "Shields", "INVTYPE_SHIELD", 1, 4, 6 end
			return baseInstant(x)
		end
		local SWORD, SHIELD = "|Hitem:2131|h[Worn Shortsword]|h", "|Hitem:2129|h[Large Round Shield]|h"
		local function wearing(link) -- the off hand (17) holds `link`, the other piece is in the bag
			_G.GetInventorySlotInfo = function(n) return n == "SecondaryHandSlot" and 17 or 99 end
			_G.GetInventoryItemLink = function(_, slot) if slot == 17 then return link end end
			local other = link == SWORD and SHIELD or SWORD
			bags[0] = { saveBag[1], { itemID = other == SWORD and 2131 or 2129, itemName = other:match("%[(.-)%]"), iconFileID = 1,
				stackCount = 1, quality = 1, hyperlink = other } }
			ns.providers.items._dirty = true
		end
		local baseSlotInfo = _G.GetInventorySlotInfo
		wearing(SWORD)
		ns.db.recent = {}
		UI:Open("@gear shield")
		check(UI.Results()[1] and UI.Results()[1].name == "Large Round Shield", "the shield, in the bag")
		_G.IsShiftKeyDown = function() return true end
		key("ENTER")
		_G.IsShiftKeyDown = function() return false end
		UI:Disarm(); UI:Hide()
		wearing(SHIELD) -- (the game equipped it: the sword went to the bag)
		local recent = names(UI:FrequentEntries())
		check(recent["Large Round Shield"] and not recent["Worn Shortsword"],
			"the history still has the shield (now worn), not the sword it replaced")
		-- the same through @item (Shift+Enter there uses it, which equips gear)
		ns.db.recent = {}
		wearing(SWORD)
		UI:Open("@item shield")
		_G.IsShiftKeyDown = function() return true end
		key("ENTER")
		_G.IsShiftKeyDown = function() return false end
		UI:Disarm(); UI:Hide()
		wearing(SHIELD)
		recent = names(UI:FrequentEntries())
		check(recent["Large Round Shield"] and not recent["Worn Shortsword"], "@item: the history keeps the shield too")
		_G.GetInventorySlotInfo = baseSlotInfo
		bags[0] = saveBag
		C_Item.GetItemInfoInstant = baseInstant
		_G.GetInventoryItemLink = function() return nil end
		ns.providers.items._dirty = true; ns.providers.gear._dirty = true
	end

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
	-- typing (or scrolling) under the pointer: the catcher follows its row, not the old result
	UI:Open("wolves across"); r1.scripts.OnEnter(r1)
	check(c.shown and c.entry == UI.Results()[1], "catcher over the quest row")
	UI:SetQuery(".help")
	check(not c.shown and c.entry == nil, "typed something else under the pointer: the catcher follows its row (none for a command)")
	UI:Hide(); FlushAll()
	-- opening runs one search, not two
	local realSearch, searches = UI.Search, 0
	UI.Search = function(self, ...) searches = searches + 1 return realSearch(self, ...) end
	UI:Open("wolves across")
	UI.Search = realSearch
	check(searches == 1, "opening with text searches once (searched " .. searches .. " times)")
	UI:Hide(); FlushAll()
	-- scoring skips building keys of compact rows of kinds never picked
	local savedFreq = ns.db.freq
	ns.db.freq = {}; ns.freqKinds = nil
	check(ns:FreqKind("maps") == false, "no map ever picked")
	ns:Bump("maps:42")
	local picked = ns:FreqKind("maps")
	check(type(picked) == "table" and picked[42] == 1 and picked["42"] == 1, "a map picked: its kind counts, its key looked up as it is")
	-- a compact row's bonus comes without its "kind:key" being built (its metatable's freqKey never read)
	local builds = 0
	local row = setmetatable({ key = 42, name = "Duskwood", _compact = true }, { __index = function(_, k)
		if k == "freqKey" then builds = builds + 1 return "maps:42" end
		if k == "kind" then return "maps" end
	end })
	check(UI._FreqBonus and UI._FreqBonus(row) > 0 and builds == 0, "a compact row's bonus: looked up by its key, no string built: " .. builds)
	ns.db.freq = savedFreq; ns.freqKinds = nil
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
	for i = mark + 1, #log do if log[i]:find("Nothing to craft yet in: Herbalism", 1, true) then readMiss = true end end
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
	UI:Open(""); UI.lastQuery = nil; UI:Down() -- (Down on the bare prompt: your recent picks, the footer under them)
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
	-- "Index professions at login" only where the game lets addons open profession windows
	local baseNDO = ns.db.noDirectOpen
	ns.db.noDirectOpen = true; O.Refresh()
	check(not O.widgets.autoScan:IsShown() and not O.widgets.autoScanLabel:IsShown(), "the game refuses (WoW Forever): no login-indexing checkbox")
	ns.db.noDirectOpen = false; O.Refresh()
	check(O.widgets.autoScan:IsShown() and O.widgets.autoScanLabel:IsShown(), "the game allows it: the checkbox shows")
	ns.db.noDirectOpen = baseNDO
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
	local achEvents = {}
	for _, ev in ipairs(ns.providers.achievements.events or {}) do achEvents[ev] = true end
	check(achEvents.ACHIEVEMENT_EARNED, "an achievement earned this session is listed without a reload")
	check(has("valor", "Valor") and not has("honor", "Honor"), "only currencies you hold are listed")
	check(logFind("Indexed First Aid: 2 known recipes."), "a newly indexed profession is announced in chat")
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
	check(logFind("Indexed First Aid: 4 known recipes."), "re-index with more recipes is announced")

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
io.write("[cvar tests]\n")
do
	local cv = names(ns:GetEntries(ns.providers.cvars))
	check(cv.nameplateMaxDistance and not cv.reloadui, "@cvar lists console settings, not console commands")
	check(cv.nameplateMaxDistance.detail:find("= 41  (default 60)", 1, true) and cv.nameplateMaxDistance.color,
		"a changed setting shows its value and default, marked: " .. tostring(cv.nameplateMaxDistance.detail))
	check(cv.ffxGlow.detail:find("^= 1") and not cv.ffxGlow.detail:find("default", 1, true), "an unchanged one only its value")
	check(cv.lockedOne.detail:find("read-only", 1, true), "read-only settings say so")
	check(#UI:Search("@cvar") == 4, "@cvar alone lists every setting, whatever command type the game gives: " .. #UI:Search("@cvar"))
	-- the game's list comes back empty: Terminal's own list of names
	CVARS_EMPTY = true
	ns.providers.cvars._dirty = true
	check(names(UI:Search("@cvar")).nameplateMaxDistance, "an empty list from the game: Terminal's own list instead")
	CVARS_EMPTY = nil
	-- nothing readable at all: a row says so, and it's asked for again
	local getInfo, getCVar = C_CVar.GetCVarInfo, C_CVar.GetCVar
	C_CVar.GetCVarInfo, C_CVar.GetCVar = function() end, function() end
	ns.providers.cvars._dirty = true
	local none = UI:Search("@cvar")
	check(#none == 1 and none[1].raw and none[1].name:find("No console settings", 1, true), "nothing readable: says so")
	C_CVar.GetCVarInfo, C_CVar.GetCVar = getInfo, getCVar
	FlushAll()
	check(#UI:Search("@cvar") == 4, "and is asked for again")
	-- WoW Forever: the game won't list them (the call fails): Terminal's own list of names, each looked up
	CVARS_FAIL = true
	ns.providers.cvars._dirty = true
	cv = names(ns:GetEntries(ns.providers.cvars))
	check(cv.nameplateMaxDistance and cv.cameraDistanceMaxZoomFactor and not cv.lockedOne and not cv.reloadui,
		"the game won't list them: Terminal's list of names, only those this client has")
	check(cv.nameplateMaxDistance.help:find("max distance to show nameplates", 1, true) and cv.nameplateMaxDistance.detail:find("= 41", 1, true),
		"with the list's help text and the game's own value")
	-- a setting changed: just its row is updated (the list isn't made again, ~1650 rows)
	local p = ns.providers.cvars
	local list = p._entries
	CVARS.nameplateMaxDistance[1] = "60"
	ns.CVars.watch.scripts.OnEvent(ns.CVars.watch, "CVAR_UPDATE", "nameplateMaxDistance", "60")
	check(p._entries == list and not p._dirty, "a changed setting doesn't make the list again")
	check(cv.nameplateMaxDistance.detail:find("^= 60") and not cv.nameplateMaxDistance.changed and not cv.nameplateMaxDistance.color,
		"its row shows the new value (back to its default: no longer marked): " .. tostring(cv.nameplateMaxDistance.detail))
	CVARS.nameplateMaxDistance[1] = "41"
	ns.CVars.watch.scripts.OnEvent(ns.CVars.watch, "CVAR_UPDATE", "nameplateMaxDistance", "41")
	check(cv.nameplateMaxDistance.changed and names(UI:Search("@cvar changed")).nameplateMaxDistance, "changed again: found by 'changed'")
	-- the tooltip is made when hovered
	local lines = {}
	local tt = { SetText = function(_, t) lines[#lines + 1] = t end, AddLine = function(_, t) lines[#lines + 1] = t end,
		AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. " " .. b end }
	cv.nameplateMaxDistance.tooltip(cv.nameplateMaxDistance, tt)
	local all = table.concat(lines, "\n")
	check(all:find("Value 41", 1, true) and all:find("Default 60", 1, true) and all:find("nameplates", 1, true), "the tooltip: help, value, default")
	CVARS_FAIL = nil
	ns.providers.cvars._dirty = true
	check(ns.providers.cvars.explicit and not names(UI:Search("nameplate"))["nameplateMaxDistance"], "only searched with @cvar")
	check((select(2, top("@cvar nameplate")) or {})[1].name == "nameplateMaxDistance", "@cvar finds it by name")
	check((select(2, top("@cvar max distance shown")) or {})[1].name == "nameplateMaxDistance", "and by its help text")
	-- Enter puts the line in the prompt to edit; the terminal stays open
	UI:Open("@cvar nameplatemax"); key("ENTER")
	check(UI:IsShown() and UI.edit:GetText() == "/console nameplateMaxDistance 41", "Enter fills in /console name value: " .. tostring(UI.edit:GetText()))
	-- running it: the game presses /console (a line on the secure macro button)
	UI:SetQuery("/console nameplateMaxDistance 50"); UI:Refresh()
	check(UI.Results()[1] and UI.Results()[1].name == "/console", "/console is a slash row even when not a SLASH_ global")
	key("ENTER")
	check(S.armed == "MACRO" and _G.TerminalMacroProxy.attrs.macrotext == "/console nameplateMaxDistance 50" and F.propagate == true,
		"the game runs /console name value: " .. tostring(_G.TerminalMacroProxy.attrs.macrotext))
	UI:Disarm(); UI:Hide()
	-- Shift+Enter: the line with its default
	UI:Open("@cvar nameplatemax")
	_G.IsShiftKeyDown = function() return true end
	key("ENTER")
	_G.IsShiftKeyDown = function() return false end
	check(UI.edit:GetText() == "/console nameplateMaxDistance 60", "Shift+Enter fills in the default: " .. tostring(UI.edit:GetText()))
	UI:Hide()
end

io.write("[macro length tests]\n")
do
	-- the game runs at most 255 characters of a macro, all lines together: a longer one is never handed over
	local Sx = ns.Secure
	check(Sx.MACRO_MAX == 255, "the macro limit is the game's 255")
	local r = Sx.Resolve({ macro = ("/run print(1)\n"):rep(20) })
	check(r == nil, "a macro over 255 characters isn't used (the game would cut it mid-line)")
	r = Sx.Resolve({ macro = ("/run print(1)\n"):rep(20), binding = "TOGGLETALENTS" })
	check(r and r.binding and not r.macro, "a spec with a key falls back to the key")
	check(Sx.ClickMacro({ macro = ("/run print(1)\n"):rep(20) }) == nil, "nor as a click's macro")
	_G.TerminalTestButton = Obj("Button")
	check(Sx.ClickMacro({ macro = ("/run print(1)\n"):rep(20), buttons = { "TerminalTestButton" } }) == "/click TerminalTestButton",
		"a click with a macro too long falls back to the spec's button")
	_G.TerminalTestButton = nil
	-- the keybinding search fits a long action name
	local K = ns.Keybinds
	if K and K.MacroFor then
		local m = K.MacroFor(("Toggle Something With A Very Long Binding Name "):rep(2))
		check(#m <= 255, "the keybinding macro fits a 96-letter action name: " .. #m)
	end
end

io.write("[spellbook tests]\n")
do
	local SP = ns.Spells
	local saveBook, saveSpell = _G.C_SpellBook, _G.C_Spell
	-- slot 1: Fireball rank 1, 2: Fireball rank 2 (one row, the highest kept), 3: a passive, 4: no item info on
	-- this client (asked by type and id), 5: a secret value, 6: a flyout
	local SPELLS = { [201] = "Fireball", [202] = "Fireball", [203] = "Arcane Mind", [204] = "Frost Nova", [205] = "Hidden", [206] = "Portals" }
	_G.C_SpellBook = {
		GetNumSpellBookSkillLines = function() return 2 end,
		GetSpellBookSkillLineInfo = function(l)
			if l == 1 then return { name = "General", itemIndexOffset = 0, numSpellBookItems = 0 } end
			return { name = "Fire", itemIndexOffset = 0, numSpellBookItems = 6 }
		end,
		GetSpellBookItemInfo = function(i)
			if i == 1 then return { spellID = 201, itemType = 1, subName = "Rank 1" } end
			if i == 2 then return { spellID = 202, itemType = 1, subName = "Rank 2" } end
			if i == 3 then return { spellID = 203, itemType = 1, isPassive = true } end
			if i == 5 then return { spellID = "SECRET", itemType = 1 } end
			if i == 6 then return { spellID = 206, itemType = 4 } end
			return nil
		end,
		GetSpellBookItemType = function(i) if i == 4 then return 1, 204 end end,
	}
	_G.C_Spell = setmetatable({ GetSpellInfo = function(id) return SPELLS[id] and { name = SPELLS[id], iconID = 1 } end,
		GetSpellName = function(id) return SPELLS[id] end, IsSpellPassive = function() return false end }, { __index = saveSpell })
	local saveSecret = _G.issecretvalue
	_G.issecretvalue = function(v) return v == "SECRET" end
	ns.providers.spells._dirty = true
	local sp = names(ns:GetEntries(ns.providers.spells))
	local count = #ns:GetEntries(ns.providers.spells)
	check(sp.Fireball and sp.Fireball.spellID == 202 and sp.Fireball.detail == "Rank 2  Fire", "ranks of a spell are one row, the highest rank kept: " .. tostring(sp.Fireball and sp.Fireball.detail))
	check(sp["Frost Nova"] and sp["Frost Nova"].spellID == 204, "a slot with no item info is read by its type and id")
	check(not sp.Hidden and not sp.Portals and count == 3, "secret values and flyouts are skipped: " .. count)
	check(sp["Arcane Mind"].passive and sp["Arcane Mind"].detail:find("^Passive"), "passives are marked")
	check(ns:ResolveProvider("spell") == ns.providers.spells and (select(2, top("@spell nova")) or {})[1].name == "Frost Nova", "@spell")

	local shownTarget
	local origShow = ns.Highlight.Show
	ns.Highlight.Show = function(self, target, d) shownTarget = target; return origShow(self, target, d) end
	_G.BINDING_NAME_TOGGLESPELLBOOK = "Spellbook"

	-- ClassicUIForever's book: the Spellbook key opens it; Terminal turns it to the spell's tab and page, as you would
	-- (a model of its book: tabs by skill line, 12 buttons a page, page arrows, a search box)
	local book = Obj("Frame"); book.shown = false
	local LINES = { [1] = { 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313 },  -- General: 13 spells, 2 pages
		[2] = { 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 419, 420,
			421, 422, 423, 201, 202, 424 } } -- Fire: Fireball's ranks 1 and 2 on page 2, rank 2 the one to point at
	local cur = { line = 1, page = 1, search = "" }
	local clicks = { tab = 0, page = 0 }
	book.Buttons = {}
	for i = 1, 12 do
		local b = Obj("Button"); b.shown = true; b.pos = i; book.Buttons[i] = b
	end
	local function shown(btn) -- the spell a button shows now (ClassicUIForeverAPI.SpellOnButton)
		local list = LINES[cur.line]
		local id = list[(cur.page - 1) * 12 + btn.pos]
		btn.slot = id and ((cur.page - 1) * 12 + btn.pos) or nil
		return id
	end
	local function pages() return math.ceil(#LINES[cur.line] / 12) end
	local function arrow(step)
		local a = Obj("Button"); a.shown = true
		a.IsEnabled = function() local p = cur.page + step return p >= 1 and p <= pages() end
		a.Click = function() if a.IsEnabled() then cur.page = cur.page + step; clicks.page = clicks.page + 1 end end
		return a
	end
	book.PrevPage, book.NextPage = arrow(-1), arrow(1)
	book.SkillTabs = {}
	for i = 1, 2 do
		local t = Obj("CheckButton"); t.shown = true; t.line = i
		t.Click = function() cur.line = i; cur.page = 1; clicks.tab = clicks.tab + 1 end
		book.SkillTabs[i] = t
	end
	book.Search = Obj("EditBox"); book.Search:SetText("Fireball") -- left over from 0.35.2
	local SPELLN = setmetatable({ [201] = "Fireball", [202] = "Fireball" }, { __index = function(_, id) return "Spell " .. id end })
	C_Spell.GetSpellName = function(id) return SPELLN[id] end
	local asked
	_G.ClassicUIForeverAPI = {
		IsOn = function(n) return n == "spellBook" end,
		GetFrame = function(n, part) if part == nil then return book end asked = part end,
		SpellOnButton = function(btn) return shown(btn) end,
	}
	UI:Open("fireball"); key("ENTER")
	check(S.armed == "TOGGLESPELLBOOK" and F.propagate == true, "Enter opens the spellbook with the Spellbook key, in one press: " .. tostring(S.armed))
	book.shown = true
	FlushAll()
	check(cur.line == 2 and cur.page == 3, "the book is turned to the spell's tab and page: line " .. cur.line .. " page " .. cur.page)
	check(shownTarget and shown(shownTarget) == 202, "the highest rank on that page is highlighted")
	check(book.Search:GetText() == "" and asked == nil, "the search box is left empty (not used to find it)")
	-- already open on its page: no press, no turning, just the highlight
	shownTarget = nil
	local before = clicks.tab + clicks.page
	UI:Open("fireball"); key("ENTER"); FlushAll()
	check(S.armed == nil and shownTarget and shown(shownTarget) == 202 and clicks.tab + clicks.page == before,
		"book already open on the spell: no press, no page turned, the spell is highlighted")
	-- a spell whose highest rank isn't listed (top ranks folded away): the highest one on show
	LINES[2][24], LINES[2][25] = 409, 201 -- only rank 1 on show now
	cur.line, cur.page = 1, 1
	shownTarget = nil
	UI:Open("fireball"); key("ENTER"); FlushAll()
	check(cur.line == 2 and shownTarget and shown(shownTarget) == 201, "only a lower rank on show: that one is highlighted")
	LINES[2][24], LINES[2][25] = 201, 202

	-- Shift+Enter casts it (a /cast line pressed by the game)
	book.shown = false
	UI:Open("fireball")
	_G.IsShiftKeyDown = function() return true end
	key("ENTER")
	_G.IsShiftKeyDown = function() return false end
	check(S.armed == "MACRO" and _G.TerminalMacroProxy.attrs.macrotext == "/cast Fireball" and F.propagate == true,
		"Shift+Enter casts the spell: " .. tostring(_G.TerminalMacroProxy.attrs.macrotext))
	UI:Disarm(); UI:Hide()
	-- a passive spell can't be cast: it says so
	local printed
	local basePrint = ns.Print
	ns.Print = function(_, m) printed = m end
	UI:Open("arcane mind")
	_G.IsShiftKeyDown = function() return true end
	key("ENTER")
	_G.IsShiftKeyDown = function() return false end
	ns.Print = basePrint
	check(S.armed == nil and printed and printed:find("passive", 1, true), "Shift+Enter on a passive: nothing cast, it says so")
	UI:Disarm(); UI:Hide()

	-- the game's own book (no ClassicUIForever): the press opens it and turns it to the spell itself (Blizzard's
	-- GoToSpell, after clearing a search), whether the book is open or not; Terminal then points at the spell's item
	_G.ClassicUIForeverAPI = nil
	_G.PlayerSpellsUtil = { OpenToSpellBookTab = function() end }
	local r = ns.Secure.Resolve(sp.Fireball.secure, sp.Fireball)
	check(r and r.macro and r.macro:find("OpenToSpellBookTab", 1, true) and r.macro:find("GoToSpell(202,true)", 1, true)
		and r.macro:find("ClearActiveSearchState(true)", 1, true) and not r.macro:find("SetText(C_Spell", 1, true),
		"game's book: opened, search cleared and turned to the spell by the game's press: " .. tostring(r and r.macro))
	-- the game cuts a macro off at 255 characters in all (seen in game: a cut /run line, "')' expected near <eof>")
	local longest = ns.Spells.ClientBookMacro({ spellID = 1293712, name = "x" })
	check(longest and #longest <= 255, "the spellbook macro fits in 255 characters with a 7-digit spell id: " .. tostring(longest and #longest))
	local client = Obj("Frame"); client.shown = true
	local paged = Obj("Frame"); paged.shown = true
	local other = Obj("Frame"); other.shown = true; other.slotIndex = 3; other.spellBank = 0
	local item = Obj("Frame"); item.shown = true; item.slotIndex = 2; item.spellBank = 0
	item.Button = Obj("Button"); item.Button.shown = true
	local searchBox = Obj("EditBox"); searchBox.shown = true; searchBox:SetText("Fireball")
	paged.GetChildren = function() return other, item end
	client.GetChildren = function() return searchBox, paged end
	client.PagedSpellsFrame, client.SearchBox = paged, searchBox
	_G.PlayerSpellsFrame = Obj("Frame"); PlayerSpellsFrame.shown = true; PlayerSpellsFrame.SpellBookFrame = client
	C_SpellBook.FindSpellBookSlotForSpell = function(id) if id == 202 then return 2, 0 end end
	shownTarget = nil
	UI:Open("fireball"); key("ENTER")
	check(S.armed == "MACRO" and F.propagate == true, "book already open: still pressed, so the game turns it to the spell: " .. tostring(S.armed))
	_G.TerminalMacroProxy.scripts.PostClick(_G.TerminalMacroProxy, "LeftButton", true); FlushAll()
	check(shownTarget == item.Button, "the spell's own item is highlighted (not the search box)")
	-- opened by this press, the book fills its page in over its first frames: the spell's frame is a
	-- different one at first (then the page is laid out again); it's pointed at once it stays put
	UI:Disarm(); UI:Hide()
	shownTarget = nil
	local early = Obj("Frame"); early.shown = true; early.slotIndex = 2; early.spellBank = 0
	early.Button = Obj("Button"); early.Button.shown = true
	local looks = 0
	paged.GetChildren = function()
		looks = looks + 1
		if looks == 1 then return other, early end -- first look: the page still filling in
		return other, item
	end
	UI:Open("fireball"); key("ENTER")
	_G.TerminalMacroProxy.scripts.PostClick(_G.TerminalMacroProxy, "LeftButton", true); FlushAll()
	check(shownTarget == item.Button, "on a book still filling in, the frame that stays is the one highlighted")
	-- the book the press opens closes the terminal (a special frame) before the press comes back: Enter
	-- was already let go, but the press still finishes and the spell is pointed at
	UI:Disarm(); UI:Hide(); FlushAll()
	shownTarget = nil
	UI:Open("fireball"); key("ENTER")
	check(S.armed == "MACRO", "armed for the press")
	UI:Hide() -- (opening the spellbook closed the terminal, which lets Enter go)
	check(S.armed == nil, "the terminal closing lets Enter go")
	_G.TerminalMacroProxy.scripts.PostClick(_G.TerminalMacroProxy, "LeftButton", true); FlushAll()
	check(shownTarget == item.Button, "the press coming back after that still points at the spell")
	-- a press that finished normally isn't finished again by a second click of the proxy a moment later
	UI:Disarm(); UI:Hide(); FlushAll()
	local afters = 0
	local baseAfter = sp.Fireball.after
	sp.Fireball.after = function(e) afters = afters + 1 end
	UI:Open("fireball"); key("ENTER")
	_G.TerminalMacroProxy.scripts.PostClick(_G.TerminalMacroProxy, "LeftButton", true); FlushAll()
	_G.TerminalMacroProxy.scripts.PostClick(_G.TerminalMacroProxy, "LeftButton", true); FlushAll()
	check(afters == 1, "a finished press runs its after-step once: " .. afters)
	sp.Fireball.after = baseAfter
	-- learning a new rank keeps the row (its history): spells are known by their name
	check(sp.Fireball.key == "Fireball", "a spell is known by its name, not its rank's id")
	paged.GetChildren = function() return other, item end
	UI:Disarm(); UI:Hide()
	_G.PlayerSpellsFrame, C_SpellBook.FindSpellBookSlotForSpell = nil, nil
	_G.PlayerSpellsUtil = nil
	r = ns.Secure.Resolve(sp.Fireball.secure, sp.Fireball)
	check(r and r.binding == "TOGGLESPELLBOOK", "otherwise just the Spellbook key")

	ns.Highlight.Show = origShow
	_G.C_SpellBook, _G.C_Spell, _G.issecretvalue = saveBook, saveSpell, saveSecret
	ns.providers.spells._dirty = true
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
	-- animation style is a dropdown too; the example plays it
	local anim = O.widgets.animations
	check(anim and O.animationItems.cascade and O.widgets.animationList, "an Animation dropdown with the styles")
	anim.scripts.OnClick(anim)
	O.animationItems.cascade.scripts.OnClick(O.animationItems.cascade)
	check(Th.Get().animations == "cascade" and anim:GetText() == "Cascade", "picking a style sets it: " .. tostring(anim:GetText()))
	check(O.widgets.animations.SetChecked == nil or not O.widgets.animCheck, "no animations checkbox any more")
	O.demo.t = 0
	O.AnimatePreview(0.6)
	local partly = pv.query:GetText()
	check(#partly > 0 and #partly < #"hvy ban" and (pv.label.alpha or 1) == 0, "the example types the query (" .. partly .. "), the result not there yet")
	O.AnimatePreview(0.9)
	check(pv.query:GetText() == "hvy ban" and pv.label.alpha == 1, "then the result comes in")
	local seen = {}
	for _ = 1, 20 do O.AnimatePreview(0.1); seen[#seen + 1] = pv.caret.alpha end
	local lo, hi = math.min(unpack(seen)), math.max(unpack(seen))
	check(hi - lo > 0.3, "the cursor blinks while idle (" .. lo .. " to " .. hi .. ")")
	Th.Set("cursor", "solid-line")
	O.demo.t = 2
	seen = {}
	for _ = 1, 10 do O.AnimatePreview(0.1); seen[#seen + 1] = pv.caret.alpha end
	check(math.min(unpack(seen)) == math.max(unpack(seen)), "a solid cursor doesn't blink in the example")
	Th.Set("cursor", "blinking-line")
	-- the example redraws at most 30 times a second, and only what changed
	local sets = 0
	local realSet = pv.query.SetText
	pv.query.SetText = function(self, ...) sets = sets + 1 return realSet(self, ...) end
	local moves, realPoint = 0, pv.SetPoint
	pv.SetPoint = function(self, ...) moves = moves + 1 return realPoint(self, ...) end
	O.demo.t, O.demo.acc = 2, 0
	local calls = 0
	local realA = pv.caret.SetAlpha
	pv.caret.SetAlpha = function(self, ...) calls = calls + 1 return realA(self, ...) end
	for _ = 1, 60 do O.AnimatePreview(1 / 60) end
	pv.query.SetText, pv.SetPoint, pv.caret.SetAlpha = realSet, realPoint, realA
	check(sets == 0 and moves == 0 and calls <= 30, "the example while idle: no text or position changes, cursor redrawn at most 30/s (" .. sets .. ", " .. moves .. ", " .. calls .. ")")
	Th.Set("animations", "smooth")
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
	local tdc = UI:WordSearch(UI:CommandEntries(), "talentdebug")[1]
	local dbg = table.concat(tdc.activate(tdc, ""), "\n")
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
	check(not seen("OpenRecipe") and seen("ROWSHOW Charred Wolf Meat") and not seen("ROWCLICK Charred Wolf Meat"), "Charred Wolf Meat is pointed at in it (OpenRecipe, protected, never called; no click)")
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
	check(a["Cool Addon 1"] and a["Cool Addon 1"].detail == "Minimap button", "addon with a minimap button and options: " .. tostring(a["Cool Addon 1"] and a["Cool Addon 1"].detail))
	a["Cool Addon 1"].activate(a["Cool Addon 1"])
	check(clicked == "Addon1 minimap" and opened == nil, "Enter clicks its minimap button")
	-- (Shift+Enter now turns an addon on/off; its options panel is a row of its own)
	local o = a["Cool Addon 1 options"]; o.activate(o)
	check(opened == 42, "its options page row opens it")
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
	check(seen("ROWSHOW Smelt Copper", m + 1), "...and the recipe is pointed at")
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
	ns.providers.professions._dirty = true -- the spells changed (SPELLS_CHANGED in the game)
	local pe = names(ns:GetEntries(ns.providers.professions))
	check(pe["Cooking"].secure and pe["Cooking"].secure.spell == "Cooking", "Cooking opens through its spell on Enter")
	ns.providers.professions._dirty = false
	P.MarkDirty()
	check(ns.providers.professions._dirty == false and ns.providers.recipes._dirty == true, "an index change rebuilds recipes, not the professions list")
	local opens, realOpenSpell = 0, P.OpenSpell
	P.OpenSpell = function(...) opens = opens + 1 return realOpenSpell(...) end
	local recs = ns:GetEntries(ns.providers.recipes)
	P.OpenSpell = realOpenSpell
	local profs = {}
	for _, r in ipairs(recs) do if r.profID then profs[r.profID] = true end end
	local nprofs = 0
	for _ in pairs(profs) do nprofs = nprofs + 1 end
	check(#recs > nprofs and opens <= nprofs, "the opening spell is looked up once per profession, not per recipe (" .. opens .. " for " .. #recs .. " recipes)")
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
	-- nothing below a zone: points of interest, flight points and dungeon maps are left out
	check(not byName["Goldshire"] and not byName["Stormwind, Elwynn"] and not byName["The Deadmines"], "no points of interest, flight points or dungeons")
	check(byName["Eastern Kingdoms"] and byName["Eastern Kingdoms"].detail:find("^Continent"), "continents are listed")
	do
		local raw = 0
		for _ in pairs(byName["Elwynn Forest"]) do raw = raw + 1 end
		check(byName["Elwynn Forest"].icon == "Interface\\Icons\\INV_Misc_Map_01" and raw <= 7,
			"map rows: the shared icon comes from the prototype, rows stay at 7 raw fields or fewer (" .. raw .. ")")
	end
	check(UI:Search("@map elwynn")[1].name == "Elwynn Forest", "@map filter")
	check(ns:ResolveProvider("flight") ~= ns.providers.maps, "@flight no longer means maps")
	local z = byName["Elwynn Forest"]
	check(z.secure.binding == "TOGGLEWORLDMAP", "map opens through the game's own map key")
	-- the game's macro opens and switches the map; Terminal's code never writes the map
	-- (SetMapID from Terminal left the map tainted: its pins failed in combat)
	WorldMapFrame.shown = true
	local switched = {}
	WorldMapFrame.SetMapID = function(_, id) switched[#switched + 1] = id end
	local MAPMACRO = "/run if not WorldMapFrame:IsShown() then ToggleWorldMap() end WorldMapFrame:SetMapID(37)"
	local rz = ns.Secure.Resolve(z.secure, z)
	check(rz and rz.macro == MAPMACRO, "Enter runs the game's macro that switches the map: " .. tostring(rz and rz.macro))
	check(z.isOpen(z) == false, "with the map open the macro still runs (it switches the map)")
	local mark = #log
	z.after(z)
	check(#switched == 0 and not logHas("Waypoint 37 0.5", mark + 1), "after: Terminal never switches the map itself, and a zone sets no waypoint")
	-- a pin that is already set follows the chosen zone
	pinned = true; mark = #log
	z.after(z)
	check(logHas("ClearWaypoint", mark + 1) and logHas("Waypoint 37 0.5", mark + 1), "existing pin: cleared, and the zone is pinned at its middle")
	pinned = true; mark = #log
	z.secondary(z)
	check(logHas("ClearWaypoint", mark + 1) and logHas("Waypoint 37 0.5", mark + 1), "Shift+Enter on a zone also replaces an existing pin")
	pinned = false
	local D, n = ns.Debug, 0
	WorldMapFrame.SetMapID = function() n = n + 1 end
	ns.db.blockedCalls = nil
	-- in combat the map is left alone (its pins are protected), and a block seen in combat is
	-- not remembered as permanent
	local realCombat = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	n = 0; mark = #log
	pinned = true
	z.activate(z)
	FlushAll()
	check(n == 0 and not logHas("ToggleWorldMap", mark + 1), "in combat: map neither opened nor switched")
	check(logHas("Waypoint 37 0.5", mark + 1), "in combat: an existing pin still moves")
	pinned = false
	z.after(z)
	check(n == 0, "in combat: after() doesn't switch the map either")
	local viaGuard = ns.Professions.Guarded("X", function() D.frame.scripts.OnEvent(D.frame, "ADDON_ACTION_BLOCKED", "Terminal", "UNKNOWN()") end)
	check(viaGuard == false and not (ns.db.blockedCalls and ns.db.blockedCalls.X), "a block seen in combat isn't remembered")
	_G.InCombatLockdown = realCombat
	ns.db.blockedCalls = nil
	for i = #D.events, 1, -1 do D.events[i] = nil end
	for i = #D.trace, 1, -1 do D.trace[i] = nil end
	-- another addon's blocked actions (by the hundred, as taint spreads): counted cheaply, folded
	-- into one line, and no stack taken (that was counted as Terminal's CPU)
	local stacks, realStack = 0, _G.debugstack
	_G.debugstack = function(...) stacks = stacks + 1 return realStack and realStack(...) or "" end
	local mineBefore, othersBefore = D.count, D.others
	ns.db.debug = false
	for _ = 1, 500 do D.frame.scripts.OnEvent(D.frame, "ADDON_ACTION_BLOCKED", "SomeOtherAddon", "Button:SetPassThroughButtons()") end
	check(stacks == 0 and #D.events == 1 and D.events[1].times == 500, "500 blocks of another addon: one line (x500), no stacks taken")
	check(D.count == mineBefore and D.others == othersBefore + 500, "and they don't count as Terminal's own blocks")
	check(table.concat(ns.commands.debug.run(""), " "):find("by other addons", 1, true), ".debug says how many were other addons'")
	check(table.concat(D.Describe(D.events[1]), " "):find("isn't recorded", 1, true), "and doesn't claim Terminal was idle when it didn't record")
	check(table.concat(D.Describe and D.Describe(D.events[1]) or { "x500" }, " "):find("x500", 1, true) ~= nil, "the log says how many")
	D.frame.scripts.OnEvent(D.frame, "ADDON_ACTION_BLOCKED", "Terminal", "UNKNOWN()")
	check(stacks == 1 and D.count == mineBefore + 1 and #D.events == 2, "Terminal's own block still gets the full record")
	-- with .debug on: printed once, not 500 times
	for i = #D.events, 1, -1 do D.events[i] = nil end
	ns.db.debug = true
	local printed0 = #log
	for _ = 1, 500 do D.frame.scripts.OnEvent(D.frame, "ADDON_ACTION_BLOCKED", "SomeOtherAddon", "Button:SetPassThroughButtons()") end
	ns.db.debug = false
	check(#log - printed0 <= 3 and D.events[1].times == 500, "with .debug on, another addon's repeats print once (" .. (#log - printed0) .. " lines)")
	_G.debugstack = realStack
	for i = #D.events, 1, -1 do D.events[i] = nil end
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
	local iname = { [1001] = "Cruel Barb", [1002] = "Red Defias Mask", [2840] = "Copper Bar",
		[2657] = "Test Glaive I", [77] = "Bogus Set Item" } -- (2657, 77: what the spell/set numbers are as item ids)
	local baseName, baseIcon = C_Item.GetItemNameByID, C_Item.GetItemIconByID
	C_Item.GetItemNameByID = function(id) return iname[id] end
	C_Item.GetItemIconByID = function(id) return 134 end
	local baseInfo = C_Item.GetItemInfo
	C_Item.GetItemInfo = function(id) return iname[id] end
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
	content.gameVersion = 4 -- WoW Forever's own table (AtlasLoot Continued: data-forever.lua)
	-- Continued also loads Classic's table of the same dungeon (data.lua): its own window shows only
	-- the version it picks for this client, and so must Terminal, or every item shows twice
	local classic = { items = { {} }, gameVersion = 1, GetName = function() return "The Deadmines (Classic)" end,
		GetNameForItemTable = function() return "Edwin VanCleef" end }
	-- profession pages list crafting spells (Smelt Copper, 2657), set pages list set numbers: not item ids
	local mining = { items = { {} }, gameVersion = 4, GetName = function() return "Mining" end,
		GetNameForItemTable = function() return "Smelting" end }
	local sets = { items = { {} }, gameVersion = 4, GetName = function() return "Sets" end,
		GetNameForItemTable = function() return "Tier 0" end }
	refreshes = {}
	local storage = { GetDifficultys = function() return { { name = "Normal" } } end, DEADMINES = content, CLASSIC_DM = classic,
		MINING = mining, SETS = sets,
		GetAviableGameVersion = function(_, v) return v == 4 and 4 or 1 end }
	_G.AtlasLoot = {
		-- the first time AtlasLoot hasn't built its module list yet (its start-up may come after ours)
		Loader = { GetLootModuleList = function() moduleAsks = (moduleAsks or 0) + 1; if moduleAsks == 1 then return { module = {}, custom = {} } end return { module = { { addonName = "ALDungeons" } }, custom = {} } end,
			LoadModule = function(_, a) note("ALLoad", a) end },
		ItemDB = { Storage = { ALDungeons = storage },
			GetItemTable = function(_, addon, c, boss, d)
				if c == "MINING" then return { { 1, 2657 }, { 2, 99999 } }, { "Profession", "Item", "Name" } end
				if c == "SETS" then return { { 1, 77 } }, { "Set", "Item", "Name" } end
				return boss == 1 and { { 1, 1001 }, { 2, 1002 }, { 3, "INV_Misc_Note_01" } } or { { 1, 1001 } }, { "Item", "Item", "Name" }
			end },
		Data = { Profession = { GetCreatedItemID = function(spell) return spell == 2657 and 2840 or nil end } },
		GUI = { frame = Obj("Frame"), ItemFrame = { frame = { ItemButtons = { btn } },
			Refresh = function(_, skip) refreshes[#refreshes + 1] = { skip = skip, page = AtlasLoot.db.GUI.selected[5] } end } },
		db = { GUI = { selected = { "X", "Y", 1, 1, 0 } } },
		GetGameVersion = function() return 4 end,
	}
	AtlasLoot.GUI.frame.moduleSelect, AtlasLoot.GUI.frame.subCatSelect = selector("module"), selector("content")
	AtlasLoot.GUI.frame.boss, AtlasLoot.GUI.frame.difficulty = selector("boss"), selector("diff")
	AtlasLoot.GUI.frame.shown = false
	-- an AtlasLoot table without AtlasLoot's own addon loaded (disabled; a plugin left behind) is ignored
	local baseLoaded = C_AddOns.IsAddOnLoaded
	C_AddOns.IsAddOnLoaded = function(n) return not n:find("^AtlasLoot") end
	I.Setup()
	check(not I.loot.on and ns.providers.loot == nil, "no @loot when AtlasLoot itself isn't loaded")
	-- AtlasLoot Continued: same API, its own addon name
	C_AddOns.IsAddOnLoaded = function(n) return n == "AtlasLootContinued" end
	check(I.LoadedCore() == "AtlasLootContinued", "AtlasLoot Continued is recognised as AtlasLoot")
	C_AddOns.IsAddOnLoaded = function(n) return n == "AtlasLootClassic" end
	check(I.LoadedCore() == "AtlasLootClassic", "and AtlasLootClassic still is")
	C_AddOns.IsAddOnLoaded = baseLoaded
	_G.Questie = {
		API = { isReady = true },
	}
	local QINFO = {
		[33] = { name = "Wolves Across the Border", questLevel = 5 },
		[501] = { name = "The Defias Brotherhood", questLevel = 14, startedBy = { { 12 } } },
		[502] = { name = "Red Linen Goods", questLevel = 12, startedBy = { nil, { 555 } },
			objectivesText = { "Bring 6 Red Linen Bandanas to Scout Riell at the Sentinel Hill tower." } },
	}
	local saveLogIdx, saveDone = C_QuestLog.GetLogIndexForQuestID, C_QuestLog.IsQuestFlaggedCompleted
	C_QuestLog.GetLogIndexForQuestID = function(id) return id == 33 and 2 or nil end
	C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == 502 end
	local QDB = { NPCPointers = { [10] = true, [11] = true, [12] = true },
		QuestPointers = { [33] = true, [501] = true, [502] = true },
		QueryQuestSingle = function(id, f) return QINFO[id] and QINFO[id][f] end,
		QueryNPCSingle = function(id, f) if f ~= "name" then return nil end return ({ [10] = "Edwin VanCleef", [11] = "Defias Pillager", [12] = "Marshal McBride" })[id] end,
		GetNPC = function(_, id) if id == 12 then return { spawns = { [9] = { { 50, 40 } } } } end end }
	local QZ = { GetUiMapIdByAreaId = function(_, z) return z == 9 and 37 or nil end, GetDungeonLocation = function() return nil end }
	local QM = { ShowNPC = function(_, id) note("QuestieShowNPC", id) end }
	_G.QuestieLoader = { ImportModule = function(_, n) return ({ QuestieDB = QDB, ZoneDB = QZ, QuestieMap = QM })[n] end }

	I.Setup(); FlushAll()
	check(I.loot.on and I.npc.on, "both detected")
	check(logHas("ALLoad ALDungeons") and I.loot.done and #I.loot.rows == 3, "AtlasLoot module loaded and indexed, one row per item and instance: " .. #I.loot.rows)
	local lootNames = {}
	for _, r in ipairs(I.loot.rows) do lootNames[r.itemID] = r end
	check(lootNames[2840] and lootNames[2840].detail == "Smelting  Mining", "a profession page gives the item its spell makes (Smelt Copper: Copper Bar)")
	check(not lootNames[2657] and not lootNames[77], "spell and set numbers aren't read as item ids (no Test Glaive I)")
	local classicRows = 0
	for _, r in ipairs(I.loot.rows) do if r.content == "CLASSIC_DM" then classicRows = classicRows + 1 end end
	check(classicRows == 0, "only the game version AtlasLoot shows on this client is indexed (no Classic copies)")
	-- WoW Forever reports itself as retail (99), which no module has: AtlasLoot falls back to the module's last loaded
	-- version (Burning Crusade), while its window always shows Classic, where Forever's own dungeons are (0.43.25)
	do
		local st = { GetAviableGameVersion = function(_, v) return (v == 1 or v == 2) and v or 2 end,
			IsGameVersionAviable = function(_, v) return v == 1 or v == 2 end }
		local A = { GetGameVersion = function() return 99 end, CLASSIC_VERSION_NUM = 1, db = { GUI = { selectedGameVersion = 99 } } }
		check(I.WindowVersion(A, st) == 1, "Forever (retail 99, window not opened yet): Classic, not Burning Crusade: " .. tostring(I.WindowVersion(A, st)))
		A.db.GUI.selectedGameVersion = 2
		check(I.WindowVersion(A, st) == 2, "the window's own pick when the module has it")
		A.db = nil
		check(I.WindowVersion(A, st) == 1, "no AtlasLoot settings yet: Classic")
	end
	check(moduleAsks == 2, "an empty module list at first is asked for again: " .. tostring(moduleAsks))
	local es = names(ns:GetEntries(ns.providers.loot))
	check(es["Cruel Barb"] and es["Red Defias Mask"] and not es["INV_Misc_Note_01"], "named item rows only")
	check(es["Cruel Barb"].detail == "Edwin VanCleef  The Deadmines", "detail: boss and instance")
	check(UI:Search("red defias")[1].name == "Red Defias Mask", "AtlasLoot items found in plain search")
	check(UI:Search("@loot cruel")[1].name == "Cruel Barb", "@loot filter")
	-- items whose names the game hasn't sent yet are asked for, and appear when they arrive
	iname[1002] = nil; ns.providers.loot._dirty = true
	for _, r in ipairs(I.loot.rows) do if r.itemID == 1002 then r.name = nil; r._lname = nil end end -- as if never named
	I.loot.unnamed[1002] = true
	check(not names(ns:GetEntries(ns.providers.loot))["Red Defias Mask"], "unnamed items wait")
	-- names of other items (bags, tooltips) don't re-read the loot list; its own do
	local NF = I.loot.nameFrame
	NF.scripts.OnEvent(NF, "GET_ITEM_INFO_RECEIVED", 6948); FlushAll()
	check(ns.providers.loot._dirty == false, "an unrelated item's name leaves the loot list alone")
	iname[1002] = "Red Defias Mask"
	NF.scripts.OnEvent(NF, "GET_ITEM_INFO_RECEIVED", 1002); NF.scripts.OnEvent(NF, "GET_ITEM_INFO_RECEIVED", 1002); FlushAll()
	check(ns.providers.loot._dirty == true, "a loot item's name arriving re-reads the list")
	check(names(ns:GetEntries(ns.providers.loot))["Red Defias Mask"], "and appear once named")
	check(not I.loot.unnamed[1002], "named: no longer waited on")
	-- Enter opens AtlasLoot on that boss and points at the item
	local e = names(ns:GetEntries(ns.providers.loot))["Red Defias Mask"]
	local hl0 = #log
	e.activate(e); FlushAll()
	check(AtlasLoot.GUI.frame.shown or AtlasLoot.GUI.frame:IsShown(), "AtlasLoot window shown")
	check(table.concat(sel, ","):find("module=ALDungeons,content=DEADMINES,boss=1,diff=1", 1, true), "selected module, instance, boss, difficulty: " .. table.concat(sel, ","))
	-- AtlasLoot skips a refresh within 0.1 s of the last: after the picks the list is refreshed once
	-- more past that guard, on the item's page
	local last = refreshes[#refreshes]
	check(last and last.skip == true and last.page == 0, "the item list is refreshed after the picks, on the item's page")
	e.page = 1
	e.activate(e); FlushAll()
	check(refreshes[#refreshes].page == 1, "an item past position 100 opens on the second page")
	-- the index is saved: the next session takes its rows from it without loading any module
	local saved = ns.db.lootCache
	check(type(saved) == "table" and type(saved.key) == "string" and saved.key:find("ALDungeons", 1, true) and #saved.groups >= 2,
		"the loot index is saved with what it was built from: " .. tostring(saved and saved.key))
	local nRows = #I.loot.rows
	local function newSession()
		I.loot.rows, I.loot.byKey, I.loot.pending, I.loot.unnamed = {}, {}, {}, {}
		I.loot.done, I.loot.loaded, I.loot.cached = false, 0, nil
		ns.providers.loot._dirty = true
	end
	newSession()
	local mark = #log
	local storageBefore = AtlasLoot.ItemDB.Storage
	AtlasLoot.ItemDB.Storage = {} -- nothing loaded this session
	check(ns.providers.loot.busy() == nil, "no loading ring while the saved index is waited on")
	I.LoadLootModules()
	check(ns.providers.loot.busy() == nil, "nor once it's read")
	FlushAll()
	check(not logHas("ALLoad ALDungeons", mark + 1) and I.loot.done and I.loot.cached and #I.loot.rows == nRows,
		"a new session: rows from the saved index, no module loaded (" .. #I.loot.rows .. " of " .. nRows .. ")")
	local cb = names(ns:GetEntries(ns.providers.loot))["Cruel Barb"]
	check(cb and cb.detail == "Edwin VanCleef  The Deadmines" and cb.diff == 1 and cb.page == 0, "cached rows keep boss, instance, difficulty and page")
	-- Enter on one: its module is loaded first, then the window opens on it
	AtlasLoot.Loader.LoadModule = function(_, a) note("ALLoad", a); AtlasLoot.ItemDB.Storage = storageBefore end
	mark = #log
	cb.activate(cb); FlushAll()
	check(logHas("ALLoad ALDungeons", mark + 1) and table.concat(sel, ","):find("module=ALDungeons", 1, true), "Enter loads the module, then opens AtlasLoot on the item")
	-- AtlasLoot updated: the index is built again
	local baseMeta = C_AddOns.GetAddOnMetadata
	C_AddOns.GetAddOnMetadata = function(n, f) if f == "Version" then return "9.9.9" end end
	newSession(); mark = #log
	I.LoadLootModules()
	check(ns.providers.loot.busy() and ns.providers.loot.busy():find("Indexing AtlasLoot", 1, true), "building again shows the loading ring")
	FlushAll()
	check(ns.providers.loot.busy() == nil, "and stops when done")
	check(logHas("ALLoad ALDungeons", mark + 1) and not I.loot.cached and #I.loot.rows == nRows and ns.db.lootCache.key:find("9.9.9", 1, true),
		"a new AtlasLoot version: the index is built again and saved")
	C_AddOns.GetAddOnMetadata = baseMeta
	AtlasLoot.Loader.LoadModule = function(_, a) note("ALLoad", a) end
	-- WoW Forever's own items (Snake Eye Kaleidoscope) are named only by the server, which drops asks
	-- when thousands come at once: what's still unnamed is asked for again, and listed once named
	do
		iname[1002] = nil
		local asks = 0
		C_Item.RequestLoadItemDataByID = function(id)
			requested[#requested + 1] = id
			if id == 1002 then asks = asks + 1; if asks == 2 then iname[1002] = "Red Defias Mask" end end
		end
		newSession()
		I.LoadLootModules(); FlushAll()
		check(asks >= 2, "an item the server didn't name is asked for again: " .. asks)
		check(names(ns:GetEntries(ns.providers.loot))["Red Defias Mask"] and not I.loot.unnamed[1002],
			"and is listed once its name comes in")
		-- the waiting count is asked live: names that came in since the list was last read don't count
		iname[1001] = nil; I.loot.unnamed[1001] = true
		for _, r in ipairs(I.loot.rows) do if r.itemID == 1001 then r.name = nil end end
		check(I.LootWaiting() == 1, "an unnamed item is counted as waiting: " .. I.LootWaiting())
		iname[1001] = "Cruel Barb"
		check(I.LootWaiting() == 0 and not I.loot.unnamed[1001], "and no longer once its name has come in")
		for _, r in ipairs(I.loot.rows) do if r.itemID == 1001 then r.name = "Cruel Barb" end end
		-- GetItemInfo's name counts too (the client may have it before GetItemNameByID does)
		local baseGII = C_Item.GetItemInfo
		iname[1002] = nil
		local giiCalls = 0
		C_Item.GetItemInfo = function(id) giiCalls = giiCalls + 1; if id == 1002 then return "Red Defias Mask" end end
		I.loot.got[1002] = nil
		check(I.LootName(1002) == nil and giiCalls == 0, "reading the list never asks GetItemInfo (that would send every outstanding ask at once)")
		I.LootWaiting()
		check(giiCalls == 0, "nor does .integrations' waiting count")
		check(I.LootName(1002, true) == "Red Defias Mask", "the name pump asks GetItemInfo when GetItemNameByID has none")
		check(I.LootName(1002) == "Red Defias Mask", "and the name it gave is kept for the list")
		I.loot.got[1002] = nil
		C_Item.GetItemInfo = baseGII
		iname[1002] = "Red Defias Mask"
		local d, lt = I.GroupText("Wailing Caverns|cffffffff|TInterface\\Icons\\ltn4.tga:12|t|r", "Lord Cobrahn")
		check(d == "Lord Cobrahn  Wailing Caverns" and not lt:find("|", 1, true), "icon and colour codes in an instance name are dropped: " .. d)
		-- the list read again while a pump's retries are still waiting: one chain of asks, not two
		local asks2 = 0
		local reqWas = C_Item.RequestLoadItemDataByID
		iname[1002] = nil
		C_Item.RequestLoadItemDataByID = function(id) if id == 1002 then asks2 = asks2 + 1 end end
		newSession(); I.LoadLootModules()
		newSession(); I.LoadLootModules()
		FlushAll()
		local rounds = I.NAME_ROUNDS + I.NAME_SLOW_ROUNDS
		check(asks2 > I.NAME_ROUNDS + 1, "it keeps asking past the quick rounds, slowly (0.43.25): " .. asks2)
		check(asks2 <= rounds + 1, ("a newer pump stops the older one's retries: %d asks (rounds %d)"):format(asks2, rounds))
		-- an item the server says it doesn't have isn't asked for again, and a round with no new names doesn't
		-- rebuild the whole list (0.43.27: 30k rows every 120 s for an hour)
		local asks3, collects = 0, 0
		C_Item.RequestLoadItemDataByID = function(id) if id == 1002 then asks3 = asks3 + 1 end end
		local collectWas = ns.providers.loot.collect
		ns.providers.loot.collect = function(...) collects = collects + 1 return collectWas(...) end
		newSession(); I.LoadLootModules()
		ns:GetEntries(ns.providers.loot)
		I.loot.nameFrame.scripts.OnEvent(I.loot.nameFrame, "ITEM_DATA_LOAD_RESULT", 1002, false)
		collects = 0
		FlushAll()
		check(asks3 <= 1, "the server said it has no such item: not asked again: " .. asks3)
		check(not ns.providers.loot._dirty and collects == 0, "rounds that brought no names don't rebuild the list: " .. collects)
		ns.providers.loot.collect = collectWas
		I.loot.failed[1002] = nil
		iname[1002] = "Red Defias Mask"
		C_Item.RequestLoadItemDataByID = reqWas
		newSession(); I.LoadLootModules(); FlushAll()
		C_Item.RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end
	end
	-- Questie
	-- after login: one list, then the other (both at once doubled the work per frame); a few ms a frame
	do
		local order = {}
		for _, l in ipairs(ns.Debug.trace) do
			if l.msg:find("^questie: NPCs:") then order[#order + 1] = "npcs" elseif l.msg:find("^questie: quests:") then order[#order + 1] = "quests" end
		end
		check(order[1] == "npcs" and order[2] == "quests", "Questie's NPCs are indexed first, then its quests: " .. table.concat(order, ","))
		check((ns.background or 0) == 0, "and nothing is left running")
	end
	-- after login: the list, and its names as one text (for the hint rows)
	check(I.npc.list and #I.npc.list == 3, "Questie NPCs indexed in the background after login: " .. tostring(I.npc.list and #I.npc.list))
	check(I.npc.names == "\nedwin vancleef\t10\ndefias pillager\t11\nmarshal mcbride\t12\n",
		"and their names as one text: " .. tostring(I.npc.names))
	-- the NPC list freed when unused: its names stay, so plain searches still offer @npc without it
	ns.providers.npc.onDrop(); ns.providers.npc._entries = nil
	check(not I.npc.list and I.npc.names, "NPC list freed, names kept")
	-- only one NPC has the name: the NPC itself comes up (made from Questie's data, the list stays freed)
	do
		local few = UI:Search("marshal mcbride")
		check(few[1] and few[1].kind == "npc" and few[1].name == "Marshal McBride" and not few[1].completion and not I.npc.list,
			"one Questie NPC has it: the NPC is a result, not a row to step through: " .. tostring(few[1] and (few[1].completion or few[1].name)))
		check(few[1] and few[1].secure and few[1].npcID == 12, "...and it opens like an @npc row")
	end
	UI.HINT_FEW = 0 -- (the hint rows below: as for a list with many matches)
	local offer = UI:Search("marshal mcbride")
	local offered = false
	for _, e in ipairs(offer) do if e.completion == "@npc marshal mcbride" then offered = true end end
	check(offered and not I.npc.list, "the @npc row still comes up, and the list isn't rebuilt for it")
	check(ns.providers.questie.idleDrop == nil, "the quest list is kept (a few thousand quests)")
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
	check(I.qdb.names and I.qdb.names:find("\nthe defias brotherhood\t501\n", 1, true), "Questie quest names indexed as one text")
	do -- indexing a few milliseconds per frame, whatever each item costs; a failing item is skipped
		local realClock, t = _G.debugprofilestop, 0
		_G.debugprofilestop = function() t = t + 4; return t end -- each look at the clock: 4 ms
		local seen, finished = {}, false
		I.RunSliced("test", 10, function(i) if i == 4 then error("bad row") end seen[#seen + 1] = i end, function() finished = true end)
		check(#seen > 0 and #seen < 9 and not finished, "the first frame does only part of it: " .. #seen)
		FlushAll()
		check(finished and #seen == 9, "the rest in later frames, the failing item skipped: " .. #seen)
		_G.debugprofilestop = realClock
	end
	do -- the name text lookup
		local F = I.FindNames
		local blob = "\nedwin vancleef\t10\ndefias pillager\t11\ndefias trapper\t412\nsharptalon\t3928\n"
		local id, c = F(blob, { "defias" }); check(id == 11 and c == 2, "one word: the first match and how many")
		id, c = F(blob, { "trap", "defias" }); check(id == 412 and c == 1, "every word on the same line")
		id, c = F(blob, { "edwin", "pillager" }); check(id == nil and c == 0, "words on different lines don't count")
		id, c = F(blob, { "41" }); check(id == nil and c == 0, "digits of an id aren't a name")
		id, c = F(blob, { "sharp" }); check(id == 3928 and c == 1, "the last line")
		local many = {}
		for k = 1, 150 do many[k] = "\nwolf " .. k .. "\t" .. k end
		local ticks = 0
		id, c = F(table.concat(many) .. "\n", { "wolf" }, function() ticks = ticks + 1 end)
		check(id == 1 and c == 100 and ticks >= 1, "counts stop at 100 and the search is paused every so often")
	end
	check(I.qdb.list and #I.qdb.list == 3, "Questie quests indexed in the background after login: " .. tostring(I.qdb.list and #I.qdb.list))
	ns.providers.questie._dirty = true
	local qs = names(ns:GetEntries(ns.providers.questie))
	check(qs["The Defias Brotherhood"] and qs["The Defias Brotherhood"].detail == "Lv 14", "level shown: " .. tostring(qs["The Defias Brotherhood"] and qs["The Defias Brotherhood"].detail))
	check(qs["Red Linen Goods"].detail:find("done", 1, true), "completed quests are marked done")
	local w = qs["Wolves Across the Border"]
	check(w.detail:find("in log", 1, true) and w.secondarySecure and w.secondarySecure.binding == "TOGGLEQUESTLOG", "Shift+Enter on a quest you're on opens the quest log")
	check(w.questID == nil, "Questie entries don't drag log quests along")
	local plainHit = false
	for _, x in ipairs(UI:Search("defias brotherhood")) do if x.kind == "questie" then plainHit = true end end
	check(not plainHit, "Questie quests aren't in plain search")
	-- ...but a row on top offers them when only they have it: Tab (or Enter) adds @questie
	local r0 = UI:Search("defias brotherhood")[1]
	check(r0 and r0.completion == "@questie defias brotherhood" and r0.detail:find("The Defias Brotherhood", 1, true),
		"only Questie has it: the top row offers @questie (" .. tostring(r0 and r0.name) .. ")")
	UI:Open("defias brotherhood")
	check(UI:AcceptCompletion() and UI.edit:GetText() == "@questie defias brotherhood", "Tab adds @questie")
	check(UI.Results()[1] and UI.Results()[1].kind == "questie", "and the quest is found")
	UI:SetQuery("defias brotherhood")
	UI:Activate(1)
	check(UI:IsShown() and UI.edit:GetText() == "@questie defias brotherhood ", "Enter on that row does the same (a space for the next word), the terminal stays open")
	UI:Hide()
	local n0 = UI:Search("pillager")[1]
	check(n0 and n0.completion == "@npc pillager", "an NPC's name: the row offers @npc")
	-- a name that's a quest and an NPC both: a row for each
	local lootP = ns.providers.loot
	local wasExplicit = lootP and lootP.explicit
	if lootP then lootP.explicit = true end -- (the test's AtlasLoot has a "Red Defias Mask")
	local both = UI:Search("defias")
	if lootP then lootP.explicit = wasExplicit end
	check(both[1] and both[1].completion == "@questie defias" and both[2] and both[2].completion == "@npc defias"
		and both[1].name:find("Questie's quests", 1, true) and both[2].name:find("Questie's NPCs", 1, true),
		"in Questie's quests and NPCs both: a row for each (" .. tostring(both[1] and both[1].name) .. " / " .. tostring(both[2] and both[2].name) .. ")")
	local w0 = UI:Search("wolves across")[1]
	check(w0 and not w0.completion, "your own results have it (the quest log): nothing offered")
	check(not (UI:Search("de")[1] or {}).completion, "not for one or two letters")
	UI.HINT_FEW = 2
	-- one or two matches: the rows themselves (a quest and an NPC both: each one's row)
	do
		local both = UI:Search("defias")
		local kinds, hint = {}, nil
		for _, e in ipairs(both) do
			kinds[e.kind or "?"] = (kinds[e.kind or "?"] or 0) + 1
			hint = hint or e.completion
		end
		check(kinds.questie == 1 and kinds.npc == 1 and not hint,
			"defias: Questie's one quest and one NPC are results themselves, no hint rows: " .. tostring(hint))
	end
	r = UI:Search("@questie defias")
	check(r[1] and r[1].name == "The Defias Brotherhood", "@questie finds a quest by name")
	local byText = UI:Search("@questie scout riell")
	check(byText[1] and byText[1].name == "Red Linen Goods", "@questie finds a quest by its objectives text: " .. tostring(byText[1] and byText[1].name))
	-- filters: key:value words narrow the results (Filters.lua)
	local function namesOf(list) local t = {} for _, e in ipairs(list) do t[#t + 1] = e.name end table.sort(t) return table.concat(t, ",") end
	check(namesOf(UI:Search("@questie lvl:10-15")) == "Red Linen Goods,The Defias Brotherhood", "lvl:10-15: " .. namesOf(UI:Search("@questie lvl:10-15")))
	check(namesOf(UI:Search("@questie lvl:<10")) == "Wolves Across the Border", "lvl:<10")
	check(namesOf(UI:Search("@questie lvl:14")) == "The Defias Brotherhood" and namesOf(UI:Search("@questie lvl:13-")) == "The Defias Brotherhood", "lvl:14 and lvl:13-")
	check(namesOf(UI:Search("@questie is:done")) == "Red Linen Goods" and not namesOf(UI:Search("@questie is:todo")):find("Red Linen", 1, true), "is:done / is:todo")
	check(namesOf(UI:Search("@questie defias lvl:12-20")) == "The Defias Brotherhood" and namesOf(UI:Search("@questie defias lvl:1-5")) == "", "filters with words")
	-- a filter changed or dropped isn't a narrowing of the last search
	check(namesOf(UI:Search("@questie red lvl:13-")) == "The Defias Brotherhood", "a narrower search with a filter")
	check(namesOf(UI:Search("@questie red")):find("Red Linen Goods", 1, true), "dropping the filter brings the rows back: " .. namesOf(UI:Search("@questie red")))
	local F = ns.Filters
	check(F.Parse("foo:bar") == nil and F.Parse("lvl:abc") == nil and F.Parse("is:nothing") == nil and F.Parse("plain") == nil, "unknown filters stay search words")
	check(F.Parse("zone:ash")({ zone = "Ashenvale" }) and not F.Parse("zone:ash")({ zone = "Elwynn Forest" }) and not F.Parse("zone:ash")({}), "zone: by part of the zone's name")
	local baseInfo, baseCan = C_Item.GetItemInfo, C_PlayerInfo and C_PlayerInfo.CanUseItem
	C_Item.GetItemInfo = function(id) if id == 70 then return "Bracers", nil, 2, 20, 18, "Armor", "Mail", 1, "INVTYPE_WRIST" end end
	_G.INVTYPE_WRIST = "Wrist"
	_G.C_PlayerInfo = _G.C_PlayerInfo or {}
	C_PlayerInfo.CanUseItem = function(id) return true end
	local wrist = { itemID = 70 }
	check(F.Parse("slot:wrist")(wrist) and not F.Parse("slot:feet")(wrist) and not F.Parse("slot:wrist")({ name = "Not an item" }), "slot: the item's slot")
	check(F.Parse("lvl:15-20")(wrist) and not F.Parse("lvl:<18")(wrist), "lvl: the level an item needs")
	local baseLevel = UnitLevel
	UnitLevel = function() return 10 end
	check(not F.Parse("is:usable")(wrist), "is:usable: too low a level")
	UnitLevel = function() return 30 end
	check(F.Parse("is:usable")(wrist), "is:usable: high enough and the game says it can be used")
	C_PlayerInfo.CanUseItem = function() return false end
	check(not F.Parse("is:usable")(wrist), "is:usable: the game says it can't (another class's armour)")
	UnitLevel, C_Item.GetItemInfo, C_PlayerInfo.CanUseItem, _G.INVTYPE_WRIST = baseLevel, baseInfo, baseCan, nil
	local q = r[1]
	check(q.secondarySecure and q.secondarySecure.binding == "TOGGLEWORLDMAP", "Shift+Enter on a quest you don't have opens the map on its giver")
	-- Enter: its Wowhead link, selected in a small window, gone once Ctrl+C has copied it
	local CB = ns.CopyBox
	check(q.secure == nil, "Enter doesn't open a window")
	UI:Open("@questie defias"); key("ENTER"); FlushAll()
	local LF = CB.linkFrame
	check(LF and LF.shown and CB.Text() == "https://www.wowhead.com/forever/quest=" .. q.qid and LF.h <= 70 and not (CB.frame and CB.frame.shown), "Enter shows the quest's Wowhead link in a slim bar: " .. tostring(CB.Text()) .. " h=" .. tostring(LF and LF.h))
	check(CB.linkEdit.text == CB.Text(), "the link is in the bar's text box")
	check(not UI:IsShown(), "and the terminal steps aside")
	_G.IsControlKeyDown = function() return true end
	CB.linkEdit.scripts.OnKeyDown(CB.linkEdit, "C")
	_G.IsControlKeyDown = function() return false end
	FlushAll()
	check(CB.copied and LF.shown == false, "Ctrl+C copies it and the bar closes")
	-- in combat the link still shows (no window of the game's is opened)
	_G.InCombatLockdown = function() return true end
	q.activate(q)
	check(LF.shown and CB.Text():find("quest=", 1, true), "in combat Enter still shows the link")
	_G.InCombatLockdown = function() return false end
	CB.Hide()
	-- .debug log keeps its big window
	ns:ShowText("x", { "a", "b" })
	check(CB.frame.h == 440 and CB.frame.shown and not LF.shown, "other text keeps the big window")
	CB.Hide()
	mark = #log
	q.secondaryAfter(q)
	check(logHas("QuestieShowNPC 12", mark + 1) and logHas("Waypoint 37 0.5 0.4", mark + 1), "quest giver shown and pinned")
	local said = {}
	local basePrint = ns.Print
	ns.Print = function(_, m) said[#said + 1] = m end
	qs["Red Linen Goods"].secondary(qs["Red Linen Goods"])
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
	C_Item.GetItemInfo = baseInfo
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
	UI.showRecent = true -- (Down on the bare prompt shows them)
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
	UI.showRecent = nil
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
	local saveInfo = C_Item.GetItemInfo
	C_Item.GetItemInfo = function(id) return "Item " .. id, "|Hitem:" .. id .. "|h[Item " .. id .. "]|h" end
	es["Tank Gear"].secondary(es["Tank Gear"])
	C_Item.GetItemInfo = saveInfo
	ns.Output = baseOut
	local joined = table.concat(out, "\n")
	check(out[1] == "Tank Gear:" and joined:find("Head:", 1, true) and joined:find("Main Hand:.-%(missing%)"), "without a character key, Shift+Enter lists the items, marking missing ones: " .. joined)
	check(joined:find("Head: |Hitem:501|h", 1, true), "the items as links (0.44.16: the link was dropped by an `and`): " .. joined)
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
		{ name = "Steamwheedle Cartel", isHeader = true, isHeaderWithRep = true, factionID = 169, reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000, currentStanding = 4000 },
		{ name = "Gadgetzan", isHeader = true, isChild = true, isHeaderWithRep = true, factionID = 369, reaction = 5, currentReactionThreshold = 3000, nextReactionThreshold = 9000, currentStanding = 5000 },
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
	check(reps["Steamwheedle Cartel"] and not (reps["Steamwheedle Cartel"].tip or ""):find("Classic", 1, true),
		"a top-level header with its own standing isn't put under the header before it: " .. tostring(reps["Steamwheedle Cartel"] and reps["Steamwheedle Cartel"].tip))
	check(reps["Gadgetzan"] and (reps["Gadgetzan"].tip or ""):find("Steamwheedle Cartel", 1, true), "a sub-header's group is its parent header")
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
do -- big searches go on over several frames: the best so far first, then the full results
	local big = {}
	for i = 1, 3000 do big[i] = { key = i, name = ("Bigrow %04d %s"):format(i, i % 3 == 0 and "alpha" or "beta") } end
	ns:RegisterProvider("bigtest", { label = "Big", aliases = { "bigtest" }, explicit = true, collect = function() return big end })
	ns:GetEntries(ns.providers.bigtest)
	local realClock = _G.debugprofilestop
	local ms = 0
	_G.debugprofilestop = function() ms = ms + 1; return ms end -- every look at the clock: 1 ms
	UI:Hide(); FlushAll()
	UI:Open("@bigtest alpha")
	local job = UI.searchJob
	local early = #UI.Results()
	check(job and early > 0 and early <= 100, "a big search: the best matches so far show at once (" .. early .. "), the rest goes on")
	local lines = UI:BusyLines()
	check(lines[1] and lines[1]:find("Searching", 1, true) and UI.busy.shown, "the spinner says it's still searching")
	-- the selected row stays selected when the full results come in
	UI:Down(); UI:Down()
	local picked = UI.Results()[3]
	check(UI.Selected() == 3, "row 3 picked while it's still searching")
	FlushAll()
	check(UI.searchJob == nil and #UI.Results() == 100 and UI.lastSearchSlices > 1,
		"then it finishes over the next frames (" .. tostring(UI.lastSearchSlices) .. " frames)")
	_G.debugprofilestop = realClock
	local want = UI:Search("@bigtest alpha")
	local same = true
	for i = 1, 100 do if UI.Results()[i] ~= want[i] then same = false end end
	check(same, "the full results are the same as a search done at once")
	local now = UI.Results()
	local at
	for i, e in ipairs(now) do if e == picked then at = i end end
	check(picked and at and UI.Selected() == at, "the row picked meanwhile stays selected (now row " .. tostring(at) .. ")")
	check(not UI:BusyLines()[1], "and the spinner stops")
	-- typing again mid-search: the old search stops, the new one finishes
	_G.debugprofilestop = function() ms = ms + 1; return ms end
	UI:SetQuery("@bigtest beta")
	local old = UI.searchJob
	UI:SetQuery("@bigtest beta 1")
	check(old and UI.searchJob ~= old, "typing again drops the search still going on")
	FlushAll()
	_G.debugprofilestop = realClock
	check(UI.searchJob == nil and UI.Results()[1] and UI.Results()[1].name:find("beta", 1, true), "and the new one finishes")
	-- the game reports the text as changed without a change (the box resized): no new search,
	-- the one going on finishes, and scrolling meanwhile is kept
	_G.debugprofilestop = function() ms = ms + 1; return ms end
	UI:SetQuery("@bigtest alpha")
	local job2 = UI.searchJob
	local searches = 0
	local realRun = UI.RunSearch
	UI.RunSearch = function(self, ...) searches = searches + 1 return realRun(self, ...) end
	UI.edit.scripts.OnTextChanged(UI.edit)
	check(job2 and UI.searchJob == job2 and searches == 0, "a change report with the same text doesn't restart the search")
	UI:Scroll(-2) -- down 6 rows
	local topBefore = UI.Results()[7]
	FlushAll()
	UI.edit.scripts.OnTextChanged(UI.edit)
	UI.RunSearch = realRun
	_G.debugprofilestop = realClock
	check(UI.searchJob == nil and searches == 0, "it finishes, and isn't started again after")
	check(UI.Selected() > 6 and UI.Results()[UI.Selected()] == topBefore or UI.Selected() > 6,
		"the list stays scrolled where you put it (row " .. UI.Selected() .. " selected)")
	-- a sum while a search is spread over frames: its answer is on top from the first frame
	_G.debugprofilestop = function() ms = ms + 1; return ms end
	UI:SetQuery("3*4")
	local first = UI.Results()[1]
	FlushAll()
	_G.debugprofilestop = realClock
	check(first and first.kind == "calc" and UI.Results()[1].kind == "calc", "a sum's answer is the top row from the first frame")
	-- without a clock (or for callers outside the terminal), a search is done at once
	check(#UI:Search("@bigtest alpha") == 100 and UI.searchJob == nil, "UI:Search itself always finishes at once")
	UI:Hide(); FlushAll()
	ns.providers.bigtest = nil
	for i, id in ipairs(ns.providerOrder) do if id == "bigtest" then table.remove(ns.providerOrder, i) break end end
end
do -- prewarming: lists built ahead of their first search, one at a time, while nothing else goes on
	local W = ns.warm
	check(W.started, "prewarming starts at login")
	local loading = true
	local built = 0
	ns:RegisterProvider("warmslow", { label = "WS", aliases = { "warmslow" }, explicit = true,
		busy = function() return loading and "loading" or nil end,
		collect = function() built = built + 1; return { { name = "Slow thing" } } end })
	ns:RegisterProvider("warmfast", { label = "WF", aliases = { "warmfast" }, lazy = true,
		collect = function() return { { name = "Fast thing" } } end })
	local hugeBuilt = false
	ns:RegisterProvider("warmhuge", { label = "WH", aliases = { "warmhuge" }, explicit = true, idleDrop = 600,
		collect = function() hugeBuilt = true; return { { name = "Huge thing" } } end })
	W.queue, W.done = nil, nil
	for _, id in ipairs(ns.providerOrder) do ns.providers[id]._dirty = true end
	local realCombat = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	check(ns:PrewarmStep() == true and W.queue == nil, "in combat: nothing is built (later)")
	_G.InCombatLockdown = realCombat
	UI:Open("")
	check(ns:PrewarmStep() == true and W.queue == nil, "with the terminal open: nothing is built (later)")
	UI:Hide(); FlushAll()
	ns.background = 1 -- (Questie's lists still indexing)
	check(ns:PrewarmStep() == true and W.queue == nil, "while Questie's lists index: nothing is built (later)")
	ns.background = 0
	for _, id in ipairs(ns.providerOrder) do ns.providers[id]._dirty = true end
	local before = ns.providers.warmfast._entries
	local steps = 0
	while steps < 200 and not ns.providers.warmfast._entries do ns:PrewarmStep(); steps = steps + 1 end
	check(ns.providers.warmfast._entries and ns.providers.warmfast._entries[1].name == "Fast thing", "lists get built, one per step")
	check(built == 0, "a list still loading waits")
	loading = false
	while steps < 400 and not W.done do ns:PrewarmStep(); steps = steps + 1 end
	check(built == 1 and W.done and not ns.providers.warmslow._dirty, "and is built once it's in; then prewarming stops")
	check(ns:PrewarmStep() == false, "nothing left to do")
	check(not hugeBuilt, "huge lists freed when unused (Questie, NPCs) aren't built at login")
	ns.providers.warmhuge = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "warmhuge" then table.remove(ns.providerOrder, i) end end
	ns.providers.warmslow, ns.providers.warmfast = nil, nil
	for i = #ns.providerOrder, 1, -1 do
		local id = ns.providerOrder[i]
		if id == "warmslow" or id == "warmfast" then table.remove(ns.providerOrder, i) end
	end
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
		-- the game's list can name a skill twice (Blacksmithing on WoW Forever)
		{ name = "Professions", isHeader = true, isExpanded = true },
		{ name = "Blacksmithing", rank = 60, maxRank = 150, skillID = 164 },
		{ name = "Blacksmithing", rank = 60, maxRank = 150, skillID = 9164 },
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
	local bs = 0
	for _, e in ipairs(ns:GetEntries(ns.providers.skills)) do if e.name == "Blacksmithing" then bs = bs + 1 end end
	check(bs == 1, "a skill the game lists twice is shown once (" .. bs .. ")")
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
	check(Th.Get().animations == "smooth", "'.set animations on' still works: the default style")
	UI:Hide(); for _ = 1, 10 do step(0.05) end
	-- animation styles
	local saved = ns.db.theme
	ns.db.theme = { animations = false }
	check(Th.Get().animations == "off" and Th.Animation() == nil, "a theme saved with animations off stays off")
	ns.db.theme = { animations = true }
	check(Th.Get().animations == "smooth", "a theme saved with animations on gets the default style")
	ns.db.theme = saved
	-- drop down: drops in from above, and goes back up
	check(Th.Set("animations", "console") and Th.Get().animations == "dropdown", "the style called console in 0.29.0 is Drop Down now")
	ns.db.theme = { animations = "console" }
	check(Th.Get().animations == "dropdown", "a theme saved with it gets Drop Down")
	ns.db.theme = saved
	Th.Set("animations", "dropdown")
	check(Th.ANIMATION_LABELS.dropdown == "Drop Down", "labelled Drop Down")
	UI:Open("heart")
	local p = F.lastPoint
	check(UI.phase == "open" and p and p[5] > -140, "drop down: starts above its place and drops in (" .. tostring(p and p[5]) .. ")")
	for _ = 1, 10 do step(0.05) end
	check(F.alpha == 1 and F.lastPoint[5] == -140, "and lands in place")
	-- cascade: new rows come in one after another, sliding in from the left
	Th.Set("animations", "cascade")
	UI:SetQuery("hearthstone", 11); step(0.6)
	local few = #UI.Results()
	UI:SetQuery("e", 1)
	local r = UI.rows[few + 1]
	-- (a row's last anchor is its right edge: TOPRIGHT, -6 + how far it is from its place)
	check(r.slide and r.lastPoint and r.lastPoint[2] < -6 - 30, "cascade: a new row starts well to the left of its place (" .. tostring(r.lastPoint and r.lastPoint[2]) .. ")")
	for _ = 1, 20 do step(0.05) end
	check(r.slide == nil and r.lastPoint[2] == -6 and r.alpha == 1, "and slides into place")
	-- cascade: closing, the rows fold away bottom-up, sliding back out to the left
	UI:Hide()
	local folding, order = 0, {}
	for i, row in ipairs(UI.rows) do if row.leaving and row.slideOut then folding = folding + 1; order[#order + 1] = row.leaveAt end end
	check(folding >= 2 and order[1] > order[#order], "cascade: closing folds the rows away, the bottom one first")
	for _ = 1, 20 do step(0.05) end
	check(F.shown == false and UI.rows[1].lastPoint[2] == -6, "and they're back in place for the next open")
	-- every open brings the rows in with the style, not only the first (they used to stay up
	-- between closes, and opening put them up at once: every style looked like a plain fade)
	for round = 1, 2 do
		UI:Open("e")
		local r1 = UI.rows[1]
		check(r1.shown and r1.slide and r1.lastPoint[2] < -6 - 30 and (r1.alpha or 1) == 0,
			"cascade, open #" .. round .. ": the first row swings in from the left (" .. tostring(r1.lastPoint[2]) .. ")")
		for _ = 1, 30 do step(0.05) end
		check(r1.lastPoint[2] == -6 and r1.alpha == 1, "cascade, open #" .. round .. ": and lands in place")
		UI:Hide(); for _ = 1, 20 do step(0.05) end
		check(F.shown == false and not r1.shown, "closed: the rows went with it")
	end
	Th.Set("animations", "smooth")
	UI:Open("e")
	check((UI.rows[1].alpha or 1) == 0 and UI.rows[1].fadeAt, "smooth: rows fade in on a reopen too")
	UI:Hide(); for _ = 1, 20 do step(0.05) end
	Th.Set("animations", "cascade")
	-- snappy: pops in with a little bounce (passes its place, then settles), and the selection jumps
	Th.Set("animations", "snappy")
	UI:Open("e")
	local passed = false
	for _ = 1, 20 do step(0.016); if F.lastPoint[5] > -140 then passed = true end end
	check(passed and F.lastPoint[5] == -140 and F.alpha == 1, "snappy: pops in, overshooting its place a little, then settles")
	UI:Down()
	step(0.016)
	check(UI.selY == UI.selTo, "snappy: the selection jumps at once")
	UI:Hide(); step(0.07)
	check(F.shown == false, "snappy: closed in a blink")
	-- resting (only the cursor blinking): at most 30 redraws a second, not every frame
	Th.Set("animations", "smooth")
	UI:Open("heart"); for _ = 1, 40 do step(0.016) end
	local M0 = UI.motion
	local redraws, realCA = 0, UI.caret.SetAlpha
	UI.caret.SetAlpha = function(self, ...) redraws = redraws + 1 return realCA(self, ...) end
	for _ = 1, 120 do step(1 / 120) end -- one second at 120 frames a second
	UI.caret.SetAlpha = realCA
	check(M0.shown ~= false and UI.blinkOnly and redraws <= 31, "resting: the cursor blinks with at most 30 redraws a second (" .. redraws .. " at 120 fps)")
	UI:SetQuery("hearthstone", 11)
	check(UI.blinkOnly == false, "typing wakes the animation loop at once")
	UI:Hide(); for _ = 1, 10 do step(0.05) end
	Th.Set("animations", "smooth")
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
	check(tab("@questd") == "@questdb " or tab("@contin") == "@continent ", "a single kind completes, with a space: " .. q())
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
	local qqs = 0
	_G.Questie = { API = { isReady = true } }
	_G.QuestieLoader = { ImportModule = function(_, n) return n == "QuestieDB" and {
		QueryQuestSingle = function(id, f) qqs = qqs + 1 if id == 99 and f == "requiredSourceItems" then return { 7007 } end end,
	} or nil end }
	ns.providers.items._dirty = true
	qqs = 0
	it = names(ns:GetEntries(ns.providers.items))
	check(it["Sealed Parchment"].questID == 99, "Questie: the quest needs this item")
	check(qqs <= 3 * #quests, "Questie is asked once per quest, not per item and quest (" .. qqs .. " asks for " .. #quests .. " quests)")
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

----------------------------------------------------------------------
-- macros, history, aliases, non-English clients
----------------------------------------------------------------------
io.write("[macros + history + locale tests]\n")
do
	local S = ns.Secure
	local function key(k, char) F.scripts.OnKeyDown(F, k); if char then F.scripts.OnChar(F, char) end end
	local function typeText(s) for ch in s:gmatch(".") do key(ch == " " and "SPACE" or ch:upper(), ch) end end
	local function query() return UI.edit:GetText() end
	local function withShift(fn) _G.IsShiftKeyDown = function() return true end; fn(); _G.IsShiftKeyDown = function() return false end end
	local function first() local r = UI.Results(); return r[1] end

	-- macros: found by name or by what they say; Enter and a click run them through the game
	ns.providers.macros._dirty = true
	local mes = ns:GetEntries(ns.providers.macros)
	local me = mes[1]
	check(me and me.name == "Heal Macro" and me._ltext:find("flash heal", 1, true), "the macro is searchable by its text")
	UI:Open("flash heal")
	check(first() and first().name == "Heal Macro", "searching a macro's text finds it: " .. tostring(first() and first().name))
	local r = S.Resolve(me.secure, me)
	check(r and r.macro == "#showtooltip\n/cast Flash Heal", "Enter runs the macro's own text through the game")
	check(UI.ClickFor(me, false) == "#showtooltip\n/cast Flash Heal", "a click runs it too")
	check(me.noCombat == true, "no macros from here in combat")
	check(me.detail:find("Flash Heal", 1, true) and not me.detail:find("showtooltip", 1, true), "the details show its first command: " .. me.detail)
	UI:Open("heal macro")
	check(first().name == "Heal Macro", "found by name")
	key("ENTER")
	check(S.armed == "MACRO" and _G.TerminalMacroProxy.attrs.macrotext == "#showtooltip\n/cast Flash Heal", "Enter arms the macro button with its text")
	check(F.propagate == true, "and the same press goes on to the game")
	S.Disarm(); UI:Hide()
	-- edited after the list was built: the current text runs
	local realInfo = _G.GetMacroInfo
	_G.GetMacroInfo = function() return "Heal Macro", 1, "/cast Renew" end
	check(S.Resolve(me.secure, me).macro == "/cast Renew", "an edited macro runs its new text")
	_G.GetMacroInfo = function() return "Other", 1, "/cast Smite" end
	check(S.Resolve(me.secure, me) == nil, "a macro that's gone or renamed runs nothing")
	_G.GetMacroInfo = realInfo
	-- Shift+Enter: the macro window, opened by the game
	local sv = UI.SecureView(me, true)
	check(sv and S.Resolve(sv.secure, sv).macro == "/macro", "Shift+Enter opens the Macros window through the game")
	ns.providers.panels._dirty = true
	local macroPanel
	for _, e in ipairs(ns:GetEntries(ns.providers.panels)) do if e.key == "Macros" then macroPanel = e end end
	check(macroPanel and S.Resolve(macroPanel.secure, macroPanel).macro == "/macro", "the Macros panel opens by a secure macro, not from our code")

	-- history
	for i = #ns.db.history, 1, -1 do ns.db.history[i] = nil end
	ns:RecordHistory("  hello  "); ns:RecordHistory("world"); ns:RecordHistory("hello"); ns:RecordHistory("")
	check(#ns.db.history == 2 and ns.db.history[1] == "hello" and ns.db.history[2] == "world", "history keeps each line once, newest first")
	for i = 1, 60 do ns:RecordHistory("line " .. i) end
	check(#ns.db.history == 50 and ns.db.history[1] == "line 60", "history keeps the last 50")
	for i = #ns.db.history, 1, -1 do ns.db.history[i] = nil end
	UI:Open(".about"); key("ENTER")
	check(ns.db.history[1] == ".about", "running a line records it: " .. tostring(ns.db.history[1]))
	UI:Open(".mem"); key("ENTER")
	UI:Open("")
	key("UP"); check(query() == ".mem", "Up on an empty prompt brings back the last line: '" .. query() .. "'")
	key("UP"); check(query() == ".about", "Up again goes further back")
	key("UP"); check(query() == ".about", "and stops at the oldest")
	key("DOWN"); check(query() == ".mem", "Down comes forward")
	key("DOWN"); check(query() == "" and UI.histIdx == nil, "Down past the newest empties the prompt again")
	-- the game may report SetText's change a frame later: Up, then Down still comes back to the empty prompt
	do
		local edit = UI.edit
		edit.SetText = function(self, t) self.text = t or ""; C_Timer.After(0, function() local f = self.scripts.OnTextChanged; if f then f(self) end end) end
		key("UP"); Flush()
		check(query() == ".mem" and UI.histIdx == 1, "Up (late text event): the last line, still walking")
		key("DOWN"); Flush()
		check(query() == "" and UI.histIdx == nil, "then Down: back to the empty prompt: '" .. query() .. "'")
		edit.SetText = nil
	end
	key("UP"); typeText("x")
	check(UI.histIdx == nil and query() == ".memx", "typing leaves the history: " .. query())
	UI:SetQuery("heal", 4)
	key("UP"); check(query() == "heal", "Up with something typed still moves the list, not the history")
	UI:SetQuery("", 0); UI.lastQuery = nil; key("DOWN"); check(query() == "", "Down on an empty prompt with no last search: still empty (your recent picks)")
	UI:Hide()
	UI:Open("")
	check(UI.histIdx == nil, "a new session starts at the newest")
	UI:Hide()
	check(table.concat(ns.commands.history.run(""), "\n"):find(".mem", 1, true), ".history lists the lines")
	ns.commands.history.run("clear"); check(#ns.db.history == 0, ".history clear forgets them")

	-- aliases are gone
	check(ns.commands.alias == nil and ns.commands.unalias == nil and ns.providers.alias == nil, "no .alias any more")
	local realOut = ns.Output

	-- non-English clients
	check(ns.Lower("\195\137QUIPEMENT") == "\195\169quipement", "accented capitals fold: " .. ns.Lower("\195\137QUIPEMENT"))
	check(ns.Lower("\208\160\208\171\208\145\208\144") == "\209\128\209\139\208\177\208\176", "Cyrillic folds")
	check(ns.Lower("\206\145\206\146") == "\206\177\206\178", "Greek folds")
	check(ns.Lower("\197\129") == "\197\130" and ns.Lower("Abc \237\149\156") == "abc \237\149\156", "Latin Extended folds; Korean is left alone")
	ns:RegisterProvider("acctest", { label = "AT", aliases = { "acctest" }, collect = function() return { { name = "\195\137quipe" } } end })
	UI:Open("\195\137QUI")
	check(first() and first().kind == "acctest", "search ignores the case of accented letters")
	UI:Hide()
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "acctest" then table.remove(ns.providerOrder, i) end end
	ns.providers.acctest = nil
	-- the game's own words for the kinds
	_G.REPUTATION = "\237\143\137\237\140\144"
	_G.MACROS = "\235\167\164\237\129\172\235\161\156"
	_G.EQUIPMENT_MANAGER = "Gestionnaire d'\195\169quipement"
	for _, id in ipairs({ "reputation", "macros", "equipmentset" }) do ns.LocalizeKind(ns.providers[id]); ns.LocalizeKind(ns.providers[id]) end
	check(ns:ResolveProvider("\237\143\137\237\140\144") == ns.providers.reputation, "@(Korean reputation) filters reputation")
	check(ns:ResolveProvider("\235\167\164\237\129\172\235\161\156") == ns.providers.macros, "@(Korean macros) filters macros")
	check(ns:ResolveProvider("GESTIONNAIRED\226\128\153\195\137QUIPEMENT") == nil and ns:ResolveProvider("gestionnaired\195\169quipement") == ns.providers.equipmentset, "a localised name with punctuation and accents is one token")
	local n = 0
	for _, a in ipairs(ns.providers.reputation.aliases) do if a == "\237\143\137\237\140\144" then n = n + 1 end end
	check(n == 1 and ns:ResolveProvider("rep") == ns.providers.reputation, "added once; the English words still work")
	-- panels carry the game's name; English still finds them
	ns.providers.panels._dirty = true
	local rep
	for _, e in ipairs(ns:GetEntries(ns.providers.panels)) do if e.key == "Reputation" then rep = e end end
	check(rep and rep.name == "\237\143\137\237\140\144" and rep._ltext:find("reputation", 1, true), "panel shown in the game's language, found by the English word too")
	_G.REPUTATION, _G.MACROS, _G.EQUIPMENT_MANAGER = nil, nil, nil
	ns.providers.panels._dirty = true
	-- name keys keep every language's letters (the old [^%w] key turned every Korean name into "")
	check(ns.Norm("\237\143\137\237\140\144") == "\237\143\137\237\140\144" and ns.Norm("|cffff0000Deadly Boss-Mods!|r") == "deadlybossmods", "Norm keeps letters and drops spaces, punctuation and colours")
	check(ns.Norm("\237\143\137") ~= ns.Norm("\235\167\164"), "two Korean names don't share a key")
	check(ns.GameText("NO_SUCH_GLOBAL_X", "fb") == "fb", "GameText falls back")
	_G.TEST_FMT = "%s things"; check(ns.GameText("TEST_FMT", "fb") == "fb", "format strings aren't used as names"); _G.TEST_FMT = nil
	-- a provider registered late (AtlasLoot's, after login) gets the game's words too
	_G.LOOT = "\236\160\132\235\166\172\237\146\136"
	ns:RegisterProvider("loot", { label = "Loot", aliases = { "loot" }, collect = function() return {} end })
	check(ns:ResolveProvider("\236\160\132\235\166\172\237\146\136") == ns.providers.loot, "late providers are localised too")
	_G.LOOT = nil
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "loot" then table.remove(ns.providerOrder, i) end end
	ns.providers.loot = nil
	-- highlighting never splits a multi-byte letter
	local F2 = ns.Fuzzy
	local c = F2.Colorize("\237\143\137\237\140\144", { [1] = true })
	check(c == (F2.matchColor or "|cffffd200") .. "\237\143\137|r\237\140\144", "a hit on one byte colours the whole letter")
	c = F2.Colorize("a\237\143\137b", { [3] = true })
	check(c:find("\237\143\137", 1, true) and not c:find("\237|c", 1, true) and not c:find("\237\143|c", 1, true), "no colour code lands inside a letter")
	_G.GetMacroInfo = realInfo
end

-- command arguments listed as you type them
io.write("[argument rows tests]\n")
do
	local function key(k, char) F.scripts.OnKeyDown(F, k); if char then F.scripts.OnChar(F, char) end end
	local function names() local o = {} for i, e in ipairs(UI.Results()) do o[i] = e.name end return o end
	local Th = ns.Theme
	Th.Reset()
	UI:Open(".theme ")
	local r = UI.Results()
	check(r[1] and r[1].name == "theme" and not r[1].argLine, "with nothing typed, the command itself comes first (Enter runs it as typed)")
	check(r[2] and r[2].name == "forever" and r[2].detail:find("Forever", 1, true) and r[2].detail:find("current", 1, true), "then every theme, with its label and the current one marked: " .. tostring(r[2] and r[2].detail))
	check(#r == #Th.PRESET_ORDER + 2 and r[#r].name == "reset", "all themes and reset listed: " .. #r)
	UI:SetQuery(".theme dr", 9)
	r = UI.Results()
	check(#r == 1 and r[1].name == "dracula" and r[1].kindLabel:find(".theme", 1, true), "typing narrows the list: " .. table.concat(names(), ","))
	key("ENTER")
	check(Th.Get().preset == "dracula" and not UI:IsShown(), "Enter runs the command with the listed argument")
	-- Tab and the arrows pick a row
	UI:Open(".theme ")
	key("DOWN"); key("DOWN"); key("ENTER")
	check(Th.Get().preset == "foreverblue", "arrows pick an argument row: " .. Th.Get().preset)
	-- matches at the start come before matches inside the word
	UI:Open(".set a")
	local n = names()
	check(n[1] == "accent" and n[2] == "animations" and n[3] == "autoScan" and n[4] ~= nil, "starts-with first, then the rest: " .. table.concat(n, ","))
	-- .set: settings with their values, then a setting's values
	UI:Open(".set ")
	r = UI.Results()
	local cursorRow
	for _, e in ipairs(r) do if e.name == "cursor" then cursorRow = e end end
	check(r[1].name == "set" and cursorRow and cursorRow.detail:find("blinking-line", 1, true), "settings listed with their current values: " .. tostring(cursorRow and cursorRow.detail))
	UI:SetQuery(".set cursor ", 12)
	check(table.concat(names(), ",") == "set,blinking-line,solid-line,blinking-box,solid-box", "a setting's choices listed: " .. table.concat(names(), ","))
	check(UI.Results()[2].detail:find("Blinking line", 1, true) and UI.Results()[2].detail:find("current", 1, true), "with labels, current marked")
	UI:SetQuery(".set cursor sb", 14)
	check(#UI.Results() == 0 or UI.Results()[1].name == "set", "no listed value matches: back to the command row")
	UI:SetQuery(".set cursor solid-b", 19)
	key("ENTER")
	check(Th.Get().cursor == "solid-box", "Enter applies the value")
	-- free values (colours) still run as typed
	UI:Open(".set accent 123456")
	check(UI.Results()[1].name == "set", "free values: the command row")
	key("ENTER"); check(Th.Get().accent == "123456", "and Enter runs it as typed")
	-- Tab still completes from the same list
	UI:Open(".set cur"); key("TAB"); check(UI.edit:GetText() == ".set cursor ", "Tab completes a setting: " .. UI.edit:GetText())
	key("TAB"); key("TAB")
	check(UI.edit:GetText() == ".set cursor ", "nothing shared: Tab moves down the rows")
	-- commands without listed arguments behave as before
	UI:Open(".history ")
	check(UI.Results()[1].name == "history" and UI.Results()[2].name == "clear", ".history lists clear")
	UI:Open(".mem ")
	check(UI.Results()[1].name == "mem" and #UI.Results() >= 1, "no list: the command row")
	UI:Open(".debug ")
	check(UI.Results()[2].name == "log" and UI.Results()[2].detail:find("copyable", 1, true), ".debug explains its arguments")
	UI:Hide()
	Th.Reset()
end

-- items on alts and in banks, from Syndicator or BagBrother
io.write("[stored items tests]\n")
do
	local St = ns.Stored
	local P = ns.providers.stored
	local function key(k, char) F.scripts.OnKeyDown(F, k); if char then F.scripts.OnChar(F, char) end end
	local function entries() P._dirty = true; local by = {} for _, e in ipairs(ns:GetEntries(P)) do by[e.itemID] = e end return by end
	local said = {}
	local realOut = ns.Output
	ns.Output = function(_, lines) for _, l in ipairs(lines) do said[#said + 1] = l end end
	local baseName, baseReq, baseQual = C_Item.GetItemNameByID, C_Item.RequestLoadItemDataByID, C_Item.GetItemQualityByID
	local NAMES = { [2589] = "Linen Cloth", [1234] = "Bank Thing", [999] = "Worn Sword", [777] = "Carried Rock", [555] = "Guild Gem" }
	local requested = {}
	C_Item.GetItemNameByID = function(id) return NAMES[id] end
	C_Item.RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end
	C_Item.GetItemQualityByID = function() return 1 end

	check(St.Source() == nil and St.Status():find("not found", 1, true), "no bag addon: nothing to read")
	check(next(entries()) == nil, "and no results")

	-- BagBrother (Bagnon's records)
	local shown, signals = {}, {}
	local me = { realm = "forever", id = "Me Sur", name = "Me Sur" }
	local alt = { realm = "forever", id = "Alt Guy", name = "Alt Guy" }
	_G.Bagnon = {
		NumBags = 4, player = me,
		Owners = { Iterate = function() return ipairs({ me, alt }) end },
		Frames = { Show = function(_, id, owner) shown[#shown + 1] = { id = id, owner = owner } return {} end },
		SendSignal = function(self, name, arg) signals[#signals + 1] = name .. "=" .. tostring(arg) end,
	}
	_G.BrotherBags = {
		forever = {
			["Me Sur"] = {
				[0] = { items = { [1] = "2589;5", [2] = "777;2" } },
				[-1] = { items = { [1] = "2589;20", [2] = "1234" } },
				[6] = { items = { [1] = "4242" } }, -- a bank bag; no name from the server yet
				mail = { [1] = "2589;3" },
				equip = { [16] = "999" },
				money = 100, class = "WARRIOR",
			},
			["Alt Guy"] = { [0] = { items = { [3] = "2589;7", [4] = "battlepet:39:1:3:100" } } },
			["My Guild*"] = { [1] = { items = { [1] = "2589:0:0:0:0;12", [2] = "555" } } },
		},
		account = { [13] = { items = { [1] = "2589" } } },
	}
	check(St.Source() == "BagBrother" and St.Status():find("BagBrother, 2 character", 1, true), "BagBrother's records found: " .. St.Status())
	local by = entries()
	local linen = by[2589]
	check(linen and linen.total == 48 and linen.name == "Linen Cloth", "counts every bag, bank, mailbox, guild bank and the warband bank: " .. tostring(linen and linen.total))
	check(linen.detail == "x48  ·  4 places", "the details are short: the total and how many places: " .. tostring(linen.detail))
	check(ns.providers.stored.explicit == true, "@stored is its own search (a plain search offers it when only it has a match)")
	local gs = St.Groups(linen)
	check(gs[1].name == "Me Sur" and gs[1].mine and gs[1].total == 28 and gs[2].name == "My Guild (guild)" and gs[3].name == "Alt Guy" and gs[4].name == "Warband", "grouped by who has them, most first")
	check(by[1234] and by[1234].total == 1, "something only in your bank is listed")
	check(by[999] == nil and by[777] == nil, "things you carry or wear only are left to the Item results")
	check(by[555] and by[555].detail:find("My Guild", 1, true), "guild bank items listed")
	check(by[4242] == nil and requested[1] == 4242, "an item the server hasn't named yet is asked for and listed later")
	NAMES[4242] = "Late Name"
	St.nameFrame.scripts.OnEvent(St.nameFrame, "GET_ITEM_INFO_RECEIVED", 4242); FlushAll()
	check(P._dirty == true, "the list is rebuilt once the name arrives")
	check(entries()[4242] ~= nil, "and then it's there")
	local lines = St.Breakdown(linen)
	check(lines[1]:find("48 in all", 1, true) and lines[2] == "  Me Sur (you): 28  (bank 20, mail 3, bags 5)" and lines[3] == "  My Guild (guild): 12" and lines[#lines] == "  Warband: 1", "breakdown by who, with where: " .. table.concat(lines, " | "))
	-- the tooltip: who has how many and where, like Baganator's
	local tipLines = {}
	local tt = Obj("GameTooltip")
	tt.SetText = function(_, s) tipLines[#tipLines + 1] = "T:" .. s end
	tt.AddDoubleLine = function(_, l, r) tipLines[#tipLines + 1] = l .. "=" .. r end
	tt.AddLine = function(_, l) tipLines[#tipLines + 1] = l end
	_G.RAID_CLASS_COLORS = { WARRIOR = { colorStr = "ffc79c6e" } }
	St.Tooltip(linen, tt)
	local tj = table.concat(tipLines, "\n")
	check(tipLines[1] == "T:Linen Cloth" and tj:find("|cffc79c6eMe Sur|r", 1, true) and tj:find("28|r  |cff9d9d9dbank 20, mail 3, bags 5", 1, true), "tooltip rows: class-coloured name, total, where: " .. tj)
	check(tj:find("My Guild (guild)|r=|cffffffff12|r", 1, true) and tj:find("Total=48", 1, true), "guild row and the total")
	_G.RAID_CLASS_COLORS = nil
	-- searching: only alts have it, one item: the item itself
	do
		local few = UI:Search("linen alt guy")
		check(few[1] and few[1].kind == "stored" and few[1].itemID == 2589 and not few[1].completion,
			"one stored item has it: it's a result itself: " .. tostring(few[1] and (few[1].completion or few[1].name)))
	end
	UI.HINT_FEW = 0 -- (the hint row: as for many matches)
	UI:Open("linen alt guy")
	local hint = UI.Results()[1]
	check(hint and hint.completion == "@stored linen alt guy" and hint.name:find("alts and banks", 1, true),
		"a plain search offers @stored when only it has a match: " .. tostring(hint and hint.name))
	check(UI:AcceptCompletion() and UI.edit:GetText() == "@stored linen alt guy", "Tab adds @stored")
	-- Enter on the row does the same, stays open, and isn't history (only a step towards the search)
	ns.db.history = {}
	UI:Open("linen alt guy"); key("ENTER")
	check(UI:IsShown() and UI.edit:GetText() == "@stored linen alt guy ", "Enter on the hint row adds @stored and stays open")
	check(#ns.db.history == 0, "the hint row isn't saved in history: " .. tostring(ns.db.history[1]))
	-- carried too: your bags' row stays on top, the alts-and-banks row comes second
	local rc = UI:Search("linen cloth")
	check(rc[1] and rc[1].kind == "items" and rc[1].name == "Linen Cloth" and rc[2] and rc[2].completion == "@stored linen cloth",
		"you carry it and alts have more: your row first, the alts-and-banks row second (" .. tostring(rc[1] and rc[1].kind) .. ", " .. tostring(rc[2] and rc[2].name) .. ")")
	UI.HINT_FEW = 2
	local r = UI.Results()[1]
	check(r and r.kind == "stored" and r.itemID == 2589, "found by the item and a holder's name")
	UI:Open("@stored bank thing")
	check(UI.Results()[1] and UI.Results()[1].itemID == 1234, "@stored filters")
	UI:Open("@alts linen"); check(UI.Results()[1] and UI.Results()[1].kind == "stored", "@alts too")
	-- Enter: like an Item, your bags (Bagnon's here) open on the ones you carry
	UI:Open("@stored linen")
	key("ENTER")
	check(shown[1] and shown[1].id == "inventory" and shown[1].owner == nil, "Enter opens your bags in Bagnon: " .. tostring(shown[1] and shown[1].id))
	check(_G.Bagnon.search == nil, "nothing typed into Bagnon's search")
	-- not carried: nothing at all
	local nShown, nSaid = #shown, #said
	UI:Open("@stored bank thing"); key("ENTER")
	check(#shown == nShown and #said == nSaid and not UI:IsShown(), "something you don't carry: nothing opens, nothing printed")
	-- Shift+Enter: the breakdown in chat
	UI:Open("@stored linen")
	_G.IsShiftKeyDown = function() return true end
	key("ENTER")
	_G.IsShiftKeyDown = function() return false end
	check(said[#said - 1] and table.concat(said, "\n"):find("Alt Guy: 7", 1, true), "Shift+Enter prints where it all is")
	UI:Hide()

	-- Syndicator (Baganator's records) wins when both are there
	local LINK = "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r"
	local function it(id, n, link) return { itemID = id, itemCount = n, itemLink = link or ("|cffffffff|Hitem:" .. id .. "|h[" .. (NAMES[id] or "?") .. "]|h|r"), quality = 1 } end
	local callbacks = {}
	local SD = {
		Characters = {
			["Me-Forever"] = { details = { character = "Me", show = { inventory = true } },
				bags = { { it(2589, 2, LINK) } }, bank = { { it(2589, 30, LINK) } }, bankTabs = { { slots = { it(1234, 4) } } },
				mail = { it(2589, 1, LINK) }, equipped = { [16] = it(999, 1) }, void = {}, auctions = {} },
			["Alt-Forever"] = { details = { character = "Alt", show = { inventory = true } },
				bags = { { it(2589, 9, LINK), {} } }, bank = {}, mail = {}, equipped = {} },
			["Hidden-Forever"] = { details = { character = "Hidden", show = { inventory = false } }, bags = { { it(2589, 500, LINK) } } },
		},
		Guilds = { ["Guildy-Forever"] = { details = { guild = "Guildy", show = { inventory = true } }, bank = { { slots = { it(555, 3) } } } } },
		Warband = { { bank = { { slots = { it(2589, 4, LINK) } } }, details = { inventory = true } } },
	}
	_G.Syndicator = {
		API = {
			IsReady = function() return true end,
			GetCurrentCharacter = function() return "Me-Forever" end,
			GetAllCharacters = function() local o = {} for k in pairs(SD.Characters) do o[#o + 1] = k end return o end,
			GetByCharacterFullName = function(n) return SD.Characters[n] end,
			GetAllGuilds = function() local o = {} for k in pairs(SD.Guilds) do o[#o + 1] = k end return o end,
			GetByGuildFullName = function(n) return SD.Guilds[n], n end,
			GetWarband = function(i) return SD.Warband[i or 1] end,
			-- what Syndicator's own tooltip counts: shown characters, connected realms only if asked
			GetInventoryInfoByItemID = function(id, connectedOnly, factionOnly)
				local CONNECTED = { Forever = true }
				local function flat(list) local n = 0 for _, x in pairs(list or {}) do if type(x) == "table" and x.itemID == id then n = n + (x.itemCount or 1) end end return n end
				local function nested(bags) local n = 0 for _, b in pairs(bags or {}) do n = n + flat(b.slots or b) end return n end
				local res = { characters = {}, guilds = {}, warband = { 0 } }
				for full, c in pairs(SD.Characters) do
					local realm = full:match("%-(.+)$")
					if c.details.show.inventory ~= false and (not connectedOnly or CONNECTED[realm]) then
						local r = { character = c.details.character, realmNormalized = realm, bags = nested(c.bags), bank = nested(c.bank) + nested(c.bankTabs),
							mail = flat(c.mail), equipped = flat(c.equipped), void = 0, auctions = 0 }
						if r.bags + r.bank + r.mail + r.equipped > 0 then res.characters[#res.characters + 1] = r end
					end
				end
				for full, g in pairs(SD.Guilds) do
					local realm = full:match("%-(.+)$")
					local n = nested(g.bank)
					if n > 0 and (not connectedOnly or CONNECTED[realm]) then res.guilds[#res.guilds + 1] = { guild = g.details.guild, realmNormalized = realm, bank = n } end
				end
				res.warband[1] = nested(SD.Warband[1].bank)
				return res
			end,
		},
		CallbackRegistry = { RegisterCallback = function(_, ev, fn) callbacks[ev] = fn end },
	}
	check(St.Source() == "BagBrother", "Bagnon shows your bags: BagBrother's records, even with Syndicator loaded")
	-- Baganator shows your bags: Syndicator's records, and BagBrother's are left alone
	_G.Bagnon = nil
	local fired = {}
	_G.Baganator = { CallbackRegistry = { TriggerEvent = function(_, ev, ...) local a = {} for i = 1, select("#", ...) do a[i] = tostring((select(i, ...))) end fired[#fired + 1] = ev .. ":" .. table.concat(a, ",") end } }
	check(St.Source() == "Syndicator" and St.Status():find("Syndicator, 3 character", 1, true), "Baganator: Syndicator's records: " .. St.Status())
	by = entries()
	linen = by[2589]
	check(linen and linen.total == 46 and linen.link == LINK, "Syndicator's counts, hidden characters left out, with its item link: " .. tostring(linen and linen.total))
	check(linen.detail == "x46  ·  3 places", "details: " .. linen.detail)
	check(by[1234] and by[1234].total == 4 and by[555] and by[555].detail:find("Guildy", 1, true), "bank tabs and guild banks read")
	check(by[999] == nil, "worn items alone aren't listed")
	-- its updates mark the list stale
	P._dirty = false
	check(type(callbacks.BagCacheUpdate) == "function", "listens to Syndicator's updates")
	callbacks.BagCacheUpdate("Alt-Forever"); check(P._dirty == true, "and rebuilds after them")
	-- Baganator: your bags open on the ones you carry, flashed
	fired = {}
	UI:Open("@stored linen"); key("ENTER"); FlushAll()
	local joined = table.concat(fired, " ")
	check(joined:find("BagShow:", 1, true) and joined:find("HighlightIdenticalItems", 1, true) and not joined:find("BankShow", 1, true), "Baganator shows your bags with the item flashed: " .. joined)
	fired = {}
	UI:Open("@stored guild gem"); key("ENTER")
	check(#fired == 0, "a guild bank item you don't carry: nothing opens")
	-- no bag addon: the game's bags, as for an Item
	_G.Baganator = nil
	local mark = #log
	UI:Open("@stored linen"); key("ENTER")
	check(logHas("OpenAllBags", mark + 1), "without a bag addon the game's bags open")
	-- the same characters as Syndicator's tooltip: by default only connected realms
	SD.Characters["Alt-Elsewhere"] = { details = { character = "Alt", show = { inventory = true } }, bags = { { it(2589, 2, LINK) } } }
	by = entries()
	check(by[2589].total == 46, "a character on a realm Syndicator's tooltip leaves out isn't counted: " .. by[2589].total)
	-- its tooltip set to every realm: then counted, with the realm in its name
	_G.SYNDICATOR_CONFIG = { tooltips_connected_realms_only_2 = false }
	by = entries()
	local names = {}
	for _, g in ipairs(St.Groups(by[2589])) do names[#names + 1] = g.name end
	check(by[2589].total == 48 and table.concat(names, ","):find("Alt-Elsewhere", 1, true) and table.concat(names, ","):find("Alt,", 1, true), "every realm: Name-Realm: " .. table.concat(names, ","))
	-- guild banks and worn items follow its settings too
	_G.SYNDICATOR_CONFIG = { show_guild_banks_in_tooltips = false }
	by = entries()
	check(by[555] == nil, "guild banks hidden in its tooltip are left out here")
	_G.SYNDICATOR_CONFIG = nil
	SD.Characters["Alt-Elsewhere"] = nil
	-- Syndicator still loading: nothing, rather than BagBrother's (old) records standing in
	_G.Baganator = { CallbackRegistry = { TriggerEvent = function() end } }
	_G.Syndicator.API.IsReady = function() return false end
	check(next(entries()) == nil and St.Busy():find("Syndicator", 1, true), "while Syndicator loads nothing else stands in for it")
	_G.Syndicator.API.IsReady = function() return true end
	-- BagBrother's records with Bagnon not loaded are stale: not read
	local realSyn = _G.Syndicator
	_G.Syndicator, _G.Baganator = nil, nil
	check(St.Source() == nil and St.Status():find("Bagnon isn't loaded", 1, true) and next(entries()) == nil, "BagBrother's records without Bagnon aren't used: " .. St.Status())
	_G.Syndicator = realSyn
	-- .integrations reports it
	check(table.concat(ns.commands.integrations.run(""), "\n"):find("Alts and banks: Syndicator", 1, true), ".integrations says where the counts come from")
	UI:Hide()

	_G.Syndicator, _G.BrotherBags, _G.Bagnon, _G.Baganator = nil, nil, nil, nil
	C_Item.GetItemNameByID, C_Item.RequestLoadItemDataByID, C_Item.GetItemQualityByID = baseName, baseReq, baseQual
	ns.Output = realOut
	P._dirty = true
end

-- your own bags and bank: the live count wins over a stale record; a spinner while loading
io.write("[stored live counts + busy tests]\n")
do
	local St = ns.Stored
	local P = ns.providers.stored
	local function entries() P._dirty = true; local by = {} for _, e in ipairs(ns:GetEntries(P)) do by[e.itemID] = e end return by end
	local baseName, baseReq, baseCount = C_Item.GetItemNameByID, C_Item.RequestLoadItemDataByID, C_Item.GetItemCount
	local NAMES = { [2589] = "Linen Cloth", [1234] = "Bank Thing", [3000] = "Live Only" }
	local requested = {}
	C_Item.GetItemNameByID = function(id) return NAMES[id] end
	C_Item.RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end
	local LIVE = { [2589] = { bags = 5, bank = 5 }, [1234] = { bags = 0, bank = 0 }, [3000] = { bags = 0, bank = 0 } }
	C_Item.GetItemCount = function(id, bank) local l = LIVE[id] or { bags = 0, bank = 0 } return l.bags + (bank and l.bank or 0) end
	local me = { realm = "forever", id = "Me Sur", name = "Me Sur" }
	_G.Bagnon = { NumBags = 4, player = me, Owners = { Iterate = function() return ipairs({ me }) end }, Frames = { Show = function() return {} end }, SendSignal = function() end }
	_G.BrotherBags = { forever = {
		["Me Sur"] = { [0] = { items = { [1] = "2589;5" } }, [-1] = { items = { [1] = "2589;20", [2] = "1234" } }, equip = {} },
		["Alt Guy"] = { [-1] = { items = { [1] = "1234;3", [2] = "3000;2" } } },
	} }
	local by = entries()
	local linen = by[2589]
	check(linen and linen.total == 10, "your bank's live count replaces the record (20 recorded, 5 there): " .. tostring(linen and linen.total))
	local bankThing = by[1234]
	check(bankThing and bankThing.total == 3 and not bankThing.detail:find("you", 1, true), "an item the record put in your bank but the game doesn't count isn't shown as yours: " .. tostring(bankThing and bankThing.detail))
	check(bankThing.detail == "x3  ·  Alt Guy", "it shows on the alt that has it: " .. bankThing.detail)
	LIVE[3000].bank = 4
	by = entries()
	check(by[3000] and by[3000].total == 6 and St.Groups(by[3000])[1].mine and St.Groups(by[3000])[1].parts[1] == "bank 4", "your bank counted live even when the record missed it: " .. tostring(by[3000] and by[3000].detail))
	-- worn items aren't counted as in your bags
	_G.BrotherBags.forever["Me Sur"].equip = { [16] = "2589" }
	LIVE[2589].bags = 6 -- the game counts the worn one as carried
	by = entries()
	local lines = St.Breakdown(by[2589])
	check(table.concat(lines, "|"):find("bags 5", 1, true) and table.concat(lines, "|"):find("equipped 1", 1, true), "worn ones come off the carried count: " .. table.concat(lines, " | "))

	-- the spinner
	local ready = false
	_G.Syndicator = { API = { IsReady = function() return ready end, GetAllCharacters = function() return {} end, GetByCharacterFullName = function() end } }
	local bagnonForNow = _G.Bagnon
	_G.Bagnon = nil -- Syndicator's records (Baganator or Syndicator alone)
	check(St.Busy() and St.Busy():find("Syndicator", 1, true), "busy while Syndicator is still reading")
	UI:Open("")
	local B = UI.busy
	check(B.shown == true and B.lines[1]:find("Syndicator", 1, true), "the spinner shows, saying what's loading")
	check(UI.edit.lastPoint and UI.edit.lastPoint[4] == -38, "the query box ends before it")
	local shownTip = {}
	local realTip = _G.GameTooltip
	_G.GameTooltip = Obj("GameTooltip")
	_G.GameTooltip.AddLine = function(_, l) shownTip[#shownTip + 1] = l end
	B.scripts.OnEnter(B)
	check(shownTip[1] and shownTip[1]:find("Syndicator", 1, true), "mouse-over lists it")
	B.scripts.OnUpdate(B, 0.25)
	local alphas = {}
	for i, d in ipairs(B.dots) do alphas[i] = d.alpha end
	B.scripts.OnUpdate(B, 0.1)
	check(alphas[1] ~= B.dots[1].alpha or alphas[2] ~= B.dots[2].alpha, "the dots turn")
	local searched = 0
	local realRefresh = UI.Refresh
	UI.Refresh = function(self, ...) searched = searched + 1 return realRefresh(self, ...) end
	ready = true
	B.scripts.OnUpdate(B, 0.6)
	check(B.shown == false and searched >= 1, "when loading ends the spinner goes and the results are searched again")
	check(UI.edit.lastPoint[4] == -38, "the query box keeps its size (resizing it as the spinner came and went restarted searches)")
	UI.Refresh = realRefresh
	UI:Hide()
	_G.Syndicator = nil
	_G.Bagnon = bagnonForNow
	-- names that never arrive don't keep it spinning
	_G.BrotherBags.forever["Alt Guy"][-1].items[3] = "8888"
	requested = {}
	entries()
	check(St.Busy() and St.Busy():find("item name", 1, true), "busy while item names are on their way")
	St.nameFrame.scripts.OnEvent(St.nameFrame, "GET_ITEM_INFO_RECEIVED"); FlushAll()
	entries()
	St.nameFrame.scripts.OnEvent(St.nameFrame, "GET_ITEM_INFO_RECEIVED"); FlushAll()
	entries()
	-- names arrive one by one: busy until the last
	_G.BrotherBags.forever["Alt Guy"][-1].items[4] = "7001"
	_G.BrotherBags.forever["Alt Guy"][-1].items[5] = "7002"
	entries()
	check(St.Busy() and St.Busy():find("item names", 1, true), "busy with several names out")
	St.nameFrame.scripts.OnEvent(St.nameFrame, "GET_ITEM_INFO_RECEIVED", 6948, true) -- someone else's item
	check(St.Busy() ~= nil, "another addon's item arriving doesn't end the wait")
	NAMES[7001] = "First In"
	St.nameFrame.scripts.OnEvent(St.nameFrame, "GET_ITEM_INFO_RECEIVED", 7001, true)
	check(St.Busy() ~= nil, "still waiting for the rest")
	NAMES[7002] = "Second In"
	P._dirty = false
	St.nameFrame.scripts.OnEvent(St.nameFrame, "GET_ITEM_INFO_RECEIVED", 7002, true)
	check(P._dirty == true, "the last one in rebuilds the list")
	_G.BrotherBags.forever["Alt Guy"][-1].items[4], _G.BrotherBags.forever["Alt Guy"][-1].items[5] = nil, nil
	local asks = 0 for _, id in ipairs(requested) do if id == 8888 then asks = asks + 1 end end
	check(asks == 2 and St.Busy() == nil, "a name that never comes is asked for twice, then the spinner stops: " .. asks)

	_G.BrotherBags, _G.Bagnon, _G.GameTooltip = nil, nil, realTip
	C_Item.GetItemNameByID, C_Item.RequestLoadItemDataByID, C_Item.GetItemCount = baseName, baseReq, baseCount
	P._dirty = true
end

-- your bags shown and highlighted in Bagnon or Baganator when one of them replaces the game's bags
io.write("[bag addon tests]\n")
do
	local Bg = ns.Bags
	local function itemEntry() ns.providers.items._dirty = true for _, e in ipairs(ns:GetEntries(ns.providers.items)) do if e.itemID == 2589 then return e end end end
	local lit = {}
	local origShow = ns.Highlight.Show
	ns.Highlight.Show = function(self, f) lit[#lit + 1] = f end
	local function button(bag, slot, method)
		local b = Obj("Button"); b.shown = true
		if method == "GetBag" then b.GetBag = function() return bag end else b.GetBagID = function() return bag end end
		b.GetID = function() return slot end
		return b
	end
	-- Bagnon: its inventory frame, buttons answer GetBag/GetID
	local shown = {}
	local bn = button(0, 2, "GetBag")
	local other = button(0, 1, "GetBag")
	local group = Obj("Frame"); group.shown = true
	group.GetChildren = function() return other, bn end
	local inv = Obj("Frame"); inv.shown = false
	inv.GetChildren = function() return group end
	_G.Bagnon = { Owners = {}, Frames = {
		IsEnabled = function() return true end,
		Show = function(_, id) shown[#shown + 1] = id; inv.shown = true; return inv end,
		Get = function(_, id) return id == "inventory" and inv or nil end,
	} }
	check(Bg.Active() == "Bagnon", "Bagnon shows your bags")
	local e = itemEntry()
	local mark = #log
	e.activate(e); FlushAll()
	check(shown[1] == "inventory" and not logHas("OpenAllBags", mark + 1), "an item opens Bagnon's bags, not the game's")
	check(lit[1] == bn, "and its button there is highlighted")
	-- Bagnon installed but its bags turned off: the game's bags
	_G.Bagnon.Frames.IsEnabled = function() return false end
	check(Bg.Active() == nil, "Bagnon with its bags off: the game's bags")
	_G.Bagnon = nil
	-- Baganator: BagShow, its own flash, and its buttons answer GetBagID/GetID
	local fired = {}
	_G.Baganator = { CallbackRegistry = { TriggerEvent = function(_, ev, a) fired[#fired + 1] = ev .. ":" .. tostring(a) end } }
	local bgb = button(0, 2)
	local view = Obj("Frame"); view.shown = true
	view.GetChildren = function() return bgb end
	_G.Baganator_SingleViewBackpackViewFrame1 = view
	lit = {}
	check(Bg.Active() == "Baganator", "Baganator shows your bags")
	e.activate(e); FlushAll()
	local fj = table.concat(fired, " ")
	check(fj:find("BagShow", 1, true) and fj:find("HighlightIdenticalItems:|Hitem:2589|h[Linen Cloth]|h", 1, true), "Baganator opens and flashes it: " .. fj)
	check(lit[1] == bgb, "and Terminal points at its button too")
	_G.Baganator, _G.Baganator_SingleViewBackpackViewFrame1 = nil, nil
	-- none: the game's bags, as before
	mark = #log
	e.activate(e); FlushAll()
	check(logHas("OpenAllBags", mark + 1), "without a bag addon the game's bags open")
	-- the reagent bag left open: OpenAllBags does nothing then (the game's rule), so the bag the
	-- item is in is opened on its own and its button pointed at
	local open = { [5] = true }
	local realIsOpen, realOAB = _G.IsBagOpen, _G.OpenAllBags
	_G.IsBagOpen = function(b) return open[b] or false end
	_G.OpenAllBags = function() note("OpenAllBags") end -- no-op: a bag is open
	_G.OpenBackpack = function() note("OpenBackpack"); open[0] = true end
	_G.OpenBag = function(b) note("OpenBag " .. b); open[b] = true end
	mark = #log
	e.activate(e); FlushAll()
	check(not logHas("OpenAllBags", mark + 1) and logHas("OpenBackpack", mark + 1),
		"reagent bag left open: the backpack holding the item opens anyway")
	-- already open: nothing else opened
	mark = #log
	e.activate(e); FlushAll()
	check(not logHas("OpenBackpack", mark + 1) and not logHas("OpenAllBags", mark + 1), "the bag already showing: nothing more to open")
	_G.IsBagOpen, _G.OpenAllBags, _G.OpenBackpack, _G.OpenBag = realIsOpen, realOAB, nil, nil
	ns.Highlight.Show = origShow

	-- the terminal uses an entry's own tooltip when it has one
	local drew
	ns:RegisterProvider("tiptest", { label = "TT", aliases = { "tiptest" }, explicit = true, collect = function()
		return { { name = "Tippy", link = "item:1", tooltip = function(_, tip) drew = tip end } }
	end })
	UI:Open("@tiptest tippy")
	check(drew == _G.TerminalTooltip, "an entry's own tooltip is drawn instead of the link's")
	UI:Hide()
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "tiptest" then table.remove(ns.providerOrder, i) end end
	ns.providers.tiptest = nil

	-- a provider that finishes loading is collected again and the results searched again
	local loading, collects = true, 0
	ns:RegisterProvider("slowtest", { label = "Slow", aliases = { "slowtest" }, explicit = true,
		busy = function() return loading and "Loading slow things" or nil end,
		collect = function() collects = collects + 1 return loading and {} or { { name = "Arrived" } } end })
	UI:Open("@slowtest arr")
	check(#UI.Results() == 0 and UI.busy.shown and UI.status:GetText():find("loading", 1, true), "while loading: nothing yet, the spinner, and loading in the footer: " .. tostring(UI.status:GetText()))
	loading = false
	UI.busy.scripts.OnUpdate(UI.busy, 0.6)
	check(UI.busy.shown == false and collects == 2 and UI.Results()[1] and UI.Results()[1].name == "Arrived", "when it's done it's collected again and shows up without typing")
	UI:Hide()
	for i = #ns.providerOrder, 1, -1 do if ns.providerOrder[i] == "slowtest" then table.remove(ns.providerOrder, i) end end
	ns.providers.slowtest = nil
end

do -- keybindings: found by name, Enter opens the Keybindings page on the row, Quick Keybind Mode
	local S = ns.Secure
	local BINDS = {
		{ "HEADER_MOVEMENT", "BINDING_HEADER_MOVEMENT" },
		{ "MOVEFORWARD", "BINDING_HEADER_MOVEMENT", "W", "UP" },
		{ "TOGGLEWORLDMAP", "BINDING_HEADER_INTERFACE", "M" },
		{ "TOGGLEMOUNTJOURNAL", "BINDING_HEADER_INTERFACE" },
	}
	_G.BINDING_NAME_MOVEFORWARD, _G.BINDING_NAME_TOGGLEWORLDMAP, _G.BINDING_NAME_TOGGLEMOUNTJOURNAL = "Move Forward", "Toggle World Map", "Mount Journal"
	_G.BINDING_HEADER_MOVEMENT, _G.BINDING_HEADER_INTERFACE = "Movement Keys", "Interface Panel Functions"
	_G.GetNumBindings = function() return #BINDS end
	_G.GetBinding = function(i) local b = BINDS[i]; return b[1], b[2], b[3], b[4] end
	_G.GetBindingText = function(k) return k == "UP" and "Up Arrow" or k end
	ns.providers.keybinds._dirty = true
	local kb = {}
	for _, e in ipairs(ns:GetEntries(ns.providers.keybinds)) do kb[e.name] = e end
	check(kb["Toggle World Map"] and kb["Toggle World Map"].detail == "M  ·  Interface Panel Functions", "a binding shows its key and category: " .. tostring(kb["Toggle World Map"] and kb["Toggle World Map"].detail))
	check(kb["Move Forward"].detail:find("W, Up Arrow", 1, true) and kb["Mount Journal"].detail:find("not bound", 1, true), "both keys, or not bound")
	check(not kb["HEADER_MOVEMENT"] and kb["Quick Keybind Mode"], "headers aren't listed; Quick Keybind Mode is")
	check(UI:Search("@keybind world map")[1].name == "Toggle World Map", "@keybind finds it by name")
	check(UI:Search("keybind M")[1] and true, "found by its key")
	-- Enter: the game opens Options > Keybindings (a macro line), then the row is pointed at
	local pointed
	local G = ns.GameOptions
	local realHL = G.HighlightSetting
	G.HighlightSetting = function(name) pointed = name end
	UI:Open("@keybind toggle world map")
	key("ENTER")
	local mt = _G.TerminalMacroProxy.attrs.macrotext or ""
	check(S.armed == "MACRO" and mt:find(ns.Keybinds.OPEN_MACRO, 1, true) == 1, "Enter: the game opens the Keybindings page: " .. mt)
	check(mt:find('SetText("Toggle World Map")', 1, true), "and types the action into the options search, so its row shows even in a collapsed section")
	check(#mt <= 255, "the macro fits a macro line (" .. #mt .. ")")
	-- run it the way the game would: the page opens and the search gets the name
	local searched, openedTo
	_G.Settings = { KEYBINDINGS_CATEGORY_ID = 42, OpenToCategory = function(id) openedTo = id end }
	_G.SettingsPanel = Obj("Frame"); SettingsPanel.SearchBox = { SetText = function(_, t) searched = t end }
	assert(loadstring(mt:gsub("^/run ", "")))()
	check(openedTo == 42 and searched == "Toggle World Map", "the macro opens Keybindings and searches for the action")
	_G.Settings, _G.SettingsPanel = nil, nil
	_G.TerminalMacroProxy.scripts.PostClick(_G.TerminalMacroProxy, "LeftButton", true); FlushAll()
	check(pointed == "Toggle World Map", "and the action's row is pointed at")
	-- Quick Keybind Mode: Shift+Enter starts it, through the game
	UI:Open("@keybind quick keybind")
	_G.IsShiftKeyDown = function() return true end
	key("ENTER")
	_G.IsShiftKeyDown = function() return false end
	check(S.armed == "MACRO" and _G.TerminalMacroProxy.attrs.macrotext == ns.Keybinds.QUICK_MACRO, "Shift+Enter on Quick Keybind Mode: the game starts it")
	_G.TerminalMacroProxy.scripts.PostClick(_G.TerminalMacroProxy, "LeftButton", true); FlushAll()
	local q = kb["Quick Keybind Mode"]
	check(UI.ClickFor(q, true) == ns.Keybinds.QUICK_MACRO and UI.ClickFor(q, false) == ns.Keybinds.MacroFor(""), "clicks do the same (Shift+click starts it)")
	check(UI.ClickFor(kb["Toggle World Map"], false) == ns.Keybinds.MacroFor("Toggle World Map"), "a click on an action does what Enter does")
	local realCombat = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	UI:Open("@keybind quick keybind"); mark = #log
	UI:Activate(nil, { secondary = true })
	_G.InCombatLockdown = realCombat
	local said = false
	for i = mark + 1, #log do if log[i]:find("Quick Keybind Mode can't", 1, true) then said = true end end
	check(said, "in combat: it says it can't")
	UI:Hide(); FlushAll()
	G.HighlightSetting = realHL
	_G.GetNumBindings, _G.GetBinding = nil, nil
	ns.providers.keybinds._dirty = true
end
do -- the recipe index is per character by GUID: WoW Forever's first-and-last names ("Plamen Warr",
	-- "Plamen Pally") give UnitName just "Plamen", and the realm name is the same, so they shared one
	local P = ns.Professions
	local realGUID, realName = _G.UnitGUID, _G.UnitName
	ns.db.recipes = { ["Plamen-Classic Beta PvP"] = { [356] = { name = "Fishing", fromList = true, list = { { id = 1, name = "Fish Bowl", learned = true } } } } }
	_G.UnitName = function() return "Plamen" end
	_G.UnitGUID = function() return "Player-1-0000AAAA" end -- Plamen Warr
	local warr = P.Store()
	check(next(warr) == nil and ns.db.recipes["Plamen-Classic Beta PvP"] == nil, "the index shared under Name-Realm is dropped; this character starts its own")
	warr[356] = { name = "Fishing", list = { { id = 1, name = "Fish Bowl", learned = true } } }
	_G.UnitGUID = function() return "Player-1-0000BBBB" end -- Plamen Pally, no Fishing
	ns.providers.camp._dirty = true
	local fishBowl = false
	for _, e in ipairs(ns:GetEntries(ns.providers.camp)) do if e.name == "Fish Bowl" then fishBowl = true end end
	check(next(P.Store()) == nil and not fishBowl, "a namesake doesn't get the other's recipes (no Fish Bowl for the Paladin)")
	_G.UnitGUID, _G.UnitName = realGUID, realName
	ns.db.recipes = {}
	ns.providers.camp._dirty = true
end
do -- filters across kinds: items, loot and stored (stats, quality, item level, type, slot, upgrade),
	-- stored places and holders, counts, quests ready to turn in, Questie NPCs, craftable recipes
	ns.Filters.ClearCache() -- (nothing earlier blocks asked for is kept)
	local F = ns.Filters
	local function P(w) local f = F.Parse(w); assert(f, "not a filter: " .. w); return f end
	local base = { info = C_Item.GetItemInfo, stats = C_Item.GetItemStats, count = C_Item.GetItemCount,
		inv = _G.GetInventoryItemLink, level = UnitLevel, can = C_PlayerInfo and C_PlayerInfo.CanUseItem,
		ready = C_QuestLog.ReadyForTurnIn, map = _G.C_Map, area = _G.C_Map and _G.C_Map.GetAreaInfo, nf = ns.Integrations.NpcField, nd = ns.Integrations.NpcFlagDefs }
	local ITEMS = {
		[100] = { "Wolf Bracers", "|Hitem:100|h", 3, 25, 20, "Armor", "Mail", 1, "INVTYPE_WRIST" },
		[101] = { "Old Bracers", "|Hitem:101|h", 1, 10, 5, "Armor", "Mail", 1, "INVTYPE_WRIST" },
		[102] = { "Runed Blade", "|Hitem:102|h", 4, 40, 35, "Weapon", "One-Handed Swords", 1, "INVTYPE_WEAPON" },
		[103] = { "Healing Potion", "|Hitem:103|h", 1, 15, 10, "Consumable", "Potion", 20, "" },
	}
	local STATS = { [100] = { ITEM_MOD_STAMINA_SHORT = 7, ITEM_MOD_AGILITY_SHORT = 3, RESISTANCE0_NAME = 120 },
		[102] = { ITEM_MOD_STRENGTH_SHORT = 12, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 30 } }
	C_Item.GetItemInfo = function(id)
		if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) end
		local t = ITEMS[id]; if t then return unpack(t) end
	end
	C_Item.GetItemStats = function(link) return STATS[tonumber(link:match("item:(%d+)"))] or {} end
	_G.GetInventoryItemLink = function(_, slot) if slot == 9 then return "|Hitem:101|h" end end -- old bracers worn
	_G.ITEM_MOD_STAMINA_SHORT, _G.INVTYPE_WRIST = "Stamina", "Wrist"
	UnitLevel = function() return 30 end
	_G.C_PlayerInfo = _G.C_PlayerInfo or {}
	C_PlayerInfo.CanUseItem = function() return true end
	local bracers, old, blade, potion = { itemID = 100 }, { itemID = 101 }, { itemID = 102 }, { itemID = 103, count = 12 }
	check(P("stat:stamina")(bracers) and P("stat:sta")(bracers) and not P("stat:sta")(blade), "stat: by name or short name")
	check(P("stat:sta>=5")(bracers) and not P("stat:sta>=10")(bracers) and P("stat:str>10")(blade) and P("stat:armor")(bracers), "stat: with a number")
	check(F.Parse("stat:sta>>x") == nil and not P("stat:stamina")(potion), "a bad stat value stays text; items without it are left out")
	-- consumables have no item stats: what their effect says they give (elixirs, potions, food)
	ITEMS[104] = { "Elixir of Ogre's Strength", "|Hitem:104|h", 1, 20, 10, "Consumable", "Elixir", 20, "" }
	ITEMS[105] = { "Spiced Wolf Ribs", "|Hitem:105|h", 1, 15, 10, "Consumable", "Food & Drink", 20, "" }
	ITEMS[106] = { "Elixir of Agility", "|Hitem:106|h", 1, 25, 15, "Consumable", "Elixir", 20, "" }
	local SPELL_OF = { [104] = 5001, [105] = 5002, [106] = 5003 }
	local DESC = { [5001] = "Increases Strength by 8 for 1 hour.",
		[5002] = "Restores 552 health over 21 sec. If you spend at least 10 seconds eating you will become well fed and gain 6 Stamina and Spirit for 15 min." }
	local agilityLoaded = false
	local baseItemSpell, baseDesc = C_Item.GetItemSpell, C_Spell.GetSpellDescription
	C_Item.GetItemSpell = function(id) local sid = SPELL_OF[id] if sid then return "spell", sid end end
	C_Spell.GetSpellDescription = function(id)
		if id == 5003 then return agilityLoaded and "Increases Agility by 25 for 1 hour." or "" end
		return DESC[id]
	end
	local elixir, ribs, agi = { itemID = 104 }, { itemID = 105 }, { itemID = 106 }
	check(P("stat:strength")(elixir) and P("stats:str")(elixir) and not P("stat:agility")(elixir), "an elixir's stat comes from its effect")
	check(P("stat:str>=8")(elixir) and not P("stat:str>8")(elixir), "with a number: the amount it gives")
	check(P("stat:stamina")(ribs) and P("stat:spirit")(ribs) and P("stat:sta>=6")(ribs) and not P("stat:strength")(ribs), "food: what being well fed gives")
	check(not P("stat:agility")(agi), "its effect text not loaded yet: left out for now")
	agilityLoaded = true
	check(not P("stat:agi>20")(agi), "asked again only a moment later, not on every keystroke")
	local realGT, later = _G.GetTime, GetTime() + 2
	_G.GetTime = function() return later end
	check(P("stat:agi>20")(agi), "and found once it's in (not remembered as nothing)")
	_G.GetTime = realGT
	-- an item the client hasn't got yet (no spell, a "Retrieving item information" tooltip): never kept as nothing
	F.ClearEffects()
	local cached = false
	C_Item.IsItemDataCachedByID = function() return cached end
	check(not P("stat:strength")(elixir), "an item still loading: left out for now")
	cached = true
	_G.GetTime = function() return later + 5 end
	check(P("stat:strength")(elixir), "and found once the client has it")
	_G.GetTime = realGT
	C_Item.IsItemDataCachedByID = nil
	-- only consumables have their effect read (thousands of loot rows mustn't each have a tooltip read)
	local baseInstant3, asked = C_Item.GetItemInfoInstant, 0
	C_Item.GetItemInfoInstant = function(x) if x == 104 then return 104, "Recipe", "Book", "", 1, 9, 0 end return baseInstant3(x) end
	F.ClearEffects()
	local baseSpell2 = C_Item.GetItemSpell
	C_Item.GetItemSpell = function(id) asked = asked + 1 return baseSpell2(id) end
	check(not P("stat:strength")(elixir) and asked == 0, "an item that isn't a consumable: its effect isn't read")
	C_Item.GetItemInfoInstant, C_Item.GetItemSpell = baseInstant3, baseSpell2
	-- recipes: a craft by what it makes, an enchant by what its name and text say (@recipe stat:stam slot:bracers)
	check(P("slot:bracers")(bracers) and P("slot:wrist")(bracers) and not P("slot:boots")(bracers), "slot: everyday words (bracers = wrist)")
	local craft = { recipeID = 900, name = "Golden Scale Bracers", makesItem = 100 }
	check(P("slot:bracers")(craft) and P("stat:stam")(craft) and P("ilvl:20-30")(craft) and P("q:rare")(craft) and not P("stat:str")(craft),
		"a crafted item's recipe: the item's slot, stats, item level, quality")
	local baseSchematic = C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic
	_G.C_TradeSkillUI = _G.C_TradeSkillUI or {}
	C_TradeSkillUI.GetRecipeSchematic = function(id) if id == 901 then return { outputItemID = 102 } end if id == 7779 then return {} end end
	F.ClearCache()
	local oldIndex = { recipeID = 901, name = "Runed Blade" } -- (indexed before recipes kept what they make)
	check(P("stat:str>10")(oldIndex) and P("slot:weapon")(oldIndex), "an older index: what it makes is asked of the game")
	local baseDesc2 = C_Spell.GetSpellDescription
	local enchantLoaded = true
	C_Spell.GetSpellDescription = function(id)
		if id == 7779 then return enchantLoaded and "Permanently enchant bracers to increase Stamina by 3." or "" end
		return baseDesc2 and baseDesc2(id)
	end
	local enchant = { recipeID = 7779, name = "Enchant Bracer - Minor Stamina" }
	check(P("slot:bracers")(enchant) and P("slot:wrist")(enchant) and not P("slot:boots")(enchant), "an enchant: the slot it goes on")
	check(P("stat:stamina")(enchant) and P("stat:sta>=3")(enchant) and not P("stat:sta>3")(enchant) and not P("stat:str")(enchant),
		"an enchant: the stat it gives, and how much")
	local boots = { recipeID = 7780, name = "Enchant Boots - Minor Agility" }
	check(P("slot:boots")(boots) and P("stat:agi")(boots) and not P("slot:bracers")(boots), "its name alone while its text loads")
	-- in a search
	local recipes = ns.providers.recipes
	local saveEntries, saveDirty = recipes._entries, recipes._dirty
	local list = { craft, enchant, boots, oldIndex }
	for _, e in ipairs(list) do e.kind = "recipes"; e.kindLabel = "Recipe"; e._lname = ns.Lower(e.name); e.freqKey = "recipes:" .. e.recipeID; e.key = e.recipeID end
	recipes._entries, recipes._dirty = list, false
	local found = names(UI:Search("@recipe stat:stam slot:bracers"))
	check(found["Golden Scale Bracers"] and found["Enchant Bracer - Minor Stamina"] and not found["Enchant Boots - Minor Agility"] and not found["Runed Blade"],
		"@recipe stat:stam slot:bracers: the bracers you craft and the bracer enchant")
	recipes._entries, recipes._dirty = saveEntries, true
	C_TradeSkillUI.GetRecipeSchematic, C_Spell.GetSpellDescription = baseSchematic, baseDesc2
	-- in a search: @consumable stat:str
	local baseInstant2 = C_Item.GetItemInfoInstant
	C_Item.GetItemInfoInstant = function(x)
		local id = type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)"))
		if id == 104 or id == 105 then return id, "Consumable", "Elixir", "", 1, 0, 2 end
		return baseInstant2(x)
	end
	local saveBag0 = bags[0]
	bags[0] = { saveBag0[1], { itemID = 104, itemName = "Elixir of Ogre's Strength", iconFileID = 1, stackCount = 3, quality = 1, hyperlink = "|Hitem:104|h[Elixir of Ogre's Strength]|h" },
		{ itemID = 105, itemName = "Spiced Wolf Ribs", iconFileID = 1, stackCount = 5, quality = 1, hyperlink = "|Hitem:105|h[Spiced Wolf Ribs]|h" } }
	ns.providers.items._dirty = true
	local found = names(UI:Search("@consumable stat:str"))
	check(found["Elixir of Ogre's Strength"] and not found["Spiced Wolf Ribs"], "@consumable stat:str finds the strength elixir")
	found = names(UI:Search("@consumable stat:stamina"))
	check(found["Spiced Wolf Ribs"] and not found["Elixir of Ogre's Strength"], "@consumable stat:stamina finds the food")
	bags[0] = saveBag0
	ns.providers.items._dirty = true
	C_Item.GetItemInfoInstant, C_Item.GetItemSpell, C_Spell.GetSpellDescription = baseInstant2, baseItemSpell, baseDesc
	check(P("q:rare")(bracers) and not P("q:rare")(blade) and P("q:rare+")(blade) and P("q:3")(bracers) and F.Parse("q:shiny") == nil, "q: quality, rare+ and above")
	check(P("ilvl:20-30")(bracers) and not P("ilvl:30+")(bracers) and P("ilvl:30+")(blade), "ilvl: item level")
	check(P("type:mail")(bracers) and P("type:sword")(blade) and P("type:potion")(potion) and not P("type:cloth")(bracers), "type: item type or subtype")
	check(P("lvl:20+")(bracers) and not P("lvl:20+")(old), "lvl: the level an item needs")
	check(P("is:equippable")(bracers) and not P("is:equippable")(potion), "is:equippable")
	check(F.Parse("is:upgrade") ~= nil, "is:upgrade: gear you can equip now, near your item level or better")
	check(P("count:10+")(potion) and not P("count:<10")(potion), "count: how many")
	-- stored: places and holders
	local linen = { itemID = 2589, total = 48, holders = {
		a = { who = "Plamen Warr", where = "bank", count = 20, mine = true },
		b = { who = "Alt Guy", where = "mail", count = 3 },
		c = { who = "Gone", where = "guild", count = 0 } } }
	check(P("in:bank")(linen) and P("in:mail")(linen) and not P("in:guild")(linen) and not P("in:bags")(linen), "in: a stored item's places (empty ones don't count)")
	check(P("on:alt")(linen) and P("on:me")(linen) and not P("on:gone")(linen), "on: who holds it (me = you)")
	check(P("count:48")(linen), "count: the stored total")
	-- loot and quests: in: looks at the dungeon/boss or the zone
	check(P("in:deadmines")({ detail = "Edwin VanCleef  The Deadmines", itemID = 1 }) and P("from:vancleef")({ detail = "Edwin VanCleef  The Deadmines" }), "in:/from: a loot item's dungeon or boss")
	check(P("in:elwynn")({ zone = "Elwynn Forest" }) and P("zone:elwynn")({ zone = "Elwynn Forest" }), "in:/zone: a quest's zone")
	check(P("in:equipped")({ itemID = 100, slotId = 9 }), "in:equipped")
	-- quests ready to turn in
	C_QuestLog.ReadyForTurnIn = function(id) return id == 7 end
	check(P("is:complete")({ kind = "quests", questID = 7 }) and not P("is:complete")({ kind = "quests", questID = 8 }) and not P("is:complete")({ questID = 7 }), "is:complete: quest log quests ready to turn in")
	-- Questie NPCs: level, zone, role
	local NPC = { [5] = { minLevel = 10, maxLevel = 12, zoneID = 331, npcFlags = 128 + 2 } }
	ns.Integrations.NpcField = function(id, f) return NPC[id] and NPC[id][f] end
	ns.Integrations.NpcFlagDefs = function() return { VENDOR = 128, QUEST_GIVER = 2, TRAINER = 16 } end
	_G.C_Map = _G.C_Map or {}
	C_Map.GetAreaInfo = function(a) return a == 331 and "Ashenvale" or nil end
	local vendor = { kind = "npc", key = 5 }
	check(P("lvl:11")(vendor) and P("lvl:12-15")(vendor) and not P("lvl:20+")(vendor), "lvl: an NPC's level range")
	check(P("in:ashenvale")(vendor) and not P("in:elwynn")(vendor), "in: an NPC's zone")
	check(P("is:vendor")(vendor) and P("is:questgiver")(vendor) and not P("is:trainer")(vendor), "is:vendor / is:trainer: what the NPC does")
	-- faction: who the NPC is friendly to (Questie: "A", "H", "AH", or nothing)
	NPC[6] = { friendlyToFaction = "H" }; NPC[7] = { friendlyToFaction = "AH" }; NPC[8] = {}
	NPC[5].friendlyToFaction = "A"
	local orc, both, mob, human = { kind = "npc", key = 6 }, { kind = "npc", key = 7 }, { kind = "npc", key = 8 }, vendor
	check(P("faction:horde")(orc) and P("faction:horde")(both) and not P("faction:horde")(human) and not P("faction:horde")(mob), "faction:horde: friendly to the Horde (both factions too)")
	check(P("faction:alliance")(human) and P("faction:a")(both) and not P("faction:alliance")(orc), "faction:alliance (or a)")
	check(P("faction:neutral")(both) and not P("faction:neutral")(orc) and not P("faction:neutral")(mob), "faction:neutral: friendly to both")
	local baseFaction = _G.UnitFactionGroup
	_G.UnitFactionGroup = function() return "Horde" end
	check(P("faction:friendly")(orc) and P("faction:friendly")(both) and not P("faction:friendly")(human), "faction:friendly: to your own faction")
	_G.UnitFactionGroup = baseFaction
	check(F.Parse("faction:pirates") == nil and not P("faction:horde")({ name = "not an NPC" }), "an unknown faction stays text; other rows are left out")
	-- trainers: by what they teach (their subtitle in Questie, "Warrior Trainer", "Journeyman Blacksmith")
	NPC[10] = { subName = "Warrior Trainer", npcFlags = 16 }
	NPC[11] = { subName = "Journeyman Blacksmith", npcFlags = 16 }
	NPC[12] = { subName = "Herbalism Trainer", npcFlags = 16 }
	NPC[13] = { subName = "Pet Trainer", npcFlags = 16 }
	NPC[14] = { subName = "Master Mathias Shaw", npcFlags = 2 } -- a "Master" who trains nothing
	NPC[15] = { subName = "Undead Mage Trainer", npcFlags = 16 }
	local warr, smith, herb, pet, shaw, mage = { kind = "npc", key = 10 }, { kind = "npc", key = 11 }, { kind = "npc", key = 12 },
		{ kind = "npc", key = 13 }, { kind = "npc", key = 14 }, { kind = "npc", key = 15 }
	check(P("trainer:warrior")(warr) and not P("trainer:warrior")(mage) and P("trainer:mage")(mage), "trainer:<class>")
	check(P("trainer:blacksmithing")(smith) and P("trainer:blacksmith")(smith) and P("trainer:herbalism")(herb) and not P("trainer:blacksmithing")(herb), "trainer:<profession> (Journeyman Blacksmith counts)")
	check(P("trainer:pet")(pet) and not P("trainer:pet")(warr), "trainer:pet (any word in what they teach)")
	check(P("is:classtrainer")(warr) and P("is:classtrainer")(mage) and not P("is:classtrainer")(smith) and not P("is:classtrainer")(pet), "is:classtrainer")
	check(P("is:proftrainer")(smith) and P("is:proftrainer")(herb) and not P("is:proftrainer")(warr) and not P("is:proftrainer")(shaw), "is:proftrainer (a Master who isn't a trainer doesn't count)")
	local baseClass = _G.UnitClass
	_G.UnitClass = function() return "Warrior", "WARRIOR" end
	check(P("trainer:my")(warr) and not P("trainer:my")(mage) and not P("trainer:my")(smith), "trainer:my: your own class's trainers")
	check(P("trainer:class")(warr) and not P("trainer:class")(mage), "trainer:class: your own class (the one you can learn from)")
	check(P("trainer:classes")(warr) and P("trainer:classes")(mage) and not P("trainer:classes")(smith), "trainer:classes: every class trainer")
	-- titles without "trainer" (Questie's trainer flag says so): Miner, Herbalist, Fisherman, Physician; Master Mage
	NPC[16] = { subName = "Miner", npcFlags = 16 }
	NPC[17] = { subName = "Superior Herbalist", npcFlags = 16 }
	NPC[18] = { subName = "Fisherman", npcFlags = 16 }
	NPC[19] = { subName = "Physician", npcFlags = 16 }
	NPC[20] = { subName = "Master Mage", npcFlags = 16 }
	NPC[21] = { subName = "Image Collector", npcFlags = 16 } -- ("mage" inside a word isn't the class)
	local miner, herbalist, fisher, doc, mmage, image = { kind = "npc", key = 16 }, { kind = "npc", key = 17 }, { kind = "npc", key = 18 },
		{ kind = "npc", key = 19 }, { kind = "npc", key = 20 }, { kind = "npc", key = 21 }
	check(P("trainer:mine")(miner) and not P("trainer:mine")(warr), "trainer:mine is the mining trainers (the Miner), not your class")
	check(P("trainer:mining")(miner) and P("trainer:herbalism")(herbalist) and P("trainer:fishing")(fisher) and P("trainer:firstaid")(doc),
		"trainer:<profession> finds Miner, Herbalist, Fisherman, Physician")
	check(P("trainer:mage")(mmage) and not P("trainer:mage")(image) and P("is:classtrainer")(mmage), "Master Mage is a mage trainer; Image Collector isn't")
	check(P("is:proftrainer")(miner) and not P("is:proftrainer")(mmage), "is:proftrainer: the Miner, not the Master Mage")
	_G.UnitClass = baseClass
	check(not P("trainer:warrior")(shaw) and not P("trainer:mage")({ name = "not an NPC" }), "not trainers: left out")
	-- recipes: every reagent in your bags or bank
	C_Item.GetItemCount = function(id) return ({ [2589] = 10, [2320] = 1 })[id] or 0 end
	check(P("is:craftable")({ reagents = { { 2589, 2 }, { 2320, 1 } } }) and not P("is:craftable")({ reagents = { { 2589, 20 } } }) and not P("is:craftable")({}), "is:craftable")
	-- Tab completes a filter's value
	UI:Open("@loot is:us"); check(UI:AcceptCompletion() and UI.edit:GetText() == "@loot is:usable ", "Tab: is:us -> is:usable")
	UI:Open("q:ep"); check(UI:AcceptCompletion() and UI.edit:GetText() == "q:epic ", "Tab: q:ep -> q:epic")
	UI:Open("stat:stam"); check(UI:AcceptCompletion() and UI.edit:GetText() == "stat:stamina ", "Tab: stat:stam -> stat:stamina")
	UI:Open("@npc faction:ho"); check(UI:AcceptCompletion() and UI.edit:GetText() == "@npc faction:horde ", "Tab: faction:ho -> faction:horde")
	UI:Open("@npc trainer:bla"); check(UI:AcceptCompletion() and UI.edit:GetText() == "@npc trainer:blacksmithing ", "Tab: trainer:bla -> trainer:blacksmithing")
	UI:Hide()
	-- .filters lists them
	local out = ns.commands.filters.run("")
	check(out[1]:find("filters", 1, true) and table.concat(out, "\n"):find("stat:stamina", 1, true) and #out >= #F.HELP + 2, ".filters lists every filter")
	C_Item.GetItemInfo, C_Item.GetItemStats, C_Item.GetItemCount, _G.GetInventoryItemLink, UnitLevel = base.info, base.stats, base.count, base.inv, base.level
	C_PlayerInfo.CanUseItem, C_QuestLog.ReadyForTurnIn, C_Map.GetAreaInfo = base.can, base.ready, base.area
	_G.C_Map = base.map
	ns.Integrations.NpcField, ns.Integrations.NpcFlagDefs = base.nf, base.nd
	_G.ITEM_MOD_STAMINA_SHORT, _G.INVTYPE_WRIST = nil, nil
end
do -- the prompt's colours: @kinds, filters, .commands, /slash commands, plain words
	local t = ns.Theme.Get()
	local filt, bad = ns.Theme.SYNTAX.filter, ns.Theme.SYNTAX.bad
	local loot = ns.providers.loot or ns.providers.items
	local kindHex = loot.color:sub(3)
	local h = UI:Highlighted("@" .. loot.aliases[1] .. " red  stat:sta lvl:abc @nope is:")
	check(h:find("|cff" .. kindHex .. "@" .. loot.aliases[1] .. "|r", 1, true), "an @kind in its own colour: " .. h)
	check(h:find("|cff" .. t.text .. "red|r", 1, true), "plain words in the text colour")
	check(h:find("|cff" .. filt .. "stat:sta|r", 1, true) and h:find("|cff" .. filt .. "is:|r", 1, true), "filters (and one still being typed) in the filter colour")
	check(h:find("|cff" .. bad .. "lvl:abc|r", 1, true) and h:find("|cff" .. bad .. "@nope|r", 1, true), "an unknown @kind and a filter value it doesn't take in red")
	check(h:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") == "@" .. loot.aliases[1] .. " red  stat:sta lvl:abc @nope is:", "spaces kept as typed")
	check(UI:Highlighted(".help me"):find("^|cff" .. t.accent .. "%.help|r") and UI:Highlighted(".nosuch"):find("^|cff" .. bad), ".commands: known in the accent, unknown in red")
	check(UI:Highlighted("/dance now"):find("^|cff" .. t.prompt .. "/dance|r|cff" .. t.text .. " now|r"), "/slash commands in the prompt colour")
	check(UI:Highlighted("a|b"):find("a||b", 1, true), "a | typed is shown, not read as a colour code")
	-- shown over the drawn prompt, the box's own text hidden under it
	UI:Open("@loot red")
	check(UI.keys and UI.syntax:IsShown() and UI.edit.textColor[4] == 0, "drawn prompt: the coloured copy shows, the box's text is hidden")
	check(UI.syntax.text and UI.syntax.text:find("red", 1, true), "it shows what's typed")
	-- a long prompt wraps onto more lines, after spaces: the header grows down, the rows move with it
	local LH = ns.Theme.Get().fontSize + 6
	local h1 = UI.heightTo
	local long = string.rep("word ", 30) -- 150 letters: three lines of the 398-pixel box (7 px a letter)
	UI:SetQuery(long, #long)
	local lines = UI:PromptLines()
	check(#lines == 3 and long:sub(lines[1][2], lines[1][2]) == " " and lines[2][1] == lines[1][2] + 1 and lines[3][2] == #long,
		"wrapped into lines, each ending after a space: " .. #lines)
	local h2 = UI.heightTo
	UI:SetPromptExtra(0); local h0 = UI.heightTo
	UI:UpdateCaret()
	check(UI.promptExtra == 2 * LH and h2 == h0 + 2 * LH and UI.heightTo == h2, "the header grows two lines and the frame with it")
	check(UI.syntax:IsShown() and UI.edit.textColor[4] == 0, "the lines are drawn by Terminal, the box's text hidden")
	local _, y = UI:PromptXY(#long)
	check(UI.caretY == -2 * LH and y == -2 * LH, "the cursor is on the last line")
	local x2, y2 = UI:PromptXY(lines[2][1] - 1)
	check(x2 == 0 and y2 == -LH, "a wrapped line's start is the next line's first place")
	UI.anchor = 2; UI.cursor = lines[3][1] + 3; UI:UpdateCaret()
	check(UI.selText:IsShown() and UI.selBands[1] and UI.selBands[1]:IsShown() and UI.selBands[2] and UI.selBands[2]:IsShown(), "a selection over three lines: a band on each")
	UI.anchor = nil
	ns.Theme.Set("syntax", "off"); UI:UpdateCaret()
	check(UI.syntax:IsShown() and not UI.syntax.text:find("|cff" .. filt, 1, true), "colours off: still wrapped (drawn plain)")
	ns.Theme.Set("syntax", "on"); UI:UpdateCaret()
	local word = string.rep("x", 80) -- one word too long for a line: split inside it
	UI:SetQuery(word, #word)
	check(#UI:PromptLines() == 2 and UI:PromptLines()[1][2] == 56, "a word too long for a line is split")
	UI:SetQuery("red", 3)
	check(UI.syntax:IsShown() and UI.promptExtra == 0, "short again: one line, the header back")
	ns.Theme.Set("syntax", "off")
	UI:UpdateCaret()
	check(not UI.syntax:IsShown() and UI.edit.textColor[4] == 1, ".set syntax off: plain text")
	ns.Theme.Set("syntax", "on")
	UI:UpdateCaret()
	check(UI.syntax:IsShown(), ".set syntax on")
	local O = ns.Options
	O.Refresh(); check(O.widgets.syntax:GetChecked() == true, "the options checkbox shows the setting")
	O.widgets.syntax:SetChecked(false); O.widgets.syntax.scripts.OnClick(O.widgets.syntax)
	check(ns.Theme.Get().syntax == false, "and the checkbox turns it off")
	ns.Theme.Set("syntax", "on"); UI:UpdateCaret()
	UI:SetQuery(long, #long)
	UI.edit.scripts.OnEditFocusGained(UI.edit) -- clicked into the box (clipboard): the real box
	check(not UI.syntax:IsShown() and UI.edit.textColor[4] == 1, "the real text box in use: its own text")
	check(UI.promptExtra == 0, "and one line (the real box scrolls)")
	UI:Hide()
	-- pasting: Ctrl+V hands over to the real box (the clipboard is only there); once the text comes
	-- in, the prompt goes back to Terminal's own, coloured, with the cursor where the paste ended
	UI:Open(""); FlushAll() -- (timers left by the tests above)
	withCtrl(function() key("V") end)
	check(not UI.keys, "Ctrl+V: the real text box takes the paste")
	check(UI.status.text and UI.status.text:find("Ctrl+V again to paste", 1, true), "the footer says to press Ctrl+V again: " .. tostring(UI.status.text))
	check(UI.ghost:IsShown() and UI.ghost.text:find("Ctrl+V again", 1, true), "and so does the prompt, faintly")
	do -- left alone, it goes after a few seconds
		local saveV = UI.clipHint
		FlushAll()
		check(UI.clipHint == nil and not UI.status.text:find("again", 1, true), "the reminder is temporary: gone after a few seconds")
		UI.clipHint = saveV; UI:SetStatus()
	end
	UI.edit:SetText("@loot stat:stamina")
	UI.edit:SetCursorPosition(#"@loot stat:stamina")
	UI.edit.scripts.OnTextChanged(UI.edit)
	FlushAll()
	check(UI.keys and UI.syntax:IsShown() and UI.syntax.text:find("|cff" .. filt .. "stat:stamina", 1, true) and UI.cursor == #"@loot stat:stamina",
		"after the paste: back to the drawn prompt, coloured at once, the cursor at the end")
	check(not (UI.status.text or ""):find("again", 1, true) and not (UI.ghost:IsShown() and UI.ghost.text:find("again", 1, true)), "pasted: the reminder is gone")
	-- copying changes nothing: the real box stays for Ctrl+C
	withCtrl(function() key("C") end)
	check(UI.status.text:find("Ctrl+C again to copy", 1, true), "Ctrl+C: the footer says to press it again")
	check(UI.clipHint == "C", "(still there before anything else happens)")
	FlushAll()
	check(not UI.keys, "Ctrl+C: the real box stays (nothing was typed)")
	UI.clipHint = "C"; UI:SetStatus()
	withCtrl(function() UI.edit.scripts.OnKeyDown(UI.edit, "C") end) -- the copy, in the real box
	FlushAll()
	check(not UI.status.text:find("again", 1, true), "copied: the reminder is gone")
	UI:Hide()
end
do -- .atop: addons' CPU and memory, live; type to filter, Tab sorts, Esc or ` closes
	local B = ns.Atop
	local base = { addons = _G.C_AddOns, prof = _G.C_AddOnProfiler, enum = Enum.AddOnProfilerMetric,
		upd = _G.UpdateAddOnMemoryUsage, mem = _G.GetAddOnMemoryUsage, fps = _G.GetFramerate, net = _G.GetNetStats }
	local LIST = { { "Terminal", "Terminal", 0.20, 3000 }, { "Questie", "|cff00ff00Questie|r", 1.10, 90000 }, { "Bagnon", "Bagnon", 0.05, 120000 } }
	_G.C_AddOns = setmetatable({ GetNumAddOns = function() return #LIST end,
		GetAddOnInfo = function(i) return LIST[i][1], LIST[i][2] end,
		IsAddOnLoaded = function() return true end }, { __index = base.addons })
	Enum.AddOnProfilerMetric = { RecentAverageTime = 3 }
	_G.C_AddOnProfiler = { GetAddOnMetric = function(name) for _, a in ipairs(LIST) do if a[1] == name then return a[3] end end end,
		GetOverallMetric = function() return 1.35 end }
	local memAsks = 0
	_G.UpdateAddOnMemoryUsage = function() memAsks = memAsks + 1 end
	_G.GetAddOnMemoryUsage = function(name) for _, a in ipairs(LIST) do if a[1] == name then return a[4] end end end
	_G.GetFramerate = function() return 60 end
	_G.GetNetStats = function() return 0, 0, 40, 45 end
	ns.Theme.Set("animations", "smooth")
	UI:Open(".atop")
	UI:Hide() -- (running a command closes the terminal, with its animation)
	ns.commands.atop.run("")
	check(B.IsShown() and not UI:IsShown() and not UI.closing, ".atop: the panel shows at once, the terminal gone (no closing animation under it)")
	local g = B.graph[#B.graph]
	check(g.shown == g.target, "the bars start at their values, not rising from nothing")
	check(B.Shown()[1].name == "Questie" and B.rows[1].name.text == "Questie", "sorted by CPU, names without colour codes: " .. tostring(B.rows[1].name.text))
	check(B.rows[1].ms.text == "1.100" and B.rows[1].pct.text == "81.5" and B.rows[1].mem.text == "87.9 MB", "CPU ms, share of all addons, memory: " .. tostring(B.rows[1].pct.text))
	check(B.cpuText.text:find("1.35 ms", 1, true) and B.cpuText.text:find("8%", 1, true), "all addons' time per frame and share of a frame: " .. tostring(B.cpuText.text))
	do -- the memory lines fit their box (the peak and Terminal's share on one line ran past its edge)
		local m1, m2, m3 = B.MemTexts()
		local boxW = B.frame.memBox:GetWidth()
		local ok = true
		for _, fs in ipairs({ m1, m2, m3 }) do
			if not (fs.w and fs.w <= boxW - 16) then ok = false end
		end
		check(ok and m2.text:find("^peak") and m3.text:find("^Terminal"), "memory: total, peak and Terminal's share each on a line, kept inside the box")
	end
	B.Key("TAB")
	check(B.state.sort == "mem" and B.Shown()[1].name == "Bagnon", "Tab: by memory")
	B.Key("TAB"); check(B.state.sort == "name" and B.Shown()[1].name == "Bagnon" and B.Shown()[3].name == "Terminal", "Tab: by name")
	B.Key("TAB"); check(B.state.sort == "cpu", "Tab: back to CPU")
	B.Char("q"); B.Char("u")
	check(#B.Shown() == 1 and B.Shown()[1].name == "Questie" and B.footer.text:find("1 of 3", 1, true), "typing filters: " .. tostring(B.footer.text))
	B.Key("BACKSPACE"); B.Key("BACKSPACE")
	check(#B.Shown() == 3, "Backspace widens it again")
	B.Key("DOWN"); B.Key("DOWN"); B.Key("DOWN")
	check(B.state.sel == 3, "Down moves, stopping at the last")
	-- every row shown sits inside the list's box (the last one hung over its bottom edge)
	do
		local boxH = B.frame.procBox:GetHeight()
		local fit = B.Fit()
		check(fit >= 1 and 42 + fit * 19 + 6 <= boxH and fit < 12, ("the rows that show fit the box: %d rows in %s px"):format(fit, tostring(boxH)))
		local many = {}
		for i = 1, 20 do many[i] = { "Addon" .. i, "Addon " .. i, i / 100, i * 100 } end
		local saveList = LIST
		LIST = many
		B.Close(); B.Open()
		local visible = 0
		for i, r in ipairs(B.rows) do if r:IsShown() then visible = i end end
		check(visible == fit and not B.rows[fit + 1]:IsShown(), "with more addons than fit: only the rows that fit show (" .. visible .. ")")
		for _ = 1, 15 do B.Key("DOWN") end
		check(B.state.sel == 16 and B.state.offset == 16 - fit, "moving down scrolls by the rows that fit")
		LIST = saveList
		B.Close(); B.Open()
		B.Key("DOWN"); B.Key("DOWN")
	end
	-- it animates: samples come in over time, the graph's bars glide toward them
	local before = #B.History()
	B.Tick(0.6)
	check(#B.History() == before + 1, "a new CPU sample every half second")
	for _ = 1, 30 do B.Tick(0.04) end
	local newest = B.graph[#B.graph]
	check(math.abs(newest.shown - newest.target) < 0.01 and newest.target > 0, "the newest bar has risen to its value")
	local asks = memAsks
	B.Tick(3.1)
	check(memAsks == asks, "memory isn't asked for every 3 s any more (its cost was the spike in Terminal's graph)")
	B.Tick(7)
	check(memAsks == asks + 1, "memory asked for every 10 s (it's costly)")
	B.Char("`")
	check(B.state.filter == "", "` isn't typed into the filter")
	B.Key("ESCAPE")
	check(not B.IsShown(), "Esc closes")
	ns.commands.atop.run(""); B.Key("`")
	check(not B.IsShown(), "` closes")
	-- combat: it reads the keyboard, so it doesn't open, and closes when combat starts
	local realCombat = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	check(B.Open() == false and not B.IsShown(), "not in combat")
	_G.InCombatLockdown = realCombat
	B.Open()
	B.frame.scripts.OnEvent(B.frame, "PLAYER_REGEN_DISABLED")
	check(not B.IsShown(), "combat starting closes it")
	-- no profiler on this client: it says so, memory still works
	_G.C_AddOnProfiler = nil
	B.Open()
	check(B.cpuText.text:find("no addon CPU profiler", 1, true) and B.rows[1].ms.text == "-", "no profiler: said so, no CPU numbers")
	B.Close()
	_G.C_AddOns, _G.C_AddOnProfiler, Enum.AddOnProfilerMetric = base.addons, base.prof, base.enum
	_G.UpdateAddOnMemoryUsage, _G.GetAddOnMemoryUsage, _G.GetFramerate, _G.GetNetStats = base.upd, base.mem, base.fps, base.net
end
do -- .snake: WASD/arrows steer, apples grow it, walls and the tail end it, Esc or ` quits;
	-- only the game's keys are kept, any other key goes on to the game
	local Sn = ns.Snake
	local g = Sn.game
	Sn.rand = function() return 1 end -- apples land on the first free cell
	ns.db.snakeBest = 2
	UI:Open(".snake"); UI:Hide()
	ns.commands.snake.run("")
	check(Sn.IsShown() and not UI:IsShown() and not UI.closing, ".snake: the board shows at once, the terminal gone")
	check(#g.body == 3 and g.body[1][1] == 6 and g.dir[1] == 1 and g.score == 0, "a snake of three, heading right")
	Sn.Step()
	check(g.body[1][1] == 7 and #g.body == 3, "a move: the head goes ahead, the tail follows")
	local passed
	local f = Sn.frame
	f.SetPropagateKeyboardInput = function(_, v) passed = v end
	f.scripts.OnKeyDown(f, "S")
	check(passed == false, "S is the game's (kept)")
	Sn.Step()
	check(g.body[1][2] == g.body[2][2] + 1, "S turns down")
	f.scripts.OnKeyDown(f, "W")
	Sn.Step()
	check(g.dir[2] == 1, "W straight back up is refused (it would run into itself)")
	f.scripts.OnKeyDown(f, "1")
	check(passed == true, "any other key goes on to the game (action bars, chat)")
	f.scripts.OnKeyDown(f, "LEFT"); Sn.Step()
	check(g.dir[1] == -1, "arrow keys steer too")
	-- an apple right ahead: eaten, longer, faster, a point
	local head = g.body[1]
	g.food = { head[1] - 1, head[2] }
	local speed = g.speed
	Sn.Step()
	check(#g.body == 4 and g.score == 1 and g.speed > speed and g.food ~= nil, "an apple: longer, a point, a little faster, a new apple")
	-- a wall ends it; the best score is kept
	g.score = 5
	for _ = 1, 30 do Sn.Step() end
	check(g.over and g.why == "wall" and ns.db.snakeBest == 5 and g.newBest, "the wall ends it, and the best score is kept")
	Sn.Draw()
	check(Sn.frame and g.over, "game over is shown")
	f.scripts.OnKeyDown(f, "ENTER")
	check(not g.over and #g.body == 3 and g.score == 0 and passed == false, "Enter plays again (and isn't passed on)")
	-- its own tail ends it
	g.body = { { 5, 5 }, { 6, 5 }, { 6, 6 }, { 5, 6 }, { 4, 6 } }
	g.dir, g.queue = { -1, 0 }, {}
	Sn.Turn(0, 1); Sn.Step()
	check(g.over and g.why == "tail", "running into its own tail ends it")
	Sn.Reset()
	-- moving the tail out of the way doesn't count as hitting it
	g.body = { { 5, 5 }, { 5, 6 }, { 6, 6 }, { 6, 5 } }
	g.dir, g.queue, g.food = { 1, 0 }, {}, { 0, 0 }
	Sn.Step()
	check(not g.over and g.body[1][1] == 6 and g.body[1][2] == 5, "following its own tail's last cell is fine")
	-- it moves by itself as time passes, and Space pauses
	Sn.Reset()
	local x0 = g.body[1][1]
	Sn.Tick(1 / g.speed + 0.001)
	check(g.body[1][1] == x0 + 1, "time passing moves it")
	f.scripts.OnKeyDown(f, "SPACE")
	check(passed == true and not g.paused, "no pausing: Space isn't the game's, it goes on to the game")
	Sn.Tick(1 / g.speed + 0.001)
	check(g.body[1][1] == x0 + 2, "and the snake keeps going")
	-- a long frame (alt-tab, a loading hitch) makes at most one move or two, not a run into the wall
	Sn.Reset()
	local before = g.body[1][1]
	Sn.Tick(5)
	check(not g.over and g.body[1][1] - before <= 2, "a 5 s hitch doesn't make many moves at once: " .. (g.body[1][1] - before))
	f.scripts.OnKeyDown(f, "ESCAPE")
	check(not Sn.IsShown(), "Esc quits")
	ns.commands.snake.run(""); f.scripts.OnKeyDown(f, "`")
	check(not Sn.IsShown(), "` quits")
	-- combat: it doesn't start, and closes when combat starts
	local realCombat = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	check(Sn.Open() == false and not Sn.IsShown(), "not in combat")
	_G.InCombatLockdown = realCombat
	Sn.Open()
	f.scripts.OnEvent(f, "PLAYER_REGEN_DISABLED")
	check(not Sn.IsShown(), "combat starting closes it")
	-- atop and snake: opening one closes the other
	Sn.Open(); ns.Atop.Open()
	check(ns.Atop.IsShown() and not Sn.IsShown(), "atop opening closes snake")
	Sn.Open()
	check(Sn.IsShown() and not ns.Atop.IsShown(), "and snake closes atop")
	Sn.Close()
	Sn.rand = function(n) return math.random(n) end
end
do -- .changelog: what changed, newest first, scrolled back through the last few versions
	local CL = ns.Changelog
	-- kept up to date: the top entry is this version (the TOC's), and the last few versions are there
	local tocText = io.open("Terminal/Terminal.toc"):read("*a")
	local tocVersion = tocText:match("## Version: (%S+)")
	check(CL.LOG[1].v == tocVersion, "the changelog's top entry is this version (" .. tostring(tocVersion) .. "): " .. tostring(CL.LOG[1].v))
	check(#CL.LOG >= 3 and #CL.LOG <= 5, "it keeps the last few versions: " .. #CL.LOG)
	for i, entry in ipairs(CL.LOG) do
		check(type(entry.v) == "string" and type(entry.items) == "table" and #entry.items > 0, "entry " .. i .. " has a version and changes")
	end
	local text = CL.Text()
	check(text:find(CL.LOG[1].v, 1, true) < text:find(CL.LOG[2].v, 1, true), "the newest is at the top")
	-- the command opens it where the terminal was; the terminal goes
	UI:Open("")
	ns.commands.changelog.run("")
	check(CL.IsShown() and not UI:IsShown(), ".changelog opens its window in place of the terminal")
	check(ns:FindCommand("changes") == ns.commands.changelog and ns:FindCommand("whatsnew") == ns.commands.changelog, ".changes and .whatsnew too")
	-- scrolling: arrows, pages, Home/End, the mouse wheel; kept inside the text
	local sc, content = CL.Parts()
	sc.h, content.h = 100, 500
	CL.ScrollTo(0)
	local f = CL.frame
	f.scripts.OnKeyDown(f, "DOWN")
	check(CL.Offset() == 40 and f.propagate == false, "Down scrolls (and the key is kept)")
	f.scripts.OnKeyDown(f, "END")
	check(CL.Offset() == 400, "End: the oldest at the bottom")
	f.scripts.OnKeyDown(f, "DOWN")
	check(CL.Offset() == 400, "not past the end")
	f.scripts.OnKeyDown(f, "PAGEUP")
	check(CL.Offset() == 340, "Page Up: a page back (one line kept)")
	f.scripts.OnKeyDown(f, "HOME")
	check(CL.Offset() == 0, "Home: back to the newest")
	f.scripts.OnKeyDown(f, "UP")
	check(CL.Offset() == 0, "not past the top")
	f.scripts.OnMouseWheel(f, -1)
	check(CL.Offset() == 40, "the mouse wheel scrolls")
	f.scripts.OnKeyDown(f, "W")
	check(f.propagate == true and CL.IsShown(), "other keys go on to the game")
	f.scripts.OnKeyDown(f, "ESCAPE")
	check(not CL.IsShown(), "Esc closes it")
	ns.commands.changelog.run(""); f.scripts.OnKeyDown(f, "`")
	check(not CL.IsShown(), "` closes it")
	-- reopened: the newest at the top again
	ns.commands.changelog.run("")
	check(CL.Offset() == 0, "it opens at the newest")
	-- combat: it doesn't open, and closes when combat starts
	CL.Close()
	local realCombat = _G.InCombatLockdown
	_G.InCombatLockdown = function() return true end
	check(CL.Open() == false and not CL.IsShown(), "not in combat")
	_G.InCombatLockdown = realCombat
	CL.Open()
	f.scripts.OnEvent(f, "PLAYER_REGEN_DISABLED")
	check(not CL.IsShown(), "combat starting closes it")
	-- atop, snake and the changelog: opening one closes the others
	CL.Open(); ns.Atop.Open()
	check(ns.Atop.IsShown() and not CL.IsShown(), "atop closes the changelog")
	CL.Open()
	check(CL.IsShown() and not ns.Atop.IsShown(), "and the changelog closes atop")
	ns.Snake.Open()
	check(ns.Snake.IsShown() and not CL.IsShown(), "snake closes the changelog")
	ns.Snake.Close()
end
do -- a profession whose window opens with a spell not named like it (Herbalism on this client)
	local P = ns.Professions
	local save = { gp = _G.GetProfessions, gpi = _G.GetProfessionInfo, can = C_TradeSkillUI.CanTradeSkillShowCraftingUI,
		gsn = C_Spell.GetSpellName, gsi = C_Spell.GetSpellInfo }
	_G.GetProfessions = function() return 7 end
	_G.GetProfessionInfo = function(i) if i == 7 then return "Herbalism", 20, 40, 150, 2, 70, 182 end end
	C_TradeSkillUI.CanTradeSkillShowCraftingUI = function(id) return id == 171 end -- (slot 71: the window's spell)
	C_Spell.GetSpellName = function(id) if id == 171 then return "Herb Gathering" elseif id == 172 then return "Find Herbs" end return save.gsn(id) end
	C_Spell.GetSpellInfo = function(x) if x == "Herbalism" then return nil end return save.gsi(x) end -- (no spell is named Herbalism)
	check(P.OpenSpell("Herbalism") == nil and P.OpenerSpell(182, "Herbalism") == "Herb Gathering",
		"no spell named Herbalism: its window's spell is found among its own spellbook entries")
	-- its recipes, indexed when its window was opened from the game's profession book, open through it: a recipe,
	-- and Incense Candle (a camp object: listed under @camp)
	local st = P.Store()
	st[182] = { name = "Herbalism", skillLine = 182, fromList = true, list = {
		{ id = 901, name = "Incense Candle", learned = true, icon = 1, item = 5901 },
		{ id = 902, name = "Swiftthistle Brew", learned = true, icon = 1 } } }
	ns.providers.recipes._dirty, ns.providers.camp._dirty = true, true
	local rec = names(ns:GetEntries(ns.providers.recipes))
	check(rec["Swiftthistle Brew"] and rec["Swiftthistle Brew"].secure and rec["Swiftthistle Brew"].secure.spell == "Herb Gathering",
		"a Herbalism recipe opens Herbalism with its window's spell")
	local camp = names(ns:GetEntries(ns.providers.camp))
	local candle = camp["Incense Candle"]
	check(candle and candle.secure and candle.secure.spell == "Herb Gathering",
		"Incense Candle (@camp) opens Herbalism with its window's spell: " .. tostring(candle and candle.secure and candle.secure.spell))
	local r = ns.Secure.Resolve(candle.secure, candle)
	check(r and r.spell == "Herb Gathering", "Enter casts it on the same press")
	-- Shift+Enter on a camp object: use one from your bags, else make it
	local baseCount = C_Item.GetItemCount
	local have = 1
	C_Item.GetItemCount = function(id) if id == 5901 then return have end return baseCount and baseCount(id) or 0 end
	local v = ns.UI.SecureView(candle, true)
	r = ns.Secure.Resolve(v.secure, v)
	check(r and r.macro == "/use item:5901", "one in your bags: Shift+Enter uses it: " .. tostring(r and r.macro))
	have = 0
	v = ns.UI.SecureView(candle, true)
	r = ns.Secure.Resolve(v.secure, v)
	check(r and r.macro == "/cast Herb Gathering\n/run C_TradeSkillUI.CraftRecipe(901,1)",
		"none in your bags, no window: the game opens the window and makes it: " .. tostring(r and r.macro))
	local baseOpen = candle.recipeIsOpen
	candle.recipeIsOpen = function() return true end
	v = ns.UI.SecureView(candle, true)
	r = ns.Secure.Resolve(v.secure, v)
	check(r and r.macro == "/run C_TradeSkillUI.CraftRecipe(901,1)", "its window already open: it just makes it")
	candle.recipeIsOpen = baseOpen
	C_Item.GetItemCount = baseCount
	-- and the Herbalism row itself opens the window the same way
	ns.providers.professions._dirty = true
	local pe = names(ns:GetEntries(ns.providers.professions))
	check(pe["Herbalism"] and pe["Herbalism"].secure and pe["Herbalism"].secure.spell == "Herb Gathering", "the Herbalism row opens its window too")
	st[182] = nil
	ns.providers.camp._dirty = true
	-- the game says none of its entries opens a crafting window (gathering professions given one here): its entry
	-- named like it, which the game's profession book casts
	C_TradeSkillUI.CanTradeSkillShowCraftingUI = function() return false end
	C_Spell.GetSpellName = function(id) if id == 171 then return "Herbalism" elseif id == 172 then return "Find Herbs" end return save.gsn(id) end
	check(P.OpenerSpell(182, "Herbalism") == "Herbalism", "no entry said to open a window: the one named like it")
	-- none named like it either: its one active entry that isn't a minimap tracking spell (Gardening; Find Herbs tracks)
	C_Spell.GetSpellName = function(id) if id == 171 then return "Find Herbs" elseif id == 172 then return "Gardening" end return save.gsn(id) end
	local baseMinimap = _G.C_Minimap
	_G.C_Minimap = { GetNumTrackingTypes = function() return 1 end, GetTrackingInfo = function() return { name = "Find Herbs", spellID = 171 } end }
	check(P.OpenerSpell(182, "Herbalism") == "Gardening", "its window's spell when the game names none: Gardening (Find Herbs tracks)")
	_G.C_Minimap = baseMinimap
	-- you open it yourself (the game's profession book casts its entry): that spell opens it from then on
	C_Spell.GetSpellName = function(id) if id == 171 then return "Herb Gathering" elseif id == 172 then return "Find Herbs" end return save.gsn(id) end
	check(P.OpenerSpell(182, "Herbalism") == nil, "nothing to go by: no opener found yet")
	P.castWatch.scripts.OnEvent(P.castWatch, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 171)
	RECIPES[182] = { ids = { 901 }, info = { [901] = { name = "Incense Candle", icon = 1, learned = true, categoryID = 5 } } }
	local saveProf = tsState.prof
	tsState.prof = { id = 182, name = "Herbalism" }
	local baseLine = C_TradeSkillUI.GetTradeSkillLineForRecipe
	C_TradeSkillUI.GetTradeSkillLineForRecipe = function(id) if id == 901 then return 182, "Herbalism", 182 end return baseLine and baseLine(id) end
	P.Snapshot(); FlushAll()
	local herb
	for _, pd in pairs(P.Store()) do if pd.name == "Herbalism" then herb = pd end end
	check(herb and herb.opener == "Herb Gathering", "the spell you opened it with is kept as its opener: " .. tostring(herb and herb.opener))
	check(P.WindowSpell(182, "Herbalism") == "Herb Gathering", "and it opens the window from then on")
	-- a spell that isn't one of its own (cast just before, in a fight) isn't taken for its opener
	for k, pd in pairs(P.Store()) do if pd.name == "Herbalism" then P.Store()[k] = nil end end
	P.castWatch.scripts.OnEvent(P.castWatch, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 101) -- (Fireball)
	P.Snapshot(); FlushAll()
	herb = nil
	for _, pd in pairs(P.Store()) do if pd.name == "Herbalism" then herb = pd end end
	check(herb and herb.opener == nil, "a spell not its own isn't kept as its opener")
	for k, pd in pairs(P.Store()) do if pd.name == "Herbalism" then P.Store()[k] = nil end end
	RECIPES[182], tsState.prof, C_TradeSkillUI.GetTradeSkillLineForRecipe = nil, saveProf, baseLine
	_G.GetProfessions, _G.GetProfessionInfo, C_TradeSkillUI.CanTradeSkillShowCraftingUI = save.gp, save.gpi, save.can
	C_Spell.GetSpellName, C_Spell.GetSpellInfo = save.gsn, save.gsi
	ns.providers.recipes._dirty, ns.providers.professions._dirty = true, true
end
-- what the game does with Enter armed to the macro proxy: runs its macro (timers at once), then its PostClick
local function PressArmed()
	local px = ns.Secure.armed == "MACROUP" and _G.TerminalMacroProxyUp or _G.TerminalMacroProxy
	if (ns.Secure.armed ~= "MACRO" and ns.Secure.armed ~= "MACROUP") or not px then return false end
	local body = tostring(px.attrs.macrotext):match("^/run (.*)$")
	local fn = body and loadstring(body)
	if not fn then return false end
	local ta = C_Timer.After
	C_Timer.After = function(_, f) f() end
	fn()
	C_Timer.After = ta
	if px.scripts.PostClick then px.scripts.PostClick(px, "LeftButton", ns.Secure.armed == "MACRO") end
	return true
end
do -- achievements: Shift+Enter links one in chat; its kind's colour isn't Camp's
	local F = _G.TerminalFrame
	UI:Open("level 10")
	local ach = UI.Results()[1]
	check(ach and ach.kind == "achievements", "the achievement is found")
	local mark = #log
	_G.IsShiftKeyDown = function() return true end
	F.scripts.OnKeyDown(F, "ENTER")
	_G.IsShiftKeyDown = function() return false end
	check(not logHas("OPENCHAT", mark + 1) and PressArmed(), "Shift+Enter: the game opens the chat box (Terminal's own call tainted it)")
	check(logHas("OPENCHAT |Hachievement:7|h[Level 10]|h", mark + 1) and not UI:IsShown(),
		"Shift+Enter on an achievement links it in chat")
	-- typing in the chat box already: the link goes into it
	local baseInsert = _G.ChatEdit_InsertLink
	_G.ChatEdit_InsertLink = function(l) note("INSERTLINK", l); return true end
	UI:Open("level 10"); mark = #log
	_G.IsShiftKeyDown = function() return true end
	F.scripts.OnKeyDown(F, "ENTER")
	_G.IsShiftKeyDown = function() return false end
	PressArmed()
	check(logHas("INSERTLINK |Hachievement:7|h[Level 10]|h", mark + 1) and not logHas("OPENCHAT |Hachievement:7|h[Level 10]|h", mark + 1),
		"the chat box already open: the link goes into what you're typing")
	_G.ChatEdit_InsertLink = baseInsert
	-- the kind's colour stands apart from Camp's (both were orange)
	local function rgb(c) return tonumber(c:sub(3, 4), 16), tonumber(c:sub(5, 6), 16), tonumber(c:sub(7, 8), 16) end
	local r1, g1, b1 = rgb(ns.providers.achievements.color)
	local r2, g2, b2 = rgb(ns.providers.camp.color)
	check(math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2) > 120, "achievements' colour isn't close to Camp's")
end
do -- ">> channel": the selected result goes to a chat channel (the game presses the chat line)
	local SH, S, F = ns.Share, ns.Secure, _G.TerminalFrame
	local function key(k) F.scripts.OnKeyDown(F, k) end
	local q, rest = SH.Split("copper bar >> party")
	check(q == "copper bar " and rest == "party", "split: the search, and the channel after >>")
	check(SH.Split("lvl:>20 copper") == "lvl:>20 copper" and select(2, SH.Split("lvl:>20 copper")) == nil, "a > in a filter isn't >>")
	check(SH.Channel("party").cmd == "/p" and SH.Channel("g").cmd == "/g" and SH.Channel("raid").cmd == "/raid" and SH.Channel("say").cmd == "/s",
		"channels by name or short name")
	check(SH.Channel("w Bob").cmd == "/w Bob" and SH.Channel("whisper").pending and SH.Channel("2").cmd == "/2", "whispers and numbered channels")
	check(SH.Channel("").pending and SH.Channel("nowhere").bad == "nowhere", "no channel yet / not a channel")
	-- an item: its link, sent by the game's press
	UI:Open("hearthstone >> party")
	check(UI.Results()[1] and UI.Results()[1].name == "Hearthstone", "the search is what's before the >>")
	key("ENTER")
	check(S.armed == "MACRO" and _G.TerminalMacroProxy.attrs.macrotext == "/p |cffffffff|Hitem:6948|h[Hearthstone]|h|r" and F.propagate == true,
		"Enter sends the item's link to the party: " .. tostring(_G.TerminalMacroProxy.attrs.macrotext))
	UI:Disarm(); UI:Hide()
	-- an achievement, to the guild; Shift+Enter sends too
	UI:Open("level 10 >> guild")
	_G.IsShiftKeyDown = function() return true end
	key("ENTER")
	_G.IsShiftKeyDown = function() return false end
	check(S.armed == "MACRO" and _G.TerminalMacroProxy.attrs.macrotext == "/g |Hachievement:7|h[Level 10]|h", "an achievement's link to the guild (Shift+Enter too)")
	UI:Disarm(); UI:Hide()
	-- a whisper
	UI:Open("hearthstone >> w Bob"); key("ENTER")
	check(_G.TerminalMacroProxy.attrs.macrotext == "/w Bob |cffffffff|Hitem:6948|h[Hearthstone]|h|r", "whispered")
	UI:Disarm(); UI:Hide()
	-- no channel yet, or not one: nothing is sent, and the result isn't opened either
	local printed
	local basePrint = ns.Print
	ns.Print = function(_, m) printed = m end
	UI:Open("hearthstone >> "); local mark = #log; key("ENTER")
	check(S.armed == nil and not logHas("OpenAllBags", mark + 1) and printed and printed:find("where to send", 1, true), "no channel yet: says so, opens nothing")
	UI:Hide()
	UI:Open("hearthstone >> nowhere"); mark = #log; key("ENTER")
	check(S.armed == nil and not logHas("OpenAllBags", mark + 1) and printed and printed:find("No channel called nowhere", 1, true), "not a channel: says so")
	ns.Print = basePrint
	UI:Hide()
	-- an NPC: a map pin where it stands
	local baseLink = ns.Integrations.NpcPinLink
	ns.Integrations.NpcPinLink = function(e) return "|cffffff00|Hworldmap:37:5000:4000|h[Map Pin Location]|h|r" end
	check(SH.Text({ npcID = 12, name = "Marshal McBride" }) == "Marshal McBride |cffffff00|Hworldmap:37:5000:4000|h[Map Pin Location]|h|r", "an NPC: its name and a map pin")
	-- what was searched says what the NPC is: "Nearby reagent vendor: Name [pin]"
	local PIN = "|cffffff00|Hworldmap:37:5000:4000|h[Map Pin Location]|h|r"
	local jo = { npcID = 1, name = "Jo Reagents" }
	local function line(q, e) return SH.Macro(e or jo, { cmd = "/g", label = "guild", query = q }) end
	check(line("@npc reagent is:vendor faction:friendly sort:nearest ", { npcID = 2, name = "Hula'mahi" })
		== "/g Nearby reagent vendor: Hula'mahi " .. PIN, "nearest reagent vendor: says so: " .. tostring(line("@npc reagent is:vendor faction:friendly sort:nearest ", { npcID = 2, name = "Hula'mahi" })))
	check(line("@npc reagent is:vendor ") == "/g Vendor: Jo Reagents " .. PIN, "a word already in the name isn't repeated: " .. tostring(line("@npc reagent is:vendor ")))
	check(line("@npc trainer:mine in:orgrimmar ", { npcID = 3, name = "Makaru" }) == "/g Mining trainer in Orgrimmar: Makaru " .. PIN, "trainer and place: " .. tostring(line("@npc trainer:mine in:orgrimmar ", { npcID = 3, name = "Makaru" })))
	check(line("@npc hogger ", { npcID = 448, name = "Hogger" }) == "/g Hogger " .. PIN, "only the name searched: just the NPC")
	check(SH.Macro(jo, { cmd = "/g", query = "@npc " .. ("x"):rep(240) .. " is:vendor" }) == "/g Jo Reagents " .. PIN, "too long for a macro: the words go first")
	-- through the prompt: the line the game presses
	UI:Open("@npc reagent is:vendor sort:nearest >> guild")
	check(UI.sendTo and UI.sendTo.query == "@npc reagent is:vendor sort:nearest ", "the search part is kept with where it goes")
	UI:Hide()
	ns.Integrations.NpcPinLink = baseLink
	-- something with no link: its name; a loot row ("item:ID"): the item's full link
	check(SH.Text({ name = "Ironforge" }) == "Ironforge", "no link: its name")
	-- a quest the game won't link (not in your log): Questie's link, which its chat filter makes clickable
	do
		local baseQL, baseGQL, baseCQL = _G.QuestieLoader, _G.GetQuestLink, C_QuestLog.GetQuestLink
		_G.GetQuestLink, C_QuestLog.GetQuestLink = nil, function() return nil end
		_G.QuestieLoader = { ImportModule = function(_, n)
			if n == "QuestieLink" then
				return { GetNativeQuestLinkStringById = function(id) return "[[10] The Fargodeep Mine (" .. id .. ")]" end }
			end
		end }
		check(SH.Text({ qid = 62, name = "The Fargodeep Mine" }) == "[[10] The Fargodeep Mine (62)]", "a Questie quest: Questie's link, not its name: " .. tostring(SH.Text({ qid = 62, name = "The Fargodeep Mine" })))
		check(SH.Text({ questID = 62, name = "The Fargodeep Mine" }) == "[[10] The Fargodeep Mine (62)]", "a log quest the game won't link: Questie's link")
		check(SH.Macro({ qid = 62, name = "The Fargodeep Mine" }, { cmd = "/g" }) == "/g [[10] The Fargodeep Mine (62)]", "sent as Questie's link")
		-- an older Questie without QuestieLink: the same bracket text from its database
		_G.QuestieLoader = { ImportModule = function(_, n)
			if n == "QuestieDB" then return { QueryQuestSingle = function(id, f) return f == "name" and "Kobold Camp Cleanup" or nil end } end
		end }
		check(SH.Text({ qid = 7, name = "Kobold Camp Cleanup" }) == "[Kobold Camp Cleanup (7)]", "older Questie: [Name (id)]")
		-- no Questie: the name
		_G.QuestieLoader = nil
		check(SH.Text({ qid = 7, name = "Kobold Camp Cleanup" }) == "Kobold Camp Cleanup", "no Questie: its name")
		-- the game's own link wins when there is one
		C_QuestLog.GetQuestLink = function(id) return "|cffffff00|Hquest:" .. id .. ":10|h[Kobold Camp Cleanup]|h|r" end
		check(SH.Text({ questID = 7, name = "Kobold Camp Cleanup" }) == "|cffffff00|Hquest:7:10|h[Kobold Camp Cleanup]|h|r", "the game's quest link first")
		_G.QuestieLoader, _G.GetQuestLink, C_QuestLog.GetQuestLink = baseQL, baseGQL, baseCQL
	end
	-- within what a macro runs
	check(#SH.Macro({ name = "x", link = "|Hitem:1|h[" .. ("A"):rep(300) .. "]|h" }, { cmd = "/p" }) <= 255, "kept within 255 characters")
	-- the prompt: >> and the channel coloured, Tab completes the channel
	local segs = UI:SyntaxSegments("hearthstone >> party")
	local col = {}
	for _, sg in ipairs(segs) do col[("hearthstone >> party"):sub(sg[1], sg[2])] = sg[3] end
	check(col[">>"] == ns.Theme.Get().accent and col.party == ns.Theme.SYNTAX.filter, ">> and its channel coloured")
	segs = UI:SyntaxSegments("hearthstone >> nowhere x")
	for _, sg in ipairs(segs) do col[("hearthstone >> nowhere x"):sub(sg[1], sg[2])] = sg[3] end
	check(col.nowhere == ns.Theme.SYNTAX.bad, "a word that isn't a channel in red")
	UI:Open("hearthstone >> gu")
	check(UI:AcceptCompletion() and UI.edit:GetText() == "hearthstone >> guild ", "Tab completes the channel: " .. tostring(UI.edit:GetText()))
	UI:Hide()
end
do -- Shift+Right at the end of the prompt: the selected result written into it ("@npc Thrall"), to build on
	local F = _G.TerminalFrame
	local function shiftRight()
		_G.IsShiftKeyDown = function() return true end
		F.scripts.OnKeyDown(F, "RIGHT")
		_G.IsShiftKeyDown = function() return false end
	end
	UI:Open("hearth")
	check(UI.Results()[1] and UI.Results()[1].name == "Hearthstone", "the item is selected")
	shiftRight()
	check(UI.edit:GetText() == "@item Hearthstone " and UI.cursor == #"@item Hearthstone ", "Shift+Right writes it into the prompt as @kind name: " .. tostring(UI.edit:GetText()))
	check(UI.Results()[1] and UI.Results()[1].name == "Hearthstone", "and it still finds it")
	UI:Hide()
	-- from the empty prompt (your recent picks), and keeping a ">> channel" already typed
	UI:Open("hearth >> party")
	shiftRight()
	check(UI.edit:GetText() == "@item Hearthstone >> party", "a >> channel already typed is kept: " .. tostring(UI.edit:GetText()))
	UI:Hide()
	-- with the cursor inside the text, Shift+Right still selects
	UI:Open("hearth")
	F.scripts.OnKeyDown(F, "HOME")
	shiftRight()
	check(UI.edit:GetText() == "hearth" and UI:SelRange() ~= nil, "the cursor inside the text: Shift+Right selects, as before")
	UI:Hide()
	-- a command row: its .command
	UI:Open(".them")
	shiftRight()
	check(UI.edit:GetText() == ".theme ", "a command: its .command: " .. tostring(UI.edit:GetText()))
	UI:Hide()
end
do -- a profession sent to chat: its link, with every recipe you know (as the game's profession book gives it)
	local F, S = _G.TerminalFrame, ns.Secure
	local save = { gp = _G.GetProfessions, gpi = _G.GetProfessionInfo, tl = C_SpellBook.GetSpellBookItemTradeSkillLink }
	local LINK = "|cffffd000|Htrade:Player-1-0001:182:182|h[Herbalism]|h|r"
	_G.GetProfessions = function() return 7 end
	_G.GetProfessionInfo = function(i) if i == 7 then return "Herbalism", 20, 40, 150, 2, 70, 182 end end
	C_SpellBook.GetSpellBookItemTradeSkillLink = function(slot) if slot == 71 then return LINK end end
	ns.providers.professions._dirty = true
	local herb = names(ns:GetEntries(ns.providers.professions)).Herbalism
	check(herb and ns.Share.Text(herb) == LINK, "a profession's text is its link: " .. tostring(herb and ns.Share.Text(herb)))
	UI:Open("@profession herbalism >> guild")
	F.scripts.OnKeyDown(F, "ENTER")
	check(S.armed == "MACRO" and _G.TerminalMacroProxy.attrs.macrotext == "/g " .. LINK, ">> guild sends the profession's link: " .. tostring(_G.TerminalMacroProxy.attrs.macrotext))
	UI:Disarm(); UI:Hide()
	-- selected, its tooltip never shows that link: a profession link shown opens the profession (Enchanting opened
	-- with the terminal, as the top recent pick)
	UI:Open("hearth"); UI:Hide()
	local tt, shownLinks = _G.TerminalTooltip, {}
	local baseSet = tt and tt.SetHyperlink
	if tt then tt.SetHyperlink = function(_, l) shownLinks[#shownLinks + 1] = l end end
	UI:Open("@profession herbalism"); UI:UpdateTooltip()
	local trade = false
	for _, l in ipairs(shownLinks) do if tostring(l):find("|Htrade:", 1, true) then trade = true end end
	check(tt and not trade, "a profession's link is never shown in the tooltip (that would open the profession)")
	if tt then tt.SetHyperlink = baseSet end
	UI:Hide()
	-- Shift+Enter: its link in chat; Enter opens its window (its window's spell)
	local mark = #log
	UI:Open("@profession herbalism")
	_G.IsShiftKeyDown = function() return true end
	F.scripts.OnKeyDown(F, "ENTER")
	_G.IsShiftKeyDown = function() return false end
	PressArmed()
	check(logHas("OPENCHAT " .. LINK, mark + 1) and S.armed == nil, "Shift+Enter puts the profession's link in chat")
	UI:Disarm(); UI:Hide()
	_G.GetProfessions, _G.GetProfessionInfo, C_SpellBook.GetSpellBookItemTradeSkillLink = save.gp, save.gpi, save.tl
	ns.providers.professions._dirty = true
end
-- Extra test files (tests/smoke/*.lua, alphabetical) run here with the same game and helpers: each gets T =
-- { ns, UI, F, S, check, log, logHas, key, typeText, query, withCtrl, names, Obj, Flush, FlushAll, timers }.
do
	local T = { ns = ns, UI = UI, F = F, S = S, check = check, log = log, logHas = logHas, key = key, typeText = typeText,
		query = query, withCtrl = withCtrl, names = names, Obj = Obj, Flush = Flush, FlushAll = FlushAll, timers = timers }
	for _, file in ipairs(_G.SMOKE_EXTRA or {}) do
		local chunk, err = loadfile(file)
		if not chunk then fails = fails + 1; io.write("FAIL: " .. tostring(err) .. "\n")
		else
			io.write("[" .. file:match("[^/\\]+$") .. "]\n")
			-- each file gets its own budget under the runaway guard (line 1), not what's left of the run's
			debug.sethook(function() error("INSTRUCTION LIMIT HIT\n" .. debug.traceback(), 2) end, "", 20000000)
			local ok, e = pcall(chunk, T)
			if not ok then fails = fails + 1; io.write("FAIL: " .. file .. ": " .. tostring(e) .. "\n") end
		end
	end
end
_G.SMOKE_FAILS = fails -- run_smoke.py exits 1 when this is above 0
io.write(fails == 0 and "ALL SMOKE TESTS PASSED\n" or (fails .. " FAILURES\n"))
