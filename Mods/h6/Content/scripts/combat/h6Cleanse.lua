local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Cleansing Light (H6 Radiant Glory)
---
--- After each move (teleport) lands: dispels one beneficial spell from each adjacent enemy stack and one negative spell from each adjacent friendly stack
--- (one spell = all effects of the same spell; when there are several, the one with the most rounds left is dispelled).

local function pick(unit, positive)
	local bonuses = unit:getBonuses({}):filter(function(b)
		if b:getSource() ~= ENUM.BonusSource.spellEffect then return false end
		local sp = LIBRARY:getSpellByName(b:getSourceID())
		if sp == nil or sp:isPersistent() or sp:isAdventure() then return false end
		if positive then return sp:isPositive() end
		return sp:isNegative()
	end)
	if bonuses:size() == 0 then return nil end
	local best, bestTurns = nil, -1
	for i = 1, bonuses:size() do
		local b = bonuses:getBonus(i)
		local t = b:getTurnsRemain() or 0
		if t > bestTurns then best, bestTurns = b:getSourceID(), t end
	end
	return bonuses:filter(function(b) return b:getSourceID() == best end)
end

function Script:onAfterMove(server, battle, unit)
	if not unit:isAlive() then return end
	local near = battle:getUnitsIf(function(o)
		return o:unitID() ~= unit:unitID() and o:isAlive() and not o:isGhost() and not o:isTurret() and L.adjacent(unit, o)
	end)
	local hits = {}
	for _, o in ipairs(near) do
		local hostile = battle:isHostile(unit, o)
		local list = pick(o, hostile)
		if list ~= nil and list:size() > 0 then
			server:removeUnitBonuses(battle, o, list)
			hits[#hits + 1] = { unit = o }
		end
	end
	if #hits > 0 and server:describeChanges() then
		server:showBattleAnimation(battle, hits, "C05SPW", "", 0.8, true)
		server:refreshBattleUnits(battle)
		L.log(server, battle, "H6_CLEANSE_H6C", 1, { L.name(unit) }, { #hits })
	end
end

return Script
