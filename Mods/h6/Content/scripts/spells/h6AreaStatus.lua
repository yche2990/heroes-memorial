local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Area active abilities of H6 creatures (Pestilent Lamasu "Breath of Worms", Fate Weaver "Frozen Web", Fate Weaver "Dance of Death")
---
--- Targets: with center = "target", the chosen enemy and the enemies adjacent to it (spell target CREATURE); with center = "single", only the chosen enemy (round 351);
---           with center = "caster", the enemies adjacent to the caster (spell target NO_TARGET);
---           with center = "all", every enemy on the battlefield (spell target NO_TARGET). If living is true, living creatures only.
--- For each target:
---   status    applies a status spell (level 3, lasting turns rounds; immune stacks are not affected)
---   dot       takes dot x number of casters Earth damage at the start of each of the next dotTurns rounds (settled by h6Dot)
---   pct       immediately takes pct% of its whole stack's initial health as damage (no reduction applied)
---   attackPct immediately takes attackPct% of the caster's normal attack as damage (H3 formula, no counterattack)
---   per       immediately takes per x number of casters damage, scaled by school and all-spell reduction
--- uses per battle are counted by this script itself (the stack's other active abilities do not use them up).
--- friendly (round 352): if true, the targets are friendly stacks instead (Uriel "Zeal").
--- radius (round 352): with center = "target", enemies within radius hexes of the target count too (default 1 = adjacent);
--- dotSrc: name of the damage-over-time source (decides the school, see h6Dot); defaults to the spell name (Earth).
--- Round 419: in the AI simulation (Proxy.trial) damage over time is not applied but reported as half its amount in proxy damage; enemies disabled by a status are reported as proxy damage by the rounds of control;
---   Fire vulnerability (Mark of Devouring) is reported as one tenth of the target's health. The rest (statuses, immediate damage) is counted as usual.
--- Parameters: center, friendly, radius, living, status, turns, dot, dotTurns, dotSrc, pct, attackPct, per, school, logIndex, uses, key, animation, sound

function Script:victim(mechanics, caster, u)
	if not L.real(u) or u:isInvincible() then return false end
	if (self.friendly == true) == mechanics:getBattle():isHostile(caster, u) then return false end
	if self.living and not L.isLiving(u) then return false end
	return true
end

function Script:victims(mechanics, caster, center)
	local battle = mechanics:getBattle()
	local out = {}
	if self.center == "target" or self.center == "single" then
		if center == nil or not self:victim(mechanics, caster, center) then return out end
		out[1] = center
		if self.center == "single" then return out end
		if (self.radius or 1) > 1 then
			for _, u in ipairs(battle:getUnitsIf(function(u) return u:unitID() ~= center:unitID() and self:victim(mechanics, caster, u)
				and L.unitDistance(center, u) <= self.radius end)) do out[#out + 1] = u end
			return out
		end
		for _, u in ipairs(L.around(battle, center, function(u) return self:victim(mechanics, caster, u) end)) do out[#out + 1] = u end
	elseif self.center == "all" then
		out = battle:getUnitsIf(function(u) return self:victim(mechanics, caster, u) end)
	else
		out = L.around(battle, caster, function(u) return self:victim(mechanics, caster, u) end)
	end
	return out
end

function Script:isValidTarget(mechanics, unit)
	local caster = mechanics:getUnitCaster()
	if caster == nil then return false end
	if self.center == "target" or self.center == "single" then return self:victim(mechanics, caster, unit) end
	return unit:unitID() == caster:unitID()
end

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	local ok = false
	local key = self.key or mechanics:getSpell():getJsonKey()
	if caster ~= nil and caster:isAlive() and not (self.uses and (L.markValue(caster, key) or 0) >= self.uses) then
		if self.center == "target" or self.center == "single" then
			ok = #mechanics:getBattle():getUnitsIf(function(u) return self:victim(mechanics, caster, u) end) > 0
		else
			ok = #self:victims(mechanics, caster, nil) > 0
		end
	end
	if not ok then problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget) end
	return ok
end

--- Review B1 (2026-11-08): center = "single" also checks the clicked target (it used to check only whether any valid target existed, so clicking a friendly or immune stack wasted an action)
function Script:applicableTarget(mechanics, problem, target)
	if self.center ~= "target" and self.center ~= "single" then return self:applicableGeneral(mechanics, problem) end
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then return true end
	end
	problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
	return false
end

function Script:filterTarget(mechanics, target)
	if self.center ~= "target" and self.center ~= "single" then return target end
	local out = {}
	for _, dest in ipairs(target) do
		if dest.unit and self:isValidTarget(mechanics, dest.unit) then out[#out + 1] = dest end
	end
	return out
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local center = target[1] and target[1].unit
	local list = self:victims(mechanics, caster, center)
	if #list > 0 then
		if self.status then
			local spell = L.spell(self.status)
			if spell then server:applySpellEffects(battle, caster, spell, list, 3, self.turns or 1, false) end
		end
		if Proxy.trial(server) then
			for _, u in ipairs(list) do
				if u:isAlive() and battle:isHostile(caster, u) then
					local hp = 0
					if (self.dot or 0) > 0 then hp = hp + self.dot * caster:getCount() * (self.dotTurns or 2) / 2 end
					if self.status and u:hasBonuses({ type = "NOT_ACTIVE" }) then hp = hp + u:getAvailableHealth() * Proxy.controlRatio(self.turns or 1, 1) end
					if self.status and u:getBonusesValue({ type = "SPELL_DAMAGE_REDUCTION", subtype = "spellSchool.fire" }) < 0 then hp = hp + u:getAvailableHealth() * 0.1 end
					if hp > 0 then Proxy.damage(server, battle, u, hp) end
				end
			end
		elseif (self.dot or 0) > 0 then
			for _, u in ipairs(list) do
				L.addDot(server, battle, u, (self.dotSrc or "") .. mechanics:getSpell():getJsonKey(), self.dot * caster:getCount(), self.dotTurns or 2)
			end
		end
		if (self.pct or 0) > 0 or (self.attackPct or 0) > 0 or (self.per or 0) > 0 then
			local total = 0
			for _, u in ipairs(list) do
				if u:isAlive() then
					local amount
					if (self.pct or 0) > 0 then
						amount = math.max(1, math.floor(u:getTotalHealth() * self.pct / 100))
					elseif (self.attackPct or 0) > 0 then
						amount = L.attackDamage(server, caster, u, self.attackPct, false)
					else
						amount = math.floor(self.per * caster:getCount() * (100 - L.schoolReduction(u, self.school)) / 100)
					end
					if amount > 0 then total = total + (L.hit(server, battle, u, amount, self.animation, self.sound) or 0) end
				end
			end
			L.log(server, battle, "H6_AREA_H6C", self.logIndex or 1, { L.name(caster) }, { #list, total })
		else
			L.show(server, battle, list, self.animation, self.sound)
		end
	end
	-- Uses per battle are counted here (see applicableGeneral) and casts are always refunded, so other active abilities of the same stack (Dual Form) are unaffected
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

--- Hover estimate: same formula as apply, only the immediate damage (pct: pct% of the stack's initial total health; attackPct: expected normal attack damage, without luck;
--- per: per x number of casters, reduced by school and all-spell damage reductions), summed over all affected stacks. Damage over time and status spells are not counted
--- (status spells are applied first; if one changes defense etc. the actual damage differs slightly)
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	if (self.pct or 0) <= 0 and (self.attackPct or 0) <= 0 and (self.per or 0) <= 0 then return zero end
	local ok, result = pcall(function()
		local caster = mechanics:getUnitCaster()
		if caster == nil or not caster:isAlive() then return zero end
		local first = self:filterTarget(mechanics, spellTarget or {})[1]
		local center = first and first.unit
		local out = { hpDelta = 0, unitsDelta = 0 }
		for _, u in ipairs(self:victims(mechanics, caster, center)) do
			if u:isAlive() then
				local amount
				if (self.pct or 0) > 0 then
					amount = math.max(1, math.floor(u:getTotalHealth() * self.pct / 100))
				elseif (self.attackPct or 0) > 0 then
					amount = hcMeanAttack(caster, u, self.attackPct, false)
				else
					amount = math.floor(self.per * caster:getCount() * (100 - L.schoolReduction(u, self.school)) / 100)
				end
				local d, killed = hcHit(u, amount)
				out.hpDelta, out.unitsDelta = out.hpDelta - d, out.unitsDelta - killed
			end
		end
		return out
	end)
	if ok and result then return result end
	return zero
end

return Script
