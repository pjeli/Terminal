local ns = select(2, ...)

-- Motion: one OnUpdate (UI.motion) drives everything that moves: the terminal fading and drifting in and out, rows
-- coming in and going, the selection band and the caret gliding, the caret blinking. Split out of UI.lua.

local UI = ns.UI
local Theme = ns.Theme
local Style, Wake, rows, motion = UI.Style, UI.Wake, UI.rows, UI.motion
local PlaceRow, CursorStyle = UI.PlaceRow, UI.CursorStyle

----------------------------------------------------------------------
-- Motion
--
-- One OnUpdate drives everything that moves: the terminal fades and drifts in when it
-- opens and out when it closes, new results fade in row by row, the selection band glides
-- to the selected row, and the caret glides as you type and breathes when idle. With
-- ".set animations off" everything snaps instead.
----------------------------------------------------------------------


local Ease, Move = Theme.Ease, Theme.Move -- ease-out cubic; and the style's movement ease
local BLINK_STEP = 1 / 30 -- resting (only the cursor blinking): 30 updates a second are plenty

--- Where the terminal rests (its saved spot), and drifted `dy` pixels from it.
local function Anchor(dy)
	local frame = UI.frame
	local pt = ns.db and ns.db.point
	frame:ClearAllPoints()
	if pt then
		frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4] + (dy or 0))
	else
		frame:SetPoint("TOP", UIParent, "TOP", 0, -140 + (dy or 0))
	end
end

function UI:StartOpen(reopening)
	local frame = UI.frame
	if not self:Animated() then
		frame:SetAlpha(1)
		Anchor(0)
		return
	end
	-- reopened while still fading out: carry on from where it is
	local A = Style()
	self.phase = "open"
	local a = frame:GetAlpha()
	a = type(a) == "number" and a or 0
	self.phaseAt = GetTime() - (reopening and A.open * a or 0)
	if not reopening then
		frame:SetAlpha(0)
		Anchor(-A.drift)
	end
	self.selY = nil
	Wake()
end

