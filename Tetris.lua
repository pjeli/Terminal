local ns = select(2, ...)

-- .tetris: falling blocks, in a small window where the terminal sits (the .snake pattern). Left/Right
-- (or A/D) move, Up/W/X rotate, Z/Q rotate the other way, Down/S drops faster, Enter drops at once,
-- C holds a piece for later, Esc or ` quits. Space stays the game's (no pausing: as Snake). Only the
-- game's keys are taken: any other key still reaches the game. The best score is kept.
--
-- Choosing which keys pass on (SetPropagateKeyboardInput) isn't allowed in combat, so the game
-- doesn't start in combat and closes when combat starts (Panel).

local TT = {}
ns.Tetris = TT

local Theme = ns.Theme
local Panel = ns.Panel
local COLS, ROWS, CELL = 10, 20, 16
local SIDE = 96 -- the column for next / hold / score
local LOCK_DELAY, LOCK_RESETS = 0.5, 15 -- a landed piece waits this long; moving it restarts the wait, this many times
local DAS, ARR = 0.17, 0.05 -- a held key repeats after DAS, every ARR (the game's own key repeats are ignored)
local SOFT_EVERY = 0.04 -- Down held: a row this often
local LINE_POINTS = { 100, 300, 500, 800 }

-- The seven pieces: their cells in a 4x4 box at rotation 0 (x, y; y down) and their classic colours
TT.PIECES = {
	I = { cells = { { 0, 1 }, { 1, 1 }, { 2, 1 }, { 3, 1 } }, size = 4, color = { 0.3, 0.85, 0.95 } },
	O = { cells = { { 1, 0 }, { 2, 0 }, { 1, 1 }, { 2, 1 } }, size = 4, color = { 0.95, 0.85, 0.25 } },
	T = { cells = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } }, size = 3, color = { 0.7, 0.4, 0.9 } },
	S = { cells = { { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 } }, size = 3, color = { 0.45, 0.85, 0.35 } },
	Z = { cells = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 2, 1 } }, size = 3, color = { 0.95, 0.35, 0.35 } },
	J = { cells = { { 0, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } }, size = 3, color = { 0.35, 0.5, 0.95 } },
	L = { cells = { { 2, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 } }, size = 3, color = { 0.95, 0.6, 0.2 } },
}
local ORDER = { "I", "O", "T", "S", "Z", "J", "L" }
-- tried in turn when a rotation doesn't fit where it is: the wall and floor kicks
local KICKS = { { 0, 0 }, { -1, 0 }, { 1, 0 }, { 0, -1 }, { -2, 0 }, { 2, 0 }, { -1, -1 }, { 1, -1 } }

local KEYS = {
	LEFT = "left", A = "left", RIGHT = "right", D = "right",
	DOWN = "down", S = "down",
	UP = "cw", W = "cw", X = "cw", Z = "ccw", Q = "ccw",
	ENTER = "drop", NUMPADENTER = "drop", C = "hold",
}
local REPEATS = { left = true, right = true }

local frame, board, scoreText, bestText, linesText, levelText, nextLabel, holdLabel, overlay, overlaySub, footer
local cellTex, pieceTex, ghostTex, nextTex, holdTex = {}, {}, {}, {}, {}
local game = {}
TT.game = game

TT.rand = function(n) return math.random(n) end -- (tests replace it)

----------------------------------------------------------------------
-- The game
----------------------------------------------------------------------

--- A piece's cells at a rotation (0-3, clockwise), relative to its box.
function TT.Cells(kind, rot)
	local p = TT.PIECES[kind]
	local out, n = {}, p.size - 1
	for i, c in ipairs(p.cells) do
		local x, y = c[1], c[2]
		for _ = 1, rot % 4 do x, y = n - y, x end
		out[i] = { x, y }
	end
	return out
end

local function Fits(kind, rot, px, py)
	for _, c in ipairs(TT.Cells(kind, rot)) do
		local x, y = px + c[1], py + c[2]
		if x < 0 or x >= COLS or y >= ROWS then return false end
		if y >= 0 and game.grid[y][x] then return false end
	end
	return true
end
TT.Fits = Fits

-- the next pieces come from shuffled bags of all seven: never a long wait for the one you need
local function NextKind()
	if #game.bag == 0 then
		local bag = {}
		for i, k in ipairs(ORDER) do bag[i] = k end
		for i = #bag, 2, -1 do
			local j = TT.rand(i)
			bag[i], bag[j] = bag[j], bag[i]
		end
		game.bag = bag
	end
	return table.remove(game.bag, 1)
end

--- A new piece at the top (the given kind, else the next one). No room for it: the game is over.
function TT.Spawn(kind)
	kind = kind or table.remove(game.queue, 1)
	while #game.queue < 1 do game.queue[#game.queue + 1] = NextKind() end
	local p = { kind = kind, rot = 0, x = math.floor((COLS - TT.PIECES[kind].size) / 2), y = kind == "I" and -1 or 0 }
	game.piece, game.fall, game.lockAt, game.resets = p, 0, nil, 0
	if not Fits(p.kind, p.rot, p.x, p.y) then TT.GameOver() end
end

function TT.Reset()
	game.grid = {}
	for y = 0, ROWS - 1 do game.grid[y] = {} end
	game.bag, game.queue = {}, {}
	game.score, game.lines, game.level = 0, 0, 1
	game.over, game.newBest, game.hold, game.held = false, false, nil, false
	game.down, game.keys = false, {}
	game.queue[1] = NextKind()
	TT.Spawn()
	game.dirty = true
end

--- Seconds between rows falling at this level (faster every 10 lines).
function TT.FallEvery(level)
	return math.max(0.05, 0.8 * (0.85 ^ ((level or 1) - 1)))
end

local function Grounded()
	local p = game.piece
	return not Fits(p.kind, p.rot, p.x, p.y + 1)
end

-- a move or turn of a landed piece restarts its wait, a limited number of times
local function Moved()
	game.dirty = true
	if game.lockAt and game.resets < LOCK_RESETS then
		game.resets = game.resets + 1
		game.lockAt = Grounded() and LOCK_DELAY or nil
	end
end

function TT.Move(dx)
	local p = game.piece
	if game.over or not p or not Fits(p.kind, p.rot, p.x + dx, p.y) then return false end
	p.x = p.x + dx
	Moved()
	return true
end

function TT.Rotate(dir)
	local p = game.piece
	if game.over or not p or p.kind == "O" then return false end
	local rot = (p.rot + dir) % 4
	for _, k in ipairs(KICKS) do
		if Fits(p.kind, rot, p.x + k[1], p.y + k[2]) then
			p.rot, p.x, p.y = rot, p.x + k[1], p.y + k[2]
			Moved()
			return true
		end
	end
	return false
end

--- Rows full across are cleared, the rows above come down; lines, score and level count up.
local function ClearLines()
	local cleared, y = 0, ROWS - 1
	while y >= 0 do
		local full = true
		for x = 0, COLS - 1 do if not game.grid[y][x] then full = false break end end
		if full then
			for yy = y, 1, -1 do game.grid[yy] = game.grid[yy - 1] end
			game.grid[0] = {}
			cleared = cleared + 1
		else
			y = y - 1
		end
	end
	if cleared > 0 then
		game.score = game.score + LINE_POINTS[math.min(cleared, 4)] * game.level
		game.lines = game.lines + cleared
		game.level = math.floor(game.lines / 10) + 1
	end
	return cleared
end

--- The piece becomes part of the stack; lines clear; the next one comes.
function TT.Lock()
	local p = game.piece
	for _, c in ipairs(TT.Cells(p.kind, p.rot)) do
		local x, y = p.x + c[1], p.y + c[2]
		if y < 0 then return TT.GameOver() end -- (locked above the top)
		game.grid[y][x] = p.kind
	end
	game.lastCleared = ClearLines()
	game.held = false
	game.dirty = true
	TT.Spawn()
end

--- One row down; landed, the lock wait starts. `soft`: Down held (a point a row).
function TT.Drop(soft)
	local p = game.piece
	if game.over or not p then return false end
	if Fits(p.kind, p.rot, p.x, p.y + 1) then
		p.y = p.y + 1
		if soft then game.score = game.score + 1 end
		game.dirty = true
		if Grounded() and not game.lockAt then game.lockAt = LOCK_DELAY end
		return true
	end
	game.lockAt = game.lockAt or LOCK_DELAY
	return false
end

--- Straight down and locked at once (two points a row).
function TT.HardDrop()
	local p = game.piece
	if game.over or not p then return end
	local rows = 0
	while Fits(p.kind, p.rot, p.x, p.y + 1) do p.y = p.y + 1; rows = rows + 1 end
	game.score = game.score + rows * 2
	TT.Lock()
end

--- The piece put aside for later (once per piece); the one held before comes out.
function TT.Hold()
	if game.over or game.held or not game.piece then return false end
	local kind = game.piece.kind
	local out = game.hold
	game.hold, game.held = kind, true
	TT.Spawn(out)
	game.held = true
	game.dirty = true
	return true
end

--- Where the piece would land (the faint copy under it).
function TT.GhostY()
	local p = game.piece
	local y = p.y
	while Fits(p.kind, p.rot, p.x, y + 1) do y = y + 1 end
	return y
end

function TT.GameOver()
	game.over = true
	game.dirty = true
	if ns.db and game.score > (ns.db.tetrisBest or 0) then
		ns.db.tetrisBest = game.score
		game.newBest = true
	end
end

--- Time passing: gravity (faster with Down held), the lock wait, and held keys repeating.
function TT.Tick(elapsed)
	if game.over or not game.piece then return end
	elapsed = math.min(elapsed or 0, 0.2) -- (a long frame isn't many rows at once)
	for action, k in pairs(game.keys) do
		if REPEATS[action] then
			k.t = k.t + elapsed
			while k.t >= DAS do
				TT.Move(action == "left" and -1 or 1)
				k.t = k.t - ARR
			end
		end
	end
	game.fall = game.fall + elapsed
	local every = game.down and math.min(SOFT_EVERY, TT.FallEvery(game.level)) or TT.FallEvery(game.level)
	while game.fall >= every and not game.over do
		game.fall = game.fall - every
		TT.Drop(game.down)
	end
	if game.lockAt and not game.over then
		if not Grounded() then
			game.lockAt = nil
		else
			game.lockAt = game.lockAt - elapsed
			if game.lockAt <= 0 then TT.Lock() end
		end
	end
	if game.dirty then TT.Draw() end
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

local function Tex(parent, pool, i, size)
	local t = pool[i]
	if not t then
		t = parent:CreateTexture(nil, "ARTWORK")
		t:SetColorTexture(1, 1, 1, 1)
		t:SetSize(size - 1, size - 1)
		pool[i] = t
	end
	return t
end

local function At(t, parent, x, y, size, ox, oy)
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", parent, "TOPLEFT", (ox or 0) + x * size + 1, -((oy or 0) + y * size) - 1)
end

local function Paint(t, kind, a)
	local c = TT.PIECES[kind].color
	t:SetVertexColor(c[1], c[2], c[3], a or 1)
end

-- a small piece in the side column (next, hold), centred in a 4x4 box of 10 px cells
local function Mini(pool, kind, top, dim)
	if not kind then
		for i = 1, 4 do if pool[i] then pool[i]:Hide() end end
		return
	end
	local cells, size = TT.Cells(kind, 0), 10
	local minx, maxx, miny, maxy = 9, -1, 9, -1
	for _, c in ipairs(cells) do
		minx, maxx = math.min(minx, c[1]), math.max(maxx, c[1])
		miny, maxy = math.min(miny, c[2]), math.max(maxy, c[2])
	end
	local ox = COLS * CELL + 12 + (SIDE - (maxx - minx + 1) * size) / 2 - minx * size
	local oy = top + (24 - (maxy - miny + 1) * size) / 2 - miny * size
	for i, c in ipairs(cells) do
		local t = Tex(frame, pool, i, size)
		At(t, frame, c[1], c[2], size, ox + 12, oy)
		Paint(t, kind, dim and 0.35 or 1)
		t:Show()
	end
end

function TT.Draw()
	if not frame then return end
	game.dirty = false
	local t = Theme.Get()
	-- the stack: one texture per cell, shown only where a block is
	local n = 0
	for y = 0, ROWS - 1 do
		local row = game.grid[y]
		for x = 0, COLS - 1 do
			n = n + 1
			local kind = row[x]
			local tx = cellTex[n]
			if kind then
				tx = Tex(board, cellTex, n, CELL)
				At(tx, board, x, y, CELL)
				Paint(tx, kind, 0.9)
				tx:Show()
			elseif tx then
				tx:Hide()
			end
		end
	end
	local p = game.piece
	if p and not game.over then
		local gy = TT.GhostY()
		for i, c in ipairs(TT.Cells(p.kind, p.rot)) do
			local g = Tex(board, ghostTex, i, CELL)
			local x, y = p.x + c[1], gy + c[2]
			At(g, board, x, y, CELL)
			Paint(g, p.kind, 0.18)
			g:SetShown(y >= 0)
			local s = Tex(board, pieceTex, i, CELL)
			y = p.y + c[2]
			At(s, board, x, y, CELL)
			Paint(s, p.kind, 1)
			s:SetShown(y >= 0)
		end
	else
		for i = 1, 4 do
			if pieceTex[i] then pieceTex[i]:Hide() end
			if ghostTex[i] then ghostTex[i]:Hide() end
		end
	end
	Mini(nextTex, game.queue[1], 52)
	Mini(holdTex, game.hold, 116, game.held)
	scoreText:SetText(("|cff%stetris|r"):format(t.accent))
	bestText:SetText(("best %d"):format(math.max(ns.db and ns.db.tetrisBest or 0, game.score)))
	linesText:SetText(("score\n%d\n\nlines\n%d"):format(game.score, game.lines))
	levelText:SetText(("level %d"):format(game.level))
	if game.over then
		overlay:SetText(game.newBest and "new best!" or "game over")
		overlaySub:SetText(("score %d\nEnter: again  ·  Esc: quit"):format(game.score))
		overlay:Show(); overlaySub:Show()
	else
		overlay:Hide(); overlaySub:Hide()
	end
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

local Text = Panel.Text

local function Build()
	if frame then return end
	frame = Panel.Build("TerminalTetris", TT)
	frame:SetSize(COLS * CELL + SIDE + 36, ROWS * CELL + 64)
	frame:SetScript("OnKeyDown", function(self, key) TT.KeyDown(self, key) end)
	frame:SetScript("OnKeyUp", function(_, key) TT.KeyUp(key) end)
	frame:SetScript("OnUpdate", function(_, elapsed) TT.Tick(elapsed) end)

	scoreText = Text(frame, 13)
	scoreText:SetPoint("TOPLEFT", 12, -10)
	bestText = Text(frame, 12, "RIGHT")
	bestText:SetPoint("TOPRIGHT", -12, -10)

	board = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	board:SetSize(COLS * CELL, ROWS * CELL)
	board:SetPoint("TOPLEFT", 12, -32)
	board:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })

	local sideX = COLS * CELL + 24
	nextLabel = Text(frame, 11, "CENTER")
	nextLabel:SetPoint("TOPLEFT", sideX, -36)
	nextLabel:SetWidth(SIDE)
	nextLabel:SetText("next")
	holdLabel = Text(frame, 11, "CENTER")
	holdLabel:SetPoint("TOPLEFT", sideX, -100)
	holdLabel:SetWidth(SIDE)
	holdLabel:SetText("hold (C)")
	linesText = Text(frame, 12, "CENTER")
	linesText:SetPoint("TOPLEFT", sideX, -170)
	linesText:SetWidth(SIDE)
	linesText:SetWordWrap(true)
	linesText:SetHeight(90)
	levelText = Text(frame, 12, "CENTER")
	levelText:SetPoint("TOPLEFT", sideX, -270)
	levelText:SetWidth(SIDE)

	overlay = Text(board, 16, "CENTER")
	overlay:SetPoint("CENTER", 0, 16)
	overlaySub = Text(board, 11, "CENTER")
	overlaySub:SetPoint("TOP", overlay, "BOTTOM", 0, -6)
	overlaySub:SetWordWrap(true)
	overlaySub:SetWidth(COLS * CELL - 8)
	footer = Text(frame, 11)
	footer:SetPoint("BOTTOMLEFT", 12, 9)
	footer:SetText("arrows move/turn  ·  Enter drop  ·  Esc quit")
	TT.frame = frame
end

local function Style()
	local t = Panel.Layout(frame)
	local br, bg, bb = Theme.RGB(t.border)
	local pr, pg, pb = Theme.RGB(t.promptBg or t.bg)
	board:SetBackdropColor(pr, pg, pb, 1)
	board:SetBackdropBorderColor(br, bg, bb, 1)
	local tr, tg, tb = Theme.RGB(t.text)
	local dr, dg, db = Theme.RGB(t.dim)
	for _, fs in ipairs({ scoreText, linesText, levelText, overlay }) do fs:SetTextColor(tr, tg, tb) end
	for _, fs in ipairs({ bestText, nextLabel, holdLabel, overlaySub, footer }) do fs:SetTextColor(dr, dg, db) end
end

--- The game's keys are kept; any other key goes on to the game. A key already held (the game's own repeats)
--- does nothing more: Tick repeats Left/Right itself.
function TT.KeyDown(self, key)
	local mine = true
	local action = KEYS[key]
	if key == "ESCAPE" or key == "`" then
		TT.Close()
	elseif game.over then
		if action == "drop" then TT.Reset(); TT.Draw() else mine = action ~= nil end
	elseif action then
		if not game.keys[action] then
			game.keys[action] = { t = 0 }
			if action == "left" then TT.Move(-1)
			elseif action == "right" then TT.Move(1)
			elseif action == "cw" then TT.Rotate(1)
			elseif action == "ccw" then TT.Rotate(-1)
			elseif action == "down" then game.down = true; game.fall = TT.FallEvery(game.level) -- (a row at once)
			elseif action == "drop" then TT.HardDrop()
			elseif action == "hold" then TT.Hold() end
			if game.dirty then TT.Draw() end
		end
	else
		mine = false
	end
	if self and self.SetPropagateKeyboardInput and not InCombatLockdown() then
		pcall(self.SetPropagateKeyboardInput, self, not mine)
	end
end

function TT.KeyUp(key)
	local action = KEYS[key]
	if not action then return end
	game.keys[action] = nil
	if action == "down" then game.down = false end
end

function TT.IsShown() return frame and frame:IsShown() or false end

function TT.Open()
	if InCombatLockdown() then
		ns:Print("Tetris takes over keys, which the game doesn't allow in combat.")
		return false
	end
	Build()
	Style()
	Panel.Opening(TT) -- (straight in: the terminal and the other panels go)
	TT.Reset()
	frame:Show()
	TT.Draw()
	return true
end

function TT.Close(why)
	if not frame or not frame:IsShown() then return end
	frame:Hide()
	game.keys, game.down = {}, false
	if why == "combat" then ns:Print("Tetris closed: combat started.") end
end

ns:RegisterCommand("tetris", {
	desc = "Play Tetris (arrows or WASD move and turn, Enter drops, C holds, Esc or ` quits)",
	run = function() TT.Open() end,
})
