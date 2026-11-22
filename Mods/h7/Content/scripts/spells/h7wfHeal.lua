local Base = require("spells/unitEffect")
local W = require("heroes-memorial.h7:combat/h7WarfareLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Healing of the normal creature version (round 428, Dream Walker's Shamanic Healing): a living friendly stack (undead, constructs and war machines excluded) regains per x casting stack size health, no resurrection.
--- The warfare version uses engine healing (amount = SPECIFIC_SPELL_POWER); normal creatures count by stack size, so it is written separately. The AI simulation follows the actual healing. Parameter: per

function Script:isValidTarget(mechanics, unit)
	return W.healable(unit, false)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil then return end
	local v = (self.per or 0) * caster:getCount()
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u and W.healable(u, false) then
			local h = W.heal(server, battle, u, v)
			if h > 0 and server:describeChanges() then
				server:showBattleAnimation(battle, { { unit = u } }, self.animation or "h7/fx/h7wfShamanHeal", "", 1.0, true)
				server:refreshBattleUnits(battle)
			end
		end
	end
end

--- Amount restored shown in the mouse hint
function Script:getHealthChange(mechanics, spellTarget)
	return { hpDelta = 0, unitsDelta = 0 }
end

function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
