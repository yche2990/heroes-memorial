local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local F = require("combat/h6FormSwap")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Light-form Sun Crusader (Sun Steed): carried by the light-form creature.
---   After each action (its own or one it is caught in): health is synced to the hidden original stack; if the original is dead but the light form was resurrected, it changes back at once.
---   When the light-form stack dies, the original stack dies with it (no second death event).
---   At the start of the next round: changes back to the original stack (effect endFx, R / L facings).
--- Parameters: endFx, sound

local function facing(unit)
	return unit:getSide() == ENUM.BattleSide.attacker and "R" or "L"
end

function Script:revert(server, battle, G)
	local O = F.original(battle, G)
	if O == nil then return end
	local pos = G:getPosition()
	local health = G:isAlive() and G:getAvailableHealth() or 0
	local dir = facing(G)
	-- First move this round's changes from G back to O, then remove G
	F.syncBack(server, battle, G, O)
	server:removeUnit(battle, G)
	if self.endFx and server:describeChanges() then
		server:showBattleAnimation(battle, { { hex = pos } }, self.endFx .. dir, self.sound or "", 1.0, false)
	end
	F.restore(server, battle, O, pos, health)
	server:refreshBattleUnits(battle)
	L.log(server, battle, "H6_SUN_STEED_H6C", 2, { L.name(O) }, {})
end

function Script:onRoundStart(server, battle, unit, other, payload)
	if unit:isGhost() then return end
	self:revert(server, battle, unit)
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if unit:isGhost() then return end
	local O = F.original(battle, unit)
	if O == nil then return end
	if unit:isAlive() and not O:isAlive() then
		self:revert(server, battle, unit)
		return
	end
	F.syncHealth(server, battle, unit, O)
end

function Script:onDeath(server, battle, unit, other, payload)
	local O = F.original(battle, unit)
	if O == nil or not O:isAlive() then return end
	F.syncHealth(server, battle, unit, O)
end

return Script
