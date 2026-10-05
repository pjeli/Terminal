local ns = select(2, ...)

-- .snake: Snake, in a small window where the terminal sits. WASD or the arrow keys steer, Enter
-- plays again after a game over, Esc or ` quits. No pausing (it's for fun; Space stays the game's). Only the game's keys are taken: any
-- other key still reaches the game (your action bars, chat...). The best score is kept.
--
-- Choosing which keys pass on (SetPropagateKeyboardInput) isn't allowed in combat, so the game
-- doesn't start in combat and closes when combat starts.

local S = {}
ns.Snake = S

local Theme = ns.Theme
local COLS, ROWS, CELL = 20, 15, 16
local START_SPEED, MAX_SPEED, SPEED_UP = 7, 16, 0.35 -- moves a second; faster with every apple
local DIRS = {
	W = { 0, -1 }, UP = { 0, -1 }, S = { 0, 1 }, DOWN = { 0, 1 },
	A = { -1, 0 }, LEFT = { -1, 0 }, D = { 1, 0 }, RIGHT = { 1, 0 },
}

local frame, board, scoreText, bestText, overlay, overlaySub, footer
local segs, food = {}, nil
local game = {}

S.rand = function(n) return math.random(n) end -- (tests replace it)

local function Key(x, y) return y * 100 + x end

----------------------------------------------------------------------
-- The game
----------------------------------------------------------------------

local function PlaceFood()
	local free = {}
	local taken = {}
	for _, c in ipairs(game.body) do taken[Key(c[1], c[2])] = true end
	for y = 0, ROWS - 1 do
		for x = 0, COLS - 1 do
			if not taken[Key(x, y)] then free[#free + 1] = { x, y } end
		end
	end
	game.food = #free > 0 and free[S.rand(#free)] or nil
end

function S.Reset()
	local y = math.floor(ROWS / 2)
	game.body = { { 6, y }, { 5, y }, { 4, y } } -- head first, moving right
	game.dir, game.queue = { 1, 0 }, {}
	game.score, game.speed, game.acc = 0, START_SPEED, 0
	game.over, game.won = false, false
	PlaceFood()
end

--- Turn (taken on the next move; two quick presses are both kept, so a fast U-turn works,
--- but never straight back into yourself).
function S.Turn(dx, dy)
	local last = game.queue[#game.queue] or game.dir
	if (dx == -last[1] and dy == -last[2]) or (dx == last[1] and dy == last[2]) then return end
	if #game.queue < 2 then game.queue[#game.queue + 1] = { dx, dy } end
end

--- One move: the head goes ahead; an apple makes the snake longer, a wall or the tail ends it.
function S.Step()
	if game.over then return end
	if #game.queue > 0 then game.dir = table.remove(game.queue, 1) end
	local head = game.body[1]
	local nx, ny = head[1] + game.dir[1], head[2] + game.dir[2]
	local eating = game.food and nx == game.food[1] and ny == game.food[2]
	if nx < 0 or ny < 0 or nx >= COLS or ny >= ROWS then return S.GameOver("wall") end
	for i = 1, #game.body - (eating and 0 or 1) do -- (the tail's last cell moves out of the way)
		local c = game.body[i]
		if c[1] == nx and c[2] == ny then return S.GameOver("tail") end
	end
	table.insert(game.body, 1, { nx, ny })
	if eating then
		game.score = game.score + 1
		game.speed = math.min(MAX_SPEED, game.speed + SPEED_UP)
		PlaceFood()
		if not game.food then game.won = true; return S.GameOver("won") end
	else
		table.remove(game.body)
	end
end

function S.GameOver(why)
	game.over, game.why = true, why
	if ns.db and game.score > (ns.db.snakeBest or 0) then
		ns.db.snakeBest = game.score
		game.newBest = true
	else
		game.newBest = false
	end
end

S.game = game

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

local function Seg(i)
	local t = segs[i]
	if not t then
		t = board:CreateTexture(nil, "ARTWORK")
		t:SetColorTexture(1, 1, 1, 1)
		t:SetSize(CELL - 2, CELL - 2)
		segs[i] = t
	end
	return t
end

local function Place(t, x, y)
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", board, "TOPLEFT", x * CELL + 1, -y * CELL - 1)
end

function S.Draw()
	if not frame then return end
	local t = Theme.Get()
	local ar, ag, ab = Theme.RGB(t.accent)
	local tr, tg, tb = Theme.RGB(t.text)
	for i, c in ipairs(game.body) do
		local seg = Seg(i)
		Place(seg, c[1], c[2])
		if i == 1 then
			seg:SetVertexColor(ar, ag, ab, 1)
		else
			local fade = 1 - 0.5 * (i - 1) / math.max(1, #game.body) -- (the tail fades a little)
			seg:SetVertexColor(tr, tg, tb, fade)
		end
		seg:Show()
	end
	for i = #game.body + 1, #segs do segs[i]:Hide() end
	if game.food then
		Place(food, game.food[1], game.food[2])
		food:Show()
	else
		food:Hide()
	end
	scoreText:SetText(("|cff%ssnake|r   score %d"):format(t.accent, game.score))
	bestText:SetText(("best %d"):format(math.max(ns.db and ns.db.snakeBest or 0, game.score)))
	if game.over then
		overlay:SetText(game.won and "you filled the board!" or (game.newBest and "new best!" or "game over"))
		overlaySub:SetText(("score %d  ·  Enter to play again  ·  Esc to quit"):format(game.score))
		overlay:Show(); overlaySub:Show()
	else
		overlay:Hide(); overlaySub:Hide()
	end
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

local function Text(parent, size, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(Theme.fonts.input)
	local font, _, flags = fs:GetFont()
	if font and size then fs:SetFont(font, size, flags) end
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

local function Build()
	if frame then return end
	frame = CreateFrame("Frame", "TerminalSnake", UIParent, "BackdropTemplate")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:Hide()
	frame:SetSize(COLS * CELL + 24, ROWS * CELL + 64)
	frame:EnableKeyboard(true)
	frame:SetScript("OnKeyDown", function(self, key) S.KeyDown(self, key) end)
	frame:SetScript("OnUpdate", function(_, elapsed) S.Tick(elapsed) end)
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:SetScript("OnEvent", function() S.Close("combat") end)

	scoreText = Text(frame, 13)
	scoreText:SetPoint("TOPLEFT", 12, -10)
	bestText = Text(frame, 12, "RIGHT")
	bestText:SetPoint("TOPRIGHT", -12, -10)

	board = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	board:SetSize(COLS * CELL, ROWS * CELL)
	board:SetPoint("TOP", 0, -32)
	board:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	food = board:CreateTexture(nil, "ARTWORK")
	food:SetColorTexture(1, 0.37, 0.37, 1)
	food:SetSize(CELL - 4, CELL - 4)

	overlay = Text(board, 16, "CENTER")
	overlay:SetPoint("CENTER", 0, 10)
	overlaySub = Text(board, 11, "CENTER")
	overlaySub:SetPoint("CENTER", 0, -12)
	footer = Text(frame, 11)
	footer:SetPoint("BOTTOMLEFT", 12, 9)
	footer:SetText("WASD or arrows steer  ·  Esc or ` quit")
	S.frame = frame
