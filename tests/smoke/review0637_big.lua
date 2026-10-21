-- The 0.63.7 review's fixes that need many rows (a file of their own: each file's own instruction budget).
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll

io.write("[review 0.63.7: sort:name past 5000 matches]\n")
do
	local syll = { "ka", "ro", "mi", "ten", "dar", "vel", "ish", "gor", "lan", "the", "bru", "sa", "nok", "fi", "zul", "an" }
	local N = 8000
	ns:RegisterProvider("zzsrt", { label = "zzsrt", aliases = { "zzsrt" }, explicit = true,
		collect = function(p)
			local meta = ns:CompactMeta(p, { icon = "x" })
			local list, sd = {}, 7
			for i = 1, N do
				local parts = {}
				for w = 1, 2 do
					local name = ""
					for _ = 1, 2 + (i + w) % 2 do sd = (sd * 1103515245 + 12345) % 2147483648; name = name .. syll[math.floor(sd / 65536) % #syll + 1] end
					parts[w] = name:sub(1, 1):upper() .. name:sub(2)
				end
				local name = table.concat(parts, " ")
				list[i] = setmetatable({ _compact = true, key = i, name = name, _lname = ns.Lower(name) }, meta)
			end
			return list
		end })
	local easy = ns.db.easyMode
	ns.db.easyMode = false; UI:EasyChanged()
	local function Sorted(r, label)
		local ok = #r > 50
		for i = 2, #r do if ns.Lower(r[i].name) < ns.Lower(r[i - 1].name) then ok = false break end end
		-- (the first is the first of every match, A-Z)
		local least
		for _, e in ipairs(ns:GetEntries(ns.providers.zzsrt)) do
			local ln = ns.Lower(e.name)
			if ln:find("k", 1, true) and (not least or ln < least) then least = ln end
		end
		check(ok and r[1] and ns.Lower(r[1].name) == least, label .. ": A-Z from the first of all: " .. tostring(r[1] and r[1].name) .. " / " .. tostring(least))
	end
	UI.lastScan = nil
	Sorted(UI:Search("@zzsrt k sort:name"), "8000 rows, k sort:name")
	-- (typed: the search runs in slices, the sort among them)
	UI:Open("@zzsrt k sort:name"); FlushAll()
	Sorted(UI.Results(), "typed")
	UI:Hide(); FlushAll()
	ns.providers.zzsrt = nil
	for i, x in ipairs(ns.providerOrder) do if x == "zzsrt" then table.remove(ns.providerOrder, i) break end end
	ns:AliasesChanged()
	ns.db.easyMode = easy; UI:EasyChanged()
	UI.lastScan = nil
end

io.write("[review 0.63.7: a search grows no compact row]\n")
do
	local N = 3000
	local rows
	ns:RegisterProvider("zzmem", { label = "zzmem", aliases = { "zzmem" }, explicit = true,
		collect = function(p)
			local meta = ns:CompactMeta(p, { icon = "x" })
			rows = {}
			-- (seven fields: the score makes eight, the hash part's size; one more doubles it)
			for i = 1, N do rows[i] = setmetatable({ _compact = true, key = i, name = "Pebble " .. i, _lname = "pebble " .. i, a = 1, b = 2, c = 3 }, meta) end
			return rows
		end })
	local easy = ns.db.easyMode
	ns.db.easyMode = false; UI:EasyChanged()
	ns:GetEntries(ns.providers.zzmem)
	collectgarbage("collect")
	local before = collectgarbage("count")
	UI.lastScan = nil
	UI:Search("@zzmem peb")
	UI.lastScan = nil
	UI:Search("@zzmem pebble")
	collectgarbage("collect")
	local grew = (collectgarbage("count") - before) * 1024 / N
	check(grew < 100, "two searches: no row's table doubled: " .. string.format("%.0f B a row", grew))
	ns.providers.zzmem = nil
	for i, x in ipairs(ns.providerOrder) do if x == "zzmem" then table.remove(ns.providerOrder, i) break end end
	ns:AliasesChanged()
	ns.db.easyMode = easy; UI:EasyChanged()
	UI.lastScan = nil
end
