local Base = require("combat/combatScript")
local BattleLog = require("battleLog")
local L = require("combat/h5B3Lib")
local Proxy = require("lib/kadAiProxy")   -- Round 375: bonuses removed precisely
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5 Centaur: Maneuver
---
--- When attacked in melee by an enemy (not retaliation), if there is a free hex within its movement range not adjacent to any enemy, it does not retaliate in melee,
--- but after this action retreats to that hex (the one farthest from the attacker) and retaliates with a shot at the attacker, at val% of normal shot damage (original 50%).
--- If no such hex is found it retaliates in melee as usual. Only one maneuver per round (normal retaliation after).
--- Approximation: the retreat is a teleport (no path walked); the retaliation shot uses no ammo and plays no shooting animation, only damage (attack/defense factor applied, no luck).
---
--- Parameter: val (damage percent of the retaliation shot)

local MARK = "H5_MANEUVER_H5C"

local function speedOf(unit)
	return math.max(1, unit:getBonusesValue({ type = "STACKS_SPEED" }))
end

local function findHex(battle, unit, attacker)
	local side = unit:getSide()
	local enemies = battle:getUnitsIf(function(u) return u:isAlive() and battle:isHostile(unit, u) and not u:isGhost() end)
	local all = battle:getAllPossibleHexes()
	local from = unit:getPosition()
	local speed = speedOf(unit)
	local best, bestDist = nil, -1
	for i = 1, all:size() do
		local h = all:at(i)
		local d = L.hexDistance(from, h)
		if d > 0 and d <= speed and battle:isAccessibleForUnit(unit, h) then
			local safe = true
			for _, e in ipairs(enemies) do
				local eh = e:getHexes()
				for j = 1, eh:size() do
					if L.hexDistance(eh:at(j), h) <= 1 then safe = false break end
				end
				if not safe then break end
			end
			if safe then
				local far = L.hexDistance(attacker:getPosition(), h)
				if far > bestDist then best, bestDist = h, far end
			end
		end
	end
	return best
end

local function marks(unit, val)
	return unit:getBonuses({ type = MARK }):filter(function(b) return val == nil or b:getVal() == val end)
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	if not unit:isAlive() or other == nil or payload.ranged or payload.isCounter then return end
	if not battle:isHostile(other, unit) then return end
	if not unit:isShooter() or not unit:ableToRetaliate() then return end
	if unit:hasBonuses({ type = "SIEGE_WEAPON" }) then return end
	if marks(unit):size() > 0 then return end -- Already maneuvered this round, or this hit already registered
	if findHex(battle, unit, other) == nil then return end

	local src = unit:getCreature():getJsonKey()
	server:addUnitBonus(battle, unit, {
		type = "NO_RETALIATION", duration = ENUM.BonusDuration.untilAfterAttackSequence,
		sourceType = ENUM.BonusSource.other, sourceID = src, stacking = "h5ManeuverNoRet", hidden = true
	}, false)
	server:addUnitBonus(battle, unit, {
		type = MARK, val = other:unitID() + 10,
		duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = src, hidden = true
	}, true)
end

function Script:onActionFinished(server, battle, unit, other, payload)
	-- Round 375: the "cannot retaliate" attached for the maneuver is attached after the exchange started, so the engine does not remove it at the end of the exchange and it would stay until the end of the round;
	-- removed at the end of the action, normal retaliation after
	local noRet = unit:getBonuses({ type = "NO_RETALIATION" }):filter(function(b) return b:getStacking() == "h5ManeuverNoRet" end)
	if noRet:size() > 0 then Proxy.removeExact(server, battle, unit, noRet) end
	local pending = marks(unit):filter(function(b) return b:getVal() >= 10 end)
	if pending:size() == 0 then return end
	local attackerId = pending:getBonus(1):getVal() - 10
	server:removeUnitBonuses(battle, unit, pending)
	if not unit:isAlive() then return end

	-- Note that it maneuvered this round (expires at the end of the round)
	server:addUnitBonus(battle, unit, {
		type = MARK, val = 1, duration = ENUM.BonusDuration.nTurns, turns = 1,
		sourceType = ENUM.BonusSource.other, sourceID = unit:getCreature():getJsonKey(), hidden = true
	}, true)

	local found = battle:getUnitsIf(function(u) return u:unitID() == attackerId end)
	local attacker = found[1]
	if attacker == nil or not attacker:isAlive() then return end
	local hex = findHex(battle, unit, attacker)
	if hex == nil then return end

	server:moveUnit(battle, unit, hex, true)
	if attacker:isInvincible() then return end
	local dmg = L.attackDamage(server, unit, attacker, self.val or 50, true)
	local done, killed = server:damageUnit(battle, attacker, dmg)
	server:appendLog(battle, {
		append = { "core.bonus.H5_MANEUVER_H5C.description.1" },
		replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) }
	})
	BattleLog.creaturesPerish(server, battle, attacker, killed)
end

return Script
