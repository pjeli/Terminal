local ns = select(2, ...)
local L = ns.L
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

-- the Currency tab of the character window: the currency key's binding (Forever's TOGGLECURRENCY runs the window's own
-- ToggleTokenFrame), its tab's /click for a mouse click where the tab is a button. (Review, 0.48.6: with only the tab's
-- route, on Forever's plain-frame tabs nothing was pressed and Enter ran ToggleCharacter from Terminal's code: taint.)
local function TokenClick() return ns.Secure.CharTabMacro("TokenFrame", { _G.CURRENCY or "Currency", "Currency" }) end
local TOKEN_SECURE = { binding = "TOGGLECURRENCY", buttons = { "CharacterMicroButton" }, click = TokenClick }
local function TokenOpen() return Shown("TokenFrame") end

-- game-run openers for panels without a binding command (a /run line on the secure macro button)
-- (the settings window as it was last: the game's own call, answered by the window's own code: Secure.SettingsMacro)
local function OptionsMacro() return ns.Secure.SettingsMacro() end
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
-- The line that clicks a tab (a global name): /click, which the game runs as your own click (clean). A tab that is a
-- plain Frame (as the character tabs are here) isn't a button: /click does nothing to it, and Terminal points at it
-- for you to click. Until 0.46.2 a /run line clicked it or ran its mouse scripts; but a /run line runs tainted
-- (0.46.1), and the window it switched then held what it wrote.
local function TabClickLine(tab) return "/click " .. tab end
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
	lines[#lines + 1] = TabClickLine(e.tab)
	return table.concat(lines, "\n")
end
local function LegacyTabFallback() ns:Print(L["Open the Legacy window from its button (a click from Terminal's own code would taint it)."]) end
local Never = ns.Never


-- A tab by its path: a global ("PaperDollSideBarTab1") or a key under one ("CommunitiesFrame.RosterTab").
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
local function TabFallback(e) ns:Print(L["Switch to %s in its window (a click from Terminal's own code would taint it)."]:format(tostring(e and e.name))) end

-- 0.48.4 (the player: "Legacy Tree" and "Legacy Challenges" opened on Rewards): the window's tabs are plain Frames
-- (Blizzard_LegacySystemTemplates.xml: LargeSideTabButtonTemplate, a Frame; its page is picked on mouse-up), so the
-- /click on them did nothing and the window showed the page it was last on (Rewards, the first). Forever's own code
-- does open Challenges: the achievement button's ToggleAchievementFrame is overridden to ToggleLegacyChallenges
-- (Blizzard_AchievementUI/Camelot), which shows the window on that page. So Challenges is opened by the game's click on
-- AchievementMicroButton (only when not already showing: it toggles), checked afterwards: a press that didn't show it
-- (the button refused: no achievement yet, say) is remembered (db.legacyRoute = false) and the window's button is used,
-- with Terminal pointing at the tab. The Tree and Rewards have no such route (nothing but a real mouse release on their
-- tab selects them: LegacySystemFrameTabMixin's custom OnMouseUp fires "Legacy.SelectPage"; no binding, no button, no C
-- call; running the window's code from Terminal or a /run line would taint it, the Tree's talent panel with it): the
-- window opens (on the page you left it on; Rewards the first time a session, its OnLoad picks page 1) and Terminal
-- points at the tab, saying once why it can't switch it.
-- 0.48.7: the tabs are keys of LegacySystemFrame (parentKey, no name: Blizzard_LegacySystem.xml), not globals, so
-- "LegacyTreeTab" alone found nothing and the Tree tab was never pointed at.
local LEGACY_PAGES = { -- (the window's own page numbers, by the tab's path)
	["LegacySystemFrame.LegacyRewardTrackTab"] = 1, ["LegacySystemFrame.LegacyChallengeTab"] = 2, ["LegacySystemFrame.LegacyTreeTab"] = 3 }
local function LegacyOn(page)
	local f = _G.LegacySystemFrame
	return type(f) == "table" and f.IsShown and f:IsShown() and f.currentPage == page or false
end
local function ChallengesRoute()
	local db = ns.db
	return _G.AchievementMicroButton and not (db and db.legacyRoute == false)
end
-- shown on that page; or shown on another with nothing to press (only Challenges has a route that switches the page)
local function LegacyPageOpen(e)
	local page = LEGACY_PAGES[e.tab]
	if LegacyOn(page) then return true end
	return Shown("LegacySystemFrame") and not (page == 2 and ChallengesRoute()) or false
end
local function LegacyPageMacro(e)
	if LEGACY_PAGES[e.tab] == 2 and ChallengesRoute() then
		if not ns.Secure.quiet then ns:Trace("legacy: Challenges by the achievement button (the game's own route to it)") end
		return "/click AchievementMicroButton"
	end
	if Shown("LegacySystemFrame") then return nil end -- (open on another page: nothing to press; Terminal points at the tab)
	if not ns.Secure.quiet then ns:Trace("legacy: " .. e.tab .. " is " .. TabKind(TabFrame(e.tab)) .. ": the window opened, the tab pointed at") end
	return "/click LegacyMicroButton"
end
local legacyHinted = {}
local LEGACY_CHECK = 0.6 -- (s after the press: the window is showing what it will)
local function LegacyAfter(e)
	local page = LEGACY_PAGES[e.tab]
	local viaAchievements = page == 2 and ChallengesRoute()
	C_Timer.After(LEGACY_CHECK, function()
		if LegacyOn(page) then
			if viaAchievements and ns.db and ns.db.legacyRoute ~= true then
				ns.db.legacyRoute = true
				ns:Trace("legacy: the achievement button opened Challenges")
			end
			return
		end
		if viaAchievements and ns.db then
			ns.db.legacyRoute = false
			ns:Trace("legacy: the achievement button didn't open Challenges: the window's button from now on")
		end
		-- (not on that page: point at its tab, and say once why Terminal can't switch it)
		TabAfter(e)
		if not legacyHinted[e.tab] then
			legacyHinted[e.tab] = true
			ns:Print(L["%s: click its tab (pointed at). The game gives Terminal no clean way to switch the Legacy window's pages."]:format(tostring(e.name)))
		end
	end)
end

-- The guild & communities window's tabs (CommunitiesFrame.RosterTab, .GuildInfoTab): keys, not globals. The press
-- opens the window (only while it's closed) and asks /click for the tab by its path, which the game looks up itself
-- (GetClickFrame: whether it takes a path on this client isn't known; when it doesn't, nothing happens and Terminal
-- points at the tab). Until 0.46.2 a /run line clicked it: a /run line runs tainted (0.46.1). No guild button: the
-- guild key's binding instead (the spec's), no tab.
local function CommunitiesTabMacro(e)
	local lines = {}
	if not Shown("CommunitiesFrame") then
		if not _G.GuildMicroButton then return nil end
		lines[1] = "/click GuildMicroButton"
	end
	local key = e.tab:match("%.(.+)$")
	if not ns.Secure.quiet then ns:Trace("communities: " .. key .. (lines[1] and ", window closed: opened first" or ", window open")) end
	lines[#lines + 1] = "/click CommunitiesFrame." .. key
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
		-- (no route left, in combat say: the client's own C opener if it has one, else said; never ToggleCharacter: taint)
		if C_CurrencyInfo and C_CurrencyInfo.OpenCurrencyPanel then C_CurrencyInfo.OpenCurrencyPanel()
		else ns:Print(L["Open the Currency tab from your character window (opening it from Terminal's own code would taint it)."]) end
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
	-- (Forever has no calendar key: the minimap's calendar button, clicked by the game; never ToggleCalendar from here)
	{ "Calendar", "calendar events", function()
		ns:Print(L["Open the calendar from the minimap's calendar button (opening it from Terminal's own code would taint it)."])
	end, nil, { binding = "TOGGLECALENDAR", buttons = { "GameTimeFrame" } }, PanelOpen, "CalendarFrame" },
	{ "Social / Friends", "friends social who ignore", function() Call("ToggleFriendsFrame") end, nil, { binding = "TOGGLESOCIAL" }, PanelOpen, "FriendsFrame" },
	{ "Backpack & Bags", "bags backpack inventory", function() Call("ToggleAllBags") end, nil, { binding = "OPENALLBAGS" }, BagsOpen },
	{ "Game Menu", "game menu escape logout exit", function() Call("ToggleGameMenu") end, "MainMenuMicroButton",
		{ binding = "TOGGLEGAMEMENU", buttons = { "MainMenuMicroButton" } }, PanelOpen, "GameMenuFrame" },
	{ "Options", "options settings interface video audio", function()
		if C_SettingsUtil and C_SettingsUtil.OpenSettingsPanel then pcall(C_SettingsUtil.OpenSettingsPanel) end
	end, nil, { macro = OptionsMacro }, PanelOpen, "SettingsPanel" },
	{ "AddOn List", "addons manager", function() if AddonList then ShowUIPanel(AddonList) end end, nil, { macro = ADDONLIST_MACRO }, PanelOpen, "AddonList" },
	{ "Macros", "macros", function() ns.LoadBlizz("Blizzard_MacroUI"); if MacroFrame then ShowUIPanel(MacroFrame) end end, nil, MACRO_WINDOW, MacroWindowOpen },
	{ "Edit Mode", "edit mode layout hud", function() ns.RunSlash("/editmode") end, nil, { macro = EDITMODE_MACRO }, PanelOpen, "EditModeManagerFrame" },
	-- WoW Forever's Legacy window (Blizzard_LegacySystem: LegacySystemFrame, its challenges and more), opened by
	-- the game clicking its micro button (ClassicUIForever moves that button off the bar, but it still clicks);
	-- listed only where the client has it
	{ "Legacy", "legacy system challenges", LegacyTabFallback, "LegacyMicroButton",
		{ buttons = { "LegacyMicroButton" } }, PanelOpen, "LegacySystemFrame", needs = "LegacyMicroButton", nameFrom = "LegacyMicroButton" },
	-- its pages: Challenges by the game's own route, Rewards and the Tree opened and pointed at (LegacyPageMacro)
	{ "Legacy Rewards", "legacy rewards reward track renown", LegacyTabFallback, "LegacyMicroButton",
		{ macro = LegacyPageMacro, opensWindow = true }, LegacyPageOpen, needs = "LegacyMicroButton",
		tab = "LegacySystemFrame.LegacyRewardTrackTab", legacy = true },
	{ "Legacy Challenges", "legacy challenges challenge achievements", LegacyTabFallback, "LegacyMicroButton",
		{ macro = LegacyPageMacro, opensWindow = true }, LegacyPageOpen, needs = "LegacyMicroButton",
		tab = "LegacySystemFrame.LegacyChallengeTab", legacy = true },
	{ "Legacy Tree", "legacy tree talents", LegacyTabFallback, "LegacyMicroButton",
		{ macro = LegacyPageMacro, opensWindow = true }, LegacyPageOpen, needs = "LegacyMicroButton",
		tab = "LegacySystemFrame.LegacyTreeTab", legacy = true },
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

-- The names as Terminal says them when the game has no words of its own (the English name stays the key and in the
-- searchable text)
local PANEL_SAID = {
	["Character Info"] = L["Character Info"], ["Reputation"] = L["Reputation"], ["Currency"] = L["Currency"],
	["Spellbook"] = L["Spellbook"], ["Talents"] = L["Talents"], ["Achievements"] = L["Achievements"],
	["Quest Log"] = L["Quest Log"], ["World Map"] = L["World Map"], ["Collections"] = L["Collections"],
	["Group Finder"] = L["Group Finder"], ["Guild & Communities"] = L["Guild & Communities"],
	["Adventure Guide"] = L["Adventure Guide"], ["Professions"] = L["Professions"], ["Calendar"] = L["Calendar"],
	["Social / Friends"] = L["Social / Friends"], ["Backpack & Bags"] = L["Backpack & Bags"], ["Game Menu"] = L["Game Menu"],
	["Options"] = L["Options"], ["AddOn List"] = L["AddOn List"], ["Macros"] = L["Macros"], ["Edit Mode"] = L["Edit Mode"],
	["Legacy"] = L["Legacy"], ["Legacy Challenges"] = L["Legacy Challenges"], ["Legacy Tree"] = L["Legacy Tree"],
	["Guild Roster"] = L["Guild Roster"], ["Guild Info"] = L["Guild Info"], ["Character Stats"] = L["Character Stats"],
	["Equipment Manager"] = L["Equipment Manager"], ["Titles"] = L["Titles"], ["Group Browser"] = L["Group Browser"],
	["Who Listing"] = L["Who Listing"], ["Shop"] = L["Shop"],
}

--- The panel's name in the game's own words: its global string, else its micro button's tooltip
--- ("Legacy |cffffd200(L)|r": the key part dropped), else Terminal's (PANEL_SAID), else the English name.
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
	return name or PANEL_SAID[english] or english
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
	label = L["Panel"],
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
				if p.tab then e.tab, e.mode, e.side, e.after = p.tab, p.mode, p.side, p.legacy and LegacyAfter or TabAfter end
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
