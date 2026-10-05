local ns = select(2, ...)

-- .btop: the terminal turns into a small btop (the Linux system monitor) for your addons. A CPU graph
-- of all addons over time, memory, frame rate and latency, and a list of addons by CPU and memory
-- with little bars, searchable by typing. Tab changes the sort, Up/Down move, Esc or ` closes.
--
-- CPU comes from the game's own profiler (C_AddOnProfiler: each addon's recent time per frame);
-- memory from GetAddOnMemoryUsage, refreshed every few seconds (asking for it is costly). The panel
-- reads the keyboard while open, so it doesn't open in combat and closes itself when combat starts.

local B = {}
ns.Btop = B

local Theme = ns.Theme
local W, H = 640, 420
local GRAPH_COLS = 48
local ROWS = 12 -- rows made; as many as fit the list's box show (`fit`)
local ROW_H, LIST_TOP, LIST_BOTTOM = 19, 42, 6 -- the list's rows, and the room above and below them in its box
local CPU_EVERY, MEM_EVERY = 0.5, 3 -- seconds between samples
local SORTS = { "cpu", "mem", "name" }
local HOT, WARM, COOL = "ff5f5f", "ffd200", "33ff99" -- btop's bar colours: low green, high red

local fit = 9
local frame, graph, memGraph, rows, header, cpuText, memText, memText2, memText3, memBar, memBarBg, sysText, filterText, footer, colHead
local hist, memHist = {}, {}
local addons, shown = {}, {}
local state = { sort = "cpu", filter = "", sel = 1, offset = 0 }

local function RGB(hex) return Theme.RGB(hex) end

--- Green, yellow or red, by how full a bar is (0..1).
local function Heat(f)
	if f >= 0.66 then return HOT elseif f >= 0.33 then return WARM end
	return COOL
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
		end
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
	end
	B.memTotal = total
	B.memPeak = math.max(B.memPeak or 0, total)
	memHist[#memHist + 1] = total
	while #memHist > GRAPH_COLS do table.remove(memHist, 1) end
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

local function Text(parent, size, justify)
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

local function Box(parent, title, x, y, w, h)
	local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	b:SetPoint("TOPLEFT", x, y)
	b:SetSize(w, h)
	b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	local t = Text(b, 11)
	t:SetPoint("TOPLEFT", 8, 7)
	b.title = t
	t:SetText(title)
	return b
end

local function Build()
	if frame then return end
	frame = CreateFrame("Frame", "TerminalBtop", UIParent, "BackdropTemplate")
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:Hide()
	frame:EnableKeyboard(true)
	pcall(frame.SetPropagateKeyboardInput, frame, false)
	frame:SetScript("OnKeyDown", function(_, key) B.Key(key) end)
	frame:SetScript("OnChar", function(_, ch) B.Char(ch) end)
	frame:SetScript("OnUpdate", function(_, elapsed) B.Tick(elapsed) end)
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:SetScript("OnEvent", function() B.Close("combat") end)

	header = Text(frame, 13)
	header:SetPoint("TOPLEFT", 12, -10)
	sysText = Text(frame, 12, "RIGHT")
	sysText:SetPoint("TOPRIGHT", -12, -10)

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
		rows[i] = r
	end
	footer = Text(frame, 11)
	footer:SetPoint("BOTTOMLEFT", 12, 10)
	B.frame, B.rows, B.footer, B.cpuText, B.graph = frame, rows, footer, cpuText, graph
end

--- Size, colours and places from the terminal's theme.
local function Layout()
	local t = Theme.Get()
	W = math.max(520, t.width or 640)
	frame:SetSize(W, H)
	frame:SetScale(t.scale or 1)
	frame:ClearAllPoints()
	local term = _G.TerminalFrame
	if term then frame:SetPoint("TOP", term, "TOP", 0, 0) else frame:SetPoint("CENTER") end
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	local r, g, b = RGB(t.bg)
	frame:SetBackdropColor(r, g, b, math.max(0.9, t.bgAlpha or 0.95))
	local br, bg, bb = RGB(t.border)
	frame:SetBackdropBorderColor(br, bg, bb, 1)
	local ar, ag, ab = RGB(t.accent)
	local half = math.floor((W - 30) * 0.62)
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
	end
	-- graph columns fill the cpu box under its title, above its text line
	local gw = (half - 16) / GRAPH_COLS
	for i, bar in ipairs(graph) do
		bar:ClearAllPoints()
		bar:SetPoint("BOTTOMLEFT", frame.cpuBox, "BOTTOMLEFT", 8 + (i - 1) * gw, 24)
		bar:SetWidth(math.max(1, gw - 1))
	end
	local mw = W - 30 - half
	memBarBg:ClearAllPoints()
	memBarBg:SetPoint("TOPLEFT", 8, -42)
	memBarBg:SetSize(mw - 16, 8)
	local dr, dg, db = RGB(t.dim)
	memBarBg:SetColorTexture(dr, dg, db, 0.25)
	memBar:ClearAllPoints()
	memBar:SetPoint("TOPLEFT", memBarBg, "TOPLEFT")
	memBar:SetHeight(8)
	local mgw = (mw - 16) / GRAPH_COLS
	for i, bar in ipairs(memGraph) do
		bar:ClearAllPoints()
		bar:SetPoint("BOTTOMLEFT", frame.memBox, "BOTTOMLEFT", 8 + (i - 1) * mgw, 8)
		bar:SetWidth(math.max(1, mgw - 1))
		bar:SetColorTexture(ar, ag, ab, 0.7)
	end
	-- columns: name, a bar, cpu ms, cpu %, memory
	local pw = W - 20
	local cols = { name = 10, bar = pw * 0.42, ms = pw * 0.66, pct = pw * 0.78, mem = pw - 10 }
	B.cols = cols
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
		local tr, tg, tb = RGB(t.text)
		for _, fs in ipairs({ r.name, r.ms, r.pct, r.mem }) do fs:SetTextColor(tr, tg, tb) end
	end
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
	B.graphH = 150 - 24 - 28
end

--- Bars move toward their values a little every frame (the animation); text is set on each sample.
local function Ease(bar, target, k)
	bar.target = target
	bar.shown = bar.shown + (target - bar.shown) * k
	if math.abs(target - bar.shown) < 0.002 then bar.shown = target end
	return bar.shown
end

function B.DrawBars(k)
	if not frame then return end
	-- cpu graph: newest on the right
	local gh = B.graphH or 98
	for i, bar in ipairs(graph) do
		local v = hist[#hist - (GRAPH_COLS - i)] or 0
		local f = Ease(bar, v, k)
		bar:SetHeight(math.max(1, f * gh))
		local r, g, b = RGB(Heat(f))
		bar:SetVertexColor(r, g, b, f > 0 and 0.9 or 0.15)
	end
	-- memory meter and graph (against the session's peak)
	local peak = math.max(1, B.memPeak or 1)
	local mf = Ease(memBar, (B.memTotal or 0) / peak, k)
	memBar:SetWidth(math.max(1, mf * memBarBg:GetWidth()))
	local r, g, b = RGB(Heat(mf))
	memBar:SetVertexColor(r, g, b, 1)
	for i, bar in ipairs(memGraph) do
		local v = memHist[#memHist - (GRAPH_COLS - i)]
		local f = Ease(bar, v and v / peak or 0, k)
		bar:SetHeight(math.max(1, f * 42))
	end
	-- the rows' bars: share of all addons' cpu (or of all memory when sorted by memory)
	local byMem = state.sort == "mem"
	local whole = byMem and math.max(1, B.memTotal or 1) or math.max(0.0001, B.total or 0)
	for i, row in ipairs(rows) do
		local a = i <= fit and shown[state.offset + i]
		if a then
			local f = Ease(row.bar, math.min(1, ((byMem and a.mem or a.cpu) or 0) / whole), k)
			row.bar:SetWidth(math.max(1, f * row.barBg:GetWidth()))
			local cr, cg, cb = RGB(Heat(f))
			row.bar:SetVertexColor(cr, cg, cb, 1)
		end
	end
end

function B.DrawText()
	if not frame then return end
	local t = Theme.Get()
	header:SetText(("|cff%sbtop|r  |cff%sfor addons|r"):format(t.accent, t.dim))
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
	for _, a in ipairs(addons) do if a.name == "Terminal" then mine = a.mem end end
	memText:SetText(("%s in %d addons"):format(MB(B.memTotal or 0), #addons))
	memText2:SetText("peak " .. MB(B.memPeak or 0))
	memText3:SetText("Terminal " .. MB(mine))
	local sortLabel = { cpu = "cpu", mem = "memory", name = "name" }
	filterText:SetText(("|cff%sfilter|r %s|cff%s_|r   |cff%ssort|r %s"):format(t.dim, state.filter, t.accent, t.dim, sortLabel[state.sort]))
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
	footer:SetText(("%d of %d addons  ·  type to filter  ·  Tab sort  ·  Up/Down move  ·  Esc or ` close"):format(#shown, #addons))
