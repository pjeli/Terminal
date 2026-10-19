-- Closing keeps the last search once (review, 0.57.7): UI:Hide kept it before Alt+`'s or Tab+`'s run ended, then the
-- frame's OnHide kept it again, the second time Advanced syntax or a fuzzy find's text (Down brought those back). The
-- game fires OnHide on a hide; the mock doesn't, so the terminal's frame does here.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll

io.write("[close: the last search kept once]\n")
do
	local easy = ns.db.easyMode
	local f = _G.TerminalFrame
	local hide = f.Hide
	f.Hide = function(self, ...)
		local was = self.shown ~= false
		hide(self, ...)
		self.shown = false
		local s = self.scripts and self.scripts.OnHide
		if was and s then s(self) end
	end
	local th = ns.Theme.Get()
	local anim = th.animations
	-- (animations off: UI:Hide hides the frame itself; on, HideNow does, as an app opening does)
	for _, how in ipairs({ "off", "now" }) do
		th.animations = how == "off" and "off" or "smooth"
		local function Close() if how == "now" then UI:HideNow() else UI:Hide() end FlushAll() end
		ns.db.easyMode = true; UI:EasyChanged()
		UI:Open(""); FlushAll()
		T.typeText("cast frost nova"); FlushAll()
		UI:AdvancedOnce(); FlushAll()
		Close()
		check(UI.lastQuery == "cast frost nova", "Alt+` then closed (" .. how .. "): your words kept, not Advanced syntax: " .. tostring(UI.lastQuery))
		UI:FuzzyOnce(); FlushAll()
		T.typeText("hrth"); FlushAll()
		Close()
		check(UI.lastQuery == "cast frost nova", "a fuzzy find closed (" .. how .. "): its text isn't kept: " .. tostring(UI.lastQuery))
	end
	th.animations = anim
	-- hidden with the interface (UIParent hidden): the frame's OnHide runs while it still says it's shown; closed for real
	UI:Open(""); FlushAll()
	f.scripts.OnHide(f)
	FlushAll()
	check(not UI:IsShown(), "hidden with the interface: closed, not back later without the keyboard")
	f.Hide = hide
	ns.db.easyMode = easy; UI:EasyChanged()
end
