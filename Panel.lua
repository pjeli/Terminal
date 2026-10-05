local ns = select(2, ...)

-- What the small apps that take the terminal's place share (.atop, .snake, .changelog): a frame
-- built the same way, laid where the terminal is in its theme's colours, the same kind of text, and
-- a registry so opening one drops the terminal at once and closes the others. Each app keeps its own
-- keys: atop takes the keyboard whole, Snake and the changelog pass on the keys they don't use.

local P = {}
ns.Panel = P

local Theme = ns.Theme
local WHITE = "Interface\\Buttons\\WHITE8X8"
local panels = {} -- every app built: { IsShown, Close }

--- A one-line FontString in the input font, at `size` (the font's own when nil), justified left unless told.
function P.Text(parent, size, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(Theme.fonts.input)
	if size then
		local font, _, flags = fs:GetFont()
		if font then fs:SetFont(font, size, flags) end
	end
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

--- An app's frame: named, above the game's windows (DIALOG), kept on screen, hidden, reading the
--- keyboard, and closing itself (`app.Close("combat")`) when combat starts: with the keyboard held you
--- couldn't move or cast. The app (`IsShown`, `Close`) is registered for P.Opening.
function P.Build(name, app)
	local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:Hide()
	frame:EnableKeyboard(true)
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:SetScript("OnEvent", function() app.Close("combat") end)
	panels[#panels + 1] = app
	return frame
end

--- Where the terminal is, in its theme: sized W x H (when given) at the terminal's scale, hung from the
--- terminal's top, with its background (never more see-through than 0.9) and border. Gives the theme.
function P.Layout(frame, W, H)
	local t = Theme.Get()
	if W and H then frame:SetSize(W, H) end
	frame:SetScale(t.scale or 1)
	frame:ClearAllPoints()
	local term = _G.TerminalFrame
	if term then frame:SetPoint("TOP", term, "TOP", 0, 0) else frame:SetPoint("CENTER") end
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	local r, g, b = Theme.RGB(t.bg)
	frame:SetBackdropColor(r, g, b, math.max(0.9, t.bgAlpha or 0.95))
	local br, bg, bb = Theme.RGB(t.border)
	frame:SetBackdropBorderColor(br, bg, bb, 1)
	return t
end

--- An app is opening: the terminal goes at once (its closing animation would play under the panel),
--- and every other app closes.
function P.Opening(app)
	if ns.UI and ns.UI.HideNow then ns.UI:HideNow() end
	for _, other in ipairs(panels) do
		if other ~= app and other.IsShown() then other.Close() end
	end
end

function P.Registered() return panels end -- (tests)
