local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Withering Breath (H6 Shadow Dragon, Black Dragon)
---
--- Cast on an enemy stack (range hexes, default 3): takes pct% of a normal attack as Dark damage (H3 formula, scaled by Dark reduction, no counterattack);
--- then at the start of each round it takes dotPct% (default 15) of that damage as Dark damage over time, +1% each round, up to dotMax% (default 20), until the battle ends.
--- Damage over time is settled by the battle-wide combat/h6WitherTick; on the target: H6_WITHER_H6C (value = this damage, visible), hidden mark h6WitherPct (current percentage),
--- h6WitherMax (cap = dotMax; from 2026-11-08 h6WitherTick reads it, so the cap is written only in the spell parameters).
--- Parameters: pct, range, dotPct, dotMax, key, animation, sound

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil or not L.real(unit) or unit:isInvincible() then return false end
	return mechanics:getBattle():isHostile(caster, unit) and L.unitDistance(caster, unit) <= (self.range or 3)
end

function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then return true end
	end
	problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
	return false
end

function Script:applicableGeneral(mechanics, problem)
	local found = mechanics:getBattle():getUnitsIf(function(u) return self:isValidTarget(mechanics, u) end)
	if #found == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:filterTarget(mechanics, target)
	local out = {}
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then out[#out + 1] = dest end
	end
	return out
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	local main = target[1] and target[1].unit
	if caster == nil or not caster:isAlive() or main == nil then return end
	local raw = L.attackDamage(server, caster, main, self.pct or 100, false)
	local amount = math.floor(raw * (100 - L.schoolReduction(main, "02darkSchool")) / 100)
	local dealt = L.hit(server, battle, main, amount, self.animation, self.sound) or 0
	if main:isAlive() and dealt > 0 then
		local tag = "h6Wither" .. tostring(caster:getSide())
		L.removeByStacking(server, battle, main, "H6_WITHER_H6C", tag)
		server:addUnitBonus(battle, main, { type = "H6_WITHER_H6C", val = dealt, duration = ENUM.BonusDuration.oneBattle,
			sourceType = ENUM.BonusSource.other, sourceID = caster:getCreature():getJsonKey(), stacking = tag }, true)
		L.setMark(server, battle, main, "h6WitherPct", self.dotPct or 15)
		L.setMark(server, battle, main, "h6WitherMax", self.dotMax or 20) -- Review B10: the cap is written only in the spell parameters; combat/h6WitherTick reads this mark
	end
	if server:describeChanges() then server:refreshBattleUnits(battle) end
	L.log(server, battle, "H6_AREA_H6C", 5, { L.name(caster) }, { 1, dealt })
	L.useCast(server, battle, caster, self.key or mechanics:getSpell():getJsonKey(), nil)
end

return Script
