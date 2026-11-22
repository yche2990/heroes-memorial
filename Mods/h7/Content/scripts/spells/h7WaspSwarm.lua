--- Wasp Swarm (H7): cast on an enemy stack. It immediately takes base + perPower x Spell Power physical damage (the H7 original ignores resistance; not adjusted here either),
--- with Luck -2 until the end of its current action; after it acts the swarm moves to another stack of that side (combat/h7WaspSwarmJump).
--- targets[mastery]: total stacks affected (3/4/6/8).
local Base = require("spells/unitEffect")
local Lib = require("spells/h5SpellLib")
local Jump = require("heroes-memorial.h7:combat/h7WaspSwarmJump")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:isValidTarget(mechanics, unit)
	if not Base.isValidTarget(self, mechanics, unit) then return false end
	return not unit:isTurret()
end

function Script:getHealthChange(mechanics, spellTarget)
	local result = { hpDelta = 0, unitsDelta = 0 }
	local raw = Lib.value(self.base, self.perPower, Lib.level(mechanics), Lib.power(mechanics))
	for _, dest in ipairs(spellTarget) do
		local unit = dest.unit
		if unit and unit:isAlive() then
			local copy = unit:copy()
			local hp, cnt = copy:getAvailableHealth(), copy:getCount()
			copy:damage(math.floor(raw))
			result.hpDelta = result.hpDelta - (hp - copy:getAvailableHealth())
			result.unitsDelta = result.unitsDelta - (cnt - copy:getCount())
		end
	end
	return result
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local spellKey = mechanics:getSpell():getJsonKey()
	local lvl = Lib.level(mechanics)
	local raw = Lib.value(self.base, self.perPower, lvl, Lib.power(mechanics)) * Lib.casterDamageFactor(mechanics)
	local total = self.targets and (self.targets[lvl + 1] or self.targets[#self.targets]) or 3
	for _, dest in ipairs(target) do
		if dest.unit and dest.unit:isAlive() then
			Jump.sting(server, battle, dest.unit, raw, total - 1, spellKey, self.icon, self.eventScript, mechanics:getEffectLevel())
		end
	end
end

function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
