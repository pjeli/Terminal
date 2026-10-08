local ns = select(2, ...)
local H = ns.Highlight
local MACRO_WINDOW, MacroWindowOpen = ns.MACRO_WINDOW, ns.MacroWindowOpen -- (Panels.lua)

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
