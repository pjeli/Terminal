local ns = select(2, ...)
local L = ns.L

-- .credits (0.56.13, the author's ask): a small window where the terminal sits, thanking the people who kept Terminal
-- going. Esc, `, Enter, Space or a click close it; any other key goes on to the game (the Panel pattern).

local CR = {}
ns.Credits = CR

local Theme, Panel = ns.Theme, ns.Panel
local Text, Hex = Panel.Text, Panel.Hex
local W, H = 440, 150

-- (names as they are: not translated)
CR.NAMES = { "Caite", "Brother", "Wesslan", "Beefnerd", "Cazador", "Kass", "TJ" }

local frame, title, versionText, body, footer

--- The thanks, the names in the accent colour.
function CR.Text()
	local t = Theme.Get()
	local acc, txt = Hex(t.accent), Hex(t.text)
	local names = {}
	for i = 1, #CR.NAMES do names[i] = ("|cff%s%s|r|cff%s"):format(acc, CR.NAMES[i], txt) end
	local last = table.remove(names)
	return ("|cff%s"):format(txt) .. L["Thank you to %s, and %s for supporting and believing in me to continue working on this."]
		:format(table.concat(names, ", "), last) .. "|r"
end

local function Close() CR.Close() end
local KEYS = { ESCAPE = Close, ["`"] = Close, ENTER = Close, SPACE = Close }

function CR.KeyDown(self, key)
	local fn = KEYS[ns.TickAs(key)] -- (the terminal's key, whichever: 0.65.1)
	if fn then fn() end
	Panel.Propagate(self, fn)
end

local function Build()
	if frame then return end
	frame = Panel.Build("TerminalCredits", CR)
	frame:SetScript("OnKeyDown", function(self, key) CR.KeyDown(self, key) end)
	frame:SetScript("OnMouseDown", Close)
	title, versionText = Panel.Header(frame)
	body = Text(frame, 13, "CENTER")
	body:SetPoint("TOPLEFT", 24, -42)
	body:SetPoint("TOPRIGHT", -24, -42)
	body:SetWordWrap(true)
	body:SetJustifyV("TOP")
	if body.SetSpacing then body:SetSpacing(4) end
	footer = Panel.Footer(frame, 10, Panel.CLOSE)
	CR.frame = frame
end

local function Layout()
	local t = Panel.Layout(frame, W, H)
	local dr, dg, db = Theme.RGB(t.dim)
	footer:SetTextColor(dr, dg, db)
	versionText:SetTextColor(dr, dg, db)
	title:SetText(Theme.FixColors(("|cff%s%s|r"):format(Hex(t.accent), L["credits"])))
	local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ns.name, "Version")
	versionText:SetText(ns.name .. (version and (" " .. tostring(version)) or ""))
	body:SetText(Theme.FixColors(CR.Text()))
end

function CR.IsShown() return Panel.Shown(frame) end
function CR.Body() return body end -- (tests)

function CR.Open()
	if not Panel.CanOpen(L["The credits take a few keys while open, which the game doesn't allow in combat."]) then return false end
	Build()
	Layout()
	Panel.Opening(CR)
	frame:Show()
	return true
end

function CR.Close(why)
	Panel.Close(frame, why, L["Credits"])
end

ns:RegisterCommand("credits", {
	desc = L["Thank you to the people who kept Terminal going"],
	aliases = { "thanks" },
	run = function() CR.Open() end,
})