end

----------------------------------------------------------------------
-- Running
----------------------------------------------------------------------

local cpuAt, memAt, drawAt = 0, 0, 0
function B.Tick(elapsed)
	elapsed = elapsed or 0
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
	if key == "ESCAPE" or key == "`" then return B.Close() end
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
	if not ch or ch == "`" or ch == "~" then return end
	state.filter = state.filter .. ch
	state.sel = 1
	B.Refilter(); B.DrawText(); B.DrawBars(1)
end

function B.IsShown() return frame and frame:IsShown() or false end
B.state = state
function B.Shown() return shown end
function B.Fit() return fit end
function B.MemTexts() return memText, memText2, memText3 end
function B.History() return hist end

function B.Open()
	if InCombatLockdown() then
		ns:Print("btop reads the keyboard while open, so not in combat.")
		return false
	end
	Build()
	Layout()
	-- straight in: the terminal goes at once (its closing animation would play under the panel)
	if ns.UI and ns.UI.HideNow then ns.UI:HideNow() end
	if ns.Snake and ns.Snake.IsShown and ns.Snake.IsShown() then ns.Snake.Close() end
	state.filter, state.sel, state.offset = "", 1, 0
	B.since = B.since or GetTime()
	ReadAddons(); SampleMem(); SampleCpu()
	cpuAt, memAt, drawAt = 0, 0, 0
	B.Refilter()
	frame:Show()
	B.DrawText()
	B.DrawBars(1) -- (the bars start at their values; they glide only as new samples come in)
	return true
end

function B.Close(why)
	if not frame or not frame:IsShown() then return end
	frame:Hide()
	if why == "combat" then ns:Print("btop closed: combat started.") end
end

ns:RegisterCommand("btop", {
	desc = "A small btop for your addons: CPU and memory, live (type to filter, Tab sort, Esc closes)",
	aliases = { "top", "htop" },
	run = function() B.Open() end,
})
