local Base = require("spells/unitEffect")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Haunting Plague (H7): at cast time every (non-immune) enemy stack gets the hidden script h7HauntingPlague (turns rounds),
--- which at the start of the next two rounds picks count[mastery] random stacks to possess (Attack -10, Dark damage at round end). See combat/h7HauntingPlague.lua.
--- Spell json: no target, whole battlefield, smart (enemies only).
---
--- Parameters:
---   count            4 numbers, stacks possessed per round
---   base, perPower   raw Dark damage to possessed stacks = base + perPower x Spell Power (average of the H7 random range), plus the hero's spell bonus
---   turns            rounds the script lasts (= 2 rounds of possession + the final settlement)

function Script:isValidTarget(mechanics, unit)
	if not unit:isValidTarget(false) then return false end
	if unit:isTurret() or Lib.has(unit, "SIEGE_WEAPON") then return false end
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local key = mechanics:getSpell():getJsonKey()
	local lvl = Lib.level(mechanics)
	local count = self.count and (self.count[lvl + 1] or self.count[#self.count]) or 2
	local raw = Lib.value(self.base, self.perPower, lvl, Lib.power(mechanics)) * Lib.casterDamageFactor(mechanics)
	-- H7 audit A4: each cast gets an id and carriers are settled grouped by id (the simulation needs no real randomness and uses a fixed value)
	local group = 1
	if server:describeChanges() then group = server:rngInt(1, 999999) end
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and unit:isAlive() then
			local dmg = mechanics:applySpellBonus(math.floor(raw), unit)
			server:addUnitBonus(battle, unit, {
				type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h7:h7HauntingPlague", val = dmg,
				duration = ENUM.BonusDuration.nTurns, turns = self.turns or 4,
				sourceType = ENUM.BonusSource.spellEffect, sourceSecondaryID = mechanics:getEffectLevel(), sourceID = key, stacking = key .. "#" .. tostring(group),
				hidden = true, addInfo = { count = count, group = group }
			}, false)
		end
	end
end

--- Newer engines call this every time a target is chosen (logging an error if missing); returning nil uses the engine's default hint
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
