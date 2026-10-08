local ns = select(2, ...)

-- Small helpers every provider needs: guarded calls, values that may be "secret" on this
-- client, and the two routines the character window's lists share (reading a list with its
-- collapsed headers opened, pointing at a row in a scrolling list).

--- fn(...) in a pcall: all its results, or nothing when it isn't a function or errors.
local function Results(ok, ...)
	if ok then return ... end
end
function ns.Safe(fn, ...)
	if type(fn) ~= "function" then return nil end
	return Results(pcall(fn, ...))
end

--- Whether the value is one of this client's secret values (quest text, health...): never compared.
function ns.Secret(v)
	return issecretvalue and issecretvalue(v) or false
end

--- A usable string: not empty, not secret; else nil.
function ns.Str(v)
	if type(v) ~= "string" or v == "" then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

--- A usable number: not secret; else nil.
function ns.Num(v)
	if type(v) ~= "number" then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

--- The colour code of an item quality ("|cffa335ee"), or nil.
function ns.QualityHex(q)
	local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	return c and c.hex
end

--- The colour code of a class ("|cffc79c6e" for "WARRIOR"), or nil. Takes the class file name.
function ns.ClassHex(class)
	local c = type(class) == "string" and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if not c then return nil end
	if c.colorStr then return "|c" .. c.colorStr end
	return ("|cff%02x%02x%02x"):format(math.floor((c.r or 1) * 255), math.floor((c.g or 1) * 255), math.floor((c.b or 1) * 255))
end

--- Every row of a list whose headers can be collapsed (reputations, skills): collapsed headers are
--- expanded for the read and collapsed again afterwards, last first (indexes shift as headers close).
--- Game state only; no window is touched. api: count(), row(i) -> { name, header, ... } or nil,
--- collapsed(row), expand(i), collapse(i); guard: at most this many rows looked at while expanding.
function ns.ReadExpanded(api, guard)
	local opened = {}
	local i, n = 1, 0
	while i <= api.count() and n < guard do
		local r = api.row(i)
		if r and r.header and r.name and api.collapsed(r) then
			api.expand(i)
			opened[#opened + 1] = r.name
		end
		i, n = i + 1, n + 1
	end
	local rows = {}
	for j = 1, api.count() do
		local r = api.row(j)
		if r and r.name then rows[#rows + 1] = r end
	end
	for k = #opened, 1, -1 do
		for j = api.count(), 1, -1 do
			local r = api.row(j)
			if r and r.header and r.name == opened[k] and not api.collapsed(r) then
				api.collapse(j)
				break
			end
		end
	end
	return rows
end

--- Scrolls a ScrollBox to the element whose data `pred` accepts (a row not scrolled into view
--- doesn't exist yet). True when the box could be asked.
function ns.ScrollBoxTo(box, pred)
	if not (box and box.ScrollToElementDataByPredicate) then return false end
	return (pcall(box.ScrollToElementDataByPredicate, box, function(node)
		local d = type(node) == "table" and (node.GetData and node:GetData() or node)
		return type(d) == "table" and pred(d) or false
	end))
end

--- Once `o.frame()` gives a showing frame: `o.find(frame)` its row; not there, `o.scroll(frame)` once
--- (the row may be further down the list) and look again; then `o.show(row)` (default: the
--- highlight). o.tries looks a tenth of a second apart; o.fail() when none found.
function ns.PointAtRow(o)
	local H = ns.Highlight
	local scrolled = false
	H:When(function()
		local f = o.frame()
		if not f then return nil end
		local row = o.find(f)
		if not row and not scrolled and o.scroll then
			scrolled = true
			o.scroll(f)
			row = o.find(f)
		end
		return row
	end, o.show or function(row) H:Show(row) end, o.tries or 20, o.fail)
end

--- This character's name as the game keys per-character settings (the AddOn list's on/off): on clients
--- where characters have a surname (RegionalUniqueNamesEnabled: "Plamen Warr"), UnitName gives the two
--- apart and only "Plamen" alone named another character (an old one called just Plamen), so the AddOn
--- list Terminal read and changed was that character's. Joined with the game's own separator, as Syndicator does.
function ns.CharacterName()
	local name, surname = UnitName("player")
	name, surname = ns.Str(name), ns.Str(surname)
	if not name then return nil end
	local regional = _G.RegionalUniqueNamesEnabled and ns.Safe(_G.RegionalUniqueNamesEnabled)
	if surname and regional then
		local C = _G.Constants and _G.Constants.CharacterNameSeparatorConsts
		local sep = C and C.CHARACTERNAME_SURNAME_SEPARATOR or " "
		return name .. sep .. surname
	end
	return name
end
