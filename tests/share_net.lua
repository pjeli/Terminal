-- Terminal: Share's tests' pretend network (tests/smoke/share.lua, share_groups.lua): endpoints by name, messages
-- delivered in order. Not a test file itself (not under tests/smoke/): each file loads it, `T` its helpers.
local T = ...
local ns = T.ns
local SSH = ns.Ssh
local H = {}

--- A group's key for the tests, from a word (any 32 bytes do: codes only, a key is never made from a typed password).
function H.Key(pw)
	return ("key|" .. tostring(pw) .. ("."):rep(32)):sub(1, 32)
end


--- A pretend network: endpoints by lowercase name, messages delivered in order on Run().
function H.Net()
	local net = { t = 1000, eps = {}, inbox = {}, sent = {}, says = {}, locked = false, throttle = 0, changed = 0,
		suffix = "" } -- (suffix: how a whisper's sender is written, "-Realm"; the guild channel's never has it)
	local function Who(s) return (SSH.Canon(s):gsub("%-realm$", "")) end
	function net.Add(name, opts)
		opts = opts or {}
		local me = { name = name, friends = opts.friends or {}, guild = opts.guild, items = opts.items or {}, realm = "realm" }
		local env = {
			now = function() return net.t end,
			claim = function() return SSH.Claim(name, me.realm) end,
			send = function(route, text)
				if net.throttle > 0 then net.throttle = net.throttle - 1; return 3 end
				if text:find("|", 1, true) then net.pipes = (net.pipes or 0) + 1 end -- (chat's escape character: never sent)
				net.sent[#net.sent + 1] = { from = name, route = route, text = text }
				if route.kind == "guild" then
					for other, ep in pairs(net.eps) do
						if other ~= name:lower() and ep.me.guild and ep.me.guild == me.guild then
							net.inbox[#net.inbox + 1] = { to = other, route = { kind = "guild", target = name }, text = text }
						end
					end
				else
					net.inbox[#net.inbox + 1] = { to = Who(route.target), route = { kind = "whisper", target = name .. net.suffix }, text = text }
				end
				return 0
			end,
			eligible = function(route)
				local who = route.target
				if Who(who) == Who(name) then return nil end
				if route.kind == "guild" then return who end
				if me.friends[Who(who)] then return who end
				local o = net.eps[Who(who)]
				if o and me.guild and o.me.guild == me.guild then return who end
				return nil
			end,
			matches = function(claim, route) return SSH.ClaimIs(claim, route.target) end,
			-- (here: ids under 1000 are consumables, 1000-1999 crafting mats; me.alt: an alt's bank, me.gold: all gold)
			items = function(mode)
				local keep = ({ limited = function(id) return id < 2000 end, consumables = function(id) return id < 1000 end,
					mats = function(id) return id >= 1000 and id < 2000 end })[mode]
				local out = {}
				for id, n in pairs(me.items) do if mode == "all" or (keep and keep(id)) then out[id] = n end end
				local snap = SSH.Simple(name, out)
				if mode == "all" then
					if me.alt then
						snap.places[2] = { who = name .. "alt", where = "k" }
						for id, n in pairs(me.alt) do
							snap.items[id] = snap.items[id] or {}
							snap.items[id][2] = n
						end
					end
					snap.gold = me.gold
				end
				return snap
			end,
			locked = function() return net.locked end,
			changed = function() net.changed = net.changed + 1 end,
			say = function(text) net.says[#net.says + 1] = name .. ": " .. text end,
			nonce = (function()
				local n = 0
				return function() n = n + 1; return ("%08x%08x"):format(#name * 7919 + name:byte(1), n) end
			end)(),
			broadcast = function()
				local out = {}
				if me.guild then out[#out + 1] = { kind = "guild" } end
				for c, shown in pairs(me.friends) do out[#out + 1] = { kind = "whisper", target = shown } end
				return out
			end,
		}
		local ep = SSH.Endpoint(env)
		ep.me = me
		ep.defaultMode = opts.mode or "all"
		net.eps[name:lower()] = ep
		return ep
	end
	function net.Run(max)
		local n = 0
		while #net.inbox > 0 and n < (max or 500) do
			local m = table.remove(net.inbox, 1)
			local ep = net.eps[m.to]
			if ep then ep:Receive(m.route, m.text) end
			n = n + 1
		end
	end
	function net.Tick(seconds)
		for _ = 1, seconds do
			net.t = net.t + 1
			for _, ep in pairs(net.eps) do ep:Tick() end
			net.Run()
		end
	end
	function net.SaidTo(from, to)
		local n = 0
		for _, m in ipairs(net.sent) do
			if m.from == from and m.route.target and SSH.Canon(m.route.target) == SSH.Canon(to) then n = n + 1 end
		end
		return n
	end
	function net.Said(pattern)
		for _, s in ipairs(net.says) do if s:find(pattern) then return true end end
		return false
	end
	return net
end

function H.Up(ep, name)
	for _, c in ipairs(ep:Connected()) do if c.name == name then return c end end
	return nil
end

-- A quick stand-in for HMAC (the harness's SHA-256 is plain arithmetic: a few handshakes would take the whole
-- instruction budget). It still differs for every key and message, so a wrong password or a relayed proof still fails.
local function QuickHMAC(key, msg)
	local s = tostring(key) .. "\0" .. tostring(msg)
	local a, b = 7, 13
	for i = 1, #s do
		local c = s:byte(i)
		a = (a * 31 + c) % 2147483629
		b = (b * 37 + c * 3 + i) % 2147483587
	end
	local out = {}
	for i = 1, 4 do out[i] = string.char(a % 256, b % 256, math.floor(a / 256) % 256, math.floor(b / 256) % 256); a, b = math.floor(a / 7) + b, math.floor(b / 5) + a end
	return table.concat(out, "", 1, 4) .. table.concat(out, "", 1, 4)
end
H.QuickHMAC = QuickHMAC

return H
