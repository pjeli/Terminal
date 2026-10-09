local ns = select(2, ...)
local H = ns.Highlight

--- A global function by name, called in a pcall (nil when the client lacks it).
local function Call(name, ...) return ns.Safe(_G[name], ...) end

local function MicroGlow(buttonName)
	C_Timer.After(0.05, function()
		local b = buttonName and _G[buttonName]
		if b and b:IsVisible() then H:Show(b) end
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
-- A tab's kind, for the trace: "not loaded yet", "a button" or "a plain frame".
local function TabKind(t)
	return type(t) ~= "table" and "not loaded yet" or t.Click and "a button" or "a plain frame"
end
-- The /run line that clicks a tab (a global): Click, or a plain Frame's mouse scripts (no Click, as the character
-- tabs are here). Pressed by the game; Terminal's code never clicks them (taint).
local function TabRunLine(tab)
	return "/run local t=" .. tab .. " if t then if t.Click then t:Click() else for _,s in ipairs({\"OnMouseDown\",\"OnMouseUp\"}) do local f=t:GetScript(s) if f then f(t,\"LeftButton\") end end end end"
end
-- The Legacy window's tabs. Its addon (Blizzard_LegacySystem) loads on demand: the tabs exist only once the
-- micro button's click has opened it, so the press clicks the button first (only while the window is closed),
-- then the tab, from one /run line: a tab that is a plain Frame (no Click, as the character tabs are here) gets
-- its mouse scripts run instead. All of it pressed by the game; Terminal's code never clicks them (taint).
local function LegacyTabMacro(e)
	local lines = {}
	if not Shown("LegacySystemFrame") then lines[1] = "/click LegacyMicroButton" end
	local how = TabKind(_G[e.tab])
	if not ns.Secure.quiet then ns:Trace("legacy: " .. e.tab .. " is " .. how .. (lines[1] and ", window closed: the micro button first" or ", window open")) end
	lines[#lines + 1] = TabRunLine(e.tab)
	return table.concat(lines, "\n")
end
-- Group Finder pages (this client's BrowsingTab / WhoListingTab, the player's /fstack names): the window opened by
-- the Dungeons micro button. Open is told by the window the tab sits in (its parents up to UIParent), so a window
-- open on another page isn't clicked shut by the micro button.
local function TabWindowShown(tab)
	local f = _G[tab]
	local guard = 0
	while type(f) == "table" and f.GetParent and guard < 20 do
		local p = f:GetParent()
		if p == nil or p == UIParent then break end
		f, guard = p, guard + 1
	end
	return type(f) == "table" and f ~= _G[tab] and f.IsVisible and f:IsVisible() and true or false
end
local function GroupFinderTabMacro(e)
	local lines = {}
	local open = Shown("PVEFrame") or TabWindowShown(e.tab)
	if not open then lines[1] = "/click LFDMicroButton" end
	local how = TabKind(_G[e.tab])
	if not ns.Secure.quiet then ns:Trace("group finder: " .. e.tab .. " is " .. how .. (open and ", window open" or ", window closed: the micro button first")) end
	lines[#lines + 1] = TabRunLine(e.tab)
	return table.concat(lines, "\n")
end
local function LegacyTabFallback() ns:Print("Open the Legacy window from its button (a click from Terminal's own code would taint it).") end
local Never = ns.Never

-- A tab by its path: a global ("LegacyChallengeTab") or a key under one ("CommunitiesFrame.RosterTab").
local function TabFrame(path)
	local f = _G
	for part in path:gmatch("[^%.]+") do
		if type(f) ~= "table" then return nil end
		f = f[part]
	end
	return type(f) == "table" and f or nil
end
-- afterwards: point at the tab
local function TabAfter(e)
	H:Find(function()
		local t = TabFrame(e.tab)
		if not t and e.side then t = ns.CharSide and ns.CharSide.Tab(e.side) end
		return t and t.IsVisible and t:IsVisible() and t or nil
	end)
end
local function TabFallback(e) ns:Print("Switch to " .. tostring(e and e.name) .. " in its window (a click from Terminal's own code would taint it).") end

-- The guild & communities window's tabs (CommunitiesFrame.RosterTab, .GuildInfoTab): keys, not globals, so /click
-- can't name them; a game-run /run clicks them (Blizzard_Communities loads with the window, so the window first).
local function CommunitiesTabMacro(e)
	local lines = {}
	if not Shown("CommunitiesFrame") then
		lines[1] = _G.GuildMicroButton and "/click GuildMicroButton" or "/run ToggleGuildFrame()"
	end
	local key = e.tab:match("%.(.+)$")
	if not ns.Secure.quiet then ns:Trace("communities: " .. key .. (lines[1] and ", window closed: opened first" or ", window open")) end
	lines[#lines + 1] = "/run local t=CommunitiesFrame and CommunitiesFrame." .. key .. " if t then t:Click() end"
	return table.concat(lines, "\n")
end
local function CommunitiesTabOpen(e)
	local cf = _G.CommunitiesFrame
	if not (Shown("CommunitiesFrame") and cf.GetDisplayMode) then return false end
	local modes = _G.COMMUNITIES_FRAME_DISPLAY_MODES
	local want = type(modes) == "table" and modes[e.mode]
	if want == nil then return false end
	local ok, mode = pcall(cf.GetDisplayMode, cf)
	return ok and mode == want or false
end

-- the character window's side tabs (Providers/EquipmentSets.lua has the route)
local function SideTabMacro(e) return ns.CharSide and ns.CharSide.Macro(e.side) or nil end
local function SideTabOpen(e) return ns.CharSide and ns.CharSide.Shown(e.side) or false end

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
	{ "Legacy", "legacy system challenges", LegacyTabFallback, "LegacyMicroButton",
		{ buttons = { "LegacyMicroButton" } }, PanelOpen, "LegacySystemFrame", needs = "LegacyMicroButton", nameFrom = "LegacyMicroButton" },
	-- its tabs (LegacyChallengeTab, LegacyTreeTab): the game opens the window if it's closed, then the tab
	{ "Legacy Challenges", "legacy challenges challenge", LegacyTabFallback, "LegacyMicroButton",
		{ macro = LegacyTabMacro, opensWindow = true }, Never, needs = "LegacyMicroButton", tab = "LegacyChallengeTab" },
	{ "Legacy Tree", "legacy tree talents", LegacyTabFallback, "LegacyMicroButton",
		{ macro = LegacyTabMacro, opensWindow = true }, Never, needs = "LegacyMicroButton", tab = "LegacyTreeTab" },
	{ "Guild Roster", "guild roster members communities", TabFallback, "GuildMicroButton",
		{ macro = CommunitiesTabMacro }, CommunitiesTabOpen, tab = "CommunitiesFrame.RosterTab", mode = "ROSTER" },
	{ "Guild Info", "guild info information news message", TabFallback, "GuildMicroButton",
		{ macro = CommunitiesTabMacro }, CommunitiesTabOpen, tab = "CommunitiesFrame.GuildInfoTab", mode = "GUILD_INFO" },
	{ "Character Stats", "character stats attributes", TabFallback, "CharacterMicroButton",
		{ macro = SideTabMacro }, SideTabOpen, tab = "PaperDollSideBarTab1", side = 1 },
	{ "Equipment Manager", "equipment manager sets outfits", TabFallback, "CharacterMicroButton",
		{ macro = SideTabMacro }, SideTabOpen, tab = "PaperDollSideBarTab2", side = 2 },
	{ "Titles", "titles title", TabFallback, "CharacterMicroButton",
		{ macro = SideTabMacro }, SideTabOpen, tab = "PaperDollSideBarTab3", side = 3 },
	-- the Group Finder's pages (BrowsingTab, WhoListingTab): the game opens the window if it's closed, then the tab
	{ "Group Browser", "group browser browse groups lfg premade dungeon finder", TabFallback, "LFDMicroButton",
		{ macro = GroupFinderTabMacro, opensWindow = true }, Never, needs = "LFDMicroButton", tab = "BrowsingTab" },
	{ "Who Listing", "who listing list lfg looking for group dungeon finder", TabFallback, "LFDMicroButton",
		{ macro = GroupFinderTabMacro, opensWindow = true }, Never, needs = "LFDMicroButton", tab = "WhoListingTab" },
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
	["Character Stats"] = "PAPERDOLL_SIDEBAR_STATS", ["Equipment Manager"] = "EQUIPMENT_MANAGER", ["Titles"] = "PAPERDOLL_SIDEBAR_TITLES",
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

local function PanelActivate(e)
	e.open(e)
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
				icon = "Interface\\Icons\\INV_Misc_Book_09", -- (not the map places' icon)
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
				if p.tab then e.tab, e.mode, e.side, e.after = p.tab, p.mode, p.side, TabAfter end
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

-- the Macros window: Macros.lua's rows open it too
ns.MACRO_WINDOW, ns.MacroWindowOpen = MACRO_WINDOW, MacroWindowOpen
-- the currency tab (Currency.lua's rows open it too)
ns.TOKEN_SECURE, ns.TokenOpen = TOKEN_SECURE, TokenOpen
