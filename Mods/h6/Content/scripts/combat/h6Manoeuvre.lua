local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Manoeuvre (H6 Centaur, Centaur Marauder)
---
--- Centaurs do not make normal melee counterattacks (NO_RETALIATION). After being attacked in melee (once per round), they fall back within their speed
--- to the free hex that is at least 3 hexes from every enemy (every hex it occupies) and farthest from the nearest enemy, then shoot the attacker once (normal shot damage). If no such hex exists, they shoot from where they stand.
--- Review B10 (2026-11-08): the comment used to say "not adjacent to any enemy" while the code requires at least 3 hexes (distance <= 2 excluded); the comment and creature description now follow the code.
--- Parameters: animation, sound

local USED = "h6Manoeuvre"

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
	if best ~= nil then server:moveUnit(battle, unit, best, true) end
	if unit:isAlive() and other:isAlive() then
		local dealt = L.hit(server, battle, other, L.attackDamage(server, unit, other, 100, true), self.animation, self.sound)
		L.log(server, battle, "H6_MANOEUVRE_H6C", 1, { L.name(unit), L.name(other) }, { dealt or 0 })
	end
end

return Script
