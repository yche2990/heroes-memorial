local Base = require("spells/unitEffect")
local BattleLog = require("battleLog")
local L = require("spells/h5AbLib")
local C, A = L.C, L.A
local Proxy = require("lib/kadAiProxy")   -- Round 344: AI simulation branch (ai-skills-design)
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- "Active attack" abilities of H5 creatures (on an enemy stack, no retaliation):
---   Call Lightning (Titan)  mode = "perCreature": damage = count x per, resistances by the spell's school (Air)
---   Incinerate (Scarlet Dragon)      mode = "attack": normal attack damage x pct%, adjacent enemies only
---   Death Touch (Wraith)  mode = "killOne": kills 1 creature of the target and dispels beneficial magic on it (dispel effect written separately in the spell)
---   Storm Bolt (Thunder Thane) mode = "attack" + chain: damage = normal attack damage, lightning chains on through adjacent enemies (each hit once; Air-immune ones break the chain)
---   Throw Goblin (Cyclops) mode = "attack" + goblin: needs an adjacent friendly goblin, throws one; half damage beyond half the battlefield
--- Parameters: mode, per, pct, adjacent (adjacent only), spellDamage (damage through spell resistance), chain, goblin,
---       uses (per battle, unlimited if omitted), key (use counter mark), log (bonus name for the battle log), hitAnimation / hitSound

function Script:isValidTarget(mechanics, unit)
	if not unit:isValidTarget(false) or not unit:isAlive() or unit:isTurret() then return false end
	local caster = mechanics:getUnitCaster()
	if caster == nil or not mechanics:getBattle():isHostile(caster, unit) then return false end
	if self.adjacent and not L.adjacent(caster, unit) then return false end
	return true
end

function Script:applicableGeneral(mechanics, problem)
	local caster = mechanics:getUnitCaster()
	if caster == nil then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	if self.goblin and self:goblinStack(mechanics:getBattle(), caster) == nil then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return Base.applicableGeneral(self, mechanics, problem)
end

function Script:goblinStack(battle, caster)
	local list = battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and not battle:isHostile(caster, u) and u:unitID() ~= caster:unitID()
			and L.isGoblin(u) and L.adjacent(caster, u)
	end)
	return list[1]
end

function Script:damageFor(server, battle, caster, unit, mechanics)
	local dmg
	if self.mode == "perCreature" then
		dmg = caster:getCount() * (self.per or 1)
	elseif self.mode == "killOne" then
		return unit:getFirstHPleft()
	else
		dmg = A.attackDamage(server, caster, unit, self.pct or 100, false)
		if self.goblin and C.unitDistance(caster, unit) > 10 then dmg = math.floor(dmg / 2) end
	end
	if self.spellDamage then
		local ok, adj = pcall(function() return mechanics:getSpell():adjustDamage(battle, caster, unit, dmg) end)
		if ok and type(adj) == "number" then dmg = adj end
	end
	return math.max(1, dmg)
end

