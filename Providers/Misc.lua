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

-- the game's keybinding commands for Character window tabs
local CHAR_BINDINGS = { PaperDollFrame = "TOGGLECHARACTER0", ReputationFrame = "TOGGLECHARACTER2" }

ns:RegisterProvider("panels", {
	label = "Panel",
	color = "ff7fe0ff",
	aliases = { "panel", "ui", "window", "frame" },
	collect = function()
		local out = {}
		for _, p in ipairs(PANELS) do
			local e = {
				key = p[1],
				name = p[1],
				icon = "Interface\\Icons\\INV_Misc_Map_01",
				text = p[2],
				activate = function()
					p[3]()
					MicroGlow(p[4])
				end,
			}
			if p[1] == "Talents" and ns.Talents then
				-- the talent window: secure click on the talent button, like a talent search
				e.secure = ns.Talents.SECURE
				e.isOpen = ns.Talents.IsOpen
				e.after = function() MicroGlow(ns.Secure.First(ns.Talents.BUTTONS)) end
			end
			if p[5] then
				-- a tab of the Character window: open it by a secure click, then switch tab
				e.secure = { binding = CHAR_BINDINGS[p[5]], buttons = { p[4] } }
				e.isOpen = function() return CharacterFrame and CharacterFrame:IsShown() end
				e.after = function()
					local sub = _G[p[5]]
					if sub and not sub:IsShown() then pcall(ToggleCharacter, p[5]) end
					MicroGlow(p[4])
				end
			end
			out[#out + 1] = e
		end
		return out
	end,
})

----------------------------------------------------------------------
-- Macros
----------------------------------------------------------------------

ns:RegisterProvider("macros", {
	label = "Macro",
	color = "ffffa040",
	aliases = { "macro" },
	events = { "UPDATE_MACROS" },
	collect = function()
		local out = {}
		local numAccount, numChar = GetNumMacros()
		local function add(index)
			local name, icon, body = GetMacroInfo(index)
			if name and name ~= "" then
				out[#out + 1] = {
					key = index,
					name = name,
					icon = icon,
					text = body,
					detail = index > 120 and "Character" or "General",
					tip = body,
					activate = function(e)
						ns.LoadBlizz("Blizzard_MacroUI")
						if MacroFrame then
							ShowUIPanel(MacroFrame)
							-- the frame needs a moment to build its buttons
							C_Timer.After(0.1, function()
								if MacroFrame.SelectMacro then pcall(MacroFrame.SelectMacro, MacroFrame, e.key) end
								H:Find(function()
									local root = MacroFrame
									return root:IsVisible() and ns.FindByText(root, e.name) or nil
								end, 8)
							end)
						end
					end,
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
					activate = function(e)
						if C_CurrencyInfo.OpenCurrencyPanel then C_CurrencyInfo.OpenCurrencyPanel() else ToggleCharacter("TokenFrame") end
						H:Find(function()
							local root = _G.TokenFrame or CharacterFrame
							return root and root:IsVisible() and ns.FindByText(root, e.name) or nil
						end, 8)
					end,
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
					activate = function() C_MountJournal.SummonByID(mountID) end,
					secondary = function(e)
						ns.LoadBlizz("Blizzard_Collections")
						if CollectionsJournal_SetTab and CollectionsJournal then
							ShowUIPanel(CollectionsJournal)
							CollectionsJournal_SetTab(CollectionsJournal, 1)
						end
						H:Find(function()
							local root = _G.MountJournal
							return root and root:IsVisible() and ns.FindByText(root, e.name) or nil
						end, 8)
					end,
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
						detail = (completed and "Done  " or "") .. (points and points > 0 and (points .. " pts") or ""),
						tip = description,
						link = GetAchievementLink(id),
						activate = function(e)
							ns.LoadBlizz("Blizzard_AchievementUI")
							if AchievementFrame_SelectAchievement then
								ShowUIPanel(AchievementFrame)
								pcall(AchievementFrame_SelectAchievement, e.key)
							else
								ToggleAchievementFrame()
							end
						end,
					}
				end
			end
		end
		return out
	end,
})


