local Proxy = require("lib/kadAiProxy")
local L = require("combat/h7dLib")

--- AI simulation branch of the H7 memorial creature active abilities (ai-skills-design, following the AI skill design document and round 352 of the collection).
--- When deciding whether to use an ability, the AI runs the spell on an imaginary battlefield (server:describeChanges() is false) and compares every stack's value before and after;
--- there this mod's "prepare the next attack", "charge in", "dive", "place magma", "runes" and similar effects are all worth 0, so the AI never used them.
--- Each ability script calls a function here first in apply: in the simulation it reports "equivalent damage to enemies" (a proxy value) and returns; real casts are unchanged and players see no difference.
--- Values use one "value unit" (value per creature x damage / health per creature), converted back to health damage on the target at the end (Proxy.damage / Proxy.credit).
--- Thresholds (design 2.4): proxy values below the target's health per creature are not reported; "prepare the next attack" types are only reported if more than 10% better than a normal attack (the reported value includes this hit,
--- on the same basis as the "attack directly" the engine compares with). This file is H7-specific; the shared library is lib/kadAiProxy.lua.

local T = {}

--- Weight: the values in this file and BattleAI's score for "attack directly" (damageDiff, by the reduction of the enemy's output) use different units;
--- tests (vcmitest H7AiCastTest) showed that with K = 1.6 Feral Charge and Dive still lost to attacking directly even when clearly better. So "worth casting or not"
--- is judged 1:1 in this file (each type must be more than 10% better than attacking directly to be reported, see each function's threshold), and the value is multiplied by K when reported, so the AI follows that judgment.
T.K = 2.5

local function speedOf(u)
	local ok, v = pcall(function() return u:getBonusesValue({ type = "STACKS_SPEED" }) end)
	if ok and type(v) == "number" then return v end
	return 0
end
T.speedOf = speedOf

--- Expected damage of one attack: as Proxy.attackEstimate, optionally with extra Attack (plusAtk) and ignoring Defense (ignoreDef)
function T.est(attacker, target, pct, ranged, plusAtk, ignoreDef)
	if attacker == nil or target == nil then return 0 end
	ranged = ranged or false
	local lo = attacker:getMinDamage(ranged)
	local hi = math.max(lo, attacker:getMaxDamage(ranged))
	local def = ignoreDef and 0 or target:getDefense(ranged)
	local diff = attacker:getAttack(ranged) + (plusAtk or 0) - def
	local f
	if diff > 0 then f = 1 + 0.05 * math.min(diff, 60) else f = 1 - 0.025 * math.min(-diff, 28) end
	return attacker:getCount() * (lo + hi) / 2 * f * (pct or 100) / 100
end

--- Damage converted to value units (not more than the remaining health)
function T.val(u, dmg)
	if u == nil or dmg == nil or dmg <= 0 then return 0 end
	return Proxy.value(u) * math.min(dmg, u:getAvailableHealth()) / u:getMaxHealth()
end

--- Within melee reach this round (adjacent, or distance - 1 <= Speed; flying not treated as an obstacle and ground also estimated as a straight line, generously)
function T.reach(caster, e)
	local d = Proxy.unitsDistance(caster, e)
	return d <= 1 or d - 1 <= speedOf(caster)
end

local function enemyAdjacent(battle, caster)
	return #Proxy.adjacent(battle, caster, function(x) return Proxy.hostile(battle, caster, x) end) > 0
end
T.enemyAdjacent = enemyAdjacent

--- Report a proxy value from a damage table: hits = { {unit, dmg}, ... } (enemies lose health, allies are a cost), extra = additional value units (may be negative).
--- Each enemy is counted on its own; the allies' cost and extra are booked on main (the main target). Returns the total value reported.
function T.report(server, battle, actor, main, hits, extra, k)
	k = k or T.K
	local total, cost = 0, 0
	for _, h in ipairs(hits) do
		if Proxy.hostile(battle, actor, h[1]) then total = total + T.val(h[1], h[2])
		else cost = cost + T.val(h[1], h[2]) end
	end
	total = total + (extra or 0) - cost
	if total <= 0 or main == nil then return 0 end
	if Proxy.hpOf(total, main) < main:getMaxHealth() then return 0 end
	local adjust = ((extra or 0) - cost) * k
	for _, h in ipairs(hits) do
		if Proxy.hostile(battle, actor, h[1]) then
			local d = h[2] * k
			if h[1]:unitID() == main:unitID() then d = d + Proxy.hpOf(adjust, main); adjust = 0 end
			if d > 0 then Proxy.damage(server, battle, h[1], d) end
		end
	end
	if adjust > 0 then Proxy.credit(server, battle, actor, adjust) end
	return total
end

--- Stacks around the main target (distance <= r), the main target included
local function around(battle, e, r)
	return battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and not u:isTurret() and Proxy.unitsDistance(u, e) <= r
	end)
