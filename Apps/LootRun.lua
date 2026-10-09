local ns = select(2, ...)

-- .lootrun: Loot Run, a maze chase in a small window where the terminal sits (the .snake pattern). You're the map's
-- arrow, picking up every coin in a dungeon while four raid-marked mobs (skull, cross, square, moon) wake in its
-- corners, one after another, and come for you, each its own way. A Divine Shield turns them for a few seconds: bump
-- into one and it's gone for a while (points); a loot chest shows up now and then. Every coin picked up: the next
-- level, faster. WASD or the arrow keys move, Enter plays again after a game over, Esc or ` quits. Only the game's
-- keys are taken: any other key still reaches the game. The best score is kept. An easter egg: not in the changelog
-- (as .tetris).
--
-- Choosing which keys pass on (SetPropagateKeyboardInput) isn't allowed in combat, so the game doesn't start in
-- combat and closes when combat starts (Panel).

local LR = {}
ns.LootRun = LR

local Theme = ns.Theme
local Panel = ns.Panel
local CELL = 16

-- The dungeon: # wall, . a coin, o a Divine Shield, P where you start, M a mob's corner (where it sleeps, letting you
-- by, and comes back to once beaten), C where a chest shows up. Every open cell can be reached (a test walks it).
LR.MAZE = {
	"#####################",
	"#M........#........M#",
	"#.###.###.#.###.###.#",
	"#.#o#...........#o#.#",
	"#.#.#.#.#####.#.#.#.#",
	"#...#.#.......#.#...#",
	"###.#.#.##.##.#.#.###",
	"#.....#.#...#.#.....#",
	"#.#.#...#.P.#...#.#.#",
	"#.#.#.#.##.##.#.#.#.#",
	"#...#.#...C...#.#...#",
	"#.#.#.###.#.###.#.#.#",
	"#.#.....#...#.....#.#",
	"#.###.#.#.#.#.#.###.#",
	"#.....#...o...#.....#",
	"#.###.###.#.###.###.#",
	"#M........#........M#",
	"#####################",
}
local W, H = #LR.MAZE[1], #LR.MAZE
LR.W, LR.H = W, H

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } -- right, left, down, up
local BACK = { 2, 1, 4, 3 }
local FACING = { -math.pi / 2, math.pi / 2, math.pi, 0 } -- the arrow's turn for each way (it points up unturned)
local KEYS = { RIGHT = 1, D = 1, LEFT = 2, A = 2, DOWN = 3, S = 3, UP = 4, W = 4 }

-- The mobs, by their raid marker, one to a corner. Each wanders until you come within its aggro range (steps along
-- the corridors; a step more each level), then comes after you, taking the way to you at a crossing as often as its
-- hunt says, until you're LEASH steps beyond that range. How fast each is, how long it sleeps at the start; the square
-- has you the moment it sees you down a straight way, and the moon gets faster, and notices you farther, once few
-- coins are left.
LR.MOBS = {
	{ id = "skull", icon = 8, aggro = 9, hunt = 0.9, speed = 4.9, wake = 2 },
	{ id = "cross", icon = 7, aggro = 6, hunt = 0.8, speed = 4.7, wake = 5 },
	{ id = "square", icon = 6, aggro = 2, hunt = 0.9, speed = 4.6, wake = 9, sight = 7 },
	{ id = "moon", icon = 5, aggro = 4, hunt = 0.8, speed = 4.5, wake = 13, enrage = 0.25 },
}
LR.LEASH = 3

LR.SPEED, LR.SPEED_UP, LR.SPEED_MAX = 6.5, 0.2, 7.5 -- yours, cells a second; a little faster each level
LR.MOB_UP, LR.MOB_MAX, LR.AFRAID_SPEED, LR.ENRAGED = 0.3, 7, 3.2, 1.3
LR.SHIELD, LR.SHIELD_MIN = 8, 3 -- the Divine Shield's seconds (one less each level)
LR.RESPAWN, LR.RESPAWN_CLEAR = 4, 3 -- a beaten mob is back in its corner after this long, once you're this far away
LR.CHEST_AT, LR.CHEST_TIME = { 60, 140 }, 9 -- coins picked up when a chest shows; how long it stays
LR.POINTS = { coin = 10, shield = 50, chest = 500, mob = 200, level = 500 }
LR.READY, LR.AGAIN, LR.DYING, LR.CLEARED = 1.6, 1.2, 1.2, 1.5 -- the pauses: a level starting, a life, a hit, cleared
LR.STEP = 0.02 -- a frame is worked out in steps this long: two fast things never pass through each other
LR.HIT = 0.6 -- this close (cells, either way): caught, or, shielded, a mob beaten
LR.TURN = 0.25 -- a turn asked for this soon after a crossing is still taken there
LR.LIVES = 3

local game = { player = {}, mobs = {}, coins = {}, changed = {} } -- (changed: cells picked up since the last drawing)
LR.game = game

LR.rand = function(n) return math.random(n) end -- (tests replace it)
local function Chance(p) return LR.rand(1000) <= p * 1000 end

local frame, board, cover, scoreText, bestText, overlay, overlaySub, footer, livesText
local wallTex, coinTex = {}, {}
local playerTex, bubbleTex, chestTex, mobTex = nil, nil, nil, {}

-- runs only while a game is on: game over takes it off (nothing moves then), Reset puts it back
local function OnUpdate(_, elapsed) LR.Tick(elapsed) end

----------------------------------------------------------------------
-- The dungeon
----------------------------------------------------------------------

local grid = {} -- [y][x] = its character in LR.MAZE
local start, homes, chestAt = nil, {}, nil
for y = 0, H - 1 do
	grid[y] = {}
	for x = 0, W - 1 do
		local c = LR.MAZE[y + 1]:sub(x + 1, x + 1)
		grid[y][x] = c
		if c == "P" then start = { x, y }
		elseif c == "M" then homes[#homes + 1] = { x, y }
		elseif c == "C" then chestAt = { x, y } end
	end
end
LR.start, LR.homes, LR.chestAt = start, homes, chestAt

local function Open(x, y) return x >= 0 and y >= 0 and x < W and y < H and grid[y][x] ~= "#" end
LR.Walkable = Open -- (not LR.Open: that opens the window)
local function Can(x, y, d) local v = DIRS[d]; return Open(x + v[1], y + v[2]) end

--- Where a mover is now (cells, fractions on the way to the next).
local function Pos(a)
	local d = a.dir and DIRS[a.dir]
	if not d or a.t == 0 then return a.x, a.y end
	return a.x + d[1] * a.t, a.y + d[2] * a.t
end
LR.Pos = Pos

-- the cell you count as in: the next one once you're past halfway to it
local function PlayerCell()
	local p = game.player
	local d = p.dir and DIRS[p.dir]
	if d and p.t >= 0.5 then return p.x + d[1], p.y + d[2] end
	return p.x, p.y
end

-- how many steps from you each cell is (walls: none), worked out again only when you're in another cell
local dist, queue = {}, {}
local function Distances()
	local cx, cy = PlayerCell()
	local from = cy * W + cx
	if game.distFrom == from then return dist end
	game.distFrom = from
	for i = 0, W * H - 1 do dist[i] = nil end
	dist[from] = 0
	queue[1] = from
	local head, tail = 1, 1
	while head <= tail do
		local k = queue[head]
		head = head + 1
		local x, y = k % W, math.floor(k / W)
		for d = 1, 4 do
			local v = DIRS[d]
			local nx, ny = x + v[1], y + v[2]
			local nk = ny * W + nx
			if dist[nk] == nil and Open(nx, ny) then
				dist[nk] = dist[k] + 1
				tail = tail + 1
				queue[tail] = nk
			end
		end
	end
	return dist
end
LR.Distances = Distances

----------------------------------------------------------------------
-- The game
----------------------------------------------------------------------

local function Score(n) game.score = game.score + n end

local function MobSpeed(m)
	if m.afraid then return LR.AFRAID_SPEED end
	local s = math.min(LR.MOB_MAX, m.def.speed + LR.MOB_UP * (game.level - 1))
	if m.def.enrage and game.left <= game.total * m.def.enrage then s = s * LR.ENRAGED end
	return s
end
LR.MobSpeed = MobSpeed

-- how far (steps along the corridors) a mob notices you from
local function AggroRange(m)
	local r = m.def.aggro + (game.level - 1)
	if m.def.enrage and game.left <= game.total * m.def.enrage then r = r + 3 end
	return r
end

--- Whether a mob sees you: in your row or column, no wall between, no farther than it looks.
function LR.Sees(m)
	local cx, cy = PlayerCell()
	local mx, my = m.x, m.y
	if mx ~= cx and my ~= cy then return false end
	local n = math.abs(cx - mx) + math.abs(cy - my)
	if n > (m.def.sight or 0) then return false end
	local sx, sy = (cx > mx and 1) or (cx < mx and -1) or 0, (cy > my and 1) or (cy < my and -1) or 0
	for i = 1, n - 1 do
		if not Open(mx + sx * i, my + sy * i) then return false end
	end
	return true
end

-- the way among `opts` that leads closest to you (sign 1) or farthest (-1)
local function Best(m, opts, n, sign)
	local dd = Distances()
	local best, bestV
	for i = 1, n do
		local v = DIRS[opts[i]]
		local d = (dd[(m.y + v[2]) * W + m.x + v[1]] or 999) * sign
		if not bestV or d < bestV then best, bestV = opts[i], d end
	end
	return best
end

local opts = {}
--- A mob at a cell picks its way on: never straight back unless it's a dead end. It notices you within its aggro
--- range (keeps after you until you're LEASH steps past it; the square: whenever it sees you); then it takes the way
--- to you as often as its hunt says (always, for the square seeing you). Afraid: away from you. Else any way.
function LR.Choose(m)
	local back = m.dir and BACK[m.dir]
	local n = 0
	for d = 1, 4 do
		if d ~= back and Can(m.x, m.y, d) then n = n + 1; opts[n] = d end
	end
	local steps = Distances()[m.y * W + m.x] or 999
	local range = AggroRange(m)
	local sees = m.def.sight and LR.Sees(m)
	m.aggro = sees or steps <= range or (m.aggro and steps <= range + LR.LEASH) or false
	if n == 0 then m.dir = back return end
	if n == 1 then m.dir = opts[1] return end
	local pick
	if m.afraid then
		if Chance(0.8) then pick = Best(m, opts, n, -1) end
	elseif sees or (m.aggro and Chance(math.min(0.97, m.def.hunt + 0.02 * (game.level - 1)))) then
		pick = Best(m, opts, n, 1)
	end
	m.dir = pick or opts[LR.rand(n)]
end

-- a mob back in its corner, at rest (sleeping `sleep` seconds first)
local function Home(m, sleep)
	m.x, m.y, m.t, m.dir = m.home[1], m.home[2], 0, nil
	m.sleep, m.gone, m.afraid, m.aggro = sleep or 0, nil, false, false
end

-- you and the mobs where a life starts: you in the middle, each mob asleep in its corner
local function Places()
	local p = game.player
	p.x, p.y, p.t, p.dir, p.want, p.face = start[1], start[2], 0, nil, nil, 4
	local scale = 0.8 ^ (game.level - 1) -- (they wake sooner each level)
	for i, m in ipairs(game.mobs) do Home(m, m.def.wake * scale) end
	game.shield, game.combo, game.chest = 0, 0, nil
	game.distFrom = nil
end

local function NewLevel()
	for k in pairs(game.coins) do game.coins[k] = nil end
	local n = 0
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local c = grid[y][x]
			if c == "." then game.coins[y * W + x] = "coin"; n = n + 1
			elseif c == "o" then game.coins[y * W + x] = "shield" end
		end
	end
	game.left, game.total, game.picked, game.chests = n, n, 0, 0
	game.speed = math.min(LR.SPEED_MAX, LR.SPEED + LR.SPEED_UP * (game.level - 1))
	game.coinsDirty = true
	Places()
	game.state, game.wait = "ready", LR.READY
end

function LR.Reset()
	game.score, game.level, game.lives = 0, 1, LR.LIVES
	game.over, game.newBest, game.clock = false, false, 0
	for i, def in ipairs(LR.MOBS) do
		game.mobs[i] = game.mobs[i] or {}
		game.mobs[i].def, game.mobs[i].home = def, homes[i]
	end
	NewLevel()
	if frame then frame:SetScript("OnUpdate", OnUpdate) end
end

--- The Divine Shield: for a while every mob is afraid of you, and bumping into one beats it.
function LR.Shield()
	game.shield = math.max(LR.SHIELD_MIN, LR.SHIELD - (game.level - 1))
	game.combo = 0
	for _, m in ipairs(game.mobs) do if not m.gone then m.afraid = true end end
end

-- a cell walked into: its coin or shield picked up (the last coin clears the level)
local function Enter(x, y)
	local k = y * W + x
	local what = game.coins[k]
	if not what then return end
	game.coins[k] = nil
	game.changed[#game.changed + 1] = k
	if what == "shield" then
		Score(LR.POINTS.shield)
		LR.Shield()
		return
	end
	Score(LR.POINTS.coin)
	game.left, game.picked = game.left - 1, game.picked + 1
	local at = LR.CHEST_AT[game.chests + 1]
	if at and game.picked >= at then
		game.chests = game.chests + 1
		game.chest = LR.CHEST_TIME
	end
	if game.left <= 0 then
		Score(LR.POINTS.level * game.level)
		game.state, game.wait = "cleared", LR.CLEARED
	end
end

--- Your move for `dt` seconds: a turn straight back is taken at once; a turn just past a crossing is taken from
--- there; walking on, the way you asked for is taken at the first cell it's open from, else straight on to a wall.
local function MovePlayer(dt)
	local p = game.player
	local want = p.want
	if want and want ~= p.dir then
		if p.dir and want == BACK[p.dir] and p.t > 0 then
			local v = DIRS[p.dir]
			p.x, p.y, p.t, p.dir = p.x + v[1], p.y + v[2], 1 - p.t, want
		elseif (not p.dir or p.t < LR.TURN) and Can(p.x, p.y, want) then
			p.t, p.dir = 0, want
		end
	end
	if not p.dir then return end
	if p.t == 0 and not Can(p.x, p.y, p.dir) then p.dir = nil return end
	p.face = p.dir
	p.t = p.t + game.speed * dt
	while p.t >= 1 do
		local v = DIRS[p.dir]
		p.x, p.y, p.t = p.x + v[1], p.y + v[2], p.t - 1
		Enter(p.x, p.y)
		if game.state ~= "play" then p.t = 0 return end
		if want and Can(p.x, p.y, want) then
			p.dir = want
		elseif not Can(p.x, p.y, p.dir) then
			p.t, p.dir = 0, nil
			return
		end
		p.face = p.dir
	end
end

local function MoveMob(m, dt)
	if m.gone then
		m.gone = m.gone - dt
		if m.gone <= 0 then
			-- (back in its corner only once you're away from it)
			local px, py = Pos(game.player)
			if math.abs(px - m.home[1]) + math.abs(py - m.home[2]) >= LR.RESPAWN_CLEAR then Home(m, 0) end
		end
		return
	end
	if m.sleep > 0 then
		m.sleep = m.sleep - dt
		if m.sleep > 0 then return end
		m.sleep = 0
	end
	if not m.dir then
		LR.Choose(m)
		if not m.dir then return end
	end
	m.t = m.t + MobSpeed(m) * dt
	while m.t >= 1 do
		local v = DIRS[m.dir]
		m.x, m.y, m.t = m.x + v[1], m.y + v[2], m.t - 1
		LR.Choose(m)
	end
end

--- A shielded bump: the mob is gone for a while; each one more this shield is worth more.
function LR.Beat(m)
	game.combo = game.combo + 1
	Score(LR.POINTS.mob * game.combo)
	Home(m, 0)
	m.gone = LR.RESPAWN
end

--- Caught: a life less; after a moment the next one (or the game is over).
function LR.Caught()
	game.lives = game.lives - 1
	game.state, game.wait = "dying", LR.DYING
end

local function Touching(ax, ay, bx, by) return math.abs(ax - bx) < LR.HIT and math.abs(ay - by) < LR.HIT end

local function Step(dt)
	MovePlayer(dt)
	if game.state ~= "play" then return end
	if game.shield > 0 then
		game.shield = game.shield - dt
		if game.shield <= 0 then
			game.shield = 0
			for _, m in ipairs(game.mobs) do m.afraid = false end
		end
	end
	if game.chest then
		game.chest = game.chest - dt
		if game.chest <= 0 then game.chest = nil end
	end
	for _, m in ipairs(game.mobs) do MoveMob(m, dt) end
	local px, py = Pos(game.player)
	if game.chest and Touching(px, py, chestAt[1], chestAt[2]) then
		game.chest = nil
		Score(LR.POINTS.chest)
	end
	-- (a mob still asleep in its corner lets you by, unless you're shielded: then it's beaten too)
	for _, m in ipairs(game.mobs) do
		if not m.gone and (m.afraid or m.sleep <= 0) then
			local mx, my = Pos(m)
			if Touching(px, py, mx, my) then
				if m.afraid then LR.Beat(m) else return LR.Caught() end
			end
		end
	end
end

function LR.GameOver()
	game.over, game.state = true, "over"
	if frame then frame:SetScript("OnUpdate", nil) end -- (nothing moves on the game-over screen)
	if ns.db and game.score > (ns.db.lootrunBest or 0) then
		ns.db.lootrunBest = game.score
		game.newBest = true
	end
end

--- Time passing: the pauses count down; in play, everything moves in short steps.
function LR.Tick(elapsed)
	if game.over then return end
	elapsed = math.min(elapsed or 0, 0.2) -- (a long frame isn't a long way at once, into a mob unseen)
	game.clock = game.clock + elapsed
	if game.state ~= "play" then
		game.wait = game.wait - elapsed
		if game.wait <= 0 then
			if game.state == "dying" then
				if game.lives <= 0 then
					LR.GameOver()
				else
					Places()
					game.state, game.wait = "ready", LR.AGAIN
				end
			elseif game.state == "cleared" then
				game.level = game.level + 1
				NewLevel()
			else
				game.state = "play"
			end
		end
	else
		local left = elapsed
		while left > 0 and game.state == "play" do
			local dt = math.min(LR.STEP, left)
			left = left - dt
			Step(dt)
		end
	end
	LR.Draw()
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

local function Tex(path, size, layer, sub)
	local t = board:CreateTexture(nil, layer or "ARTWORK", nil, sub)
	if path then t:SetTexture(path) else t:SetColorTexture(1, 1, 1, 1) end
	t:SetSize(size, size)
	return t
end

-- (centred on a spot of the board, in cells; placed again only when it moved)
local function At(t, x, y)
	if t.ax == x and t.ay == y then return end
	t.ax, t.ay = x, y
	t:ClearAllPoints()
	t:SetPoint("CENTER", board, "TOPLEFT", (x + 0.5) * CELL, -(y + 0.5) * CELL)
end

local shieldTex = {} -- { k = cell, t = texture } of the Divine Shields (they glow)
-- the walls and a texture for every coin and shield, made once where they stay; then the chest, the mobs, the
-- shield's glow around you and you (you over the mobs)
local function BuildBoard()
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local c = grid[y][x]
			if c == "#" then
				local t = Tex(nil, CELL - 1)
				At(t, x, y)
				wallTex[#wallTex + 1] = t
			elseif c == "." or c == "o" then
				local t = c == "o" and Tex("Interface\\Icons\\Spell_Holy_DivineIntervention", 12)
					or Tex("Interface\\MoneyFrame\\UI-CopperIcon", 8)
				At(t, x, y)
				coinTex[y * W + x] = t
				if c == "o" then shieldTex[#shieldTex + 1] = { k = y * W + x, t = t } end
			end
		end
	end
	chestTex = Tex("Interface\\Icons\\INV_Box_02", 14, "ARTWORK", 1)
	At(chestTex, chestAt[1], chestAt[2])
	chestTex:Hide()
	for i, def in ipairs(LR.MOBS) do mobTex[i] = Tex("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. def.icon, 14, "OVERLAY", 1) end
	bubbleTex = Tex("Interface\\Icons\\Spell_Holy_DivineIntervention", 22, "OVERLAY", 0)
	bubbleTex:Hide()
	playerTex = Tex("Interface\\Minimap\\MinimapArrow", 20, "OVERLAY", 2)
end

local function DrawCoins()
	local changed = game.changed
	if game.coinsDirty then
		game.coinsDirty = false
		for k, t in pairs(coinTex) do t:SetShown(game.coins[k] ~= nil) end
		for i = #changed, 1, -1 do changed[i] = nil end
	else
		for i = #changed, 1, -1 do
			local t = coinTex[changed[i]]
			if t then t:Hide() end
			changed[i] = nil
		end
	end
	-- the shields still there glow, slowly
	local a = 0.65 + 0.35 * math.sin(game.clock * 4)
	for _, s in ipairs(shieldTex) do if game.coins[s.k] then s.t:SetAlpha(a) end end
end

-- a mob's look: afraid (bluish, faded), asleep (faded), else as it is; set only when it changes
local function Look(t, m)
	local look = (m.afraid and 1) or (m.sleep > 0 and 2) or 3
	if t.look == look then return end
	t.look = look
	if look == 1 then t:SetVertexColor(0.55, 0.65, 1, 0.8)
	else t:SetVertexColor(1, 1, 1, look == 2 and 0.5 or 1) end
end

local function DrawMovers()
	local p = game.player
	local px, py = Pos(p)
	At(playerTex, px, py)
	if playerTex.face ~= p.face then playerTex:SetRotation(FACING[p.face] or 0); playerTex.face = p.face end
	-- caught: the arrow blinks out
	playerTex:SetAlpha(game.state == "dying" and (math.floor(game.wait * 8) % 2 == 0 and 0.2 or 1) or 1)
	if game.shield > 0 then
		At(bubbleTex, px, py)
		-- (its last two seconds: it flickers)
		bubbleTex:SetAlpha((game.shield > 2 or math.floor(game.shield * 6) % 2 == 0) and 0.45 or 0.15)
		bubbleTex:Show()
	else
		bubbleTex:Hide()
	end
	for i, m in ipairs(game.mobs) do
		local t = mobTex[i]
		if m.gone then
			t:Hide()
		else
			At(t, Pos(m))
			Look(t, m)
			t:Show()
		end
	end
	chestTex:SetShown(game.chest ~= nil)
end

-- the header, the lives and the words over the board: written again only when what they say changes
local said = {}
local function DrawWords()
	local best = math.max(ns.db and ns.db.lootrunBest or 0, game.score)
	local accent = Theme.Get().accent
	if said.score ~= game.score or said.level ~= game.level or said.best ~= best or said.lives ~= game.lives
		or said.state ~= game.state or said.accent ~= accent then
		said.score, said.level, said.best, said.lives, said.state, said.accent = game.score, game.level, best, game.lives, game.state, accent
		scoreText:SetText(("|cff%sloot run|r   score %d"):format(accent, game.score))
		bestText:SetText(("best %d"):format(best))
		livesText:SetText(("lvl %d  ·  lives %d"):format(game.level, math.max(0, game.lives)))
		local big, small
		if game.over then
			big = game.newBest and "new best!" or "game over"
			small = ("score %d  ·  Enter: again  ·  Esc: quit"):format(game.score)
		elseif game.state == "ready" then
			big = game.level > 1 and ("level %d"):format(game.level) or "ready"
			small = "every coin, and mind the marks"
		elseif game.state == "cleared" then
			big = "level cleared!"
			small = ("+%d"):format(LR.POINTS.level * game.level)
		end
		overlay:SetText(big or "")
		overlaySub:SetText(small or "")
		cover:SetShown(big ~= nil)
	end
end

function LR.Draw()
	if not frame then return end
	DrawCoins()
	DrawMovers()
	DrawWords()
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------

local Text = Panel.Text

local function Build()
	if frame then return end
	frame = Panel.Build("TerminalLootRun", LR)
	frame:SetSize(W * CELL + 24, H * CELL + 64)
	frame:SetScript("OnKeyDown", function(self, key) LR.KeyDown(self, key) end)
	frame:SetScript("OnUpdate", OnUpdate)

	scoreText, bestText = Panel.Header(frame)

	board = Panel.Board(frame)
	board:SetSize(W * CELL, H * CELL)
	board:SetPoint("TOP", 0, -32)
	BuildBoard()
	LR.tex = { coins = coinTex, mobs = mobTex, player = playerTex, chest = chestTex } -- (tests)

	-- the words over the board, on a dark band: a frame of their own, above everything on the board
	cover = CreateFrame("Frame", nil, board)
	cover:SetAllPoints(board)
	local shade = cover:CreateTexture(nil, "BACKGROUND")
	shade:SetColorTexture(0, 0, 0, 0.65)
	shade:SetSize(W * CELL - 40, 46)
	shade:SetPoint("CENTER", 0, 0)
	overlay = Text(cover, 16, "CENTER")
	overlay:SetPoint("CENTER", 0, 9)
	overlaySub = Text(cover, 11, "CENTER")
	overlaySub:SetPoint("CENTER", 0, -11)
	footer = Panel.Footer(frame, 9, "arrows or WASD  ·  Esc quits")
	livesText = Text(frame, 11, "RIGHT")
	livesText:SetPoint("BOTTOMRIGHT", -12, 9)
	LR.frame = frame
end

local function Style()
	local t = Panel.Layout(frame) -- (its size is the board's, set once)
	Panel.StyleBoard(board, t)
	local tr, tg, tb = Theme.RGB(t.text)
	local dr, dg, db = Theme.RGB(t.dim)
	-- (the walls: the theme's faint text colour, readable on its background, light or dark)
	for _, w in ipairs(wallTex) do w:SetVertexColor(dr, dg, db, 0.5) end
	for k in pairs(said) do said[k] = nil end -- (the header in the theme's colours again)
	scoreText:SetTextColor(tr, tg, tb)
	bestText:SetTextColor(dr, dg, db)
	overlay:SetTextColor(1, 1, 1)
	overlaySub:SetTextColor(0.85, 0.85, 0.85)
	footer:SetTextColor(dr, dg, db)
	livesText:SetTextColor(dr, dg, db)
end

--- The game's keys are kept; any other key goes on to the game. A way asked for is kept until it can be taken
--- (asked during a pause too: off at once when it ends).
function LR.KeyDown(self, key)
	local mine = true
	if key == "ESCAPE" or key == "`" then
		LR.Close()
	elseif KEYS[key] then
		if not game.over then game.player.want = KEYS[key] end
	elseif key == "ENTER" or key == "NUMPADENTER" then
		if game.over then LR.Reset(); LR.Draw() else mine = false end
	else
		mine = false
	end
	Panel.Propagate(self, mine)
end

function LR.IsShown() return Panel.Shown(frame) end

function LR.Open()
	if not Panel.CanOpen("Loot Run takes over keys, which the game doesn't allow in combat.") then return false end
	Build()
	Style()
	Panel.Opening(LR) -- (straight in: the terminal and the other panels go)
	LR.Reset()
	frame:Show()
	LR.Draw()
	return true
end

function LR.Close(why)
	Panel.Close(frame, why, "Loot Run")
end

ns:RegisterCommand("lootrun", {
	desc = "Play Loot Run, a maze chase (WASD or arrows move, Esc or ` quits)",
	aliases = { "maze" },
	run = function() LR.Open() end,
})