function Script:hitOne(server, battle, caster, unit, mechanics)
	if not A.damageable(unit) then return 0 end
	local dmg = self:damageFor(server, battle, caster, unit, mechanics)
	if server:describeChanges() and self.hitAnimation then
		server:showBattleAnimation(battle, { { unit = unit } }, self.hitAnimation, self.hitSound or "", 1.0, true)
	end
	local dealt, killed = server:damageUnit(battle, unit, dmg)
	if server:describeChanges() then BattleLog.creaturesPerish(server, battle, unit, killed) end
	return dealt
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local caster = mechanics:getUnitCaster()
	if caster == nil or not caster:isAlive() then return end
	local dest = target[1]
	local unit = dest and dest.unit
	if unit == nil or not unit:isAlive() then return end

	-- Round 344: AI simulation branch (ai-skills-design #4). Throwing away a friendly goblin is vetoed by the AI as an own loss:
	-- in the simulation nothing is thrown; the value of "one goblin fewer" is converted to target health and deducted from this hit (own damage deducted at its real loss). Real casts do not go through here
	if self.goblin and Proxy.trial(server) then
		local g = self:goblinStack(battle, caster)
		if g == nil or not A.damageable(unit) then return end
		local hp = self:damageFor(server, battle, caster, unit, mechanics) - Proxy.costHp(g, 1, unit)
		if hp >= unit:getMaxHealth() then Proxy.damage(server, battle, unit, hp) end
		return
	end

	if self.goblin then
		local g = self:goblinStack(battle, caster)
		if g == nil then return end
		if g:getCount() <= 1 then server:removeUnit(battle, g) else server:damageUnit(battle, g, g:getFirstHPleft()) end
	end

	local dealt = self:hitOne(server, battle, caster, unit, mechanics)
	if server:describeChanges() and self.log then
		L.log(server, battle, self.log, 1, { C.name(caster), C.name(unit) }, { dealt })
	end

	if self.chain then
		local hit = { [unit:unitID()] = true }
		local last = unit
		for _ = 1, 30 do
			local nextUnit = nil
			for _, u in ipairs(C.adjacentUnits(battle, last, function(o) return battle:isHostile(caster, o) and not hit[o:unitID()] and A.damageable(o) and not A.schoolImmune(o, "air") end)) do
				nextUnit = u
				break
			end
			if nextUnit == nil then break end
			hit[nextUnit:unitID()] = true
			self:hitOne(server, battle, caster, nextUnit, mechanics)
			last = nextUnit
		end
	end
	server:refreshBattleUnits(battle)
	L.useCast(server, battle, caster, self.key or "h5AbStrike", self.uses)
end

--- 2026-11-06: engine 89ce99f1 calls describeTargetStep when choosing a target; the core spellEffect.lua has this function,
--- but unitEffect.lua does not inherit it (heal, dispel, damage and timed all come from unitEffect), and the log reports function 'describeTargetStep' not found.
--- If the base class lacks it, one returning nil is added (= the engine's default cursor text, same display as before); once the engine adds it, the engine's is used.
if not Base.describeTargetStep then
	function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
		return nil
	end
end

--- For the hover estimate: expected value of A.attackDamage (random damage takes the average of min and max, otherwise the same formula)
local function hcMeanAttack(attacker, target, pct, ranged)
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
	return math.max(1, math.floor(base * factor * pct / 100))
end

--- Hover estimate: same formula as apply. Call Lightning = number of creatures x per; Death Touch = kills 1; normal attack types use the expected damage (without luck);
--- Goblin throw is halved beyond half the battlefield; spellDamage goes through spell resistance; Storm Bolt chains are added stack by stack in apply's order
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local battle = mechanics:getBattle()
		local caster = mechanics:getUnitCaster()
		if caster == nil or not caster:isAlive() then return zero end
		local dest = spellTarget and spellTarget[1]
		local unit = dest and dest.unit
		if unit == nil or not unit:isAlive() or not self:isValidTarget(mechanics, unit) then return zero end
		if self.goblin and self:goblinStack(battle, caster) == nil then return zero end
		local out = { hpDelta = 0, unitsDelta = 0 }
		local function one(u)
			if not A.damageable(u) then return end
			local dmg
			if self.mode == "perCreature" then
				dmg = caster:getCount() * (self.per or 1)
			elseif self.mode == "killOne" then
				dmg = u:getFirstHPleft()
			else
				dmg = hcMeanAttack(caster, u, self.pct or 100, false)
				if self.goblin and C.unitDistance(caster, u) > 10 then dmg = math.floor(dmg / 2) end
			end
			if self.mode ~= "killOne" and self.spellDamage then
				local okAdj, adj = pcall(function() return mechanics:getSpell():adjustDamage(battle, caster, u, dmg) end)
				if okAdj and type(adj) == "number" then dmg = adj end
			end
			dmg = math.max(1, math.floor(dmg))
			local copy = u:copy()
			local hp, cnt = copy:getAvailableHealth(), copy:getCount()
			copy:damage(dmg)
			out.hpDelta = out.hpDelta - (hp - copy:getAvailableHealth())
			out.unitsDelta = out.unitsDelta - (cnt - copy:getCount())
		end
		one(unit)
		if self.chain then
			local hit = { [unit:unitID()] = true }
			local last = unit
			for _ = 1, 30 do
				local nextUnit = nil
				for _, u in ipairs(C.adjacentUnits(battle, last, function(o) return battle:isHostile(caster, o) and not hit[o:unitID()] and A.damageable(o) and not A.schoolImmune(o, "air") end)) do
					nextUnit = u
					break
				end
				if nextUnit == nil then break end
				hit[nextUnit:unitID()] = true
				one(nextUnit)
				last = nextUnit
			end
		end
		return out
	end)
	if ok and result then return result end
	return zero
end

return Script
