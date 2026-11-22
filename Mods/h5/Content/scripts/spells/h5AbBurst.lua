local Base = require("spells/spellEffect")
local BattleLog = require("battleLog")
local L = require("spells/h5AbLib")
local C, A = L.C, L.A
local Proxy = require("lib/kadAiProxy")   -- Round 344: AI simulation branch (ai-skills-design)
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Area abilities of H5 creatures centered on themselves (cast on themselves):
---   mode = "deathWail"  Death Wail (Banshee): living enemies within range hexes take count x (const - target Morale) x coef / 2^(distance-1) damage
---                       (original parameters DeathWailRange 3, DamageConst 10, DamageCoef 2, DamageArgument 2; undead, elementals and mechanical units unaffected)
---   mode = "explosion"  Explosion (Horned Overseer): all adjacent stacks (friend or foe) take base[level] + per[level] x creature spell power Fire damage, itself unharmed
--- Parameters: mode, range, const, coef, arg, base, per, level (0-3, casting level if omitted), uses, hitAnimation, hitSound, mark

function Script:applicableGeneral(mechanics, problem)
	if mechanics:getUnitCaster() == nil then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local side = caster:getSide()
	local victims = {}

	if self.mode == "deathWail" then
		local range = self.range or 3
		local list = battle:getUnitsIf(function(u)
			-- Enemies only (ru wiki: 2 x (10 - Morale) x banshee count, 1, 1/2, 1/4 at 1/2/3 hexes)
			return battle:isHostile(caster, u) and A.damageable(u) and C.isLivingH5(u) and C.unitDistance(caster, u) <= range
		end)
		for _, u in ipairs(list) do
			local d = C.unitDistance(caster, u)
			local morale = 0
			pcall(function() morale = u:getMorale() end)
			local dmg = math.floor(caster:getCount() * math.max(0, (self.const or 10) - morale) * (self.coef or 2) / ((self.arg or 2) ^ (d - 1)))
			if dmg > 0 then victims[#victims + 1] = { unit = u, dmg = dmg } end
		end
	else
		local level = self.level
		if level == nil then
			local ok, lv = pcall(function() return mechanics:getEffectLevel() end)
			level = (ok and type(lv) == "number") and lv or 2
		end
		level = math.max(0, math.min(3, level))
		local sp = L.sp(caster)
		local raw = (self.base or { 5, 7, 9, 11 })[level + 1] + (self.per or { 5, 7, 9, 11 })[level + 1] * sp
		for _, u in ipairs(C.adjacentUnits(battle, caster, function(o) return A.damageable(o) end)) do
			local dmg = raw
			local ok, adj = pcall(function() return mechanics:getSpell():adjustDamage(battle, caster, u, raw) end)
			if ok and type(adj) == "number" then dmg = adj end
			if dmg > 0 then victims[#victims + 1] = { unit = u, dmg = dmg } end
		end
	end

	-- Round 344: AI simulation branch (ai-skills-design #39 Explosion). The explosion hits friend and foe, and hurting allies is vetoed by the AI:
	-- in the simulation only enemies lose health, discounted by "ally loss / enemy gain" (ally damage deducted at its real loss); not used if the net is <= 0. Real casts do not go through here
	if Proxy.trial(server) then
		local gain, loss = 0, 0
		for _, v in ipairs(victims) do
			local val = math.min(v.dmg, v.unit:getAvailableHealth()) / v.unit:getMaxHealth() * Proxy.value(v.unit)
			if battle:isHostile(caster, v.unit) then gain = gain + val else loss = loss + val end
		end
		if gain <= loss then return end
		local scale = 1 - loss / gain
		for _, v in ipairs(victims) do
			if battle:isHostile(caster, v.unit) then Proxy.damage(server, battle, v.unit, v.dmg * scale) end
		end
		return
	end

	for _, v in ipairs(victims) do
		if server:describeChanges() and self.hitAnimation then
			server:showBattleAnimation(battle, { { unit = v.unit } }, self.hitAnimation, self.hitSound or "", 1.0, true)
		end
		local dealt, killed = server:damageUnit(battle, v.unit, v.dmg)
		if server:describeChanges() then
			if self.mark then L.log(server, battle, self.mark, 1, { C.name(caster), C.name(v.unit) }, { dealt }) end
			BattleLog.creaturesPerish(server, battle, v.unit, killed)
		end
	end
	server:refreshBattleUnits(battle)
	L.useCast(server, battle, caster, "h5AbBurst" .. (self.mode or ""), self.uses)
end

return Script
