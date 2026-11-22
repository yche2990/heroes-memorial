--- H6 memorial Gating gate (comes with h6RcInfernalGate): if the gate is still there at the start of the next round, it disappears and summons demons of the same kind as the source stack in its place
--- (nothing comes if the source stack is wiped out); when the gate is destroyed, the shattering effect plays. Parameters: fx (on summoning), sound, destroyFx, destroySound, unsummonFx, unsummonSound (when returning to the Abyss)
local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local R = require("lib/h6RcLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onRoundStart(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	local tplId = (L.markValue(unit, "h6RcGateTpl") or 0) - 1
	local count = L.markValue(unit, "h6RcGateCnt") or 0
	local pos = unit:getPosition()
	local tpl = nil
	for _, u in ipairs(battle:getUnitsIf(function(x) return x:unitID() == tplId and x:isAlive() end)) do tpl = u end
	server:removeUnit(battle, unit)
	if tpl ~= nil and count > 0 then
		R.summon(server, battle, tpl, count, pos, self.fx, self.sound, self.unsummonFx, self.unsummonSound)
	end
	server:refreshBattleUnits(battle)
end

function Script:onDeath(server, battle, unit, other, payload)
	if self.destroyFx and server:describeChanges() then
		pcall(function() server:showBattleAnimation(battle, { { hex = unit:getPosition() } }, self.destroyFx, self.destroySound or "", 1.0, false) end)
	end
end

return Script
