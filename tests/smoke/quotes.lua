-- (0.52.13, the player's ask) a "quoted phrase" is one string: "outlaw saber" finds names with those words together, as
-- they are, not every name with both words somewhere.
local T = ...
local ns, UI, check, FlushAll = T.ns, T.UI, T.check, T.FlushAll
local Scan = UI._Scan

io.write("[quotes: a \"quoted phrase\" is one string]\n")

-- the words, split
do
	local w, p = Scan.Words('outlaw "saber of" the  "  shadow   bolt "')
	check(#w == 2 and w[1] == "outlaw" and w[2] == "the" and #p == 2 and p[1] == "saber of" and p[2] == "shadow bolt",
		"the words and the phrases apart, inner spaces as one: " .. table.concat(w, ",") .. " / " .. table.concat(p, ","))
	w, p = Scan.Words('in:"elwynn forest" -"outlaw saber" "open phrase')
	check(w[1] == "in:elwynn forest" and w[2] == "-outlaw saber" and p[1] == "open phrase",
		"a quote inside a word joins the phrase to it; an open quote runs to the end: " .. table.concat(w, ",") .. " / " .. tostring(p[1]))
	w, p = Scan.Words('""')
	check(#w == 0 and #p == 0, "empty quotes: nothing")
end

do
	local save = { providers = ns.providers, order = ns.providerOrder, easy = ns.db.easyMode }
	ns.providers, ns.providerOrder = {}, {}
	ns:RegisterProvider("items", { label = "Item", aliases = { "item" }, collect = function()
		return {
			{ name = "Outlaw Saber", key = 1, detail = "Elwynn Forest" },
			{ name = "Saber of the Outlaw", key = 2, detail = "Westfall" },
			{ name = "Outlaw Sabretooth Cap", key = 3, detail = "Duskwood" },
			{ name = "Rusty Blade", key = 4, detail = "", text = "drops off an outlaw saber smith" },
			{ name = "Outlaw Silver Saber", key = 5, detail = "" }, -- (the phrase's letters in order, apart)
		}
	end })
	ns:AliasesChanged()
	ns.db.easyMode = false
	UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	local function Found(text)
		UI:Open(text)
		FlushAll()
		local got = {}
		for _, e in ipairs(UI.Results()) do if not e.noActivate and not e.completion then got[#got + 1] = e.name end end
		table.sort(got)
		return table.concat(got, ",")
	end

	local plain = Found("outlaw saber")
	check(plain:find("Saber of the Outlaw", 1, true) and plain:find("Outlaw Saber", 1, true) and plain:find("Silver", 1, true),
		"unquoted: both words anywhere: " .. plain)
	local quoted = Found('"outlaw saber"')
	check(quoted == "Outlaw Saber,Rusty Blade", "quoted: the phrase as it is, in the name or the row's text: " .. quoted)
	check(Found('"Outlaw Saber"') == quoted, "any case")
	check(Found('"outlaw sab') == "Outlaw Saber,Outlaw Sabretooth Cap,Rusty Blade", "an open quote while it's typed: "
		.. Found('"outlaw sab'))
	check(Found('"saber of" outlaw') == "Saber of the Outlaw", "a phrase and a word together")
	check(Found('"oulaw saber"') == "", "no close spellings of a phrase: " .. Found('"oulaw saber"'))
	check(Found('outlaw -"outlaw saber"') == "Outlaw Sabretooth Cap,Outlaw Silver Saber,Saber of the Outlaw",
		"-\"phrase\": not that phrase: " .. Found('outlaw -"outlaw saber"'))
	-- the letters lit up: the phrase's run of letters
	UI:Open('"saber"')
	FlushAll()
	local row
	for _, e in ipairs(UI.Results()) do if e.name == "Outlaw Saber" then row = e end end
	local pos = row and UI.Positions(row, UI.posTokens) or {}
	check(pos[8] and pos[12] and not pos[1], "the phrase's letters lit up in the name")
	-- typing on: a quote changes what matches (not narrowed from the last keystroke)
	Found("outlaw saber")
	check(Found('"outlaw saber"') == quoted, "a quote added: searched afresh")
	check(Found("outlaw saber"):find("Saber of the Outlaw", 1, true), "and taken off again")

	-- Simple mode too
	ns.db.easyMode = true
	UI:EasyChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	UI:Open('"outlaw saber"')
	FlushAll()
	local names = {}
	for _, e in ipairs(UI.Results()) do names[#names + 1] = tostring(e.name) end
	local all = table.concat(names, ",")
	check(not all:find("Saber of the Outlaw", 1, true) and not all:find("Advanced", 1, true), "Simple mode: quoted too: " .. all)
	UI:Hide(); FlushAll()
	ns.db.easyMode = false
	UI:EasyChanged()

	ns.providers, ns.providerOrder = save.providers, save.order
	ns:AliasesChanged()
	UI.lastScan, UI.lastExtra = nil, nil
	ns.db.easyMode = save.easy
	UI:EasyChanged()
	UI:Hide(); FlushAll()
end

-- (0.53.1, the player's screenshot) a filter's value in quotes is a filter like any other, and looks it: q:"Rare",
-- quality:"Rare", in:"elwynn forest" (spaces and all) in the filters' colour, not a bad one's
do
	local F, Theme = ns.Filters, ns.Theme
	check(F.Parse('q:"Rare"') and F.Parse('quality:"Rare"') and F.Parse('in:"elwynn forest"'), "quoted values parse as filters")
	check(F.Parse('q:""') == nil, "an empty quoted value isn't a filter")
	for _, t in ipairs({ '@loot q:"Rare"', '@loot quality:"Rare"', 'boar in:"elwynn forest"' }) do
		local segs = UI:SyntaxSegments(t)
		local last = segs[#segs]
		check(last and last[3] == Theme.SYNTAX.filter and last[1] < #t - 4, "coloured as a filter, quotes and all: " .. t)
	end
end
