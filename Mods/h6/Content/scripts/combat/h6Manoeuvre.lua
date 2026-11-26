local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Manoeuvre (H6 Centaur, Centaur Marauder)
---
--- Centaurs do not make normal melee counterattacks (NO_RETALIATION). After being attacked in melee (once per round), they fall back within their speed
--- to the free hex that is at least 3 hexes from every enemy (every hex it occupies) and farthest from the nearest enemy, then shoot the attacker once (normal shot damage). If no such hex exists, they shoot from where they stand.
--- Review B10 (2026-11-08): the comment used to say "not adjacent to any enemy" while the code requires at least 3 hexes (distance <= 2 excluded); the comment and creature description now follow the code.
--- The engine's double strike does not check whether the two sides are still adjacent between the blows, so after stepping back the second blow would still land from several hexes away. Now, after stepping back, the centaur gets a hidden
--- 100% reduction of all damage (valid for this action), removed when the action ends, so the second blow after stepping back deals no damage.
--- The attacker also gets a hidden NOT_ACTIVE for this action, so the second blow is not struck at all (the damage formula gives at least 1, so the reduction alone would let 1 point through).
--- Parameters: animation, sound

local USED = "h6Manoeuvre"
local DODGE = "h6ManoeuvreDodge"
local STOP = "h6ManoeuvreStop"
local stopped = {}

function Script:onAfterAttacked(server, battle, unit, other, payload)
	if payload.ranged or payload.isCounter or other == nil or not unit:isAlive() or not other:isAlive() then return end
	if not battle:isHostile(unit, other) or L.markValue(unit, USED) ~= nil then return end
	L.setMark(server, battle, unit, USED, 1, 1)
	local speed = unit:getBonusesValue({ type = "STACKS_SPEED" })
	local start = unit:getPosition()
	local enemies = battle:getUnitsIf(function(u) return L.real(u) and battle:isHostile(unit, u) end)
	local best, bestD = nil, -1
	local all = battle:getAllPossibleHexes()
	for i = 1, all:size() do
		local h = all:at(i)
		if h:isAvailable() and L.hexDistance(start, h) <= speed and battle:isAccessibleForUnit(unit, h) then
			local ok, nearest = true, 1000
			for _, e in ipairs(enemies) do
				local hx = e:getHexes()
				for j = 1, hx:size() do
					local d = L.hexDistance(h, hx:at(j))
					if d <= 2 then ok = false end
					nearest = math.min(nearest, d)
				end
			end
			if ok and nearest > bestD then best, bestD = h, nearest end
		end
	end
	if best ~= nil then
		server:moveUnit(battle, unit, best, true)
		L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_REDUCTION", DODGE)
		L.addBonus(server, battle, unit, { type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", val = 100, hidden = true,
			duration = ENUM.BonusDuration.nTurns, turns = 1, stacking = DODGE, sourceType = ENUM.BonusSource.other }, false)
		-- Damage is at least 1, and the reduction cannot stop the second blow itself (its after-attack effects would still trigger). Give the attacker a hidden NOT_ACTIVE,
		-- which the engine checks before each blow of a double strike, so the second blow is skipped; removed when this action ends
		if other:isAlive() then
			L.removeByStacking(server, battle, other, "NOT_ACTIVE", STOP)
			L.addBonus(server, battle, other, { type = "NOT_ACTIVE", val = 0, hidden = true,
				duration = ENUM.BonusDuration.nTurns, turns = 1, stacking = STOP, sourceType = ENUM.BonusSource.other }, false)
			stopped[unit:unitID()] = other:unitID()
		end
	end
	if unit:isAlive() and other:isAlive() then
		local dealt = L.hit(server, battle, other, L.attackDamage(server, unit, other, 100, true), self.animation, self.sound)
		L.log(server, battle, "H6_MANOEUVRE_H6C", 1, { L.name(unit), L.name(other) }, { dealt or 0 })
	end
end


function Script:onActionFinished(server, battle, unit, other, payload)
	L.removeByStacking(server, battle, unit, "GENERAL_DAMAGE_REDUCTION", DODGE)
	local aid = stopped[unit:unitID()]
	if aid ~= nil then
		stopped[unit:unitID()] = nil
		for _, u in ipairs(battle:getUnitsIf(function(u) return u:unitID() == aid end)) do
			L.removeByStacking(server, battle, u, "NOT_ACTIVE", STOP)
		end
	end
end
return Script
