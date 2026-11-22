local Base = require("spells/spellEffect")
local L = require("combat/h6Lib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Dragon Flight (H6 Daughter of Malassa): cast on herself. She takes to the sky (cannot be attacked or targeted by spells until her next action)
--- and summons a stack of summon next to each enemy stack (summoned, gone after battle), count = pct% of that enemy's total health / health of the summoned creature (at least 1).
--- Parameters: summon, pct, key, animation, sound

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget); return false end
	return true
end
function Script:applicableTarget(mechanics, problem, target) return true end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil then return end
	local cre = LIBRARY:getCreatureByName(self.summon)
	local made = 0
	-- Round 419: in the AI simulation no stacks are added to the imaginary battlefield; each enemy stack is reported as proxy damage worth half the value of the Dark Elementals summoned
	if cre and Proxy.trial(server) then
		for _, e in ipairs(battle:getUnitsIf(function(u) return L.real(u) and battle:isHostile(caster, u) end)) do
			Proxy.damage(server, battle, e, e:getAvailableHealth() * (self.pct or 15) / 100 * 0.5)
		end
		cre = nil
	end
	if cre then
		local hp = cre:getMaxHealth()
		for _, e in ipairs(battle:getUnitsIf(function(u) return L.real(u) and battle:isHostile(caster, u) end)) do
			local hex = battle:getAvailableHex(cre, caster:getSide(), e:getPosition())
			if hex:isValid() then
				local n = math.max(1, math.floor(e:getAvailableHealth() * (self.pct or 15) / 100 / math.max(1, hp)))
				if server:addUnit(battle, { count = n, type = cre, side = caster:getSide(), position = hex, summoned = true }) then made = made + 1 end
			end
		end
	end
	server:addUnitBonus(battle, caster, { type = "INVINCIBLE", val = 0, duration = ENUM.BonusDuration.stackGetsTurn,
		sourceType = ENUM.BonusSource.other, sourceID = caster:getCreature():getJsonKey(), stacking = "h6DragonFlight" }, true)
	L.show(server, battle, { caster }, self.animation, self.sound)
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_SUMMON_H6C", 1, { L.name(caster) }, { made })
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

return Script
