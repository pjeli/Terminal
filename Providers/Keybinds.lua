local ns = select(2, ...)

-- Keybindings: every action the game lets you bind (Move Forward, Toggle World Map, Action Button 3,
-- addons' own...), with its keys. Enter opens Options > Keybindings scrolled to the action's section,
-- unfolds the section, and points at the action's row, where its key is set. "Quick Keybind Mode" is a
-- result too: Enter points at its button, Shift+Enter starts it (hover a button, press a key).
--
-- The Keybindings page and Quick Keybind Mode are opened by the game itself, as a macro line on the
-- secure macro button (QuickKeybindFrame is protected; Terminal's own code never opens either), and the
-- section is unfolded by the game's own click (NAV below). Terminal's code only reads the page and points
-- at the row, as GameOptions.lua's HighlightSetting does for a setting.

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

-- Opening Options > Keybindings: the game's own call on the secure macro button (Secure.SettingsMacro), answered by the
-- window's own code. Nothing is typed into its search box any more: until 0.46.2 the line also did SetText on it, so
-- an action's row showed inside a closed section, but a /run line runs tainted (0.46.1) and the list it rebuilt held
-- it. Now the row is pointed at once it shows, and an action in a closed section says which one to open.
function K.OpenMacro()
	local St = _G.Settings
	return ns.Secure.SettingsMacro(St and St.KEYBINDINGS_CATEGORY_ID)
end
-- Quick Keybind Mode: the options window steps aside, the protected frame is shown by the game
K.QUICK_MACRO = "/run if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end if QuickKeybindFrame then ShowUIPanel(QuickKeybindFrame) end"

local function QuickMacro() return K.QUICK_MACRO end
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

-- The action's section, scrolled to and unfolded by the game's own clicks (0.46.18, Secure.lua's "Turning a window"):
-- the press opens the page scrolled to the section's header (C_SettingsUtil.OpenSettingsPanel's own scrolling, by the
-- section's name), then a step clicks the header when it's folded, which the page answers by unfolding it (its own
-- code, untainted). Read only: the list's frames. The row is then pointed at when it shows; one further down the
-- section than the list shows says to scroll to it (scrolling the list would be Terminal writing into it).

--- The settings list's frame for the section named `name`, and its data; nil when it isn't on screen.
local function SectionFrame(name)
	local sp = _G.SettingsPanel
	local ok, list = pcall(function() return sp:GetSettingsList() end)
	local box = ok and type(list) == "table" and rawget(list, "ScrollBox")
	-- (its frames live on its view: ScrollBoxBaseMixin:GetFrames() = self:GetView():GetFrames(), read only. 0.46.18 read
	-- a field on the box itself, which the client doesn't have: the section was never found, so never unfolded)
	local okF, frames = false, nil
	if box and type(box.GetFrames) == "function" then okF, frames = pcall(box.GetFrames, box) end
	if not okF or type(frames) ~= "table" then return nil end
	for _, f in ipairs(frames) do
		local okD, init = pcall(function() return f:GetElementData() end)
		local data = okD and type(init) == "table" and rawget(init, "data")
		if type(data) == "table" and rawget(data, "name") == name then return f, data end
	end
end

--- One step toward the action's row: its section's header when folded; nil when it's unfolded (or not on screen).
local function NavStep(e)
	if not e.category then return nil, "no section" end
	if not PageOpen() then return nil, "Keybindings isn't showing" end
	local f, data = SectionFrame(e.category)
	if not f then return nil, "the " .. e.category .. " section isn't on screen" end
	if rawget(data, "expanded") then return nil, "its section is open" end
	return rawget(f, "Button"), "unfold " .. e.category
end

K.NavStep = NavStep -- (tests)

local NAV = {
	route = "keybinds", step = NavStep,
	-- what the clicks write, read after the press: the section's folded/unfolded state
	watch = { function(e)
		local _, data = SectionFrame(e.category)
		return data, "expanded"
	end },
	watchName = function() return "the Keybindings section's state" end,
}

function K.NavMacro(e)
	local St = _G.Settings
	local id = St and St.KEYBINDINGS_CATEGORY_ID
	if not (e and e.category) or not ns.Secure.NavOn("keybinds") then return K.OpenMacro() end
	local open = ns.Secure.SettingsMacro(id, e.category) -- (the page, scrolled to the section's header by its name)
	if not open then return K.OpenMacro() end
	return (ns.Secure.NavMacro(NAV, e, open)) or K.OpenMacro()
end
local OPEN_SPEC = { macro = K.NavMacro, opensWindow = true }

--- The page showing and nothing for the press to do: the Quick Keybind row, or the route turned off.
local function IsOpen(e) return PageOpen() and not (e.category and ns.Secure.NavOn("keybinds")) end

local function PointAtRow(e)
	ns:Trace("keybinds: pointing at " .. tostring(e.rowText or e.name))
	local G = ns.GameOptions
	local hint
	if e.category then
		local _, data = SectionFrame(e.category)
		if data and rawget(data, "expanded") then
			hint = ("%s is further down in the %s section: scroll to it, and Terminal points at the row."):format(tostring(e.name), e.category)
		else
			hint = ("%s is in the %s section of Keybindings: open it, and Terminal points at the row."):format(tostring(e.name), e.category)
		end
	end
	if G and G.HighlightSetting then G.HighlightSetting(e.rowText or e.name, hint) end
end

-- the fallback without the secure route (Terminal's own code): open, then point
local function OpenDirect(e)
	if InCombatLockdown() then return end
	local U, St = _G.C_SettingsUtil, _G.Settings
	if U and U.OpenSettingsPanel and St and type(St.KEYBINDINGS_CATEGORY_ID) == "number" then
		pcall(U.OpenSettingsPanel, St.KEYBINDINGS_CATEGORY_ID)
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
			secure = OPEN_SPEC, isOpen = IsOpen, after = PointAtRow, activate = OpenDirect,
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
					-- (the game's own section: an action with no category of its own is under "Other", as the page lists it)
					category = Str(cat) and (Str(_G[cat]) or cat) or Str(_G.BINDING_HEADER_OTHER) or category
					local keys = KeysText(k1, k2)
					out[#out + 1] = {
						key = command, name = name, icon = ICON,
						detail = (keys or "not bound") .. (category and ("  ·  " .. category) or ""),
						text = "keybind binding hotkey " .. (keys or "unbound") .. " " .. (category or ""),
						rowText = name, category = category,
						-- (always pressed while the section is unfolded by a click; the route off and the page open: pointed at only)
						secure = OPEN_SPEC, isOpen = IsOpen, after = PointAtRow, activate = OpenDirect,
					}
				end
			end
		end
		return out
	end,
})
