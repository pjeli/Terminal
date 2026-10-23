-- Undo in the prompt (0.66.1, the player): Ctrl+Z undoes the last edit to what's typed, Ctrl+Y (Ctrl+Shift+Z) redoes it.
local T = ...
local UI, check, key, typeText, query = T.ns.UI, T.check, T.key, T.typeText, T.query

io.write("[undo: Ctrl+Z and Ctrl+Y in the prompt]\n")
do
	local realGT, now = _G.GetTime, 1000
	_G.GetTime = function() return now end
	local function ctrl(k, shift)
		if shift then _G.IsShiftKeyDown = function() return true end end
		T.withCtrl(function() key(k) end)
		_G.IsShiftKeyDown = function() return false end
	end
	UI:Open(""); T.FlushAll()
	-- a word typed is one edit; a space starts the next
	typeText("linen")
	typeText(" cloth")
	check(query() == "linen cloth", "typed: " .. query())
	ctrl("Z")
	check(query() == "linen", "Ctrl+Z: the last word gone: " .. query())
	ctrl("Z")
	check(query() == "", "Ctrl+Z again: the first word gone: " .. query())
	ctrl("Z")
	check(query() == "", "nothing more to undo: nothing happens")
	ctrl("Y")
	check(query() == "linen", "Ctrl+Y: back again: " .. query())
	ctrl("Z", true)
	check(query() == "linen cloth", "Ctrl+Shift+Z redoes too: " .. query())

	-- Ctrl+W is one edit of its own, not part of a run of Backspaces; a pause splits a run of typing
	key("BACKSPACE"); key("BACKSPACE")
	check(query() == "linen clo", "two Backspaces: " .. query())
	ctrl("W")
	check(query() == "linen ", "Ctrl+W: " .. query())
	ctrl("Z")
	check(query() == "linen clo", "Ctrl+Z: Ctrl+W's word back, not the Backspaces: " .. query())
	ctrl("Z")
	check(query() == "linen cloth", "Ctrl+Z: both Backspaces back as one: " .. query())
	now = now + 5
	typeText("s")
	now = now + 5
	typeText("x")
	ctrl("Z")
	check(query() == "linen cloths", "a pause between keys: two edits: " .. query())

	-- a new edit after an undo: nothing left to redo
	ctrl("Z")
	typeText("q")
	ctrl("Y")
	check(query() == "linen clothq", "typing after an undo: Ctrl+Y redoes nothing: " .. query())

	-- a new run starts afresh
	UI:Hide(); T.FlushAll()
	UI:Open(""); T.FlushAll()
	local b, f = UI:UndoDepth()
	check(b == 0 and f == 0, "opened again: nothing to undo")
	ctrl("Z")
	check(query() == "", "Ctrl+Z on a fresh prompt: nothing")
	UI:Hide(); T.FlushAll()
	_G.GetTime = realGT
end
