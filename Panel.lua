local ns = select(2, ...)

-- What the small apps that take the terminal's place share (.atop, .snake, .tetris, .changelog, .wowamp and
-- the .advanced confirmation in Easy.lua): a frame built the same way, laid where the terminal is in its
-- theme's colours, the same kind of text, and a registry so opening one drops the terminal at once and
-- closes the others. Each app keeps its own keys: atop and the .advanced dialog take the keyboard whole,
-- the others pass on the keys they don't use (P.Propagate).

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

--- Passes this key press on to the game unless it was the app's own (`mine`). Choosing isn't allowed in combat:
--- then nothing changes.
function P.Propagate(frame, mine)
	if frame and frame.SetPropagateKeyboardInput and not InCombatLockdown() then
		pcall(frame.SetPropagateKeyboardInput, frame, not mine)
	end
end

--- Whether an app's frame (nil until built) is showing.
function P.Shown(frame) return frame and frame:IsShown() or false end

--- An app may open: not in combat (it couldn't choose which keys to keep). In combat `msg` is printed: false.
function P.CanOpen(msg)
	if InCombatLockdown() then
		ns:Print(msg)
		return false
	end
	return true
end

--- Hides an app's frame if it shows; closed by combat starting ("combat"), says so: "<label> closed: combat
--- started." and `extra`. Gives whether it closed (an app's own closing steps follow only then).
function P.Close(frame, why, label, extra)
	if not frame or not frame:IsShown() then return false end
	frame:Hide()
	if why == "combat" then ns:Print(label .. " closed: combat started." .. (extra or "")) end
	return true
end

--- A box inside an app (a game board, the visualizer): white backdrop with a 1 px edge, coloured by P.StyleBoard.
function P.Board(parent)
	local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	return b
end

--- A board in the theme `t`: the prompt's background (else the terminal's) and the border colour.
--- Gives the background's r, g, b.
function P.StyleBoard(board, t)
	local br, bg, bb = Theme.RGB(t.border)
	local pr, pg, pb = Theme.RGB(t.promptBg or t.bg)
	board:SetBackdropColor(pr, pg, pb, 1)
	board:SetBackdropBorderColor(br, bg, bb, 1)
	return pr, pg, pb
end

--- The header line: a title on the left (13) and a smaller text on the right (12). Gives both.
function P.Header(frame)
	local left = P.Text(frame, 13)
	left:SetPoint("TOPLEFT", 12, -10)
	local right = P.Text(frame, 12, "RIGHT")
	right:SetPoint("TOPRIGHT", -12, -10)
	return left, right
end

--- The footer line at the bottom left, `y` up from the edge, at `size` (11 when nil), saying `text` (when given).
function P.Footer(frame, y, text, size)
	local fs = P.Text(frame, size or 11)
	fs:SetPoint("BOTTOMLEFT", 12, y)
	if text then fs:SetText(text) end
	return fs
end

--- A colour as plain rrggbb for a |cff code ("|cffrrggbb", "ffrrggbb" and "rrggbb" all give rrggbb).
function P.Hex(c) return (tostring(c or "ffffff"):gsub("^|c", ""):gsub("^ff(%x%x%x%x%x%x)$", "%1")) end
