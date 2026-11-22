local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Cooldowns and uses of boss abilities (round 352): a boss creature has several active abilities with their own cooldowns, so the shared cooldown mark of the creature batch is not enough.
--- This effect goes into the ability's spell (not as an optional effect): while on cooldown or out of uses this battle, the whole spell cannot be cast.
--- After casting it records the cooldown (cd rounds: cast in round 1 with cooldown 2 -> usable again in round 4) and refunds this cast (casts are shared by all abilities).
--- Parameters: key (ability name), cd, uses

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	local k = self.key or mechanics:getSpell():getJsonKey()
	local ok = caster ~= nil and caster:isAlive()
	if ok and (self.cd or 0) > 0 and L.markValue(caster, "cd:" .. k) then ok = false end
	if ok and self.uses and (L.markValue(caster, "uses:" .. k) or 0) >= self.uses then ok = false end
	if not ok then problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget) end
	return ok
end

function Script:applicableTarget(mechanics, problem, target) return true end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil then return end
	local k = self.key or mechanics:getSpell():getJsonKey()
	if (self.cd or 0) > 0 then L.setMark(server, battle, caster, "cd:" .. k, self.cd, self.cd + 1) end
	if self.uses then L.setMark(server, battle, caster, "uses:" .. k, (L.markValue(caster, "uses:" .. k) or 0) + 1) end
	server:addUnitBonus(battle, caster, { type = "CASTS", val = 1, valueType = ENUM.BonusValueType.additiveValue,
		duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.creatureAbility,
		sourceID = caster:getCreature():getJsonKey(), hidden = true }, true)
end

return Script
