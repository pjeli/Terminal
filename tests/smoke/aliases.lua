-- Your own commands (Aliases.lua, 0.50.4, the player's ask): .alias <name> <a search, /slash or .command> makes .<name>
-- run it; words typed after it go at the end (or where $* is); .alias lists, .unalias forgets; Terminal's own command
-- names can't be taken.
local T = ...
local ns, UI, check, FlushAll, key, S = T.ns, T.UI, T.check, T.FlushAll, T.key, T.S
local A = ns.Aliases
local L = ns.L

io.write("[aliases: your own commands]\n")
do
	local save = { store = ns.db.commandAliases, easy = ns.db.easyMode }
	ns.db.commandAliases = {}
	A.Load()
	local function Run(line) return ns:FindCommand("alias").run(line) end
	check(Run("")[1]:find("No aliases yet", 1, true), ".alias with none: says how to make one")
	-- making them
	check(Run("rep durability")[1] == L["Alias .%s runs: %s"]:format("rep", "durability"), "a search")
	-- (0.50.7, review: the example was .alias rl /reload, and rl is .reload's: refused, and this only looked for ".rl")
	check(Run("brb /afk brb")[1] == L["Alias .%s runs: %s"]:format("brb", "/afk brb"), "a slash command")
	check(Run("dark .theme dracula")[1]:find(".dark", 1, true), "a dot command")
	-- (review, 0.53.6) an alias naming another in other letters (".Heal" for heal): followed to what it runs, as the
	-- store keeps names lowercase; else .heal's own command ran its /cast from Terminal's code, tainted
	Run("heal /cast Flash Heal")
	check(A.Resolve(".Heal") == "/cast Flash Heal" and A.Resolve(".heal") == "/cast Flash Heal",
		"an alias named in capitals followed to its /slash line: " .. tostring(A.Resolve(".Heal")))
	ns:FindCommand("unalias").run("heal")
	check(Run("wh /w $* hi")[1]:find(".wh", 1, true), "with $*")
	check(Run("help me")[1] == L[".%s is already one of Terminal's commands: pick another name."]:format("help")
		and Run("rl2? x")[1]:find("letters, digits", 1, true) and Run("loop .loop")[1]:find("itself", 1, true)
		and Run("h x")[1]:find("already one", 1, true),
		"not one of Terminal's names (or another name of one), not odd characters, not itself")
	check(ns.db.commandAliases.rep == "durability" and ns.commands.rep and ns.commands.rep.isAlias, "kept, and a command")
	local list = table.concat(Run(""), "\n")
	check(list:find(".dark  ->  .theme dracula", 1, true) and list:find(".rep  ->  durability", 1, true), ".alias lists them: " .. list)
	check(Run("rep")[1] == ".rep  ->  durability", ".alias rep says what it runs")
	check(A.Expand("/w $* hi", "bob") == "/w bob hi" and A.Expand("durability", "legs") == "durability legs"
		and A.Expand("durability", "") == "durability", "words after it: at the end, or where $* is")

	-- a search: the terminal walks to it (and stays open)
	ns.db.easyMode = false
	UI:Open(".rep"); FlushAll()
	local row = UI.Results()[1]
	check(row and row.name == "rep" and row.kindLabel:find(L["alias"], 1, true) and row.detail:find("durability", 1, true),
		".rep in the command list, labelled an alias: " .. tostring(row and row.kindLabel))
	key("ENTER"); FlushAll()
	check(UI:IsShown() and UI.edit:GetText() == "durability", "Enter: the terminal shows the search: " .. UI.edit:GetText())
	UI:Hide(); FlushAll()
	UI:Open(".rep legs"); FlushAll()
	key("ENTER"); FlushAll()
	check(UI.edit:GetText() == "durability legs", "with words: added to it: " .. UI.edit:GetText())
	UI:Hide(); FlushAll()
	-- closed: /term .rep opens on it
	ns.commands.rep.run("")
	check(UI:IsShown() and UI.edit:GetText() == "durability", "run with the terminal closed: it opens on the search")
	UI:Hide(); FlushAll()

	-- Advanced syntax from Simple mode: Advanced for that one run (as Alt+` makes it)
	Run("dmg @durability is:damaged")
	ns.db.easyMode = true
	UI:Open(".dmg"); FlushAll()
	key("ENTER"); FlushAll()
	check(UI:IsShown() and UI.edit:GetText() == "@durability is:damaged" and not ns.Easy.On(), "Simple mode: Advanced for that run: "
		.. UI.edit:GetText() .. " / " .. tostring(ns.Easy.On()))
	UI:Hide(); FlushAll()
	check(ns.Easy.On(), "and Simple again once it closes")
	ns.db.easyMode = false
	-- a slash command: pressed by the game, as a slash row
	UI:Open(".wh bob"); FlushAll()
	key("ENTER")
	local up = _G.TerminalMacroProxy
	check(S.armed == "MACRO" and up and up.attrs.macrotext == "/w bob hi", "a slash alias: the game presses it: " .. tostring(up and up.attrs.macrotext))
	up.scripts.PostClick(up, "LeftButton", true); FlushAll()
	check(not UI:IsShown() and S.armed == nil, "pressed: the terminal closes")
	-- (0.50.7, review) the pointer resting on the row while more words are typed: a click runs the line as typed now
	UI:Open(".wh bob"); FlushAll()
	UI:PlaceCatcher(1)
	local c = _G.TerminalClickCatcher
	check(c and c.attrs.macrotext1 == "/w bob hi", "the click: /w bob hi: " .. tostring(c and c.attrs.macrotext1))
	T.typeText(" x"); FlushAll()
	UI:PlaceCatcher(1)
	check(c.attrs.macrotext1 == "/w bob x hi", "typed on under the pointer: the click's line follows: " .. tostring(c.attrs.macrotext1))
	UI:HideCatcher(); UI:Hide(); FlushAll()
	-- (0.50.7, review) an alias naming a /slash alias: pressed by the game as that one is, not run from Terminal's code
	Run("heal /cast Flash Heal")
	Run("fh .heal")
	local h = ns.commands.fh
	UI.args = nil -- (the words typed after a command: none here)
	check(h and h.secure and h.secure.macro() == "/cast Flash Heal" and h.isOpen == ns.Never and h.aliasText == ".heal",
		".fh -> .heal -> /cast Flash Heal: a slash alias itself: " .. tostring(h and h.secure and h.secure.macro()))
	Run("fs .rep")
	check(ns.commands.fs and ns.commands.fs.staysOpen, "one naming a search alias: a search")
	ns:FindCommand("unalias").run("fh"); ns:FindCommand("unalias").run("fs"); ns:FindCommand("unalias").run("heal")
	-- a dot command: run
	local theme = ns.db.theme
	local out = ns.commands.dark.run("")
	check(type(out) == "table", "a dot alias runs that command: " .. tostring(out and out[1]))
	if ns.SetTheme and theme then pcall(ns.SetTheme, theme) end
	ns.db.theme = theme
	-- aliases running aliases stop before going round forever
	ns.db.commandAliases.a1 = ".a2"; ns.db.commandAliases.a2 = ".a1"
	A.Load()
	out = ns.commands.a1.run("")
	check(type(out) == "table" and tostring(out[1]):find("too deep", 1, true), "a loop: stopped, said so: " .. tostring(out and out[1]))

	-- forgetting
	local un = ns:FindCommand("unalias").run("rep")
	check(un[1] == L["Forgot .%s."]:format("rep") and ns.commands.rep == nil and ns.db.commandAliases.rep == nil, ".unalias rep: gone")
	check(ns:FindCommand("unalias").run("rep")[1] == L["No alias .%s"]:format("rep"), "forgetting one there isn't: said")
	-- (a name of Terminal's own kept from before isn't made a command over it)
	ns.db.commandAliases.help = "durability"
	A.Load()
	check(not ns.commands.help.isAlias, "Terminal's .help stays its own")

	ns.db.commandAliases = save.store or {}
	A.Load()
	ns.db.easyMode = save.easy
end
