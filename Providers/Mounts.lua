local ns = select(2, ...)
local H = ns.Highlight

local function SummonMount(e)
	if C_MountJournal and C_MountJournal.SummonByID then C_MountJournal.SummonByID(e.key) end
end
local function MountLink(e) return e.spellID and C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(e.spellID) or nil end

local function ShowMount(e)
	ns.LoadBlizz("Blizzard_Collections")
	if CollectionsJournal_SetTab and CollectionsJournal then
		ShowUIPanel(CollectionsJournal)
		CollectionsJournal_SetTab(CollectionsJournal, 1)
	end
	H:Find(function()
		local root = _G.MountJournal
		return root and root:IsVisible() and ns.FindByText(root, e.name) or nil
	end)
end

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
					secondary = ShowMount,
				}
			end
		end
		return out
	end,
})
