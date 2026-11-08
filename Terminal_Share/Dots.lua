-- (Terminal: Share, an addon of its own: Terminal's namespace is its public table, _G.Terminal. Not loaded, nothing of
-- this runs.)
-- Friends on the world map (1.2.3, the player: "player locations should show up as a dot. Regular class-colored dot"):
-- each friend who shares where they are (.share settings location) is a dot in their class's colour where they stand,
-- on the world map while it's open; pointed at, who and where; clicked, a waypoint on them. Nothing runs while the map
-- is closed: the dots are placed by a frame of the map's own, a few times a second while it shows.
--
-- Nothing of the map's own is written (Terminal's taint rule: its code never writes a Blizzard window's state): the dots
-- are Terminal's own frames on the map's canvas, placed from C_Map's answers (a friend's zone to the map shown). With
-- OpenMap's stitched map showing, OpenMapAPI's public calls place them on it instead (CanvasFromWorldPos, ArtTopLevel:
-- its docs say they're for an addon that puts frames on the canvas).
local ns = _G.Terminal
if not ns or not ns.Ssh then return end
local L = ns.L

local SSH = ns.Ssh
local Safe, Num = ns.Safe, ns.Num

local D = {}
SSH.Dots = D

D.SIZE = 12        -- the dot, on screen, at any zoom
D.EVERY = 0.2      -- s between placings while the map shows
local MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- (a round white disc: coloured, a dot)

local pins = {}
local driver

local function Canvas()
	local W = _G.WorldMapFrame
	local sc = W and W.ScrollContainer
	if type(sc) ~= "table" then return nil end
	return sc.Child, W, sc
end

local function ClassRGB(class)
	local c = type(class) == "string" and ((C_ClassColor and C_ClassColor.GetClassColor and Safe(C_ClassColor.GetClassColor, class))
		or (_G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]))
	if c then return c.r, c.g, c.b end
	return 1, 1, 1 -- (a class not sent: white)
end

local function Vec(x, y)
	if _G.CreateVector2D then return _G.CreateVector2D(x, y) end
	return { x = x, y = y }
end

local function XY(v)
	if type(v) ~= "table" then return nil end
	local x, y = v.x, v.y
	if v.GetXY then x, y = v:GetXY() end
	return Num(x), Num(y)
end

