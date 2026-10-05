local ns = select(2, ...)
local H = ns.Highlight

local function Call(name, ...)
	local f = _G[name]
	if type(f) == "function" then return f(...) end
end

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
----------------------------------------------------------------------

local PANELS = {
	{ "Character Info", "character equipment gear paperdoll", function() ToggleCharacter("PaperDollFrame") end, "CharacterMicroButton", "PaperDollFrame" },
	{ "Reputation", "reputation factions renown", function() ToggleCharacter("ReputationFrame") end, "CharacterMicroButton", "ReputationFrame" },
	{ "Currency", "currency tokens", function()
		-- the client's own opener first: it doesn't run our code through the Character frame
		if C_CurrencyInfo and C_CurrencyInfo.OpenCurrencyPanel then C_CurrencyInfo.OpenCurrencyPanel() else ToggleCharacter("TokenFrame") end
	end, "CharacterMicroButton" },
	{ "Spellbook", "spellbook abilities spells", function()
		ns.LoadBlizz("Blizzard_PlayerSpells")
		if PlayerSpellsUtil and PlayerSpellsUtil.ToggleSpellBookFrame then PlayerSpellsUtil.ToggleSpellBookFrame() else Call("ToggleSpellBook", "spell") end
	end, "PlayerSpellsMicroButton" },
	{ "Talents", "talents specialization spec hero", function()
		ns.LoadBlizz("Blizzard_PlayerSpells")
		if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame then PlayerSpellsUtil.ToggleClassTalentFrame() else Call("ToggleTalentFrame") end
	end, "PlayerSpellsMicroButton" },
	{ "Achievements", "achievements feats", function() ns.LoadBlizz("Blizzard_AchievementUI"); Call("ToggleAchievementFrame") end, "AchievementMicroButton" },
	{ "Quest Log", "quest log journal", function() Call("ToggleQuestLog") end, "QuestLogMicroButton" },
	{ "World Map", "map world zone", function() Call("ToggleWorldMap") end },
	{ "Collections", "collections mounts pets toys heirlooms transmog appearances", function() Call("ToggleCollectionsJournal") end, "CollectionsMicroButton" },
	{ "Group Finder", "group finder dungeon raid lfg pvp", function() Call("PVEFrame_ToggleFrame") end, "LFDMicroButton" },
	{ "Guild & Communities", "guild communities", function() Call("ToggleGuildFrame") end, "GuildMicroButton" },
	{ "Adventure Guide", "adventure guide encounter journal dungeon journal", function() Call("ToggleEncounterJournal") end, "EJMicroButton" },
	{ "Professions", "professions crafting", function() Call("ToggleProfessionsBook") end, "ProfessionMicroButton" },
	{ "Calendar", "calendar events", function() Call("ToggleCalendar") end },
	{ "Social / Friends", "friends social who ignore", function() Call("ToggleFriendsFrame") end },
	{ "Backpack & Bags", "bags backpack inventory", function() Call("ToggleAllBags") end },
	{ "Game Menu", "game menu escape logout exit", function() Call("ToggleGameMenu") end, "MainMenuMicroButton" },
	{ "Options", "options settings interface video audio", function()
		if Settings and Settings.OpenToCategory then Settings.OpenToCategory() else Call("ShowUIPanel", _G.SettingsPanel) end
	end },
	{ "AddOn List", "addons manager", function() if AddonList then ShowUIPanel(AddonList) end end },
	{ "Macros", "macros", function() ns.LoadBlizz("Blizzard_MacroUI"); if MacroFrame then ShowUIPanel(MacroFrame) end end },
	{ "Edit Mode", "edit mode layout hud", function() ns.RunSlash("/editmode") end },
	{ "Shop", "shop store", function() Call("ToggleStoreUI") end, "StoreMicroButton" },
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

local function PanelName(english) return ns.GameText(PANEL_GLOBALS[english], english) end

-- the game's keybinding commands for Character window tabs
local CHAR_BINDINGS = { PaperDollFrame = "TOGGLECHARACTER0", ReputationFrame = "TOGGLECHARACTER2" }
local CHAR_CLICKS = { PaperDollFrame = ns.Secure.PAPERDOLL_CLICK, ReputationFrame = ns.Secure.REP_CLICK }
local function PageOpen(e) local f = _G[e.page]; return f and f:IsVisible() and true or false end
local function PageAfter(e) MicroGlow(e.micro) end

-- shared by every currency, mount and achievement entry (not one copy per entry)
local function OpenCurrency(e)
	if C_CurrencyInfo.OpenCurrencyPanel then C_CurrencyInfo.OpenCurrencyPanel() else ToggleCharacter("TokenFrame") end
	H:Find(function()
		local root = _G.TokenFrame or CharacterFrame
		return root and root:IsVisible() and ns.FindByText(root, e.name) or nil
	end, 8)
end

local function SummonMount(e) C_MountJournal.SummonByID(e.key) end

local function ShowMount(e)
	ns.LoadBlizz("Blizzard_Collections")
	if CollectionsJournal_SetTab and CollectionsJournal then
		ShowUIPanel(CollectionsJournal)
		CollectionsJournal_SetTab(CollectionsJournal, 1)
	end
	H:Find(function()
		local root = _G.MountJournal
		return root and root:IsVisible() and ns.FindByText(root, e.name) or nil
	end, 8)
end

local function OpenAchievement(e)
	ns.LoadBlizz("Blizzard_AchievementUI")
	if AchievementFrame_SelectAchievement then
		ShowUIPanel(AchievementFrame)
		pcall(AchievementFrame_SelectAchievement, e.key)
	else
		ToggleAchievementFrame()
	end
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
				name = PanelName(p[1]),
				icon = "Interface\\Icons\\INV_Misc_Map_01",
				text = p[2] .. " " .. p[1],
				open = p[3], micro = p[4],
				activate = PanelActivate,
			}
			if p[1] == "Talents" and ns.Talents then
				-- the talent window: secure click on the talent button, like a talent search
				e.secure = ns.Talents.SECURE
				e.isOpen = ns.Talents.IsOpen
				e.after = function() MicroGlow(ns.Secure.First(ns.Talents.BUTTONS)) end
			end
			if p[1] == "Macros" then
				-- the macro window, opened by the game itself (a macro line, so nothing runs as Terminal)
				e.secure = MACRO_WINDOW
				e.isOpen = MacroWindowOpen
			end
			if p[5] then
				-- a tab of the Character window: the game's own key opens it on that page (or switches
				-- page when it's open on another); Terminal's code never switches it (taint)
				e.secure = { binding = CHAR_BINDINGS[p[5]], buttons = { p[4] }, click = CHAR_CLICKS[p[5]] }
				e.page, e.micro = p[5], p[4]
				e.isOpen = PageOpen
				e.after = PageAfter
			end
			out[#out + 1] = e
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
	local name, _, body = GetMacroInfo(e.key)
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
					key = index,
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
					detail = tostring(info.quantity or 0) .. ((info.maxQuantity and info.maxQuantity > 0) and (" / " .. info.maxQuantity) or ""),
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
		for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
			local name, spellID, icon, _, isUsable, _, isFavorite, _, _, hideOnChar, isCollected =
				C_MountJournal.GetMountInfoByID(mountID)
			if name and isCollected and not hideOnChar then
				out[#out + 1] = {
					key = mountID,
					name = name,
					icon = icon,
					detail = isFavorite and "Favorite" or "",
					link = spellID and C_Spell.GetSpellLink(spellID) or nil,
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
----------------------------------------------------------------------

ns:RegisterProvider("achievements", {
	label = "Achieve",
	color = "ffff8040",
	aliases = { "achievement", "ach", "achieve" },
	lazy = true,
	events = { "ACHIEVEMENT_EARNED" }, -- earned this session: listed without a /reload
	idleDrop = 600,
	collect = function()
		local out = {}
		for _, cat in ipairs(GetCategoryList()) do
			local num = GetCategoryNumAchievements(cat, true)
			for i = 1, num do
				local id, name, points, completed, _, _, _, description, _, icon = GetAchievementInfo(cat, i)
				if id and name and completed then -- only achievements you've earned
					out[#out + 1] = {
						key = id,
						name = name,
						icon = icon,
						text = description,
						detail = "Done  " .. (points and points > 0 and (points .. " pts") or ""),
						tip = description,
						link = GetAchievementLink(id),
						activate = OpenAchievement,
					}
				end
			end
		end
		return out
	end,
})



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
	aliases = { "cvar", "cvars", "console", "setting", "settings" },
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
