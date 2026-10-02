local ns = select(2, ...)

-- Pulsing gold outline drawn around any frame, plus helpers to locate frames
-- inside Blizzard UI after we open it.
local H = {}
ns.Highlight = H

local pool, active = {}, {}

local function NewGlow()
	local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:EnableMouse(false)
	f:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 3 })
	f:SetBackdropBorderColor(1, 0.82, 0, 1)
	f.fill = f:CreateTexture(nil, "BACKGROUND")
	f.fill:SetAllPoints()
	f.fill:SetColorTexture(1, 0.82, 0, 0.12)
	local ag = f:CreateAnimationGroup()
	ag:SetLooping("BOUNCE")
	local a = ag:CreateAnimation("Alpha")
	a:SetFromAlpha(1)
	a:SetToAlpha(0.25)
	a:SetDuration(0.45)
	f.pulse = ag
	return f
end

function H:Release(g)
	if not active[g] then return end
	active[g] = nil
	g:Hide()
	g.pulse:Stop()
	g:SetScript("OnUpdate", nil)
	g.target = nil
	pool[#pool + 1] = g
end

function H:Clear()
	local list = {}
	for g in pairs(active) do list[#list + 1] = g end
	for _, g in ipairs(list) do self:Release(g) end
end

function H:Show(target, duration)
	if not target or not target.IsVisible then return end
	local g = table.remove(pool) or NewGlow()
	g.target = target
	g.expires = GetTime() + (duration or 6)
	g:ClearAllPoints()
	g:SetPoint("TOPLEFT", target, "TOPLEFT", -3, 3)
	g:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 3, -3)
	g:Show()
	g.pulse:Play()
	g:SetScript("OnUpdate", function(self)
		if not self.target or not self.target:IsVisible() or GetTime() > self.expires then
			H:Release(self)
		end
	end)
	active[g] = true
	return g
end

--- Poll `finder` (returns a frame, or a list of frames, or nil) until it
--- succeeds, then call onFound. Gives Blizzard frames time to build/layout.
function H:When(finder, onFound, tries)
	local function try(n)
		local ok, res = pcall(finder)
		if ok and res then
			onFound(res)
			return
		end
		if n > 0 then
			C_Timer.After(0.1, function() try(n - 1) end)
		end
	end
	C_Timer.After(0.05, function() try(tries or 25) end)
end

function H:Find(finder, duration, tries)
	self:When(finder, function(res)
		if res.IsVisible then
			self:Show(res, duration)
		else
			for _, f in ipairs(res) do self:Show(f, duration) end
		end
	end, tries)
end

----------------------------------------------------------------------
-- Frame-tree helpers
----------------------------------------------------------------------

--- Depth-first search for a visible descendant (or root) satisfying pred.
function ns.FindFrame(root, pred, depth)
	if not root or not root.GetChildren then return nil end
	depth = depth or 10
	if root.IsVisible and root:IsVisible() then
		local ok, res = pcall(pred, root)
		if ok and res then return root end
	end
	if depth <= 0 then return nil end
	for _, child in ipairs({ root:GetChildren() }) do
		local f = ns.FindFrame(child, pred, depth - 1)
		if f then return f end
	end
end

--- Find a visible frame having a FontString whose text contains `text`.
function ns.FindByText(root, text, depth)
	if not text or text == "" then return nil end
	return ns.FindFrame(root, function(f)
		for _, r in ipairs({ f:GetRegions() }) do
			if r.GetObjectType and r:GetObjectType() == "FontString" then
				local t = r:GetText()
				if type(t) == "string" and t:find(text, 1, true) then return true end
			end
		end
		return false
	end, depth)
end

--- Convenience: highlight inside a Blizzard frame by predicate, falling back to text.
function H:FindIn(getRoot, pred, text, duration)
	self:Find(function()
		local root = getRoot()
		if not root or not root:IsVisible() then return nil end
		return (pred and ns.FindFrame(root, pred)) or ns.FindByText(root, text)
	end, duration)
end
