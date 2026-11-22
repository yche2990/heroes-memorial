local Base = require("spells/unitEffect")
local Lib = require("heroes-memorial:spells/h5SpellLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Shadow Cloak (H7): gives the target ally charges[mastery] layers of Shadow Cloak, for turns rounds or until the layers are used up.
--- Two parts are attached: the script h7ShadowCloakSpell (spell effect, dispellable; inherits the collection's h47ShadowCloak) and the layer mark (value = layers).
--- Casting again refreshes layers and rounds. Clones (mirror images) cannot be cloaked (the original script says clones have no cloak).
---
--- Parameters:
---   charges   4 numbers, layers
---   turns     rounds
---   mark      layer mark bonus name (visible)
---   flag      hidden mark bonus name for misses
---   icon      icon for display

function Script:isValidTarget(mechanics, unit)
	if not unit:isValidTarget(false) then return false end
	if unit:isClone() or unit:isTurret() then return false end
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local key = mechanics:getSpell():getJsonKey()
	local lvl = Lib.level(mechanics)
	local n = self.charges and (self.charges[lvl + 1] or self.charges[#self.charges]) or 1
	local turns = self.turns or 3
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and unit:isAlive() then
			local marks = unit:getBonuses({ type = self.mark })
			if marks:size() > 0 then server:removeUnitBonuses(battle, unit, marks) end
			local d = {
				type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h7:h7ShadowCloakSpell", val = n,
				duration = ENUM.BonusDuration.nTurns, turns = turns,
				sourceType = ENUM.BonusSource.spellEffect, sourceSecondaryID = mechanics:getEffectLevel(), sourceID = key, stacking = key,
				addInfo = { mark = self.mark, flag = self.flag }
			}
			if self.icon then d.icon = self.icon end
			server:addUnitBonus(battle, unit, d, false)
			server:addUnitBonus(battle, unit, {
				type = self.mark, val = n, duration = ENUM.BonusDuration.nTurns, turns = turns,
				sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey()
			}, true)
		end
	end
end

--- Newer engines call this every time a target is chosen (logging an error if missing); returning nil uses the engine's default hint
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
