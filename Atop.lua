local ns = select(2, ...)

-- .atop: the terminal turns into atop, "AddOn top": a small btop (the Linux system monitor) for your addons. A CPU graph
-- of all addons over time, memory, frame rate and latency, and a list of addons by CPU and memory
-- with little bars, searchable by typing. Tab changes the sort, Up/Down move, Esc or ` closes.
-- Enter (or a click) on an addon profiles it: the graphs follow that addon alone (its CPU per frame, scaled to its
-- own peak; its memory and how fast it grows), and the list gives way to the profiler's numbers for it beside all
-- addons' (recent, session, peak, last frame, in combat; frames over 1/5/10/50/100/500/1000 ms). Up/Down step to the
-- next addon; Esc, Enter or Backspace go back to the list.
--
-- CPU comes from the game's own profiler (C_AddOnProfiler: each addon's recent time per frame);
-- memory from GetAddOnMemoryUsage, refreshed every few seconds (asking for it is costly). The panel
-- reads the keyboard while open, so it doesn't open in combat and closes itself when combat starts.

local B = {}
ns.Atop = B

local Theme = ns.Theme
local Panel = ns.Panel
local W, H = 640, 420
local GRAPH_COLS = 48
local ROWS = 12 -- rows made; as many as fit the list's box show (`fit`)
local ROW_H, LIST_TOP, LIST_BOTTOM = 19, 42, 6 -- the list's rows, and the room above and below them in its box
-- seconds between samples. Memory is asked for rarely: UpdateAddOnMemoryUsage walks every addon's memory and its
-- time is charged to Terminal (at every 3 s it was the spike in Terminal's own graph, every sixth bar)
local CPU_EVERY, MEM_EVERY = 0.5, 10
local SORTS = { "cpu", "mem", "name" }
local SORT_LABEL = { cpu = "cpu", mem = "memory", name = "name" } -- (how the list's sort is named in it)
-- btop's bar colours: low green, high red (as RGB triples: parsing hex per bar per tick added up)
local HOT, WARM, COOL = { Theme.RGB("ff5f5f") }, { Theme.RGB("ffd200") }, { Theme.RGB("33ff99") }

local fit = 9
local frame, graph, memGraph, rows, header, cpuText, memText, memText2, memText3, memBar, memBarBg, sysText, filterText, footer, colHead
local hist, memHist = {}, {}
local addons, shown = {}, {}
local state = { sort = "cpu", filter = "", sel = 1, offset = 0, focus = nil }
local profLines -- the profile view's lines (label, this addon, all addons), made with the frame
B.METRICS = { -- the profiler's numbers shown for one addon: { metric name, label, kind } (left: times, right: counts)
	{ "RecentAverageTime", "recent average", "ms" }, { "SessionAverageTime", "session average", "ms" },
	{ "PeakTime", "peak", "ms" }, { "LastTime", "last frame", "ms" }, { "EncounterAverageTime", "in boss fights", "ms" },
	{ "CountTimeOver1Ms", "frames over 1 ms", "n" }, { "CountTimeOver5Ms", "over 5 ms", "n" },
	{ "CountTimeOver10Ms", "over 10 ms", "n" }, { "CountTimeOver50Ms", "over 50 ms", "n" },
	{ "CountTimeOver100Ms", "over 100 ms", "n" }, { "CountTimeOver500Ms", "over 500 ms", "n" },
	{ "CountTimeOver1000Ms", "over 1 s", "n" },
}

local RGB = Theme.RGB

--- Green, yellow or red (r, g, b), by how full a bar is (0..1).
local function Heat(f)
	local c = f >= 0.66 and HOT or f >= 0.33 and WARM or COOL
	return c[1], c[2], c[3]
end

----------------------------------------------------------------------
-- Measuring
----------------------------------------------------------------------

local function Profiler()
	local P, M = _G.C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
	if P and P.GetAddOnMetric and M and M.RecentAverageTime then return P, M.RecentAverageTime end
end

local function FrameMs()
	local fps = GetFramerate and GetFramerate() or 60
	return fps > 0 and 1000 / fps or 16.7
end

--- Every loaded addon: { name, title, ltitle, cpu (ms per frame), mem (KB) }.
local function ReadAddons()
	local list, byName = {}, {}
	for _, a in ipairs(addons) do byName[a.name] = a end
	local n = (C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns()) or 0
	local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
	for i = 1, n do
		local name, title = C_AddOns.GetAddOnInfo(i)
		if name and (not isLoaded or isLoaded(i)) then
			local a = byName[name] or { name = name, cpu = 0, mem = 0, shownCpu = 0, shownMem = 0 }
			local plain = ns.Plain and ns.Plain(title or name) or (title or name)
			a.title = plain ~= "" and plain or name
			a.ltitle = ns.Lower(a.title .. " " .. name)
			list[#list + 1] = a
		end
	end
	addons = list
end

local function SampleCpu()
	local P, metric = Profiler()
	local total = 0
	if P then
		for _, a in ipairs(addons) do
			local ok, v = pcall(P.GetAddOnMetric, a.name, metric)
			a.cpu = ok and type(v) == "number" and v or 0
			-- each addon's own history (ms per frame), for its profile
			local h = a.hist or {}
			a.hist = h
			h[#h + 1] = a.cpu
			if #h > GRAPH_COLS then table.remove(h, 1) end
		end
		B.ReadProfile()
		local ok, all = false, nil
		if P.GetOverallMetric then ok, all = pcall(P.GetOverallMetric, metric) end
		if ok and type(all) == "number" then
			total = all
		else
			for _, a in ipairs(addons) do total = total + a.cpu end
		end
	end
	B.total, B.frameMs, B.hasProfiler = total, FrameMs(), P ~= nil
	hist[#hist + 1] = math.min(1, total / B.frameMs)
	while #hist > GRAPH_COLS do table.remove(hist, 1) end
end

local function SampleMem()
	local upd = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or _G.UpdateAddOnMemoryUsage
	local get = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or _G.GetAddOnMemoryUsage
	if upd then pcall(upd) end
	local total = 0
	for _, a in ipairs(addons) do
		local ok, kb = pcall(get or function() return 0 end, a.name)
		a.mem = ok and type(kb) == "number" and kb or 0
		total = total + a.mem
		local h, ht = a.memHist or {}, a.memAt or {}
		a.memHist, a.memAt = h, ht
		h[#h + 1], ht[#ht + 1] = a.mem, B.clock or 0
		if #h > GRAPH_COLS then table.remove(h, 1); table.remove(ht, 1) end
	end
	B.memTotal = total
	B.memPeak = math.max(B.memPeak or 0, total)
	memHist[#memHist + 1] = total
	while #memHist > GRAPH_COLS do table.remove(memHist, 1) end
end

--- The addon being profiled (Enter on a row), or nil in the list.
local function Focused()
	if not state.focus then return nil end
	for _, a in ipairs(addons) do if a.name == state.focus then return a end end
end
B.Focused = Focused

--- The profiler's numbers for the focused addon and for all addons ({ [metric] = { mine, all } }); only metrics
--- this client has. Asked with each CPU sample, only while an addon is profiled.
function B.ReadProfile()
	local a = Focused()
	local P, M = _G.C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
	B.profile = nil
	if not (a and P and P.GetAddOnMetric and M) then return end
	local out = {}
	for _, m in ipairs(B.METRICS) do
		local id = M[m[1]]
		if id then
			local ok, mine = pcall(P.GetAddOnMetric, a.name, id)
			local ok2, all = false, nil
			if P.GetOverallMetric then ok2, all = pcall(P.GetOverallMetric, id) end
			out[m[1]] = { ok and type(mine) == "number" and mine or nil, ok2 and type(all) == "number" and all or nil }
		end
	end
	B.profile = out
end

--- How fast an addon's memory changes over its history, KB a second (nil with too few samples).
function B.Growth(a)
	local h, ht = a and a.memHist, a and a.memAt
	if not h or not ht or #h < 2 then return nil end
	local dt = (ht[#ht] or 0) - (ht[1] or 0)
	if dt <= 0 then return nil end
	return (h[#h] - h[1]) / dt
end

local function MB(kb) return kb >= 1024 and ("%.1f MB"):format(kb / 1024) or ("%.0f KB"):format(kb) end

----------------------------------------------------------------------
-- The list: filter, sort
----------------------------------------------------------------------

local function Matches(a, q)
	if q == "" then return true end
	if a.ltitle:find(q, 1, true) then return true end
	local F = ns.Fuzzy
	return F and F.score and F.score(q, a.title, a.ltitle) ~= nil or false
end

function B.Refilter()
	local q = ns.Lower(state.filter)
	shown = {}
	for _, a in ipairs(addons) do
		if Matches(a, q) then shown[#shown + 1] = a end
	end
	local key = state.sort
	table.sort(shown, function(x, y)
		if key == "name" then return x.ltitle < y.ltitle end
		local vx, vy = x[key] or 0, y[key] or 0
		if vx ~= vy then return vx > vy end
		return x.ltitle < y.ltitle
	end)
	state.sel = math.max(1, math.min(state.sel, #shown))
	if state.sel <= state.offset then state.offset = state.sel - 1 end
	if state.sel > state.offset + fit then state.offset = state.sel - fit end
	state.offset = math.max(0, math.min(state.offset, math.max(0, #shown - fit)))
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

local Text = Panel.Text

local function Box(parent, title, x, y, w, h)
	local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	b:SetPoint("TOPLEFT", x, y)
	b:SetSize(w, h)
	b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	local t = Text(b, 11)
	t:SetPoint("TOPLEFT", 8, 7)
	b.title = t
	t:SetText(title)
	-- the title sits on the box's top edge: a patch of the background behind it cuts the line there
	local patch = b:CreateTexture(nil, "ARTWORK")
	patch:SetPoint("TOPLEFT", t, "TOPLEFT", -4, 1)
	patch:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 4, -1)
	b.patch = patch
	return b
end

local function Build()
	if frame then return end
	frame = Panel.Build("TerminalAtop", B)
	pcall(frame.SetPropagateKeyboardInput, frame, false) -- (every key is atop's while it's open)
	frame:SetScript("OnKeyDown", function(_, key) B.Key(key) end)
	frame:SetScript("OnChar", function(_, ch) B.Char(ch) end)
	frame:SetScript("OnUpdate", function(_, elapsed) B.Tick(elapsed) end)

	header, sysText = Panel.Header(frame)

	-- cpu: a graph of all addons' share of each frame
	local cpu = Box(frame, "cpu", 10, -30, 0, 150)
	frame.cpuBox = cpu
	graph = {}
	for i = 1, GRAPH_COLS do
		local bar = cpu:CreateTexture(nil, "ARTWORK")
		bar:SetColorTexture(1, 1, 1, 1)
		bar.shown = 0
		graph[i] = bar
	end
	cpuText = Text(cpu, 11)
	cpuText:SetPoint("BOTTOMLEFT", 8, 6)

	-- mem: total, a meter against the peak, and a small graph
	local mem = Box(frame, "mem", 0, -30, 0, 150)
	frame.memBox = mem
	memText = Text(mem, 11)
	memText:SetPoint("TOPLEFT", 8, -24)
	memText2 = Text(mem, 11)
	memText2:SetPoint("TOPLEFT", 8, -58)
	memText3 = Text(mem, 11)
	memText3:SetPoint("TOPLEFT", 8, -73)
	memBarBg = mem:CreateTexture(nil, "BACKGROUND")
	memBar = mem:CreateTexture(nil, "ARTWORK")
	memBar:SetColorTexture(1, 1, 1, 1)
	memBar.shown = 0
	memGraph = {}
	for i = 1, GRAPH_COLS do
		local bar = mem:CreateTexture(nil, "ARTWORK")
		bar:SetColorTexture(1, 1, 1, 1)
		bar.shown = 0
		memGraph[i] = bar
	end

	-- the addons
	local proc = Box(frame, "addons", 10, -186, 0, 0)
	frame.procBox = proc
	filterText = Text(proc, 11, "RIGHT")
	filterText:SetPoint("TOPRIGHT", -8, -7)
	colHead = {}
	for i, c in ipairs({ { "Addon", 10, "LEFT" }, { "CPU ms", 0, "RIGHT" }, { "CPU %", 0, "RIGHT" }, { "Memory", 0, "RIGHT" } }) do
		local fs = Text(proc, 11, c[3])
		fs:SetText(c[1])
		colHead[i] = fs
	end
	rows = {}
	for i = 1, ROWS do
		local r = CreateFrame("Frame", nil, proc)
		r:SetHeight(18)
		r.sel = r:CreateTexture(nil, "BACKGROUND")
		r.sel:SetAllPoints()
		r.name = Text(r, 12)
		r.ms = Text(r, 12, "RIGHT")
		r.pct = Text(r, 12, "RIGHT")
		r.mem = Text(r, 12, "RIGHT")
		r.barBg = r:CreateTexture(nil, "BORDER")
		r.bar = r:CreateTexture(nil, "ARTWORK")
		r.bar:SetColorTexture(1, 1, 1, 1)
		r.bar.shown = 0
		r.index = i
		r:EnableMouse(true)
		r:SetScript("OnMouseUp", function(self) B.Profile(state.offset + self.index) end) -- (a click profiles it)
		rows[i] = r
	end
	-- the profile view: two blocks of label / this addon / all addons (times on the left, slow frames on the right)
	profLines = {}
	for i = 1, #B.METRICS + 2 do
		profLines[i] = { label = Text(proc, 11), mine = Text(proc, 11, "RIGHT"), all = Text(proc, 11, "RIGHT") }
	end
	footer = Panel.Footer(frame, 10)
	B.frame, B.rows, B.footer, B.cpuText, B.graph, B.profLines = frame, rows, footer, cpuText, graph, profLines
end

-- the three boxes: cpu and mem side by side, the addons under them (as many rows as fit), their edges and titles
local function LayoutBoxes(t, half)
	local br, bg, bb = RGB(t.border)
	local ar, ag, ab = RGB(t.accent)
	local pr, pg, pb = RGB(t.bg)
	frame.cpuBox:SetWidth(half)
	frame.memBox:ClearAllPoints()
	frame.memBox:SetPoint("TOPLEFT", 20 + half, -30)
	frame.memBox:SetWidth(W - 30 - half)
	local procH = H - 186 - 34 -- (the footer gets its own line under the box)
	frame.procBox:SetSize(W - 20, procH)
	fit = math.max(1, math.min(ROWS, math.floor((procH - LIST_TOP - LIST_BOTTOM) / ROW_H)))
	for _, box in ipairs({ frame.cpuBox, frame.memBox, frame.procBox }) do
		box:SetBackdropBorderColor(br, bg, bb, 1)
		box.title:SetTextColor(ar, ag, ab)
		box.title:SetWidth(math.max(20, box:GetWidth() - 16)) -- (a long addon name in it is cut, never over the edge)
		box.patch:SetColorTexture(pr, pg, pb, 1)
	end
end

-- the cpu graph's columns, the memory meter and the memory graph
local function LayoutGraphs(t, half, mw)
	cpuText:SetWidth(half - 16)
	-- graph columns fill the cpu box under its title, above its text line
	local gw = (half - 16) / GRAPH_COLS
	for i, bar in ipairs(graph) do
		bar:ClearAllPoints()
		bar:SetPoint("BOTTOMLEFT", frame.cpuBox, "BOTTOMLEFT", 8 + (i - 1) * gw, 24)
		bar:SetWidth(math.max(1, gw - 1))
	end
	memBarBg:ClearAllPoints()
	memBarBg:SetPoint("TOPLEFT", 8, -42)
	memBarBg:SetSize(mw - 16, 8)
	local dr, dg, db = RGB(t.dim)
	memBarBg:SetColorTexture(dr, dg, db, 0.25)
	memBar:ClearAllPoints()
	memBar:SetPoint("TOPLEFT", memBarBg, "TOPLEFT")
	memBar:SetHeight(8)
	local ar, ag, ab = RGB(t.accent)
	local mgw = (mw - 16) / GRAPH_COLS
	for i, bar in ipairs(memGraph) do
		bar:ClearAllPoints()
		bar:SetPoint("BOTTOMLEFT", frame.memBox, "BOTTOMLEFT", 8 + (i - 1) * mgw, 8)
		bar:SetWidth(math.max(1, mgw - 1))
		bar:SetColorTexture(ar, ag, ab, 0.7)
	end
end

-- the list: its column heads and rows (name, a bar, cpu ms, cpu %, memory)
local function LayoutRows(t, pw)
	local ar, ag, ab = RGB(t.accent)
	local dr, dg, db = RGB(t.dim)
	local tr, tg, tb = RGB(t.text)
	local cols = { name = 10, bar = pw * 0.42, ms = pw * 0.66, pct = pw * 0.78, mem = pw - 10 }
	colHead[1]:ClearAllPoints(); colHead[1]:SetPoint("TOPLEFT", cols.name, -24)
	colHead[2]:ClearAllPoints(); colHead[2]:SetPoint("TOPRIGHT", frame.procBox, "TOPLEFT", cols.ms, -24)
	colHead[3]:ClearAllPoints(); colHead[3]:SetPoint("TOPRIGHT", frame.procBox, "TOPLEFT", cols.pct, -24)
	colHead[4]:ClearAllPoints(); colHead[4]:SetPoint("TOPRIGHT", frame.procBox, "TOPLEFT", cols.mem, -24)
	for _, fs in ipairs(colHead) do fs:SetTextColor(dr, dg, db) end
	for i, r in ipairs(rows) do
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", frame.procBox, "TOPLEFT", 3, -LIST_TOP - (i - 1) * ROW_H)
		r:SetPoint("TOPRIGHT", frame.procBox, "TOPRIGHT", -3, -LIST_TOP - (i - 1) * ROW_H)
		r:SetHeight(ROW_H - 1)
		r.sel:SetColorTexture(ar, ag, ab, 0.22)
		r.name:ClearAllPoints(); r.name:SetPoint("LEFT", cols.name - 4, 0); r.name:SetWidth(cols.bar - cols.name - 10)
		r.barBg:ClearAllPoints(); r.barBg:SetPoint("LEFT", cols.bar - 4, 0); r.barBg:SetSize(cols.ms - cols.bar - 70, 6)
		r.barBg:SetColorTexture(dr, dg, db, 0.2)
		r.bar:ClearAllPoints(); r.bar:SetPoint("LEFT", r.barBg, "LEFT"); r.bar:SetHeight(6)
		r.ms:ClearAllPoints(); r.ms:SetPoint("RIGHT", r, "LEFT", cols.ms - 4, 0)
		r.pct:ClearAllPoints(); r.pct:SetPoint("RIGHT", r, "LEFT", cols.pct - 4, 0)
		r.mem:ClearAllPoints(); r.mem:SetPoint("RIGHT", r, "LEFT", cols.mem - 4, 0)
		for _, fs in ipairs({ r.name, r.ms, r.pct, r.mem }) do fs:SetTextColor(tr, tg, tb) end
	end
end

-- the profile's two blocks: a header line, then a line per metric (times left, slow-frame counts right)
local function LayoutProfile(t, pw)
	local dr, dg, db = RGB(t.dim)
	local tr, tg, tb = RGB(t.text)
	local half2 = math.floor(pw / 2)
	local left, right = 0, 0
	for i, l in ipairs(profLines) do
		local m = B.METRICS[i - 2]
		local onRight = (i == 2) or (m and m[3] == "n")
		local row
		if onRight then right = right + 1; row = right else left = left + 1; row = left end
		local x0 = onRight and half2 or 0
		local y = -24 - (row - 1) * 16
		l.label:ClearAllPoints(); l.label:SetPoint("TOPLEFT", frame.procBox, "TOPLEFT", x0 + 10, y)
		-- (each column kept to its room: the label stops before the numbers, a number before the next)
		l.label:SetWidth(math.max(40, half2 * 0.68 - 10 - 82))
		l.mine:SetWidth(76); l.all:SetWidth(76)
		l.mine:ClearAllPoints(); l.mine:SetPoint("TOPRIGHT", frame.procBox, "TOPLEFT", x0 + half2 * 0.68, y)
		l.all:ClearAllPoints(); l.all:SetPoint("TOPRIGHT", frame.procBox, "TOPLEFT", x0 + half2 - 12, y)
		l.label:SetTextColor(dr, dg, db)
		if i <= 2 then l.mine:SetTextColor(dr, dg, db) else l.mine:SetTextColor(tr, tg, tb) end
		l.all:SetTextColor(dr, dg, db)
	end
end

-- the header, the captions and the footer
local function ColourTexts(t, mw)
	local dr, dg, db = RGB(t.dim)
	local tr, tg, tb = RGB(t.text)
	header:SetTextColor(tr, tg, tb)
	sysText:SetTextColor(dr, dg, db)
	cpuText:SetTextColor(tr, tg, tb)
	memText:SetTextColor(tr, tg, tb)
	memText2:SetTextColor(dr, dg, db)
	memText3:SetTextColor(dr, dg, db)
	for _, fs in ipairs({ memText, memText2, memText3 }) do fs:SetWidth(mw - 16) end -- (never past the box's edge)
	footer:SetTextColor(dr, dg, db)
	filterText:SetTextColor(tr, tg, tb)
end

--- Size, colours and places from the terminal's theme.
local function Layout()
	W = math.max(520, Theme.Get().width or 640)
	local t = Panel.Layout(frame, W, H)
	local half = math.floor((W - 30) * 0.62)
	local mw, pw = W - 30 - half, W - 20
	LayoutBoxes(t, half)
	LayoutGraphs(t, half, mw)
	LayoutRows(t, pw)
	LayoutProfile(t, pw)
	ColourTexts(t, mw)
	B.graphH = 150 - 24 - 28
end

--- Bars move toward their values a little every frame (the animation); text is set on each sample.
--- Gives the value shown and whether it moved: a bar that sits at its value isn't redrawn (a settled
--- display costs nothing per tick). k = 1 snaps.
local function Ease(bar, target, k)
	bar.target = target
	local was = bar.shown
	local now = was + (target - was) * k
	if math.abs(target - now) < 0.002 then now = target end
	bar.shown = now
	return now, now ~= was
end

function B.DrawBars(k)
	if not frame then return end
	local fa = Focused()
	-- cpu graph: newest on the right (profiling one addon: its own history, scaled to its peak in it)
	local gh = B.graphH or 98
	local src, scale = hist, 1
	if fa then
		src, scale = fa.hist or {}, 0
		for _, v in ipairs(src) do if v > scale then scale = v end end
		scale = math.max(scale, 0.001)
	end
	for i, bar in ipairs(graph) do
		local v = (src[#src - (GRAPH_COLS - i)] or 0) / scale
		local f, moved = Ease(bar, v, k)
		if moved or k == 1 then
			bar:SetHeight(math.max(1, f * gh))
			local r, g, b = Heat(f)
			bar:SetVertexColor(r, g, b, f > 0 and 0.9 or 0.15)
		end
	end
	-- memory meter and graph (against the session's peak; one addon: its share of all, its history against its peak)
	local peak = math.max(1, B.memPeak or 1)
	local msrc, mval = memHist, (B.memTotal or 0) / peak
	if fa then
		msrc, peak = fa.memHist or {}, 1
		for _, v in ipairs(msrc) do if v > peak then peak = v end end
		mval = (fa.mem or 0) / math.max(1, B.memTotal or 1)
	end
	local mf, mmoved = Ease(memBar, mval, k)
	if mmoved or k == 1 then
		memBar:SetWidth(math.max(1, mf * memBarBg:GetWidth()))
		local r, g, b = Heat(mf)
		memBar:SetVertexColor(r, g, b, 1)
	end
	for i, bar in ipairs(memGraph) do
		local v = msrc[#msrc - (GRAPH_COLS - i)]
		local f, moved = Ease(bar, v and v / peak or 0, k)
		if moved or k == 1 then bar:SetHeight(math.max(1, f * 42)) end
	end
	-- the rows' bars: share of all addons' cpu (or of all memory when sorted by memory)
	local byMem = state.sort == "mem"
	local whole = byMem and math.max(1, B.memTotal or 1) or math.max(0.0001, B.total or 0)
	for i, row in ipairs(rows) do
		local a = not fa and i <= fit and shown[state.offset + i]
		if a then
			local f, moved = Ease(row.bar, math.min(1, ((byMem and a.mem or a.cpu) or 0) / whole), k)
			if moved or k == 1 then
				row.bar:SetWidth(math.max(1, f * row.barBg:GetWidth()))
				local cr, cg, cb = Heat(f)
				row.bar:SetVertexColor(cr, cg, cb, 1)
			end
		end
	end
end

-- the header, the graphs' captions and the boxes' titles (the focused addon's name in them while profiling)
local function DrawTitles(t, fa)
	header:SetText(("|cff%satop|r  |cff%saddon top|r"):format(t.accent, t.dim))
	local fps = GetFramerate and GetFramerate() or 0
	local _, _, home, world = (GetNetStats or function() end)()
	local up = GetTime() - (B.since or GetTime())
	sysText:SetText(("fps %.0f  ·  %s ms  ·  up %d:%02d"):format(fps, tostring(world or home or "?"), math.floor(up / 60), math.floor(up % 60)))
	if B.hasProfiler then
		cpuText:SetText(("all addons %.2f ms / frame  ·  %.0f%% of a frame"):format(B.total or 0, (B.total or 0) / (B.frameMs or 16.7) * 100))
	else
		cpuText:SetText("|cffff6b6bthis client has no addon CPU profiler|r")
	end
	local mine = 0
	for _, a in ipairs(addons) do if a.name == ns.name then mine = a.mem end end
	memText:SetText(("%s in %d addons"):format(MB(B.memTotal or 0), #addons))
	memText2:SetText("peak " .. MB(B.memPeak or 0))
	memText3:SetText(ns.name .. " " .. MB(mine))
	frame.cpuBox.title:SetText(fa and ("cpu  ·  " .. fa.title) or "cpu")
	frame.memBox.title:SetText(fa and ("mem  ·  " .. fa.title) or "mem")
	frame.procBox.title:SetText(fa and ("profile  ·  " .. fa.title) or "addons")
	-- (each title only as wide as its words, up to its box: the patch behind it hugs the text)
	for _, box in ipairs({ frame.cpuBox, frame.memBox, frame.procBox }) do
		local room = math.max(20, box:GetWidth() - 16)
		box.title:SetWidth(room)
		local w = box.title:GetStringWidth()
		if type(w) == "number" and w > 0 then box.title:SetWidth(math.min(room, w + 1)) end
	end
	for _, fs in ipairs(colHead) do fs:SetShown(not fa) end
end

-- the list of addons: the filter and sort line, the rows on show, the footer
local function DrawList(t)
	for _, l in ipairs(profLines) do l.label:Hide(); l.mine:Hide(); l.all:Hide() end
	filterText:SetText(("|cff%sfilter|r %s|cff%s_|r   |cff%ssort|r %s"):format(t.dim, state.filter, t.accent, t.dim, SORT_LABEL[state.sort]))
	local whole = math.max(0.0001, B.total or 0)
	for i, r in ipairs(rows) do
		local a = i <= fit and shown[state.offset + i]
		if a then
			r:Show()
			r.sel:SetShown(state.offset + i == state.sel)
			r.name:SetText(a.title)
			r.ms:SetText(B.hasProfiler and ("%.3f"):format(a.cpu or 0) or "-")
			r.pct:SetText(B.hasProfiler and ("%.1f"):format((a.cpu or 0) / whole * 100) or "-")
			r.mem:SetText(MB(a.mem or 0))
		else
			r:Hide()
		end
	end
	footer:SetText(("%d of %d addons  ·  type to filter  ·  Tab sort  ·  Enter profile  ·  Esc or ` close"):format(#shown, #addons))
