local ns = select(2, ...)

local function SummonMount(e)
	if C_MountJournal and C_MountJournal.SummonByID then C_MountJournal.SummonByID(e.key) end
end
local function MountLink(e) return e.spellID and C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(e.spellID) or nil end

-- Shift+Enter: the journal on the mounts tab with the name in its search box, opened by the game (a /run line on the
-- secure button, as toys and pets do: Collections.lua); Terminal only points at it afterwards. Opening it from
-- Terminal's code ran the journal's Lua tainted, and didn't search, so the mount could be on another page.
local MOUNTS_TAB = 1
local function MountJournalMacro(e)
	local C = ns.Collections
	return C and C.JournalMacro(MOUNTS_TAB, "MountJournal and MountJournal.searchBox", e.name) or nil
end
local function MountRoot() return _G.MountJournal end
local function PointAtMount(e) local C = ns.Collections if C then C.PointIn(MountRoot, e.name) end end
local function NoJournal(e) local C = ns.Collections if C then C.NoJournal(e) end end -- (combat: nothing opened)
local MOUNT_JOURNAL = { macro = MountJournalMacro }

-- Mounts (collected only). Enter = summon, Shift+Enter = show in journal.
----------------------------------------------------------------------

ns:RegisterProvider("mounts", {
	label = "Mount",
	color = "ff7bd88f",
	aliases = { "mount" },
	events = { "NEW_MOUNT_ADDED", "COMPANION_LEARNED" },
	collect = function()
		local out = {}
		local M = C_MountJournal
		if not (M and M.GetMountIDs and M.GetMountInfoByID) then return out end -- (a client without the journal)
		for _, mountID in ipairs(ns.Safe(M.GetMountIDs) or {}) do
			local name, spellID, icon, _, isUsable, _, isFavorite, _, _, hideOnChar, isCollected =
				ns.Safe(M.GetMountInfoByID, mountID)
			if name and isCollected and not hideOnChar then
				out[#out + 1] = {
					key = mountID,
					name = name,
					icon = icon,
					detail = isFavorite and "Favorite" or "",
					spellID = spellID,
					getLink = MountLink, -- (made when selected, not for every mount on every rebuild)
					activate = SummonMount,
					secondary = NoJournal, secondarySecure = MOUNT_JOURNAL, secondaryIsOpen = ns.Never,
					secondaryAfter = PointAtMount,
				}
			end
		end
		return out
	end,
})
