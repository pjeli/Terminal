local ns = select(2, ...)
local H = ns.Highlight

--- A global function by name, called in a pcall (nil when the client lacks it).
local function Call(name, ...) return ns.Safe(_G[name], ...) end

local function MicroGlow(buttonName)
	C_Timer.After(0.05, function()
		local b = buttonName and _G[buttonName]
		if b and b:IsVisible() then H:Show(b, 5) end
	end)
end

local MACRO_WINDOW = { macro = "/macro" } -- the Macros window, opened by the game
local function MacroWindowOpen()
	return _G.MacroFrame and _G.MacroFrame:IsShown() and true or false
end

----------------------------------------------------------------------
-- Interface panels
--
-- Every panel is opened the way the player's own key opens it: Enter is bound to the game's
-- binding command for it (TOGGLEWORLDMAP, TOGGLEACHIEVEMENT...), or to a macro line the game
-- runs (/macro, /editmode, a /run of the game's own opener). Opening them from Terminal's code
-- taints the window (see Secure.lua), so the `open` functions below are only the fallback when
-- no such route exists on this client. A panel already showing is only pointed at (its micro
-- button glows), never toggled closed.
----------------------------------------------------------------------

local function Shown(name)
	local f = _G[name]
	return type(f) == "table" and f.IsVisible and f:IsVisible() and true or false
end

--- Any of the panel's frames showing.
local function PanelOpen(e)
	for _, name in ipairs(e.frames or {}) do
		if Shown(name) then return true end
	end
	return false
end

local function BagsOpen()
	if Shown("ContainerFrameCombinedBags") then return true end
	return IsBagOpen and IsBagOpen(0) and true or false
end

-- the Currency tab of the character window, through its tab (as the Reputation tab is)
local function TokenClick() return ns.Secure.CharTabMacro("TokenFrame", { _G.CURRENCY or "Currency", "Currency" }) end
local TOKEN_SECURE = { macro = TokenClick, click = TokenClick }
local function TokenOpen() return Shown("TokenFrame") end

-- game-run openers for panels without a binding command (a /run line on the secure macro button)
local OPTIONS_MACRO = "/run local S=SettingsPanel if S and S.Open then S:Open() elseif Settings then Settings.OpenToCategory(Settings.GAME_CATEGORY_ID or 1) end"
local ADDONLIST_MACRO = "/run if AddonList then ShowUIPanel(AddonList) end"
local EDITMODE_MACRO = "/editmode"

-- The specs other providers own (their files load after this one): looked up when the list is made.
local function BookShown() return ns.Spells.Book() ~= nil end
local function SpellbookRoute()
	local SP = ns.Spells
	return SP and SP.SECURE or { binding = "TOGGLESPELLBOOK", buttons = { "SpellbookMicroButton" } }, SP and BookShown or nil
end
local function TalentsRoute()
	local TL = ns.Talents
	return TL and TL.SECURE or { binding = "TOGGLETALENTS", buttons = { "TalentMicroButton", "PlayerSpellsMicroButton" } }, TL and TL.IsOpen or nil
end
local function QuestLogRoute()
	local Q = ns.Quests
	return Q and Q.SECURE or { binding = "TOGGLEQUESTLOG", buttons = { "QuestLogMicroButton" } }, Q and Q.LogShown or nil
end
local function MapRoute()
	return ns.Maps and ns.Maps.SECURE or { binding = "TOGGLEWORLDMAP" }, PanelOpen
end

-- name, search words, fallback opener (Terminal's code: only without a secure route), micro button,
-- secure spec (binding / macro the game presses; or a function giving spec and isOpen), is-it-open check,
-- frames that mean it's open
local PANELS = {
	{ "Character Info", "character equipment gear paperdoll", function() ToggleCharacter("PaperDollFrame") end, "CharacterMicroButton", nil, nil, "PaperDollFrame" },
	{ "Reputation", "reputation factions renown", function() ToggleCharacter("ReputationFrame") end, "CharacterMicroButton", nil, nil, "ReputationFrame" },
	{ "Currency", "currency tokens", function()
		-- the client's own opener first: it doesn't run our code through the Character frame
		if C_CurrencyInfo and C_CurrencyInfo.OpenCurrencyPanel then C_CurrencyInfo.OpenCurrencyPanel() else ToggleCharacter("TokenFrame") end
	end, "CharacterMicroButton", TOKEN_SECURE, TokenOpen },
	{ "Spellbook", "spellbook abilities spells", function()
		ns.LoadBlizz("Blizzard_PlayerSpells")
		if PlayerSpellsUtil and PlayerSpellsUtil.ToggleSpellBookFrame then PlayerSpellsUtil.ToggleSpellBookFrame() else Call("ToggleSpellBook", "spell") end
	end, "PlayerSpellsMicroButton", SpellbookRoute },
	{ "Talents", "talents specialization spec hero", function()
		ns.LoadBlizz("Blizzard_PlayerSpells")
		if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame then PlayerSpellsUtil.ToggleClassTalentFrame() else Call("ToggleTalentFrame") end
	end, "PlayerSpellsMicroButton", TalentsRoute },
	{ "Achievements", "achievements feats", function() ns.LoadBlizz("Blizzard_AchievementUI"); Call("ToggleAchievementFrame") end, "AchievementMicroButton",
		{ binding = "TOGGLEACHIEVEMENT", buttons = { "AchievementMicroButton" } }, PanelOpen, "AchievementFrame" },
	{ "Quest Log", "quest log journal", function() Call("ToggleQuestLog") end, "QuestLogMicroButton", QuestLogRoute },
	{ "World Map", "map world zone", function() Call("ToggleWorldMap") end, nil, MapRoute, nil, "WorldMapFrame" },
	{ "Collections", "collections mounts pets toys heirlooms transmog appearances", function() Call("ToggleCollectionsJournal") end, "CollectionsMicroButton",
		{ binding = "TOGGLECOLLECTIONS", buttons = { "CollectionsMicroButton" } }, PanelOpen, "CollectionsJournal" },
	{ "Group Finder", "group finder dungeon raid lfg pvp", function() Call("PVEFrame_ToggleFrame") end, "LFDMicroButton",
		{ buttons = { "LFDMicroButton" } }, PanelOpen, "PVEFrame" },
	{ "Guild & Communities", "guild communities", function() Call("ToggleGuildFrame") end, "GuildMicroButton",
		{ binding = "TOGGLEGUILDTAB", buttons = { "GuildMicroButton" } }, PanelOpen, "CommunitiesFrame", "GuildFrame" },
	{ "Adventure Guide", "adventure guide encounter journal dungeon journal", function() Call("ToggleEncounterJournal") end, "EJMicroButton",
		{ binding = "TOGGLEENCOUNTERJOURNAL", buttons = { "EJMicroButton" } }, PanelOpen, "EncounterJournal" },
	{ "Professions", "professions crafting", function() Call("ToggleProfessionsBook") end, "ProfessionMicroButton",
		{ binding = "TOGGLEPROFESSIONBOOK", buttons = { "ProfessionMicroButton" } }, PanelOpen, "ProfessionsBookFrame" },
	{ "Calendar", "calendar events", function() Call("ToggleCalendar") end, nil, { binding = "TOGGLECALENDAR" }, PanelOpen, "CalendarFrame" },
	{ "Social / Friends", "friends social who ignore", function() Call("ToggleFriendsFrame") end, nil, { binding = "TOGGLESOCIAL" }, PanelOpen, "FriendsFrame" },
	{ "Backpack & Bags", "bags backpack inventory", function() Call("ToggleAllBags") end, nil, { binding = "OPENALLBAGS" }, BagsOpen },
	{ "Game Menu", "game menu escape logout exit", function() Call("ToggleGameMenu") end, "MainMenuMicroButton",
		{ binding = "TOGGLEGAMEMENU", buttons = { "MainMenuMicroButton" } }, PanelOpen, "GameMenuFrame" },
	{ "Options", "options settings interface video audio", function()
		if Settings and Settings.OpenToCategory then Settings.OpenToCategory() else Call("ShowUIPanel", _G.SettingsPanel) end
	end, nil, { macro = OPTIONS_MACRO }, PanelOpen, "SettingsPanel" },
	{ "AddOn List", "addons manager", function() if AddonList then ShowUIPanel(AddonList) end end, nil, { macro = ADDONLIST_MACRO }, PanelOpen, "AddonList" },
	{ "Macros", "macros", function() ns.LoadBlizz("Blizzard_MacroUI"); if MacroFrame then ShowUIPanel(MacroFrame) end end, nil, MACRO_WINDOW, MacroWindowOpen },
	{ "Edit Mode", "edit mode layout hud", function() ns.RunSlash("/editmode") end, nil, { macro = EDITMODE_MACRO }, PanelOpen, "EditModeManagerFrame" },
	-- WoW Forever's Legacy window (Blizzard_LegacySystem: LegacySystemFrame, its challenges and more), opened by
	-- the game clicking its micro button (ClassicUIForever moves that button off the bar, but it still clicks);
	-- listed only where the client has it
	{ "Legacy", "legacy system challenges", function() local b = _G.LegacyMicroButton; if b then b:Click() end end, "LegacyMicroButton",
		{ buttons = { "LegacyMicroButton" } }, PanelOpen, "LegacySystemFrame", needs = "LegacyMicroButton", nameFrom = "LegacyMicroButton" },
	{ "Shop", "shop store", function() Call("ToggleStoreUI") end, "StoreMicroButton", { buttons = { "StoreMicroButton" } }, PanelOpen, "StoreFrame" },
}

-- The game's own words for these panels (a Korean client shows 평판, not "Reputation"). The
-- English name stays as the key and in the searchable text, so both find the panel.
local PANEL_GLOBALS = {
	["Character Info"] = "CHARACTER_BUTTON", ["Reputation"] = "REPUTATION", ["Currency"] = "CURRENCY",
	["Spellbook"] = "SPELLBOOK", ["Talents"] = "TALENTS", ["Achievements"] = "ACHIEVEMENT_BUTTON",
	["Quest Log"] = "QUESTLOG_BUTTON", ["World Map"] = "WORLD_MAP", ["Collections"] = "COLLECTIONS",
	["Group Finder"] = "GROUP_FINDER", ["Guild & Communities"] = "GUILD_AND_COMMUNITIES",
	["Adventure Guide"] = "ADVENTURE_JOURNAL", ["Professions"] = "PROFESSIONS_BUTTON",
	["Calendar"] = "CALENDAR", ["Social / Friends"] = "SOCIAL_BUTTON", ["Game Menu"] = "MAINMENU_BUTTON",
	["Options"] = "OPTIONS", ["AddOn List"] = "ADDONS", ["Macros"] = "MACROS",
	["Edit Mode"] = "HUD_EDIT_MODE_MENU", ["Shop"] = "BLIZZARD_STORE",
}

--- The panel's name in the game's own words: its global string, else its micro button's tooltip
--- ("Legacy |cffffd200(L)|r": the key part dropped), else the English name.
local function PanelName(english, button)
	local name = ns.GameText(PANEL_GLOBALS[english], nil)
	if not name and button then
		local b = _G[button]
		local tip = type(b) == "table" and ns.Str(rawget(b, "tooltipText"))
		if tip then
			tip = tip:gsub("|c%x%x%x%x%x%x%x%x.-|r", "")
			tip = ns.Plain(tip):gsub("%s*%(.-%)%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
			if tip ~= "" then name = tip end
		end
	end
	return name or english
end

-- the game's keybinding commands for Character window tabs
local CHAR_BINDINGS = { PaperDollFrame = "TOGGLECHARACTER0", ReputationFrame = "TOGGLECHARACTER2" }
local CHAR_CLICKS = { PaperDollFrame = ns.Secure.PAPERDOLL_CLICK, ReputationFrame = ns.Secure.REP_CLICK }
local function PageOpen(e) local f = _G[e.page]; return f and f:IsVisible() and true or false end
local function PageAfter(e) MicroGlow(e.micro) end
local function TalentsAfter() MicroGlow(ns.Secure.First(ns.Talents.BUTTONS)) end

-- shared by every currency, mount and achievement entry (not one copy per entry)
local function PointAtCurrency(e)
	H:Find(function()
		local root = _G.TokenFrame or CharacterFrame
		return root and root:IsVisible() and ns.FindByText(root, e.name) or nil
	end)
end
-- without the tab's /click route: the client's own opener (a C call), else the character window from here
local function OpenCurrency(e)
	if C_CurrencyInfo.OpenCurrencyPanel then C_CurrencyInfo.OpenCurrencyPanel() else ToggleCharacter("TokenFrame") end
	PointAtCurrency(e)
end

local function SummonMount(e)
	if C_MountJournal and C_MountJournal.SummonByID then C_MountJournal.SummonByID(e.key) end
end
local function MountLink(e) return e.spellID and C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(e.spellID) or nil end

local function ShowMount(e)
	ns.LoadBlizz("Blizzard_Collections")
	if CollectionsJournal_SetTab and CollectionsJournal then
		ShowUIPanel(CollectionsJournal)
		CollectionsJournal_SetTab(CollectionsJournal, 1)
	end
	H:Find(function()
		local root = _G.MountJournal
		return root and root:IsVisible() and ns.FindByText(root, e.name) or nil
	end)
end

local function OpenAchievement(e)
	ns.LoadBlizz("Blizzard_AchievementUI")
	if AchievementFrame_SelectAchievement then
		ShowUIPanel(AchievementFrame)
		pcall(AchievementFrame_SelectAchievement, e.key)
	else
		Call("ToggleAchievementFrame")
	end
end
local function AchievementLink(e) return GetAchievementLink and GetAchievementLink(e.key) or nil end

-- Shift+Enter: link it in chat
local function LinkAchievement(e)
	if not ns.LinkInChat(AchievementLink(e)) then ns:Print("Couldn't link " .. tostring(e.name) .. " in chat.") end
end

local function PanelActivate(e)
	e.open()
	MicroGlow(e.micro)
end

ns:RegisterProvider("panels", {
	label = "Panel",
	color = "ff7fe0ff",
	aliases = { "panel", "ui", "window", "frame" },
	collect = function()
		local out = {}
		for _, p in ipairs(PANELS) do
			local e = {
				key = p[1],
				name = PanelName(p[1], p.nameFrom),
				icon = "Interface\\Icons\\INV_Misc_Map_01",
				text = p[2] .. " " .. p[1],
				open = p[3], micro = p[4],
				activate = PanelActivate,
			}
			if p[5] then
				-- the game's own route (binding or macro), its "is it showing" check, and the glow afterwards
				local secure, isOpen = p[5], p[6]
				if type(secure) == "function" then secure, isOpen = secure() end
				e.secure, e.isOpen, e.after = secure, isOpen, PageAfter
				if p[7] then
					e.frames = {}
					for i = 7, #p do e.frames[#e.frames + 1] = p[i] end
				end
				if p[1] == "Talents" and ns.Talents then e.after = TalentsAfter end
			elseif p[7] then
				-- a tab of the Character window: the game's own key opens it on that page (or switches
				-- page when it's open on another); Terminal's code never switches it (taint)
				e.secure = { binding = CHAR_BINDINGS[p[7]], buttons = { p[4] }, click = CHAR_CLICKS[p[7]] }
				e.page, e.micro = p[7], p[4]
				e.isOpen = PageOpen
				e.after = PageAfter
			end
			if not p.needs or _G[p.needs] then out[#out + 1] = e end
		end
		return out
	end,
})

----------------------------------------------------------------------
-- Macros
----------------------------------------------------------------------

-- Your macros: search by name or by what they say. Enter (or a click) runs the macro through
-- the game's own secure button, like pressing it on an action bar, so nothing runs as
-- Terminal. Shift+Enter opens the Macros window (`/macro`, also run by the game) and points
-- at it. Macros can't be run in combat from here (Enter can't be re-bound then).

--- The macro's current text: macros can be edited or reordered after the list was built.
local function MacroBody(e)
	local name, _, body = GetMacroInfo(e.index)
	if name ~= e.name and GetMacroIndexByName then
		local idx = GetMacroIndexByName(e.name)
		if idx and idx > 0 then name, _, body = GetMacroInfo(idx) end
	end
	if name == e.name and type(body) == "string" and body ~= "" then return body end
end

local MACRO_RUN = { macro = MacroBody }

--- Points at the macro's button once the window is up (reading only; the game selects nothing).
local function ShowInMacroWindow(e)
	H:When(function()
		local root = _G.MacroFrame
		if not (root and root:IsVisible()) then return nil end
		return ns.FindByText(root, e.name)
	end, function(row) H:Show(row) end, 20)
end

local function ShowMacroText(e)
	local body = MacroBody(e)
	if body and ns.ShowText then ns:ShowText(e.name, body) end
end

local function OneLine(body)
	local line = body:gsub("^#showtooltip[^\n]*\n?", ""):gsub("\n.*", "")
	if line == "" then line = body:gsub("\n.*", "") end
	return (line:gsub("|", "||"))
end

ns:RegisterProvider("macros", {
	label = "Macro",
	color = "ffffa040",
	aliases = { "macro", "macros" },
	events = { "UPDATE_MACROS" },
	noCombat = true,
	collect = function()
		local out = {}
		local numAccount, numChar = GetNumMacros()
		local function add(index)
			local name, icon, body = GetMacroInfo(index)
			if name and name ~= "" then
				body = type(body) == "string" and body or ""
				out[#out + 1] = {
					key = name, -- (by name, not slot: a macro moved in the window keeps its history)
					index = index,
					name = name,
					icon = icon,
					text = body, -- what the macro says is searchable too
					detail = (index > 120 and "Character" or "General") .. (body ~= "" and ("  " .. OneLine(body)) or ""),
					tip = body:gsub("|", "||"),
					secure = MACRO_RUN,
					secondary = ShowMacroText, -- without the secure route: its text in a copyable window
					secondarySecure = MACRO_WINDOW,
					secondaryIsOpen = MacroWindowOpen,
					secondaryAfter = ShowInMacroWindow,
					noCombatSecondary = true,
				}
			end
		end
		for i = 1, numAccount do add(i) end
		for i = 121, 120 + numChar do add(i) end
		return out
	end,
})

----------------------------------------------------------------------
-- Currencies
----------------------------------------------------------------------

--- A currency's id: in its list info on newer clients, else read from its link (both C calls).
local function CurrencyID(info, index)
	local id = ns.Num(info.currencyID)
	if id then return id end
	local C = C_CurrencyInfo
	local link = C.GetCurrencyListLink and ns.Safe(C.GetCurrencyListLink, index)
	return link and C.GetCurrencyIDFromLink and ns.Num(ns.Safe(C.GetCurrencyIDFromLink, link)) or nil
end

ns:RegisterProvider("currency", {
	label = "Currency",
	color = "ffffe066",
	aliases = { "currencies", "token", "tokens" },
	events = { "CURRENCY_DISPLAY_UPDATE" },
	guard = 2,
	collect = function()
		local out = {}
		for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
			local info = C_CurrencyInfo.GetCurrencyListInfo(i)
			if info and not info.isHeader and info.name and (info.quantity or 0) > 0 then -- only currencies you hold
				out[#out + 1] = {
					key = info.name,
					name = info.name,
					icon = info.iconFileID,
					-- the numbers too, for filters (count:, the weekly cap); maxQuantity 0 = uncapped
					currencyID = CurrencyID(info, i),
					quantity = ns.Num(info.quantity) or 0,
					maxQuantity = ns.Num(info.maxQuantity) or 0,
					maxWeeklyQuantity = ns.Num(info.maxWeeklyQuantity),
					quantityEarnedThisWeek = ns.Num(info.quantityEarnedThisWeek),
					detail = tostring(info.quantity or 0) .. ((info.maxQuantity and info.maxQuantity > 0) and (" / " .. info.maxQuantity) or ""),
					secure = TOKEN_SECURE, isOpen = TokenOpen, after = PointAtCurrency, -- (the game opens the tab)
					activate = OpenCurrency,
				}
			end
		end
		return out
	end,
})

----------------------------------------------------------------------
-- Mounts (collected only). Enter = summon, Shift+Enter = show in journal.
----------------------------------------------------------------------

ns:RegisterProvider("mounts", {
	label = "Mount",
	color = "ff7bd88f",
	aliases = { "mount" },
	events = { "NEW_MOUNT_ADDED", "COMPANION_LEARNED" },
	collect = function()
		local out = {}
		local M = C_MountJournal
		if not (M and M.GetMountIDs and M.GetMountInfoByID) then return out end -- (a client without the journal)
		for _, mountID in ipairs(ns.Safe(M.GetMountIDs) or {}) do
			local name, spellID, icon, _, isUsable, _, isFavorite, _, _, hideOnChar, isCollected =
				ns.Safe(M.GetMountInfoByID, mountID)
			if name and isCollected and not hideOnChar then
				out[#out + 1] = {
					key = mountID,
					name = name,
					icon = icon,
					detail = isFavorite and "Favorite" or "",
					spellID = spellID,
					getLink = MountLink, -- (made when selected, not for every mount on every rebuild)
					activate = SummonMount,
					secondary = ShowMount,
				}
			end
		end
		return out
	end,
})

----------------------------------------------------------------------
-- Achievements (heavy: indexed once, only when you actually search)
--
-- Every achievement is indexed, earned or not, into one list of compact rows (`achievementlist`,
-- what @achievement searches). Plain searches read a second list (`achievements`) holding only the
-- earned rows of the first (the same tables): thousands of unearned ones would flood every plain
-- search. Both lists' rows are of the kind "achievements" (their meta is that list's), so history,
-- colour and label are one kind either way. Unearned rows are greyed, with their progress
-- ("3/10") in the detail, worked out only when a row is read (shown, or judged by a filter).
----------------------------------------------------------------------

local ACH_COLOR = "ffff6fae" -- (rose: the oranges are Camp's and its neighbours')
local NOT_EARNED = "|cff8a8a8a"
local achMeta -- shared fields of every achievement row (made once both lists are registered)
local critGen = 0 -- bumped when criteria progress: a row's cached progress is read again then
local earnedFrom -- the whole list's rows the earned list was last made from

--- "3/10": the completed criteria of an unearned achievement, or a lone criterion's quantity
--- (kill 50 of them: "12/50"). Nil when earned or without criteria. Cached per row until progress moves.
local function Progress(t)
	if rawget(t, "completed") then return nil end
	if rawget(t, "_progGen") == critGen then return rawget(t, "_prog") or nil end
	local id, prog = rawget(t, "key"), nil
	local n = ns.Num(ns.Safe(GetAchievementNumCriteria, id)) or 0
	if n == 1 then
		local _, _, _, q, req = ns.Safe(GetAchievementCriteriaInfo, id, 1)
		q, req = ns.Num(q), ns.Num(req)
		if q and req and req > 1 then prog = math.min(q, req) .. "/" .. req end
	end
	if not prog and n > 0 then
		local done = 0
		for i = 1, n do
			local _, _, ok = ns.Safe(GetAchievementCriteriaInfo, id, i)
			if ok == true then done = done + 1 end
		end
		prog = done .. "/" .. n
	end
	rawset(t, "_prog", prog or false)
	rawset(t, "_progGen", critGen)
	return prog
end

local function AchDetail(t)
	local pts = rawget(t, "points")
	pts = pts and pts > 0 and (pts .. " pts") or ""
	if rawget(t, "completed") then return "Done  " .. pts end
	local prog = Progress(t)
	return prog and (prog .. "  " .. pts) or pts
end

-- criteria move all the time (every kill): only a number is bumped here
local critWatch = CreateFrame("Frame")
pcall(critWatch.RegisterEvent, critWatch, "CRITERIA_UPDATE")
critWatch:SetScript("OnEvent", function() critGen = critGen + 1 end)

local function CollectAchievements()
	local out = {}
	if not (GetCategoryList and GetCategoryNumAchievements and GetAchievementInfo) then return out end
	for _, cat in ipairs(ns.Safe(GetCategoryList) or {}) do
		local num = ns.Safe(GetCategoryNumAchievements, cat, true) or 0
		for i = 1, num do
			local id, name, points, completed, _, _, _, description, _, icon = ns.Safe(GetAchievementInfo, cat, i)
			if id and ns.Str(name) then
				description = ns.Str(description)
				out[#out + 1] = setmetatable({
					_compact = true,
					key = id,
					name = name,
					icon = icon,
					text = description,
					tip = description,
					points = ns.Num(points),
					completed = completed and true or false,
					color = not completed and NOT_EARNED or nil,
				}, achMeta)
			end
		end
	end
	return out
end

-- @achievement: all of them (registered first, so it owns the @words)
ns:RegisterProvider("achievementlist", {
	label = "Achieve",
	color = ACH_COLOR,
	aliases = { "achievement", "achievements", "ach", "achieve" },
	explicit = true, -- (plain searches read the earned list below)
	lazy = true,
	events = { "ACHIEVEMENT_EARNED" }, -- earned this session: listed without a /reload
	idleDrop = 600,
	collect = CollectAchievements,
})

-- plain searches: the earned ones, the same rows
ns:RegisterProvider("achievements", {
	label = "Achieve",
	color = ACH_COLOR,
	lazy = true,
	events = { "ACHIEVEMENT_EARNED" },
	idleDrop = 600,
	collect = function()
		local all = ns.providers.achievementlist
		-- this list is made again only when it's stale: so is the whole one, unless that was made again
		-- since (an @achievement search after the achievement was earned: not read twice)
		if all._entries and all._entries == earnedFrom then all._dirty = true end
		local list = ns:GetEntries(all)
		earnedFrom = list
		local out = {}
		for _, e in ipairs(list) do
			if rawget(e, "completed") then out[#out + 1] = e end
		end
		return out
	end,
})

do
	-- the game's own word for achievements (added to this list by RegisterProvider) goes to @achievement's
	local earned, all = ns.providers.achievements, ns.providers.achievementlist
	for _, a in ipairs(earned.aliases) do all.aliases[#all.aliases + 1] = a end
	wipe(earned.aliases)
	ns:AliasesChanged()
	achMeta = ns:CompactMeta(earned, {
		getLink = AchievementLink, -- (made when selected, not per achievement up front)
		activate = OpenAchievement,
		secondary = LinkAchievement, -- Shift+Enter: link it in chat
	}, { detail = AchDetail, progress = Progress })
end

----------------------------------------------------------------------
-- CVars (@cvar): the game's console settings, with their value and default. Many settings the
-- options panel never shows live only here. Enter puts "/console <name> <value>" in the prompt to
-- edit; running that line has the game set it (see Slash.lua). Shift+Enter: the same with its default.
----------------------------------------------------------------------

local CHANGED = "|cffffd200"

local function Plain(v)
	if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
	return tostring(v)
end

-- Enum.ConsoleCategory's names, by number: "Graphics", "Sound"...
local categories
local function Category(n)
	if not categories then
		categories = {}
		for k, v in pairs(Enum.ConsoleCategory or {}) do categories[v] = k end
	end
	return categories[n]
end

local function CVarLine(e, value)
	local line = "/console " .. e.name .. " " .. (value or "")
	ns.UI:SetQuery(line, #line)
end
local function EditCVar(e) CVarLine(e, Plain(C_CVar.GetCVar(e.name)) or e.value) end
local function DefaultCVar(e) CVarLine(e, e.default) end

-- Terminal's list of names (CVarList.lua), read once: name -> { category, help }, and the names in order
local known, knownOrder
local function Known()
	if not known then
		known, knownOrder = {}, {}
		for name, cat, help in (ns.CVAR_LIST or ""):gmatch("([^\t\n]+)\t([^\t\n]*)\t([^\n]*)") do
			known[name] = { tonumber(cat), help }
			knownOrder[#knownOrder + 1] = name
		end
	end
	return known, knownOrder
end

--- A setting's value and default, and whether it's read-only / protected; nil value: not a setting here.
local function Read(name)
	local value, default, readOnly, secure
	local info, get = C_CVar and C_CVar.GetCVarInfo, C_CVar and C_CVar.GetCVar
	if info then
		local ok, v, d, _, _, locked, sec, ro = pcall(info, name)
		if ok then value, default, readOnly, secure = Plain(v), Plain(d), (ro or locked) and true or false, sec and true or false end
	end
	if value == nil and get then
		local ok, v = pcall(get, name)
		value = ok and Plain(v) or nil
	end
	if value ~= nil and default == nil and C_CVar.GetCVarDefault then
		local ok, d = pcall(C_CVar.GetCVarDefault, name)
		default = ok and Plain(d) or nil
	end
	return value, default, readOnly, secure
end

--- The row's value, detail, colour and searchable text, from its current value.
local function Fill(e, value, default)
	e.value, e.default = value, default
	e.changed = value ~= nil and default ~= nil and value ~= default
	e.color = e.changed and CHANGED or nil
	e.detail = "= " .. (value or "?") .. (e.changed and ("  (default " .. default .. ")") or "")
		.. (e.readOnly and "  read-only" or "") .. (e.cat and ("  " .. e.cat) or "")
	e._ltext = ns.Lower(e.help .. " " .. (e.cat or "") .. (e.changed and " changed" or ""))
end

-- the tooltip, made when hovered (not for every one of ~1650 rows up front)
local function Tooltip(e, t)
	t:SetText(e.name, 1, 1, 1)
	if e.help ~= "" then t:AddLine(e.help, 0.8, 0.8, 0.8, true) end
	t:AddDoubleLine("Value", tostring(e.value or "?"), 1, 0.82, 0, 1, 1, 1)
	t:AddDoubleLine("Default", tostring(e.default or "?"), 1, 0.82, 0, 1, 1, 1)
	if e.readOnly then t:AddLine("Read-only: the game won't let it be changed", 1, 0.4, 0.4, true) end
	if e.secure then t:AddLine("Protected: can't be changed in combat", 1, 0.6, 0.3, true) end
	t:AddLine(" ")
	t:AddLine("Enter: edit it    Shift+Enter: back to its default", 0.6, 0.6, 0.6, true)
end

local byName = {} -- setting name -> its row (CVAR_UPDATE updates just that row)
ns.CVars = { Edit = EditCVar, Default = DefaultCVar, Rows = function() return byName end }

ns:RegisterProvider("cvars", {
	label = "CVar",
	color = "ff8ec5ff",
	aliases = { "cvar", "cvars", "console" }, -- ("settings" is the options panel's, GameOptions.lua)
	explicit = true, -- a few thousand: only with @cvar
	lazy = true,
	idleDrop = 600,
	onDrop = function() byName = {} end,
	collect = function(p)
		local out = {}
		byName = {}
		-- the game's own list, when it gives one (WoW Forever doesn't let addons have it)
		local ok, all = false, nil
		for _, fn in ipairs({ C_Console and C_Console.GetAllCommands or false, _G.ConsoleGetAllCommands or false }) do
			if fn then
				ok, all = pcall(fn)
				if ok and type(all) == "table" and #all > 0 then break end
			end
		end
		all = ok and type(all) == "table" and all or {}
		local kn, order = Known()
		local from = #all > 0 and "the game's list" or "Terminal's list"
		local names = {}
		if #all > 0 then
			for _, c in ipairs(all) do
				local name = type(c) == "table" and Plain(c.command)
				if name then names[#names + 1] = { name, c.category, Plain(c.help) } end
			end
		else
			-- otherwise the names Terminal knows, each looked up in the game below
			for _, name in ipairs(order) do names[#names + 1] = { name } end
		end
		for _, n in ipairs(names) do
			local name = n[1]
			-- a setting is whatever has a value: the command type isn't trusted (ClassicUIForever doesn't
			-- either), and console commands (reloadui...) have none
			local value, default, readOnly, secure = Read(name)
			if value ~= nil then
				local k = kn[name]
				local help = (n[3] and n[3] ~= "" and n[3]) or (k and k[2]) or ""
				local e = {
					key = name, name = name, help = help, cat = Category(n[2] or (k and k[1])),
					readOnly = readOnly, secure = secure,
					icon = "Interface\\Icons\\INV_Misc_Gear_01",
					tooltip = Tooltip,
					staysOpen = true, -- only fills the prompt in: you edit, then Enter runs it
					activate = EditCVar,
					secondary = DefaultCVar,
				}
				Fill(e, value, default)
				out[#out + 1] = e
				byName[name] = e
			end
		end
		ns:Trace(("cvars: %s: %d names (the game's own call %s), %d settings this client has"):format(from, #names, ok and "ok" or "failed", #out))
		if #out == 0 then
			-- the list can come back empty early on: ask again on the next search, and say what happened
			C_Timer.After(1, function() p._dirty = true end)
			out[1] = { key = "none", name = "No console settings could be read yet", raw = true, noActivate = true, icon = false,
				detail = ("%d names from %s, none with a value"):format(#names, from), text = "" }
		end
		return out
	end,
})

-- A setting changed (yours, the options panel's, an addon's: the camera's change often): just its row is
-- updated, not the whole list made again. A change without a name marks the list to be made again.
local cvarWatch = CreateFrame("Frame")
ns.CVars.watch = cvarWatch
pcall(cvarWatch.RegisterEvent, cvarWatch, "CVAR_UPDATE")
cvarWatch:SetScript("OnEvent", function(_, _, name)
	local p = ns.providers.cvars
	if not (p and p._entries) then return end
	local e = type(name) == "string" and byName[name]
	if not e then
		if type(name) ~= "string" then p._dirty = true end
		return
	end
	local value, default = Read(name)
	if value ~= e.value or default ~= e.default then
		Fill(e, value, default)
		ns.entriesGen = ns.entriesGen + 1 -- (searches narrowed from the last one see the new value)
	end
end)
