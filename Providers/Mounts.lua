local ns = select(2, ...)
local L = ns.L

local function SummonMount(e)
	if C_MountJournal and C_MountJournal.SummonByID then C_MountJournal.SummonByID(e.key) end
end
local function MountLink(e) return e.spellID and C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(e.spellID) or nil end

-- Shift+Enter: the journal opened with the collections key, as toys and pets do (Collections.lua: no /run line, which
-- runs tainted); Terminal points at the mount when it shows, at the Mounts tab while another shows.
local MOUNTS_TAB = 1
-- (its list, as with pets: the journal's big display above it names the mount selected, and pointed at that one when
-- it was the mount looked for; ListScrollFrame on older clients)
local function MountRoot() local M = _G.MountJournal; return M and (M.ScrollBox or M.ListScrollFrame or M) end
local function PointAtMount(e) local C = ns.Collections if C then C.PointIn(MountRoot, e.name, MOUNTS_TAB) end end
local function NoJournal(e) local C = ns.Collections if C then C.NoJournal(e) end end -- (combat: nothing opened)
-- (Shift+Enter: Collections.JOURNAL_SPEC, the same press as toys' and pets'; Collections.lua loads after this file, so
-- it's read when the rows are made)
local function JournalShown() local C = ns.Collections return C and C.JournalShown() or false end

-- Mounts (collected only). Enter = summon, Shift+Enter = show in journal.
----------------------------------------------------------------------

ns:RegisterProvider("mounts", {
	label = L["Mount"],
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
					detail = isFavorite and L["Favorite"] or "",
					spellID = spellID,
					getLink = MountLink, -- (made when selected, not for every mount on every rebuild)
					activate = SummonMount,
					secondary = NoJournal, secondarySecure = ns.Collections and ns.Collections.JOURNAL_SPEC, secondaryIsOpen = JournalShown,
					secondaryAfter = PointAtMount,
				}
			end
		end
		return out
	end,
})