function UI:StartClose()
	local frame = UI.frame
	self.closing = true
	local a = frame:GetAlpha()
	local now = GetTime()
	self.phase, self.phaseAt, self.closeFrom = "close", now, type(a) == "number" and a or 1
	-- cascade: the rows fold away bottom-up, sliding back out to the left
	local A = Style()
	if A.foldOut then
		local shown = {}
		for _, r in ipairs(rows) do if r:IsShown() and not r.leaving then shown[#shown + 1] = r end end
		local step = #shown > 1 and math.min(A.stagger, (A.close - A.rowFade * 0.5) / (#shown - 1)) or 0
		for i, r in ipairs(shown) do
			r.leaving, r.leaveAt, r.fadeAt, r.slideOut = true, now + (#shown - i) * math.max(0, step), nil, true
		end
	end
	Wake()
end

--- Back to rest: full alpha, in place, nothing moving.
function UI:MotionReset()
	local frame = UI.frame
	self.phase, self.closing = nil, false
	if frame then
		frame:SetAlpha(1)
		Anchor(0)
		-- (only called once the terminal has gone) rows go too, so the next open brings them in
		-- with the style again; left up, a reopen only changed their text and every style
		-- looked like a plain fade after the first open
		for _, r in ipairs(rows) do
			r.fadeAt, r.leaving = nil, nil
			r:Hide()
			r:SetAlpha(1)
			if r.slide or r.slideOut then r.slide, r.slideOut = nil, nil; PlaceRow(r, 0) end
		end
	end
	motion:Hide()
end

--- Open / close: the terminal fades and drifts in or out. True while it moves; "done" once the close has finished
--- (the frame hidden and back at rest: nothing more to do this frame).
local function StepPhase(frame, A, now)
	local moving = false
	-- open / close
	if UI.phase == "open" then
		local x = (now - UI.phaseAt) / A.open
		frame:SetAlpha(Ease((now - UI.phaseAt) / (A.fade or A.open)))
		Anchor(-A.drift * (1 - Move(A, x)))
		if x >= 1 then UI.phase = nil else moving = true end
	elseif UI.phase == "close" then
		local k = Ease((now - UI.phaseAt) / A.close)
		frame:SetAlpha((UI.closeFrom or 1) * (1 - k))
		Anchor(-A.closeDrift * k)
		if k >= 1 then
			UI.phase, UI.closing = nil, false
			frame:Hide()
			UI:MotionReset() -- back at rest for the next open (OnHide does it too)
			return "done"
		end
		moving = true
	end
	return moving
end

--- The height follows the results. True while it moves.
local function StepHeight(frame, elapsed, speed)
	local moving = false
	-- height: grow / shrink toward the results
	if UI.heightTo then
		local cur = frame:GetHeight()
		if type(cur) == "number" then
			local d = UI.heightTo - cur
			if math.abs(d) > 0.5 then
				frame:SetHeight(cur + d * math.min(1, (elapsed or 0) * 16 * speed))
				moving = true
			elseif d ~= 0 then
				frame:SetHeight(UI.heightTo)
			end
		end
	end
	return moving
end

--- The selection band glides to the selected row. True while it moves.
local function StepBand(selBar, blend)
	local moving = false
	-- selection band
	if UI.selTo and UI.selY and selBar:IsShown() then
		local d = UI.selTo - UI.selY
		if math.abs(d) > 0.5 then
			UI.selY = UI.selY + d * blend
			moving = true
		else
			UI.selY = UI.selTo
		end
		if UI.selY ~= UI.selPlaced then UI:SetSelectionY(UI.selY) end
	end
	return moving
end

--- The caret glides to where it goes and blinks while idle. True while it moves; and whether it blinks.
local function StepCaret(caret, caretChar, elapsed, speed, now)
	local moving, blinking = false, false
	-- caret: glide, then breathe while idle
	if caret:IsShown() and UI.caretTo then
		local d = UI.caretTo - (UI.caretX or UI.caretTo)
		if math.abs(d) > 0.3 then
			UI.caretX = (UI.caretX or UI.caretTo) + d * math.min(1, (elapsed or 0) * 28 * speed)
			moving = true
		else
			UI.caretX = UI.caretTo
		end
		-- a resting caret only blinks: nothing to re-anchor
		local moved = UI.caretX ~= UI.caretPlaced
		if moved then UI:PlaceCaret() end
		local st = CursorStyle()
		local a = 1
		if st.blink then
			local idle = now - (UI.typedAt or 0) - 0.45
			if idle > 0 then
				local wave = math.cos(idle * math.pi * 2 * (Theme.Get().blinkRate or 0.8))
				-- a line breathes; a box is mostly fully on or fully off, so the letter under it is
				-- never seen half-covered
				a = st.box and math.max(0, math.min(1, 0.5 + 1.4 * wave)) or (0.55 + 0.45 * wave)
			end
			blinking = true -- blinking never settles while the caret is up
		end
		a = math.floor(a * 50 + 0.5) / 50 -- (steps the eye can't tell apart aren't redrawn)
		if a ~= UI.caretAlpha then
			UI.caretAlpha = a
			caret:SetAlpha(a)
			caretChar:SetAlpha(a)
		end
		if moved then UI:PlaceTextSel() end
	end
	return moving, blinking
end

--- Rows coming in and going. True while any moves.
local function StepRows(A, now)
	local moving = false
	-- rows that appear fade in (staggered when set); rows that go fade out, then hide
	for _, r in ipairs(rows) do
		if r.leaving then
			local x = (now - (r.leaveAt or now)) / A.rowFade
			local k = Ease(x)
			r:SetAlpha(1 - k)
			if r.slideOut then PlaceRow(r, -A.slide * Ease(x)) end -- cascade: folding away
			if k >= 1 then
				r.leaving = nil
				r:Hide()
				r:SetAlpha(1)
				if r.slideOut then r.slideOut = nil; PlaceRow(r, 0) end
			else
				moving = true
			end
		elseif r.fadeAt and r:IsShown() then
			local x = (now - r.fadeAt) / A.rowFade
			local k = Ease(x)
			r:SetAlpha(k)
			if r.slide then PlaceRow(r, -r.slide * (1 - Move(A, x))) end -- cascade: in from the left
			if k >= 1 then
				r.fadeAt = nil
				if r.slide then r.slide = nil; PlaceRow(r, 0) end
			else
				moving = true
			end
		end
	end
	return moving
end

motion:SetScript("OnUpdate", function(self, elapsed)
	local frame, selBar, caret, caretChar = UI.frame, UI.selBar, UI.caret, UI.caretChar
	if not frame then self:Hide() return end
	-- resting: only the cursor blinks, at BLINK_STEP; anything that moves wakes it (Wake)
	self.acc = (self.acc or 0) + (elapsed or 0)
	if UI.blinkOnly and self.acc < BLINK_STEP then return end
	elapsed, self.acc = self.acc, 0
	local now = GetTime()
	local A = Style()
	local speed = A.speed or 1
	local phase = StepPhase(frame, A, now)
	if phase == "done" then return end
	if not frame:IsShown() then self:Hide() return end
	local blend = math.min(1, (elapsed or 0) * 18 * speed)
	-- (every step runs each frame, whatever else moves; what still moves is worked out after)
	local height = StepHeight(frame, elapsed, speed)
	local band = StepBand(selBar, blend)
	local caretMoving, blinking = StepCaret(caret, caretChar, elapsed, speed, now)
	local rowsMoving = StepRows(A, now)
	local moving = phase or height or band or caretMoving or rowsMoving
	UI.blinkOnly = not moving
	if not moving and not blinking then self:Hide() end
end)
