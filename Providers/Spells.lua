local ns = select(2, ...)
local H = ns.Highlight

ns:RegisterProvider("spells", {
	label = "Spell",
	color = "ff9d7bff",
	aliases = { "spell", "ability", "abilities", "spellbook" },
	events = { "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" },
	guard = 2,
	collect = function()
		local out, seen = {}, {}
		local bank = Enum.SpellBookSpellBank.Player
		for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
			local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
			if li and not li.shouldHide then
				for i = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
					local it = C_SpellBook.GetSpellBookItemInfo(i, bank)
					if it and it.spellID and it.spellID > 0 and not seen[it.spellID]
						and it.itemType == Enum.SpellBookItemType.Spell and not it.isOffSpec then
						seen[it.spellID] = true
						local info = C_Spell.GetSpellInfo(it.spellID)
						if info and info.name then
							out[#out + 1] = {
								key = it.spellID,
								name = info.name,
								icon = info.iconID,
								detail = (it.isPassive and "Passive  " or "") .. (li.name or ""),
								link = C_Spell.GetSpellLink(it.spellID),
								spellID = it.spellID,
								activate = function(e)
									ns.LoadBlizz("Blizzard_PlayerSpells")
									if PlayerSpellsUtil and PlayerSpellsUtil.OpenToSpellBookTab then
										PlayerSpellsUtil.OpenToSpellBookTab()
									elseif type(_G.ToggleSpellBook) == "function" then
										_G.ToggleSpellBook("spell")
									elseif PlayerSpellsFrame then
										ShowUIPanel(PlayerSpellsFrame)
									end
									H:Find(function()
										local root = PlayerSpellsFrame or SpellBookFrame
										if not root or not root:IsVisible() then return nil end
										return ns.FindByText(root, e.name)
									end, 8)
								end,
								-- Shift+Enter: pick the spell up so it can be dropped on an action bar
								secondary = function(e)
									C_Spell.PickupSpell(e.spellID)
								end,
							}
						end
					end
				end
			end
		end
		return out
	end,
})
