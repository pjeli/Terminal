local ns = select(2, ...)
local H = ns.Highlight

-- Talents: every talent in your tree, taken or not, searchable by name or tree, opened in
-- the talent window with its node highlighted. Forever's talents are a C_Traits tree split
-- into the classic three tabs (the same way ClassicUIForever reads it).

local TL = {}
ns.Talents = TL

-- talent windows we know by name, first visible wins (any other visible "...Talent..."
-- window is tried after these)
local ROOTS = { "ClassicUIForeverTalents", "PlayerSpellsFrame", "ClassTalentFrame", "PlayerTalentFrame", "TalentFrame" }
-- Forever shows TalentMicroButton; PlayerSpellsMicroButton is the retail one
TL.BUTTONS = { "TalentMicroButton", "PlayerSpellsMicroButton" }
-- opened through the game's own Talents keybinding command; the buttons are the fallback
TL.SECURE = { binding = "TOGGLETALENTS", buttons = TL.BUTTONS }

local TAKEN = "|cff40ff40Taken|r"
local NOT_TAKEN = "|cff8a8a8aNot taken|r"

local function ConfigID()
	local SI = C_SpecializationInfo
	local spec = SI and SI.GetActiveSpecGroup and SI.GetActiveSpecGroup()
	local id = spec and SI.GetCombatConfigIDForSpecGroup and SI.GetCombatConfigIDForSpecGroup(spec)
	if not id and C_ClassTalents and C_ClassTalents.GetActiveConfigID then id = C_ClassTalents.GetActiveConfigID() end
	return id
end

local function Usable(f)
	return f and not (f.IsForbidden and f:IsForbidden()) and f.IsVisible and f:IsVisible()
end

function TL.Window()
	for _, name in ipairs(ROOTS) do
		local f = _G[name]
		if Usable(f) then return f, name end
	end
	-- some other talent window (this client's own, or another addon's)
	for _, f in ipairs({ UIParent:GetChildren() }) do
		local ok, name = pcall(function() return f:GetName() end)
		if ok and type(name) == "string" and name:find("Talent") and not name:find("^Terminal") and Usable(f) then
			return f, name
		end
	end
end

function TL.IsOpen() return TL.Window() ~= nil end

local function IsNode(f, nodeID)
	if f.nodeID == nodeID then return true end
	if type(f.talent) == "table" and f.talent.nodeID == nodeID then return true end -- ClassicUIForever
	if f.GetNodeID then -- Blizzard talent buttons
		local ok, id = pcall(f.GetNodeID, f)
		if ok and id == nodeID then return true end
	end
	return false
end

local function AnyNode(f)
	if type(f.nodeID) == "number" then return true end
	if type(f.talent) == "table" and f.talent.nodeID then return true end
	if f.GetNodeID then
		local ok, id = pcall(f.GetNodeID, f)
		return ok and type(id) == "number"
	end
	return false
end

local Plain = ns.Plain -- (Locale.lua)