end

function B.DrawText()
	if not frame then return end
	local t = Theme.Get()
	local fa = Focused()
	DrawTitles(t, fa)
	if fa then return B.DrawProfile(fa, t) end
	DrawList(t)
end

--- Milliseconds, as many decimals as fit the column ("0.317 ms", "12.4 ms", "168 ms").
local function Ms(v)
	if not v then return "-" end
	if v >= 100 then return ("%.0f ms"):format(v) end
	if v >= 10 then return ("%.1f ms"):format(v) end
	return ("%.3f ms"):format(v)
end
B.Ms = Ms
local function Count(v) return v and ("%.0f"):format(v) or "-" end

--- The profile of one addon: its graphs' captions, and the profiler's numbers beside all addons'.
function B.DrawProfile(a, t)
	for _, r in ipairs(rows) do r:Hide() end
	filterText:SetText("")
	local peakMs = 0
	for _, v in ipairs(a.hist or {}) do if v > peakMs then peakMs = v end end
	if B.hasProfiler then
		cpuText:SetText(("%.3f ms/frame  ·  %.1f%% of addons  ·  peak %.3f"):format(a.cpu or 0,
			(a.cpu or 0) / math.max(0.0001, B.total or 0) * 100, peakMs))
	end
	local grow = B.Growth(a)
	memText:SetText(("%s  ·  %.1f%% of all"):format(MB(a.mem or 0), (a.mem or 0) / math.max(1, B.memTotal or 1) * 100))
	memText2:SetText(grow and (grow >= 0 and ("growing %.1f KB/s"):format(grow) or ("shrinking %.1f KB/s"):format(-grow)) or "growth: measuring...")
	local mpeak = 0
	for _, v in ipairs(a.memHist or {}) do if v > mpeak then mpeak = v end end
	memText3:SetText("peak " .. MB(mpeak))
	local prof = B.profile or {}
	for i, l in ipairs(profLines) do
		local m = B.METRICS[i - 2]
		local shownLine = true
		if i <= 2 then
			l.label:SetText(i == 1 and "time per frame" or "slow frames")
			l.mine:SetText("this addon"); l.all:SetText("all addons")
		elseif prof[m[1]] then
			local v = prof[m[1]]
			local f = m[3] == "ms" and Ms or Count
			l.label:SetText(m[2]); l.mine:SetText(f(v[1])); l.all:SetText(f(v[2]))
		else
			shownLine = false
		end
		l.label:SetShown(shownLine); l.mine:SetShown(shownLine); l.all:SetShown(shownLine)
	end
	if not B.hasProfiler then
		profLines[3].label:SetText("|cffff6b6bthis client has no addon CPU profiler|r"); profLines[3].label:Show()
	end
	-- (atop is Terminal: profiling Terminal measures atop's own drawing and sampling too)
	footer:SetText(("%d of %d  ·  Up/Down another addon  ·  Esc back to the list%s"):format(state.sel, #shown,
		a.name == ns.name and "  ·  includes atop itself" or "  ·  ` close"))
end

--- Profile the addon at list position `i` (nil: back to the list).
function B.Profile(i)
	local a = i and shown[i]
	state.focus = a and a.name or nil
	if a then state.sel = i; B.Refilter() end -- (the list comes back scrolled to it)
	B.ReadProfile()
	B.DrawText(); B.DrawBars(1)
end

----------------------------------------------------------------------
-- Running
----------------------------------------------------------------------

local cpuAt, memAt, drawAt = 0, 0, 0
function B.Tick(elapsed)
	elapsed = elapsed or 0
	B.clock = (B.clock or 0) + elapsed -- (time while open: what the growth rate is measured against)
	cpuAt, memAt, drawAt = cpuAt + elapsed, memAt + elapsed, drawAt + elapsed
	local sampled = false
	if memAt >= MEM_EVERY then memAt = 0; ReadAddons(); SampleMem(); sampled = true end
	if cpuAt >= CPU_EVERY then cpuAt = 0; SampleCpu(); sampled = true end
	if sampled then B.Refilter(); B.DrawText() end
	if drawAt >= 1 / 30 then -- (the bars glide at 30 updates a second)
		B.DrawBars(math.min(1, drawAt * 8))
		drawAt = 0
	end
end

function B.Key(key)
	if key == "`" then return B.Close() end
	if state.focus then
		-- profiling: Up/Down step to the next addon in the list, Esc / Enter / Backspace go back to it
		if key == "ESCAPE" or key == "ENTER" or key == "BACKSPACE" then return B.Profile(nil) end
		local step = key == "UP" and -1 or key == "DOWN" and 1 or key == "PAGEUP" and -fit or key == "PAGEDOWN" and fit
		if step then
			-- (from where the profiled addon is now: the list re-sorts as samples come in)
			local at = state.sel
			for i, a in ipairs(shown) do if a.name == state.focus then at = i end end
			return B.Profile(math.max(1, math.min(#shown, at + step)))
		end
		return
	end
	if key == "ESCAPE" then return B.Close() end
	if key == "ENTER" then return B.Profile(state.sel) end
	if key == "TAB" then
		local i = 1
		for k, s in ipairs(SORTS) do if s == state.sort then i = k end end
		state.sort = SORTS[i % #SORTS + 1]
	elseif key == "UP" then state.sel = state.sel - 1
	elseif key == "DOWN" then state.sel = state.sel + 1
	elseif key == "PAGEUP" then state.sel = state.sel - fit
	elseif key == "PAGEDOWN" then state.sel = state.sel + fit
	elseif key == "BACKSPACE" then state.filter = state.filter:sub(1, -2); state.sel = 1
	else return end
	B.Refilter(); B.DrawText(); B.DrawBars(1)
end

function B.Char(ch)
	if not ch or ch == "`" or ch == "~" or state.focus then return end
	state.filter = state.filter .. ch
	state.sel = 1
	B.Refilter(); B.DrawText(); B.DrawBars(1)
end

function B.IsShown() return Panel.Shown(frame) end
B.state = state
function B.Shown() return shown end
function B.Fit() return fit end
function B.MemTexts() return memText, memText2, memText3 end
function B.History() return hist end

function B.Open()
	if not Panel.CanOpen("atop reads the keyboard while open, so not in combat.") then return false end
	Build()
	Layout()
	Panel.Opening(B) -- (straight in: the terminal and the other panels go)
	state.filter, state.sel, state.offset, state.focus = "", 1, 0, nil
	B.since = B.since or GetTime()
	ReadAddons()
	-- each addon's own history starts again (a gap while closed would read as one long step)
	for _, a in ipairs(addons) do a.hist, a.memHist, a.memAt = nil, nil, nil end
	SampleMem(); SampleCpu()
	cpuAt, memAt, drawAt = 0, 0, 0
	B.Refilter()
	frame:Show()
	B.DrawText()
	B.DrawBars(1) -- (the bars start at their values; they glide only as new samples come in)
	return true
end

function B.Close(why)
	Panel.Close(frame, why, "atop")
end

ns:RegisterCommand("atop", {
	desc = "AddOn top: your addons' CPU and memory, live (type to filter, Tab sort, Esc closes)",
	aliases = { "top", "htop" },
	run = function() B.Open() end,
})
