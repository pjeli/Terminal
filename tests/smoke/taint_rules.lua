-- Taint rules checked over the source: calls Terminal's code must never make (Blizzard Lua that writes a window's state).
local T = ...
local check = T.check

do
	-- (1.1.6) no file of Terminal's (or its two addons') calls the game's bag openers: a friend of the player's couldn't
	-- eat from their bags after Terminal had opened them
	local calls = {}
	local OPENERS = { "OpenAllBags", "OpenBackpack", "OpenBag", "ToggleAllBags", "ToggleBackpack", "ToggleBag", "CloseAllBags", "CloseBag", "CloseBackpack" }
	for _, toc in ipairs({ "Terminal/Terminal.toc", "Terminal/Terminal_Extras/Terminal_Extras.toc", "Terminal/Terminal_Share/Terminal_Share.toc" }) do
		local dir = toc:match("^(.*)/")
		for line in io.open(toc):read("*a"):gmatch("[^\r\n]+") do
			local f = line:match("^([^#%s][^\r\n]-%.lua)%s*$")
			local h = f and io.open(dir .. "/" .. f:gsub("\\", "/"))
			local text = h and h:read("*a")
			if h then h:close() end
			-- (only files naming one at all are read line by line: the instruction budget)
			local named = false
			for _, fn in ipairs(OPENERS) do
				if text and text:find(fn, 1, true) then named = true end
			end
			if named then
				local n = 0
				for code in text:gmatch("[^\n]+") do
					n = n + 1
					local body = code:gsub("%-%-.*$", "")
					for _, fn in ipairs(OPENERS) do
						if body:find(fn, 1, true) and (body:find("[^%w_.:\"']" .. fn .. "%s*%(") or body:find("^" .. fn .. "%s*%(")
							or body:find("pcall%(%s*" .. fn .. "[,)]")) then
							calls[#calls + 1] = f .. ":" .. n .. " " .. fn
						end
					end
				end
			end
		end
	end
	check(#calls == 0, "no addon code calls the game's bag openers: " .. table.concat(calls, ", "))
end
