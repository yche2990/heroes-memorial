--- H5 damage spells: damage = base[mastery] + perPower[mastery] x SP (original values), then the engine's spell damage adjustments.
--- Parameters (in battleEffects of the spell json):
---   base, perPower   4 numbers, by none/basic/advanced/expert
---   requireAny       the target must have at least one of these bonuses (Word of Light only hits undead and demons)
---   exclude          targets with any of these bonuses are unaffected (Curse of the Netherworld does not hit undead or demons; Swarm does not hit non-living)
---   frags            true: damage also multiplied by sqrt(sum of levels of creatures the target killed this battle) (Holy Retribution, reading the target's H5_FRAGS_H5C)
---   chainLength, chainFactor  as the core damage effect
local Base = require("spells/damage")
local Lib = require("spells/h5SpellLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:isValidTarget(mechanics, unit)
	if not Base.isValidTarget(self, mechanics, unit) then return false end
	if not Lib.passesFilter(unit, self.requireAny, self.exclude) then return false end
	if self.frags and unit:getBonusesValue({ type = "H5_FRAGS_H5C" }) <= 0 then return false end
	return true
end

function Script:damageForTarget(targetIndex, mechanics, unit)
	local sp = Lib.power(mechanics)
	local lvl = Lib.level(mechanics)
	local raw = Lib.value(self.base, self.perPower, lvl, sp) * Lib.casterDamageFactor(mechanics)
	if self.frags then
		raw = raw * math.sqrt(math.max(0, unit:getBonusesValue({ type = "H5_FRAGS_H5C" })))
	end
	local dmg = Lib.adjust(mechanics, unit, raw)
	local chainLength = self.chainLength or 0
	if chainLength > 1 and targetIndex > 0 then
		dmg = math.floor((self.chainFactor ^ targetIndex) * dmg)
	end
	return dmg
end

--- 2026-11-06: engine 89ce99f1 calls describeTargetStep when choosing a target; the core spellEffect.lua has this function,
--- but unitEffect.lua does not inherit it (heal, dispel, damage and timed all come from unitEffect), and the log reports function 'describeTargetStep' not found.
--- If the base class lacks it, one returning nil is added (= the engine's default cursor text, same display as before); once the engine adds it, the engine's is used.
if not Base.describeTargetStep then
	function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
		return nil
	end
end

return Script
