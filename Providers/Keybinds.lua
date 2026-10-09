local ns = select(2, ...)

-- Keybindings: every action the game lets you bind (Move Forward, Toggle World Map, Action Button 3,
-- addons' own...), with its keys. Enter opens Options > Keybindings and points at the action's row,
-- where its key is set. "Quick Keybind Mode" is a result too: Enter points at its button, Shift+Enter
-- starts it (hover a button, press a key).
--
-- The Keybindings page and Quick Keybind Mode are opened by the game itself, as a macro line on the
-- secure macro button (QuickKeybindFrame is protected; Terminal's own code never opens either).
-- Afterwards Terminal only reads the page and points at the row (the options search does the same).

local K = {}
ns.Keybinds = K

local Str = ns.Str -- (Util.lua)

--- The keys bound to it, as the game writes them ("Ctrl-M, F5"), or nil.
local function KeysText(k1, k2)
	local parts = {}
	for _, k in ipairs({ k1, k2 }) do
		k = Str(k)
		if k then
			local ok, t = pcall(GetBindingText, k, "KEY_")
			parts[#parts + 1] = (ok and Str(t)) or k
		end
	end
	return #parts > 0 and table.concat(parts, ", ") or nil
end

-- opening Options > Keybindings: pressed by the game (a /run line on the secure macro button). Then
-- the options window's own search box gets the action's name: its row shows even when its section
-- is collapsed (expanding the section from Terminal's code would taint the window; the game typing
-- into its own search box doesn't). An empty search shows the whole page.
K.OPEN_MACRO = "/run local S=Settings S.OpenToCategory(S.KEYBINDINGS_CATEGORY_ID or KEY_BINDINGS)"
-- (the game cuts a macro off at 255 characters in all: the name has to fit after this)
local SEARCH = " local B=SettingsPanel.SearchBox if B then B:SetText(%s) end"
function K.MacroFor(name) return K.OPEN_MACRO .. SEARCH:format(("%q"):format(name or "")) end
-- Quick Keybind Mode: the options window steps aside, the protected frame is shown by the game
K.QUICK_MACRO = "/run if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end if QuickKeybindFrame then ShowUIPanel(QuickKeybindFrame) end"

local function OpenMacro(e) return K.MacroFor(e and e.search) end
local function QuickMacro() return K.QUICK_MACRO end
local OPEN_SPEC = { macro = OpenMacro, opensWindow = true }
local QUICK_SPEC = { macro = QuickMacro, opensWindow = true }

--- Options > Keybindings is the page showing (then only the row is pointed at).
local function PageOpen()
	local sp = _G.SettingsPanel
	if not (sp and sp.IsVisible and sp:IsVisible()) then return false end
	local id = Settings and Settings.KEYBINDINGS_CATEGORY_ID
	local ok, cat = pcall(function() return sp:GetCurrentCategory() end)
	if ok and type(cat) == "table" and id then
		local ok2, cid = pcall(cat.GetID, cat)
		return ok2 and cid == id or false
	end
	return false
end

local function PointAtRow(e)
	ns:Trace("keybinds: pointing at " .. tostring(e.rowText or e.name))
	local G = ns.GameOptions
	if G and G.HighlightSetting then G.HighlightSetting(e.rowText or e.name) end
end

-- the fallback without the secure route (Terminal's own code): open, then point
local function OpenDirect(e)
	if InCombatLockdown() then return end
	if Settings and Settings.OpenToCategory then
		pcall(Settings.OpenToCategory, Settings.KEYBINDINGS_CATEGORY_ID or KEY_BINDINGS)
		local B = _G.SettingsPanel and _G.SettingsPanel.SearchBox
		if B and B.SetText and e.search then pcall(B.SetText, B, e.search) end
		C_Timer.After(0.1, function() PointAtRow(e) end)
	end
end

local NeverOpen = ns.Never -- (Quick Keybind Mode: always pressed)
local function QuickInCombat(e) ns:Print("In combat: Quick Keybind Mode can't be started now.") end
local function QuickStarted() ns:Trace("keybinds: the game started Quick Keybind Mode") end

local ICON = "Interface\\Icons\\INV_Misc_Key_03"

ns:RegisterProvider("keybinds", {
	label = "Keybind",
	color = "ffffb2bf", -- (apart from @stored's lavender)
	aliases = { "keybind", "keybinds", "binding", "bindings", "hotkey", "hotkeys", "key" },
	noCombat = true, -- opening windows is protected in combat
	lazy = true, -- hundreds of actions: only offered once you type something
	events = { "UPDATE_BINDINGS" },
	guard = 1,
	collect = function()
		local out = {}
		-- Quick Keybind Mode: Enter points at its button, Shift+Enter starts it
		local quick = Str(_G.QUICK_KEYBIND_MODE) or "Quick Keybind Mode"
		out[1] = {
			key = "quickkeybind", name = quick, icon = ICON,
			detail = "Shift+Enter: start it",
			text = "keybind keybinding binding hotkey bind keys quick mode",
			tip = "Hover an action button, spell or macro and press a key to bind it.",
			rowText = quick,
			secure = OPEN_SPEC, isOpen = PageOpen, after = PointAtRow, activate = OpenDirect,
			secondary = QuickInCombat, secondarySecure = QUICK_SPEC, secondaryIsOpen = NeverOpen, secondaryAfter = QuickStarted,
		}
		if not (GetNumBindings and GetBinding) then return out end
		local category
		for i = 1, GetNumBindings() do
			local ok, command, cat, k1, k2 = pcall(GetBinding, i)
			command = ok and Str(command)
			if command and not command:find("^HEADER_") then
				local name = Str(_G["BINDING_NAME_" .. command])
				if not name and GetBindingName then
					local okn, n = pcall(GetBindingName, command)
					name = okn and Str(n) or nil
				end
				if name and name ~= command then
					category = Str(cat) and (Str(_G[cat]) or cat) or category
					local keys = KeysText(k1, k2)
					out[#out + 1] = {
						key = command, name = name, icon = ICON,
						detail = (keys or "not bound") .. (category and ("  ·  " .. category) or ""),
						text = "keybind binding hotkey " .. (keys or "unbound") .. " " .. (category or ""),
						rowText = name, search = name,
						-- (always pressed, even with the page open: the search brings the row up)
						secure = OPEN_SPEC, after = PointAtRow, activate = OpenDirect,
					}
				end
			end
		end
		return out
	end,
})