end

local function Style()
	local t = Theme.Get()
	frame:SetScale(t.scale or 1)
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	local r, g, b = Theme.RGB(t.bg)
	frame:SetBackdropColor(r, g, b, math.max(0.9, t.bgAlpha or 0.95))
	local br, bg, bb = Theme.RGB(t.border)
	frame:SetBackdropBorderColor(br, bg, bb, 1)
	local pr, pg, pb = Theme.RGB(t.promptBg or t.bg)
	board:SetBackdropColor(pr, pg, pb, 1)
	board:SetBackdropBorderColor(br, bg, bb, 1)
	local tr, tg, tb = Theme.RGB(t.text)
	local dr, dg, db = Theme.RGB(t.dim)
	scoreText:SetTextColor(tr, tg, tb)
	bestText:SetTextColor(dr, dg, db)
	overlay:SetTextColor(tr, tg, tb)
	overlaySub:SetTextColor(dr, dg, db)
	footer:SetTextColor(dr, dg, db)
	frame:ClearAllPoints()
	local term = _G.TerminalFrame
	if term then frame:SetPoint("TOP", term, "TOP", 0, 0) else frame:SetPoint("CENTER") end
end

--- The game's keys are kept; any other key goes on to the game.
function S.KeyDown(self, key)
	local mine = true
	if key == "ESCAPE" or key == "`" then
		S.Close()
	elseif DIRS[key] then
		if not game.over then S.Turn(DIRS[key][1], DIRS[key][2]) end
	elseif key == "ENTER" or key == "NUMPADENTER" then
		if game.over then S.Reset(); S.Draw() else mine = false end
	else
		mine = false
	end
	if self and self.SetPropagateKeyboardInput and not InCombatLockdown() then
		pcall(self.SetPropagateKeyboardInput, self, not mine)
	end
end

function S.Tick(elapsed)
	if game.over then return end
	game.acc = (game.acc or 0) + (elapsed or 0)
	local every = 1 / game.speed
	local moved = false
	while game.acc >= every and not game.over do
		game.acc = game.acc - every
		S.Step()
		moved = true
	end
	if moved then S.Draw() end
end

function S.IsShown() return frame and frame:IsShown() or false end

function S.Open()
	if InCombatLockdown() then
		ns:Print("Snake takes over keys, which the game doesn't allow in combat.")
		return false
	end
	Build()
	Style()
	if ns.UI and ns.UI.HideNow then ns.UI:HideNow() end -- (straight in, no closing animation under it)
	if ns.Btop and ns.Btop.IsShown and ns.Btop.IsShown() then ns.Btop.Close() end
	S.Reset()
	frame:Show()
	S.Draw()
	return true
end

function S.Close(why)
	if not frame or not frame:IsShown() then return end
	frame:Hide()
	if why == "combat" then ns:Print("Snake closed: combat started.") end
end

ns:RegisterCommand("snake", {
	desc = "Play Snake (WASD or arrows, Space pause, Esc or ` quits)",
	run = function() S.Open() end,
})
