local Base = require("spells/unitEffect")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Shadow Image (H7): summons an image of the target ally next to it (the engine's clone: vanishes on any damage, cannot be cloned again).
--- Image count = target count x pct[mastery]% x Spell Power (rounded, at least 1). The image stays until hurt or until the battle ends (H7 images have no time limit):
--- the clone marker (NONE, source = core Clone spell) lasts the whole battle.
--- Expert (with Dark Understanding III): the image gets h7ImageGuard (guardTurns rounds) and survives the first attack.
--- A stack can have only one image at a time (the engine records only one clone per stack).
---
--- Parameters:
---   pct          4 numbers, percentage of the target count copied per point of Spell Power
---   guard        4 booleans, whether the image gets h7ImageGuard
---   guardTurns   rounds of h7ImageGuard
---   icon         icon for display

function Script:isValidTarget(mechanics, unit)
	if unit:isClone() or unit:hasClone() then return false end
	if unit:isTurret() or Lib.has(unit, "SIEGE_WEAPON") then return false end
	return unit:isValidTarget(false)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local lvl = Lib.level(mechanics)
	local sp = Lib.power(mechanics)
	local pct = self.pct and (self.pct[lvl + 1] or self.pct[#self.pct]) or 1
	local guard = self.guard and self.guard[lvl + 1]
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and unit:isAlive() and unit:getCount() >= 1 then
			local creature = unit:getCreature()
			local hex = battle:getAvailableHex(creature, mechanics:getCasterSide(), unit:getPosition())
			if not hex:isValid() then break end
			local count = math.max(1, math.floor(unit:getCount() * pct * sp / 100))
			local clone = server:addUnit(battle, {
				count = count, type = creature, side = mechanics:getCasterSide(), position = hex, summoned = true
			})
			if clone == nil then break end
			local cs = clone:copy()
			cs:setCloned(true)
			server:changeUnit(battle, cs)
			local os = unit:copy()
			os:setClone(clone)
			server:changeUnit(battle, os)
			-- Clone marker: the engine only recognizes a NONE bonus whose source is the core Clone spell (BonusCache CLONE_MARKER), lasting the whole battle
			server:addUnitBonus(battle, clone, {
				type = "NONE", val = 0, duration = ENUM.BonusDuration.oneBattle,
				sourceType = ENUM.BonusSource.spellEffect, sourceSecondaryID = mechanics:getEffectLevel(), sourceID = "clone"
			}, true)
			if guard then
				local d = {
					type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h7:h7ImageGuard", val = 1,
					duration = ENUM.BonusDuration.nTurns, turns = self.guardTurns or 3,
					sourceType = ENUM.BonusSource.spellEffect, sourceSecondaryID = mechanics:getEffectLevel(), sourceID = mechanics:getSpell():getJsonKey()
				}
				if self.icon then d.icon = self.icon end
				server:addUnitBonus(battle, clone, d, true)
			end
		end
	end
end

--- Newer engines call this every time a target is chosen (logging an error if missing); returning nil uses the engine's default hint
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