-- a tab label for the tree: "Fury", or "Fury (5)" with points spent
local function TabText(f, tabName)
	local texts = {}
	if f.GetText then
		local ok, t = pcall(f.GetText, f)
		if ok and type(t) == "string" then texts[#texts + 1] = t end
	end
	for _, r in ipairs({ f:GetRegions() }) do
		if r.GetObjectType and r:GetObjectType() == "FontString" then texts[#texts + 1] = r:GetText() end
	end
	for _, t in ipairs(texts) do
		t = Plain(t)
		if t == tabName then return true end
		local nxt = t:sub(#tabName + 1, #tabName + 1)
		if t:sub(1, #tabName) == tabName and (nxt == " " or nxt == "(") then return true end
	end
	return false
end

local function FindTab(root, rootName, tabName, tabIndex)
	if tabName and tabName ~= "" then
		local tab = ns.FindFrame(root, function(f) return f.Click and TabText(f, tabName) end, 10)
		if tab then return tab end
	end
	-- unlabelled tabs: the window's numbered tab buttons, in tree order
	if tabIndex and rootName then
		local t = _G[rootName .. "Tab" .. tabIndex]
		if Usable(t) and t.Click then return t end
	end
end

-- Blizzard's own talent windows: nothing in them is clicked from Terminal's code (a click runs tainted and
-- the window's state stays so). ClassicUIForever's and classic clients' windows are turned as a player would.
local BLIZZARD_ROOTS = { PlayerSpellsFrame = true, ClassTalentFrame = true }

--- Highlight the talent's node. Windows that show one tree at a time only have buttons for
--- the tree on screen, so if the node isn't there, the talent's tree tab is clicked first.
function TL.Highlight(nodeID, tabName, tabIndex)
	local switched = false
	H:Find(function()
		local root, rootName = TL.Window()
		if not root then return nil end
		local node = ns.FindFrame(root, function(f) return IsNode(f, nodeID) end, 14)
		if node then return node end
		if not switched and not BLIZZARD_ROOTS[rootName] then
			local tab = FindTab(root, rootName, tabName, tabIndex)
			if tab then
				switched = true
				pcall(tab.Click, tab)
			end
		elseif not switched then
			switched = true
			ns:Trace("talents: " .. tostring(rootName) .. " shows another tree; its tabs aren't clicked from here (taint)")
		end
		return nil
	end, 60) -- a freshly opened window can take a moment to build its buttons
end

-- Direct opener: only used when neither the keybinding nor a micro button is available.
local function OpenFallback(e)
	ns:Trace("DIRECT talent window open (addon code, may be blocked)")
	ns.LoadBlizz("Blizzard_PlayerSpells")
	if PlayerSpellsUtil and PlayerSpellsUtil.OpenToClassTalentsTab then
		pcall(PlayerSpellsUtil.OpenToClassTalentsTab)
	elseif PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame then
		pcall(PlayerSpellsUtil.ToggleClassTalentFrame)
	elseif ToggleTalentFrame then
		pcall(ToggleTalentFrame)
	end
	TL.Highlight(e.nodeID, e.tab, e.tabIndex)
end

--- Reads the active talent tree. Returns configID, treeID, { groupID -> tab name }.
local function ReadTree()
	if not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes) then return end
	local configID = ConfigID()
	local config = configID and C_Traits.GetConfigInfo(configID)
	local treeID = config and config.treeIDs and config.treeIDs[1]
	if not treeID then return end
	local tabs, order = {}, {}
	local ok, groups = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
	if ok and type(groups) == "table" then
		table.sort(groups, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
		for i, g in ipairs(groups) do
			tabs[g.groupID] = g.displayName
			order[g.groupID] = i
		end
	end
	return configID, treeID, tabs, order
end

local function HighlightNode(e) TL.Highlight(e.nodeID, e.tab, e.tabIndex) end

local function TalentLink(e) return e.spellID and C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(e.spellID) or nil end
local function LinkTalent(e) ns.LinkInChat(TalentLink(e)) end

ns:RegisterProvider("talents", {
	label = "Talent",
	color = "ffa3e05f",
	aliases = { "talent", "talents", "tree" },
	events = { "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "PLAYER_TALENT_UPDATE",
		"ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "CHARACTER_POINTS_CHANGED" },
	guard = 1,
	collect = function()
		local out = {}
		local configID, treeID, tabs, order = ReadTree()
		if not treeID then return out end
		for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
			local node = C_Traits.GetNodeInfo(configID, nodeID)
			if node and node.isVisible ~= false then
				local rank = node.ranksPurchased or 0
				local entryID = node.activeEntry and node.activeEntry.entryID or (node.entryIDs and node.entryIDs[1])
				local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
				local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
				local spellID = def and (def.overriddenSpellID or def.spellID)
				local name = def and def.overrideName
				if (not name or name == "") and spellID and C_Spell and C_Spell.GetSpellName then
					name = C_Spell.GetSpellName(spellID)
				end
				if type(name) == "string" and name ~= "" then
					local tab, tabIndex
					for _, gid in ipairs(node.groupIDs or {}) do
						if tabs[gid] then tab, tabIndex = tabs[gid], order[gid] break end
					end
					local taken = rank > 0
					out[#out + 1] = {
						key = nodeID,
						name = name,
						color = (not taken) and "|cffa0a0a0" or nil,
						icon = (def and def.overrideIcon)
							or (spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)),
						detail = ((tab and tab ~= "") and (tab .. "  ") or "") .. (taken and TAKEN or NOT_TAKEN)
							.. " " .. rank .. "/" .. (node.maxRanks or 1),
						text = (tab or "") .. " talent",
						getLink = TalentLink, -- (made when selected, not per talent on every rebuild)
						nodeID = nodeID,
						tab = tab,
						tabIndex = tabIndex,
						taken = taken,
						spellID = spellID,
						-- opened through the game's Talents keybinding, then the node is highlighted
						secure = TL.SECURE,
						isOpen = TL.IsOpen,
						after = HighlightNode,
						activate = OpenFallback,
						-- Shift+Enter: link the talent in chat
						secondary = LinkTalent,
					}
				end
			end
		end
		return out
	end,
})

-- .talentdebug : what Terminal sees of the open talent window, for bug reports.
ns:RegisterCommand("talentdebug", {
	desc = "Show what Terminal sees in the open talent window (for bug reports)",
	run = function()
		local lines = { "Talent debug (open the talent window first):" }
		local configID, treeID, tabs = ReadTree()
		local names = {}
		for _, n in pairs(tabs or {}) do names[#names + 1] = n end
		lines[#lines + 1] = ("  Tree: config %s, tree %s, tabs: %s"):format(tostring(configID), tostring(treeID),
			#names > 0 and table.concat(names, ", ") or "none")
		local root, rootName = TL.Window()
		lines[#lines + 1] = "  Window: " .. (rootName or "none open")
		if root then
			local nodes, tabButtons, labels = 0, {}, {}
			local function walk(f, depth)
				if depth > 14 or not Usable(f) then return end
				if AnyNode(f) then nodes = nodes + 1 end
				for _, n in ipairs(names) do
					if f.Click and TabText(f, n) then tabButtons[#tabButtons + 1] = n end
				end
				if f.Click and f.GetText and #labels < 10 then
					local ok, t = pcall(f.GetText, f)
					if ok and type(t) == "string" and t ~= "" then labels[#labels + 1] = Plain(t) end
				end
				for _, child in ipairs({ f:GetChildren() }) do walk(child, depth + 1) end
			end
			walk(root, 0)
			lines[#lines + 1] = ("  Talent buttons visible: %d   Tree tabs found: %s"):format(nodes,
				#tabButtons > 0 and table.concat(tabButtons, ", ") or "none")
			local numbered = {}
			for i = 1, 4 do
				if _G[rootName .. "Tab" .. i] then numbered[#numbered + 1] = rootName .. "Tab" .. i end
			end
			lines[#lines + 1] = "  Numbered tabs: " .. (#numbered > 0 and table.concat(numbered, ", ") or "none")
			lines[#lines + 1] = "  Button labels: " .. (#labels > 0 and table.concat(labels, " | ") or "none")
		end
		return lines
	end,
})
