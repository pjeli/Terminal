local ns = select(2, ...)
local L = ns.L

-- What the small apps that take the terminal's place share (.atop, .changelog, .keybinds, the extras' .snake, .tetris,
-- .lootrun, .typing and .wowamp, the drop-quests confirmation): a frame built the same
-- way, laid where the terminal is in its theme's colours, the same kind of text, and a registry so opening one drops
-- the terminal at once and closes the others. Each app keeps its own keys: atop, .typing and the confirmations take the
-- keyboard whole, the others pass on the keys they don't use (P.Propagate).

local P = {}
ns.Panel = P

local Theme = ns.Theme
local WHITE = "Interface\\Buttons\\WHITE8X8"
local panels = {} -- every app built: { IsShown, Close }
local frames = {} -- their frames (.zen keeps them up while the interface fades)

--- A one-line FontString in the input font, at `size` (the font's own when nil), justified left unless told.
--- (0.49.2, review: a size is its own font object, Theme.FontAt, so `.set font` reaches every app's text; a face set
--- on the FontString itself stayed the one it was made with)
function P.Text(parent, size, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(size and Theme.FontAt(size) or Theme.fonts.input)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

--- An app's frame: named, above the game's windows (DIALOG), kept on screen, hidden, reading the
--- keyboard, catching the mouse, and closing itself (`app.Close("combat")`) when combat starts: with the
--- keyboard held you couldn't move or cast. The app (`IsShown`, `Close`) is registered for P.Opening.
function P.Build(name, app)
	local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:Hide()
	frame:EnableKeyboard(true)
	-- (0.49.2, review: only WoWamp caught the mouse, as the terminal does: a click on F1's or the changelog's text went
	-- through to the world and targeted the mob behind it, a drag on .atop turned the camera)
	frame:EnableMouse(true)
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:SetScript("OnEvent", function() app.Close("combat") end)
	panels[#panels + 1] = app
	frames[#frames + 1] = frame
	if ns.Zen then ns.Zen.Made(frame) end -- (built while .zen has the interface faded, the first time it opens: kept up)
	return frame
end

--- Where the terminal is, in its theme: sized W x H (when given) at the terminal's scale, hung from the
--- The flat backdrop Terminal's windows use (white with a 1 px edge, coloured by each), and one with the edge alone
--- (a box drawn round a part of a window). One table each (review, 0.53.6: written out in six files).
P.FLAT = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }
P.EDGE = { edgeFile = WHITE, edgeSize = 1 }
--- Gives a frame the flat backdrop, once (setting it makes its textures again: some did on every show).
function P.Flat(frame, backdrop)
	backdrop = backdrop or P.FLAT
	if frame.flatSet == backdrop then return end
	frame.flatSet = backdrop
	frame:SetBackdrop(backdrop)
end

--- terminal's top, with its background (never more see-through than 0.9) and border. Gives the theme.
function P.Layout(frame, W, H)
	local t = Theme.Get()
	if W and H then frame:SetSize(W, H) end
	frame:SetScale(t.scale or 1)
	frame:ClearAllPoints()
	local term = _G.TerminalFrame
	if term then frame:SetPoint("TOP", term, "TOP", 0, 0) else frame:SetPoint("CENTER") end
	P.Flat(frame)
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

function P.Registered() return panels end -- (every app built; Zen and the tests read it)
--- Whether one of Terminal's apps shows (in the terminal's place: they count as Terminal).
function P.AnyShown()
	for _, app in ipairs(panels) do
		if type(app.IsShown) == "function" and app.IsShown() then return true end
	end
	return false
end
function P.Frames() return frames end

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

-- The apps' footers say their keys alike, as the terminal's own footer does ("<key> <what it does>"): review, 0.48.6
-- (quitting was said seven ways, each its own text to translate)
P.QUIT = L["Esc or ` quit"]
P.CLOSE = L["Esc or ` close"]
P.AGAIN = L["Tab again"] -- (the games' own game-over keys: Terminal_Extras/Game.lua)

--- Hides an app's frame if it shows; closed by combat starting ("combat"), says so: "<label> closed: combat
--- started." and `extra`. Gives whether it closed (an app's own closing steps follow only then).
function P.Close(frame, why, label, extra)
	if not frame or not frame:IsShown() then return false end
	frame:Hide()
	if why == "combat" then ns:Print(L["%s closed: combat started."]:format(label) .. (extra or "")) end
	return true
end

--- A scrolling box in an app's window (the changelog, the keys window): its edge, the scroll frame and its content, a
--- thumb on the right; the mouse wheel scrolls it. `top`: where it starts below the window's top; `step`: pixels a line.
--- Gives { box, scroll, content, thumb, offset, ScrollTo(to), Max(), KEYS (the scroll keys: Up/Down, PgUp/PgDn,
--- Home/End) }. (One copy: the two apps had one each, line for line; review, 0.53.6.)
function P.Scroller(frame, top, step)
	local sc = { offset = 0, step = step or 40 }
	local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	box:SetPoint("TOPLEFT", 10, top)
	box:SetPoint("BOTTOMRIGHT", -10, 30)
	P.Flat(box, P.EDGE)
	local scroll = CreateFrame("ScrollFrame", nil, box)
	scroll:SetPoint("TOPLEFT", 10, -8)
	scroll:SetPoint("BOTTOMRIGHT", -14, 8)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	local thumb = box:CreateTexture(nil, "ARTWORK")
	thumb:SetColorTexture(1, 1, 1, 1)
	thumb:SetWidth(3)
	sc.box, sc.scroll, sc.content, sc.thumb = box, scroll, content, thumb
	function sc.Max() return math.max(0, (content:GetHeight() or 0) - (scroll:GetHeight() or 0)) end
	--- Scroll to `to` pixels from the top (kept inside), the thumb following.
	function sc.ScrollTo(to)
		local max = sc.Max()
		sc.offset = math.max(0, math.min(max, to or 0))
		scroll:SetVerticalScroll(sc.offset)
		local viewH = scroll:GetHeight() or 1
		local h = math.max(16, viewH * viewH / math.max(1, viewH + max))
		thumb:SetHeight(h)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", box, "TOPRIGHT", -3, -4 - (max > 0 and (viewH - h) * sc.offset / max or 0))
		thumb:SetShown(max > 0)
	end
	local function Page() return (scroll:GetHeight() or 200) - sc.step end
	sc.KEYS = {
		UP = function() sc.ScrollTo(sc.offset - sc.step) end,
		DOWN = function() sc.ScrollTo(sc.offset + sc.step) end,
		PAGEUP = function() sc.ScrollTo(sc.offset - Page()) end,
		PAGEDOWN = function() sc.ScrollTo(sc.offset + Page()) end,
		HOME = function() sc.ScrollTo(0) end,
		END = function() sc.ScrollTo(sc.Max()) end,
	}
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta) sc.ScrollTo(sc.offset - delta * sc.step) end)
	return sc
end

--- An app's keys: the scroller's and its own (its own win).
function P.Keys(sc, own)
	local keys = {}
	for k, fn in pairs(sc.KEYS) do keys[k] = fn end
	for k, fn in pairs(own) do keys[k] = fn end
	return keys
end

--- A box inside an app (a game board, the visualizer): white backdrop with a 1 px edge, coloured by P.StyleBoard.
function P.Board(parent)
	local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	P.Flat(b)
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
