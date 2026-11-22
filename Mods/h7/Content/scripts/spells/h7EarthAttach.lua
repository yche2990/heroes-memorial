--- H7 Earth spells: put a round-based combat event on the target (Regeneration, Poison Spray, the movement damage of Expert Entangle).
--- Value = base[mastery] + perPower[mastery] x Spell Power (the h5SpellLib formula of heroes-memorial.h5; for hero casts, the hero's Spell Power).
--- Parameters:
---   eventScript   full name of the combat event script (e.g. "heroes-memorial.h7:h7RegenTick")
---   base, perPower   4 numbers, by none/basic/advanced/expert
---   adjust        true: the value is adjusted by the spell damage flow (school reduction, magic reduction, vulnerability, hero spell bonus), separately for each target
---   turns         4 numbers, rounds it lasts; 0 = the whole battle
---   requireAny, exclude   target filters (bonus type names)
---   icon          icon shown on the stack
---   stacking      stacking group (one per group, recasting refreshes), default the spell name
local Base = require("spells/unitEffect")
local Lib = require("spells/h5SpellLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:isValidTarget(mechanics, unit)
	if not Base.isValidTarget(self, mechanics, unit) then return false end
	if unit:isTurret() then return false end
	return Lib.passesFilter(unit, self.requireAny, self.exclude)
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local spellKey = mechanics:getSpell():getJsonKey()
	local sp, lvl = Lib.power(mechanics), Lib.level(mechanics)
	local raw = Lib.value(self.base, self.perPower, lvl, sp) * Lib.casterDamageFactor(mechanics)
	local turns = 0
	if self.turns then turns = self.turns[lvl + 1] or self.turns[#self.turns] or 0 end
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and unit:isAlive() then
			local val = math.floor(raw)
			if self.adjust then val = Lib.adjust(mechanics, unit, raw) end
			if val > 0 then
				local d = {
					type = "COMBAT_EVENT_TRIGGER",
					subtype = self.eventScript,
					val = val,
					sourceType = "SPELL_EFFECT", sourceSecondaryID = mechanics:getEffectLevel(),
					sourceID = spellKey,
					stacking = self.stacking or spellKey,
					addInfo = { side = mechanics:getCasterSide(), spell = spellKey }
				}
				if turns > 0 then
					d.duration = "N_TURNS"
					d.turns = turns
				else
					d.duration = "ONE_BATTLE"
				end
				if self.icon then d.icon = self.icon end
				server:addUnitBonus(battle, unit, d, false)
			end
		end
	end
end

--- Newer engines call this when choosing a target; returning nil uses the engine's default hint
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