end

--- "Prepare the next attack" (spells/h7AbArm): estimates the prepared attack by mark type; reported only if more than 10% better than a normal attack
local ARM = {}

-- Mana Nova: the shot hits all stacks on the target hex and the ring around it (friend or foe), full damage
ARM.H7_NOVA_ARMED_H7C = function(battle, c, e)
	local hits = {}
	for _, u in ipairs(around(battle, e, 1)) do
		if u:unitID() ~= c:unitID() then hits[#hits + 1] = { u, T.est(c, u, 100, true) } end
	end
	return hits, 0
end
-- Scatter Shot: as above, half damage
ARM.H7_SCATTER_ARMED_H7C = function(battle, c, e)
	local hits = {}
	for _, u in ipairs(around(battle, e, 1)) do
		if u:unitID() ~= c:unitID() then hits[#hits + 1] = { u, T.est(c, u, 50, true) } end
	end
	return hits, 0
end
-- Leaf Blade: pierces enemies on the straight line, ignoring Defense; other enemies on the line are estimated at half for those adjacent behind the target and farther from the caster (the line may not line up exactly)
ARM.H7_LEAF_ARMED_H7C = function(battle, c, e)
	local hits = { { e, T.est(c, e, 100, true, 0, true) } }
	local de = Proxy.unitsDistance(c, e)
	for _, u in ipairs(around(battle, e, 1)) do
		if u:unitID() ~= e:unitID() and Proxy.hostile(battle, c, u) and Proxy.unitsDistance(c, u) > de then
			hits[#hits + 1] = { u, T.est(c, u, 50, true, 0, true) }
		end
	end
	return hits, 0
end
-- Implosion Arrow: this arrow as usual; enemies within 3 hexes of the target are pulled in (grouped for later attacks; position type F8, 0.1 x one shot each)
ARM.H7_IMPLODE_ARMED_H7C = function(battle, c, e)
	local hits = { { e, T.est(c, e, 100, true) } }
	local extra = 0
	for _, u in ipairs(around(battle, e, 3)) do
		if u:unitID() ~= e:unitID() and Proxy.hostile(battle, c, u) then extra = extra + 0.1 * T.val(u, T.est(c, u, 100, true)) end
	end
	return hits, extra
end
-- Ink Spray: hits the target and the enemies on both sides, 30% each; inked enemies deal half melee damage until the end of the next round (control F4: 1 round x 0.5, melee stacks only)
ARM.H7_INK_ARMED_H7C = function(battle, c, e)
	local hits, extra = {}, 0
	local heads = { e }
	for _, u in ipairs(Proxy.adjacent(battle, e, function(x) return Proxy.hostile(battle, c, x) end)) do
		if #heads < 3 and Proxy.unitsDistance(c, u) <= 2 then heads[#heads + 1] = u end
	end
	for _, u in ipairs(heads) do
		hits[#hits + 1] = { u, T.est(c, u, 30, false) }
		if not u:isShooter() then extra = extra + T.val(u, u:getAvailableHealth()) * Proxy.controlRatio(1, 0.5) end
	end
	return hits, extra
end
-- Crippling Sting: this hit deals half damage and is not retaliated; the target cannot retaliate until the end of the next round (retaliation ban only, 0.15)
ARM.H7_STING_ARMED_H7C = function(battle, c, e)
	local hits = { { e, T.est(c, e, 50, false) } }
	local extra = T.val(c, T.est(e, c, 100, false)) + T.val(e, e:getAvailableHealth()) * Proxy.controlRatio(1, 0.15)
	return hits, extra
end
local RANGED = { H7_NOVA_ARMED_H7C = true, H7_SCATTER_ARMED_H7C = true, H7_LEAF_ARMED_H7C = true, H7_IMPLODE_ARMED_H7C = true }

--- Value of a normal attack (the hit it would make without preparing; retaliation deducted in melee)
local function plain(battle, c, e, ranged)
	local v = T.val(e, T.est(c, e, 100, ranged))
	if not ranged and not e:isShooter() then v = v - T.val(c, T.est(e, c, 100, false)) end
	return v
end

function T.arm(server, battle, caster, mark)
	local f = ARM[mark]
	if f == nil then return end
	local ranged = RANGED[mark] or false
	if ranged and (not caster:isShooter() or enemyAdjacent(battle, caster)) then return end
	local best, bestHits, bestExtra, bestGain = nil, nil, 0, 0
	for _, e in ipairs(battle:getUnitsIf(function(x) return Proxy.hostile(battle, caster, x) end)) do
		if ranged or T.reach(caster, e) then
			local hits, extra = f(battle, caster, e)
			local v = extra
			for _, h in ipairs(hits) do
				local hv = T.val(h[1], h[2])
				if Proxy.hostile(battle, caster, h[1]) then v = v + hv else v = v - hv end
			end
			local gain = v - math.max(0, plain(battle, caster, e, ranged)) * 1.1
			if gain > bestGain then best, bestHits, bestExtra, bestGain = e, hits, extra, gain end
		end
	end
	if best ~= nil then T.report(server, battle, caster, best, bestHits, bestExtra) end
end

--- Charge / Pounce (spells/h7AbCharge): the hit after landing (extra Attack, no retaliation; Pounce hits all adjacent enemies);
--- Feral Charge sets Defense to 0 this round: cost = expected damage from enemies able to reach it this round x 0.3
function T.charge(server, battle, caster, unit, hex, mode, plusAtk)
	local hits = { { unit, T.est(caster, unit, 100, false, plusAtk or 0) } }
	if mode == "pounce" then
		for _, u in ipairs(battle:getUnitsIf(function(x) return Proxy.hostile(battle, caster, x) end)) do
			if u:unitID() ~= unit:unitID() and Proxy.unitDistance(u, hex) <= 1 then
				hits[#hits + 1] = { u, T.est(caster, u, 100, false) }
			end
		end
	end
	local extra = 0
	if mode == "feral" then extra = -T.val(caster, Proxy.threat(battle, caster) * 0.3) end
	-- Targets reachable by walking this round: the charge hit must be more than 10% better than attacking directly (retaliation deducted) to be reported, otherwise the AI attacks directly
	if T.reach(caster, unit) then
		local v = extra
		for _, h in ipairs(hits) do v = v + T.val(h[1], h[2]) end
		if v <= math.max(0, plain(battle, caster, unit, false)) * 1.1 then return end
	end
	T.report(server, battle, caster, unit, hits, extra)
end

--- Magma Pool (spells/h7AbZoneD magma): stacks in the ring around it take per x count Fire damage each round until the end of the next round (F2: 0.5 the first time, 0.8 for shooters, 0.4 the second time).
--- Round 403: the pool does not tell friend from foe and the caster stands in it: it takes one hit at once when placed (1.0), and another at the start of next round if still in the pool (0.4 as above);
--- damage to itself and adjacent allies counts as cost (T.report subtracts it from the enemy value; not placed if the net is below 1 creature of the target).
--- Each stack's damage applies resistances as the Magma Pool spell does (spell:adjustDamage: Magma Elementals' own Fire halving; Fire-immune stacks take none)
local function magmaDamage(spell, battle, caster, u, raw)
	if spell ~= nil then
		local ok, v = pcall(function() return spell:adjustDamage(battle, caster, u, raw) end)
		if ok and type(v) == "number" then return math.max(0, v) end
	end
	return raw
end

function T.magma(server, battle, caster, per, spell)
	local dmg = per * math.max(1, caster:getCount())
	local hits, main = { { caster, magmaDamage(spell, battle, caster, caster, dmg) * 1.4 } }, nil
	for _, u in ipairs(Proxy.adjacent(battle, caster)) do
		if not u:isTurret() then
			local p = (u:isShooter() and 0.8 or 0.5) + 0.4
			local d = magmaDamage(spell, battle, caster, u, dmg) * p
			hits[#hits + 1] = { u, d }
			if Proxy.hostile(battle, caster, u) and d > 0 and (main == nil or u:getAvailableHealth() > main:getAvailableHealth()) then main = u end
		end
	end
	if main ~= nil then T.report(server, battle, caster, main, hits, 0) end
end

--- Diving Attack (spells/h7Dive): lands next round in a 2x2 area, Attack + factor against all stacks there, no retaliation (landing spot F2 x 0.6),
--- minus the next action used up by the landing (0.5 x one attack on the nearest enemy)
function T.dive(server, battle, caster, hexes, factor)
	local hits, seen, main = {}, {}, nil
	for _, h in ipairs(hexes) do
		local u = battle:getUnitByPos(h, true)
		if u ~= nil and not seen[u:unitID()] and u:unitID() ~= caster:unitID() and not u:isTurret() then
			seen[u:unitID()] = true
			hits[#hits + 1] = { u, T.est(caster, u, 100, false, factor or 0) * 0.6 }
			if Proxy.hostile(battle, caster, u) and (main == nil or u:getAvailableHealth() > main:getAvailableHealth()) then main = u end
		end
	end
	if main == nil then return end
	local e = Proxy.nearestHostile(battle, caster)
	local lost = e and T.val(e, T.est(caster, e, 100, false)) * 0.5 or 0
	-- Threshold: more than 10% better than the best direct attack this round (retaliation deducted) (fliers can hit anything anyway; diving only pays when it hits several at once)
	local v, best = -lost, 0
	for _, h in ipairs(hits) do
		if Proxy.hostile(battle, caster, h[1]) then v = v + T.val(h[1], h[2]) else v = v - T.val(h[1], h[2]) end
	end
	for _, x in ipairs(battle:getUnitsIf(function(u) return Proxy.hostile(battle, caster, u) end)) do
		if T.reach(caster, x) then best = math.max(best, plain(battle, caster, x, false)) end
	end
	if v <= best * 1.1 then return end
	T.report(server, battle, caster, main, hits, -lost)
end

--- Rune Teleport (spells/h7AbRunePlace teleport): position type F8. A blocked shooter teleports to a hex with no adjacent enemy: it can shoot normally afterwards (0.5 x one shot);
--- a melee stack teleports next to an enemy it could not reach this round: 0.6 x one attack
function T.runeTeleport(server, battle, caster, land)
	local near = battle:getUnitsIf(function(x) return Proxy.hostile(battle, caster, x) and Proxy.unitDistance(x, land) <= 1 end)
	if caster:isShooter() then
		if not enemyAdjacent(battle, caster) or #near > 0 then return end
		local best, bv = nil, 0
		for _, e in ipairs(battle:getUnitsIf(function(x) return Proxy.hostile(battle, caster, x) end)) do
			local v = T.val(e, T.est(caster, e, 100, true))
			if v > bv then best, bv = e, v end
		end
		if best then T.report(server, battle, caster, best, { { best, T.est(caster, best, 50, true) } }, 0) end
	else
		local best, bv = nil, 0
		for _, e in ipairs(near) do
			if not T.reach(caster, e) then
				local v = T.val(e, T.est(caster, e, 100, false))
				if v > bv then best, bv = e, v end
			end
		end
		if best then T.report(server, battle, caster, best, { { best, T.est(caster, best, 60, false) } }, 0) end
	end
end

--- Round 403: moving the Rune of Balance (spells/h7AbRunePlace place). With k+1 friendly stacks in the aura, attack damage to each is shared by the k+1 stacks:
--- value estimated as "damage each ally in the aura would take this round x k/(k+1) x 0.3" (the one under focused attack loses fewer creatures, suggestion B3 of review C),
--- the gain of moving the rune = value at the new position - value at the current position. Casting uses up the priest's shot / attack this round; reported only if more than 10% better than that hit
--- (same basis as the other "prepare" types, multiplied by K when reported to the AI). centersNew / centersCur are the center hexes of the two auras (including the Rune Hierarch carrying the aura)
local function shareValue(battle, side, centers)
	if #centers == 0 then return 0 end
	local area = L.around(battle, centers)
	local inside = battle:getUnitsIf(function(u)
		if not u:isAlive() or u:isGhost() or u:isTurret() or u:isInvincible() or u:getSide() ~= side then return false end
		local hs = u:getHexes()
		for i = 1, hs:size() do
			if area[L.hexIndex(hs:at(i))] ~= nil then return true end
		end
		return false
	end)
	local n = #inside
	if n < 2 then return 0 end
	local v = 0
	for _, u in ipairs(inside) do
		v = v + T.val(u, math.min(Proxy.threat(battle, u), u:getAvailableHealth())) * (n - 1) / n * 0.3
	end
	return v
end

function T.runePlace(server, battle, caster, centersNew, centersCur)
	local side = caster:getSide()
	local gain = shareValue(battle, side, centersNew) - shareValue(battle, side, centersCur)
	if gain <= 0 then return end
	local ranged = caster:isShooter() and not enemyAdjacent(battle, caster)
	local alt = 0
	for _, e in ipairs(battle:getUnitsIf(function(x) return Proxy.hostile(battle, caster, x) end)) do
		if ranged or T.reach(caster, e) then alt = math.max(alt, plain(battle, caster, e, ranged)) end
	end
	if gain <= alt * 1.1 then return end
	Proxy.credit(server, battle, caster, gain * T.K)
end

--- Rune Stone activation and Rune of Radiance (spells/h7RuneStone). Destruction's activation is real damage the engine values itself, not handled here.
---   Fortune: allies in the aura get a shield of amount (whole battle): saves min(amount, expected damage from enemies able to reach it this round) x 0.7
---   Resilience: pushes stacks in the aura 1 hex away: enemy melee stacks next to our stacks are pushed off, saving one of its attacks on that stack x 0.3;
---         our blocked shooters get free, +0.5 x one shot
---   Radiance: aura x3 until the end of next round (2 times extra): about +4% output per point of Fortune luck, +5% per Destruction Attack point, -2.5% damage taken per Resilience Defense point
function T.rune(server, battle, stone, kind, mode, inAura, amount, auraPoints)
	local side = stone:getSide()
	local value = 0
	local allies = battle:getUnitsIf(function(u) return u:isAlive() and not u:isGhost() and u:getSide() == side
		and u:unitID() ~= stone:unitID() and inAura(u) and u:getCount() > 0 and not u:isInvincible() end)
	if mode == "radiance" then
		local extra = 2 * (auraPoints or 0)
		for _, u in ipairs(allies) do
			local e = Proxy.nearestHostile(battle, u)
			if e ~= nil then
				if kind == "fortune" then value = value + T.val(e, T.est(u, e, 100, u:isShooter())) * 0.04 * extra
				elseif kind == "destruction" then value = value + T.val(e, T.est(u, e, 100, u:isShooter())) * math.min(0.05 * extra, 1)
				else value = value + T.val(u, Proxy.threat(battle, u)) * math.min(0.025 * extra, 0.7) end
			end
		end
	elseif kind == "fortune" then
		for _, u in ipairs(allies) do value = value + T.val(u, math.min(amount or 0, Proxy.threat(battle, u))) * 0.7 end
	elseif kind == "resilience" then
		for _, u in ipairs(allies) do
			for _, e in ipairs(Proxy.adjacent(battle, u, function(x) return Proxy.hostile(battle, u, x) end)) do
				if inAura(e) then
					if not e:isShooter() then value = value + T.val(u, T.est(e, u, 100, false)) * 0.3 end
					if u:isShooter() then value = value + T.val(e, T.est(u, e, 50, true)) end
				end
			end
		end
	end
	if value > 0 then Proxy.credit(server, battle, stone, value) end
end

return T