--- Where a friend's place (a zone's map, x, y) is on the map shown: x, y on its canvas (0-1), or nil when it isn't on
--- it (another continent, a map that doesn't show that zone).
function D.OnMap(map, x, y, shown)
	local M = C_Map
	if not (M and shown and map) then return nil end
	local OM = _G.OpenMapAPI
	local stitched = OM and OM.IsStitched and OM.CanvasFromWorldPos and Safe(OM.IsStitched)
	if map == shown and not stitched then return x, y end -- (OpenMap's stitched canvas isn't the zone's: asked of it)
	if not (M.GetWorldPosFromMapPos and (stitched or M.GetMapPosFromWorldPos)) then return nil end
	local cont, world = Safe(M.GetWorldPosFromMapPos, map, Vec(x, y))
	cont = Num(cont)
	if not (cont and world) then return nil end
	if stitched then
		-- (past 0-1 is still on it: the stitched view shows beyond its own map's rectangle, its docs say)
		local wx, wy = XY(world)
		if not wx then return nil end
		local u, v = Safe(OM.CanvasFromWorldPos, cont, wx, wy)
		u, v = Num(u), Num(v)
		if u and v and u > -1 and u < 2 and v > -1 and v < 2 then return u, v end
		return nil
	end
	local _, pos = Safe(M.GetMapPosFromWorldPos, cont, world, shown)
	local u, v = XY(pos)
	if not (u and v) or u < 0 or u > 1 or v < 0 or v > 1 then return nil end
	return u, v
end

local function Enter(pin)
	local w = pin.place
	if not w then return end
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	GameTooltip:AddLine(w.name, ClassRGB(w.class))
	local I = ns.Integrations
	local zone = I and I.ZoneName and I.ZoneName(w.map)
	GameTooltip:AddLine(("%s  %.1f, %.1f"):format(zone or "?", w.x * 100, w.y * 100), 1, 1, 1)
	local ep = SSH.game
	local ago = ep and (ep:Now() - w.at) or 0
	if ago >= 60 then GameTooltip:AddLine(L["Updated %s"]:format(ns.Ago(ago)), 0.8, 0.8, 0.8) end
	GameTooltip:AddLine(L["Terminal: Share. Click: a waypoint on them"], 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function Leave() GameTooltip:Hide() end

-- a click: the map pin on them (a C call: Maps.Place), or TomTom's arrow as Terminal's waypoints go
local function Click(pin)
	local w = pin.place
	local M = ns.Maps
	if not (w and M and M.Place) then return end
	local placed = M.Place({ name = w.name, mapID = w.map, pos = { x = w.x, y = w.y } })
	if placed and M.PinLine then
		local I = ns.Integrations
		ns:Print(M.PinLine(placed, w.name, I and I.ZoneName and I.ZoneName(w.map)))
	end
end

local function Pin(i, canvas)
	local pin = pins[i]
	if pin then
		if pin:GetParent() ~= canvas then pin:SetParent(canvas) end
		return pin
	end
	pin = CreateFrame("Button", nil, canvas)
	local edge = pin:CreateTexture(nil, "ARTWORK")
	edge:SetAllPoints()
	edge:SetTexture(MASK)
	edge:SetVertexColor(0, 0, 0, 0.9)
	local dot = pin:CreateTexture(nil, "OVERLAY")
	dot:SetPoint("TOPLEFT", 1.5, -1.5)
	dot:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
	dot:SetTexture(MASK)
	pin.dot = dot
	pin:SetScript("OnEnter", Enter)
	pin:SetScript("OnLeave", Leave)
	pin:SetScript("OnClick", Click)
	pins[i] = pin
	return pin
end

local function HideFrom(i)
	for j = i, #pins do pins[j]:Hide(); pins[j].place = nil end
end

--- The dots placed on the map shown, a friend each (none while it's closed, or nobody shares theirs).
function D.Refresh()
	local canvas, W, sc = Canvas()
	if not (canvas and W and W:IsShown()) then HideFrom(1); D.lastSig = nil return end
	local ep = SSH.game
	local shown = W.GetMapID and Num(Safe(W.GetMapID, W))
	local cw, ch = canvas:GetWidth(), canvas:GetHeight()
	if not (shown and cw and ch and cw > 0 and ch > 0) then HideFrom(1); D.lastSig = nil return end
	-- (the dot the same size on screen at any zoom: the canvas scales with it)
	local scale = sc.GetCanvasScale and Num(Safe(sc.GetCanvasScale, sc)) or 1
	local size = D.SIZE / ((scale and scale > 0) and scale or 1)
	local OM = _G.OpenMapAPI
	local stitched = OM and OM.IsStitched and Safe(OM.IsStitched)
	-- (the same places on the same map at the same size and zoom: nothing to do. Every 0.2 s it worked each friend's
	-- spot out again and set every dot: 1.2.5 review. OpenMap's stitched view moves under the same map: each time)
	local sig = tostring(ep and ep.placesGen or 0) .. ":" .. shown .. ":" .. cw .. ":" .. ch .. ":" .. tostring(scale)
	if not stitched and sig == D.lastSig then return D.lastUsed end
	local list = ep and ep:Places() or {}
	local level = canvas:GetFrameLevel() + 20
	if OM and OM.ArtTopLevel then level = math.max(level, (Num(Safe(OM.ArtTopLevel)) or 0) + 1) end
	local used = 0
	for _, w in ipairs(list) do
		local u, v = D.OnMap(w.map, w.x, w.y, shown)
		if u then
			used = used + 1
			local pin = Pin(used, canvas)
			pin.place = w
			pin:SetSize(size, size)
			pin:SetFrameLevel(level)
			pin:ClearAllPoints()
			pin:SetPoint("CENTER", canvas, "TOPLEFT", u * cw, -v * ch)
			pin.dot:SetVertexColor(ClassRGB(w.class))
			pin:Show()
		end
	end
	HideFrom(used + 1)
	D.lastSig, D.lastUsed = sig, used
	return used
end

--- The frame that places them: the map's child, so it runs only while the map shows (no hook on the map itself).
function D.Start()
	local W = _G.WorldMapFrame
	if driver or not W then return driver end
	driver = CreateFrame("Frame", nil, W)
	local wait = 0
	driver:SetScript("OnShow", function() wait = 0 end)
	driver:SetScript("OnHide", function() HideFrom(1) end)
	driver:SetScript("OnUpdate", function(_, elapsed)
		wait = wait - (elapsed or 0)
		if wait > 0 then return end
		wait = D.EVERY
		D.Refresh()
	end)
	D.driver = driver
	return driver
end
D.pins = pins -- (tests)

-- (the world map is the game's, loaded at login on this client; once it's there, the frame that places the dots)
do
	local f = CreateFrame("Frame")
	pcall(f.RegisterEvent, f, "PLAYER_LOGIN")
	pcall(f.RegisterEvent, f, "ADDON_LOADED")
	f:SetScript("OnEvent", function(self)
		if D.Start() then self:UnregisterAllEvents() end
	end)
	D.Start()
end
