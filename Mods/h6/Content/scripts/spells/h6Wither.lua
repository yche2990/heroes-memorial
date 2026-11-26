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

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

--- For the hover estimate: expected value of h6Lib.attackDamage (random damage takes the average of min and max, otherwise the same formula: attack/defense modifiers, damage bonuses and reductions, pct%)
local function hcMeanAttack(attacker, target, pct, ranged)
	ranged = ranged == true
	local modifier = L.damageModifier(attacker, target, ranged)
	if modifier <= 0 then return 0 end
	local minDamage = attacker:getMinDamage(ranged)
	local maxDamage = math.max(minDamage, attacker:getMaxDamage(ranged))
	local base = attacker:getCount() * (minDamage + maxDamage) / 2
	local diff = attacker:getAttack(ranged) - target:getDefense(ranged)
	local factor
	if diff > 0 then
		factor = 1 + 0.05 * math.min(diff, 60)
	else
		factor = 1 - 0.025 * math.min(-diff, 28)
	end
	return math.max(1, math.floor(base * factor * modifier * (pct or 100) / 100))
end

--- For the hover estimate: a copy of L.hit that returns damage, kills (0, 0 when the target cannot be hit or the values are invalid)
local function hcHit(target, amount)
	amount = math.floor(amount or 0)
	if target == nil or not target:isAlive() or target:isGhost() or target:isInvincible() or amount <= 0 then return 0, 0 end
	local copy = target:copy()
	local hp, cnt = copy:getAvailableHealth(), copy:getCount()
	copy:damage(amount)
	return hp - copy:getAvailableHealth(), cnt - copy:getCount()
end

--- Hover estimate: same formula as apply. pct% of a normal attack (expected value, without luck), reduced by dark reductions; the later damage over time is not counted.
--- The Spectral Dragon's curse (h6SpectralCurse) inherits this script with the same damage formula, so it uses this function too
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local caster = mechanics:getUnitCaster()
		local first = self:filterTarget(mechanics, spellTarget or {})[1]
		local main = first and first.unit
		if caster == nil or not caster:isAlive() or main == nil then return zero end
		local raw = hcMeanAttack(caster, main, self.pct or 100, false)
		local d, killed = hcHit(main, math.floor(raw * (100 - L.schoolReduction(main, "02darkSchool")) / 100))
		return { hpDelta = -d, unitsDelta = -killed }
	end)
	if ok and result then return result end
	return zero
end

return Script
