local Base = require("spells/unitEffect")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Martyrdom (H7): choose an ally as the martyr, for turns rounds (or until the martyr dies).
---   Martyr: visible mark H7_MARTYR_H7C (value = share share[mastery] %) and the hidden h7MartyrEnd (removes the Martyrdom effects from the whole army when it dies).
---   Every other stack of the same side (arrow towers excluded): Morale +morale and the sharing script h7Martyr (damage taken is shared by the martyr).
--- All these bonuses come from this spell (spell effects) and vanish together when dispelled. Casting again switches to the new martyr.
---
--- Parameters:
---   share    4 numbers, share %
---   morale   Morale bonus of the other allies (H7 +10 converted to +1)
---   turns    rounds
---   icon     icon for display

local MARK = "H7_MARTYR_H7C"

function Script:isValidTarget(mechanics, unit)
	if not unit:isValidTarget(false) then return false end
	if unit:isTurret() or Lib.has(unit, "SIEGE_WEAPON") then return false end
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local key = mechanics:getSpell():getJsonKey()
	local lvl = Lib.level(mechanics)
	local share = self.share and (self.share[lvl + 1] or self.share[#self.share]) or 100
	local turns = self.turns or 3
	local dest = target[1]
	local martyr = dest and dest.unit
	if martyr == nil or not martyr:isAlive() then return end
	local side = martyr:getSide()

	-- First remove this side's old Martyrdom effects (switching martyrs)
	local everyone = battle:getUnitsIf(function(u) return u:getSide() == side and u:isAlive() end)
	for _, u in ipairs(everyone) do
		local old = u:getBonuses({}):filter(function(b)
			return b:getSource() == ENUM.BonusSource.spellEffect and b:getSourceID() == key
		end)
		if old:size() > 0 then server:removeUnitBonuses(battle, u, old) end
	end

	server:addUnitBonus(battle, martyr, {
		type = MARK, val = share, duration = ENUM.BonusDuration.nTurns, turns = turns,
		sourceType = ENUM.BonusSource.spellEffect, sourceSecondaryID = mechanics:getEffectLevel(), sourceID = key
	}, false)
	server:addUnitBonus(battle, martyr, {
		type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h7:h7MartyrEnd", val = share,
		duration = ENUM.BonusDuration.nTurns, turns = turns,
		sourceType = ENUM.BonusSource.spellEffect, sourceSecondaryID = mechanics:getEffectLevel(), sourceID = key, hidden = true
	}, false)

	local mid = martyr:unitID()
	for _, u in ipairs(everyone) do
		if u:unitID() ~= mid and not u:isTurret() and not u:isGhost() then
			server:addUnitBonus(battle, u, {
				type = "MORALE", val = self.morale or 1, duration = ENUM.BonusDuration.nTurns, turns = turns,
				sourceType = ENUM.BonusSource.spellEffect, sourceSecondaryID = mechanics:getEffectLevel(), sourceID = key, stacking = key .. "Adoration"
			}, false)
			local d = {
				type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h7:h7Martyr", val = share,
				duration = ENUM.BonusDuration.nTurns, turns = turns,
				sourceType = ENUM.BonusSource.spellEffect, sourceSecondaryID = mechanics:getEffectLevel(), sourceID = key, stacking = key .. "Share"
			}
			if self.icon then d.icon = self.icon end
			server:addUnitBonus(battle, u, d, false)
		end
	end
end

--- Newer engines call this every time a target is chosen (logging an error if missing); returning nil uses the engine's default hint

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Martyrdom (H7): choose the martyr who shares the damage of the whole army
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "kadCursorLink" } -- step number -> cursor
	local AIM = { ["*"] = "creature" } -- target type of the first step (spell targetType)
	if hoveredHex == nil or not hoveredHex:isValid() or mechanics:isMassive() then return nil end
	local step = #partialTarget + 1
	local cursor = CURSORS[step]
	if cursor == nil then return nil end
	local spell = mechanics:getSpell()
	if step ~= 1 then return nil end
	local aim = AIM[spell:getJsonKey()] or AIM["*"]
	if aim ~= "creature" and aim ~= "location" then return nil end
	local spellName = spell:getNameTextID()
	if aim == "creature" then
		local battle = mechanics:getBattle()
		local unit = battle:getUnitByPos(hoveredHex, true) or battle:getUnitByPos(hoveredHex, false)
		local names = { spellName }
		if unit ~= nil then table.insert(names, unit:getCreature():getNameTextID(unit:getCount())) end
		return {
			cursor = cursor,
			text = { append = { "core.genrltxt.27" }, replaceStrings = names }, -- Cast %s on %s
			blockedText = { append = { "core.genrltxt.23" } },                  -- Select a target for the spell
			healthGainTextID = "vcmi.battleWindow.healValuePreview"
		}
	end
	return {
		cursor = cursor,
		text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } }, -- Cast %s
		healthGainTextID = "vcmi.battleWindow.healValuePreview"
	}
end

return Script
