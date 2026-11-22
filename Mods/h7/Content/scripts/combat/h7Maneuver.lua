local Base = require("combat/combatScript")
local L = require("combat/h7AttackLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H7 Manoeuvre (Centaur, Centaur Marauder); written like h5Maneuver of H5
---
--- When attacked in melee by an enemy (counterattacks do not count), if this stack can counterattack and shoot, and there is a free hex within its movement range not adjacent to any enemy,
--- it does not counterattack in melee; after this action it falls back to that hex (the one farthest from the attacker), then counter-shoots the attacker:
--- val% of normal shot damage (100% in H7), halved with the range penalty. Once per round (afterwards it counterattacks in melee as usual).
--- Without such a free hex it counterattacks in melee as usual.
--- The fallback walks hex by hex (round 353d; it used to teleport) and only to hexes reachable within its speed; the counter-shot has no shooting animation and uses no ammunition, only damage (no Luck).
---
--- Parameter: val (damage percentage of the counter-shot, default 100)

local NORET = "h7ManeuverNoRet"
local PENDING = "h7ManeuverPending"
local USED = "h7ManeuverUsed"

local function speedOf(unit)
	return math.max(1, unit:getBonusesValue({ type = "STACKS_SPEED" }))
end

local function findHex(battle, unit, attacker)
	local enemies = battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and battle:isHostile(unit, u)
	end)
	local reached = L.reach(battle, unit, speedOf(unit))
	local best, bestDist, bestSteps = nil, -1, 1000
	for _, node in pairs(reached) do
		local h = node.hex
		if node.steps > 0 then
			local safe = true
			for _, e in ipairs(enemies) do
				if L.unitHexDistance(e, h) <= 1 then safe = false break end
			end
			if safe then
				local far = L.unitHexDistance(attacker, h)
				if far > bestDist or (far == bestDist and node.steps < bestSteps) then
					best, bestDist, bestSteps = h, far, node.steps
				end
			end
		end
	end
	return best, reached
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	if not unit:isAlive() or other == nil or payload.ranged or payload.isCounter then return end
	if not battle:isHostile(other, unit) or not battle:isMeleeAttackPossible(other, unit) then return end
	if not L.canShoot(unit) or not unit:ableToRetaliate() then return end
	if unit:hasBonuses({ type = "NOT_ACTIVE" }) or unit:hasBonuses({ type = "SIEGE_WEAPON" }) then return end
	if L.markValue(unit, USED) ~= nil or L.markValue(unit, PENDING) ~= nil then return end
	if findHex(battle, unit, other) == nil then return end

	-- "Removed when attacked" cannot be used: the engine deletes it when health is lost, before the counterattack check; this one is removed by this script when the action ends
	server:addUnitBonus(battle, unit, {
		type = "NO_RETALIATION", val = 0, hidden = true,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(), stacking = NORET
	}, false)
	L.setMark(server, battle, unit, PENDING, other:unitID() + 10, 1)
end

function Script:onActionFinished(server, battle, unit, other, payload)
	local pending = L.markValue(unit, PENDING)
	if pending == nil then return end
	L.clearMark(server, battle, unit, PENDING)
	L.removeByStacking(server, battle, unit, "NO_RETALIATION", NORET)
	if not unit:isAlive() then return end
	L.setMark(server, battle, unit, USED, 1, 1)

	local attackerId = pending - 10
	local found = battle:getUnitsIf(function(u) return u:unitID() == attackerId end)
	local attacker = found[1]
	if attacker == nil or not attacker:isAlive() then return end
	local hex, reached = findHex(battle, unit, attacker)
	if hex == nil then return end

	L.walkTo(server, battle, unit, hex, reached)
	server:refreshBattleUnits(battle)
	if not L.damageable(attacker) then return end
	local pct = self.val or 100
	local far = false
	pcall(function() far = battle:hasDistancePenalty(unit, attacker) end)
	if far then pct = pct / 2 end
	local dmg = L.attackDamage(server, unit, attacker, pct, true)
	if dmg <= 0 then return end -- H7 audit A3: shots at targets inside a Mist Veil deal 0 damage
	local dealt, killed = L.hit(server, battle, attacker, dmg, nil, "")
	L.log(server, battle, 5, { L.name(unit) }, { dealt })
	L.perish(server, battle, attacker, killed)
end

return Script
