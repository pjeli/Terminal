local ns = select(2, ...)

-- Ctrl+click a link in chat (an item, a spell, a quest, an achievement...): its name goes into Terminal. Closed, it
-- opens on it (searching it); open, the name goes in where the cursor is.
--
-- The game's own handling of the click runs first and as usual (hooksecurefunc on SetItemRef, never a replacement:
-- that would taint every link click): Ctrl+click on gear also opens the dressing room, as it always has.

local CL = {}
ns.ChatLinks = CL

-- the link kinds whose shown name is worth searching
CL.KINDS = { item = true, spell = true, quest = true, achievement = true, currency = true, enchant = true,
	mount = true, battlepet = true, trade = true, talent = true }

--- The plain name a link shows ("|cff...|Hitem:...|h[Linen Cloth]|h|r" -> "Linen Cloth"), else the game's name for
--- an item id; nil for a link kind that isn't searched.
function CL.NameOf(link, text)
	if type(link) ~= "string" then return nil end
	local kind, id = link:match("^(%a+):(%-?%d*)")
	if not (kind and CL.KINDS[kind]) then return nil end
	local name = type(text) == "string" and text:match("%[(.-)%]")
	if name and ns.Secret and ns.Secret(name) then name = nil end
	if (not name or name == "") and kind == "item" and tonumber(id) then
		local get = C_Item and C_Item.GetItemNameByID
		name = get and ns.Safe(get, tonumber(id)) or nil
	end
	if type(name) ~= "string" or name == "" then return nil end
	name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("^%s+", ""):gsub("%s+$", "")
	return name ~= "" and name or nil
end

--- After the game handled a chat link click: with Ctrl held, the link's name goes into Terminal.
function CL.OnRef(link, text, button)
	if not (IsControlKeyDown and IsControlKeyDown()) then return end
	if button and button ~= "LeftButton" then return end
	local name = CL.NameOf(link, text)
	if not name then return end
	local UI = ns.UI
	ns:Trace("chat link: Ctrl+click on " .. name)
	if UI:IsShown() and not UI.closing then
		-- open: in where the cursor is, with a space between it and the words around it
		local q = UI.edit and UI.edit:GetText() or ""
		local edit = UI.edit
		local cur = UI.keys and UI.cursor or (edit and edit.GetCursorPosition and edit:GetCursorPosition()) or #q
		local at = math.max(0, math.min(tonumber(cur) or #q, #q))
		local before, after = q:sub(1, at), q:sub(at + 1)
		if before ~= "" and not before:find("%s$") then before = before .. " " end
		if after ~= "" and not after:find("^%s") then after = " " .. after end
		UI:SetQuery(before .. name .. after, #before + #name)
	else
		UI:Open(name)
	end
end

local hooked = false
function CL.Hook()
	if hooked then return true end
	if type(hooksecurefunc) ~= "function" or type(_G.SetItemRef) ~= "function" then return false end
	hooked = pcall(hooksecurefunc, "SetItemRef", function(...) pcall(CL.OnRef, ...) end)
	return hooked
end

if not CL.Hook() then
	-- (the chat code may come later on some clients: try again at login)
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function(self)
		CL.Hook()
		self:UnregisterAllEvents()
	end)
end
